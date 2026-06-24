-- ============================================================================
-- 015_rls_base.sql
-- Base multi-tenant + Row Level Security (RLS) lista para expansión del modelo.
--
-- Objetivos (POL-2):
--   * Centralizar el contexto del usuario autenticado en helpers reutilizables.
--   * Aislar la operación por tenant (codigo_cuenta) y por empresa (codigo_empresa).
--   * Dejar al configurador (TI) sin tenant, con visibilidad de plataforma.
--   * Forzar que las escrituras sensibles pasen por backend (postgres/service_role
--     hacen BYPASS de RLS); el rol `authenticated` solo tiene SELECT con filtro.
--
-- Convención de escritura: NINGUNA tabla operativa concede INSERT/UPDATE/DELETE
-- al rol `authenticated`. Las mutaciones (inventario, contadores, órdenes) se
-- ejecutan desde polaria-wms-api con conexión directa `postgres` (DATABASE_URL)
-- o con `service_role`, ambos exentos de RLS.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Esquema `app` para helpers de seguridad.
--    No se expone vía PostgREST (config.toml solo publica `public`), por lo que
--    estas funciones solo se invocan desde las expresiones de las políticas RLS.
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS app;

-- ----------------------------------------------------------------------------
-- 2) Helpers de contexto. SECURITY DEFINER (propietario = postgres) para poder
--    leer `usuario` sin disparar RLS recursiva sobre la propia tabla.
--    STABLE: el resultado no cambia dentro de una misma sentencia.
-- ----------------------------------------------------------------------------

-- Rol operativo del usuario autenticado (NULL si no hay perfil activo).
CREATE OR REPLACE FUNCTION app.current_rol()
RETURNS wms_rol
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.id_rol
    FROM usuario u
    WHERE u.id_auth = auth.uid()
      AND u.esta_activo
    LIMIT 1;
$$;

-- ¿El usuario autenticado es configurador (TI, nivel plataforma)?
CREATE OR REPLACE FUNCTION app.is_configurador()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM usuario u
        WHERE u.id_auth = auth.uid()
          AND u.esta_activo
          AND u.id_rol = 'configurador'
    );
$$;

-- Empresa del usuario autenticado (NULL para configurador).
CREATE OR REPLACE FUNCTION app.current_codigo_empresa()
RETURNS varchar
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.codigo_empresa
    FROM usuario u
    WHERE u.id_auth = auth.uid()
      AND u.esta_activo
    LIMIT 1;
$$;

-- Tenant (cuenta) del usuario autenticado (NULL para configurador o usuarios
-- aún no asignados a una cuenta).
CREATE OR REPLACE FUNCTION app.current_codigo_cuenta()
RETURNS varchar
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.codigo_cuenta
    FROM usuario u
    WHERE u.id_auth = auth.uid()
      AND u.esta_activo
    LIMIT 1;
$$;

-- ----------------------------------------------------------------------------
-- 3) Helpers de acceso reutilizables por tablas futuras.
--    Tablas con `codigo_empresa`  -> app.has_empresa_access(codigo_empresa)
--    Tablas con `codigo_cuenta`   -> app.has_cuenta_access(codigo_cuenta)
--    El configurador siempre tiene acceso (nivel plataforma).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.has_empresa_access(p_codigo_empresa varchar)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT app.is_configurador()
        OR (
            p_codigo_empresa IS NOT NULL
            AND p_codigo_empresa = app.current_codigo_empresa()
        );
$$;

CREATE OR REPLACE FUNCTION app.has_cuenta_access(p_codigo_cuenta varchar)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT app.is_configurador()
        OR (
            p_codigo_cuenta IS NOT NULL
            AND p_codigo_cuenta = app.current_codigo_cuenta()
        );
$$;

-- ----------------------------------------------------------------------------
-- 4) Permisos sobre el esquema y las funciones.
--    Las políticas RLS evalúan estas funciones bajo el rol que consulta, por lo
--    que `authenticated` necesita EXECUTE. Como son SECURITY DEFINER y solo
--    devuelven el contexto del propio llamante, no filtran datos de terceros.
-- ----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA app TO authenticated;
GRANT EXECUTE ON FUNCTION
    app.current_rol(),
    app.is_configurador(),
    app.current_codigo_empresa(),
    app.current_codigo_cuenta(),
    app.has_empresa_access(varchar),
    app.has_cuenta_access(varchar)
TO authenticated;

-- ============================================================================
-- 5) Refactor de políticas existentes para usar los helpers.
-- ============================================================================

-- ---- usuario --------------------------------------------------------------
-- Visibilidad: el propio perfil + (configurador ve todo) + miembros del mismo
-- tenant. Usuarios sin cuenta (p. ej. administrador_cuenta recién creado) ven a
-- los miembros de su empresa.
DROP POLICY IF EXISTS usuario_select_own ON usuario;
DROP POLICY IF EXISTS usuario_select_scope ON usuario;
CREATE POLICY usuario_select_scope
    ON usuario
    FOR SELECT
    TO authenticated
    USING (
        id_auth = auth.uid()
        OR app.is_configurador()
        OR (
            usuario.codigo_cuenta IS NOT NULL
            AND usuario.codigo_cuenta = app.current_codigo_cuenta()
        )
        OR (
            app.current_codigo_cuenta() IS NULL
            AND usuario.codigo_empresa IS NOT NULL
            AND usuario.codigo_empresa = app.current_codigo_empresa()
        )
    );

-- ---- empresa --------------------------------------------------------------
DROP POLICY IF EXISTS empresa_select_scope ON empresa;
CREATE POLICY empresa_select_scope
    ON empresa
    FOR SELECT
    TO authenticated
    USING (app.has_empresa_access(empresa.codigo_empresa));

-- ---- cuenta ---------------------------------------------------------------
-- Por defecto, alcance por empresa (un admin de cuenta ve las cuentas de su
-- empresa). El configurador ve todas.
DROP POLICY IF EXISTS cuenta_select_scope ON cuenta;
CREATE POLICY cuenta_select_scope
    ON cuenta
    FOR SELECT
    TO authenticated
    USING (app.has_empresa_access(cuenta.codigo_empresa));

-- ---- rol ------------------------------------------------------------------
-- Catálogo de solo lectura para cualquier usuario autenticado (sin cambios).

-- ============================================================================
-- 6) Mínimo privilegio sobre las tablas fundacionales.
--    Supabase concede por defecto ALL (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/...)
--    a `anon` y `authenticated`. RLS bloquea SELECT/DML sin política, pero
--    TRUNCATE NO está sujeto a RLS. Revocamos todo y reconcedemos solo SELECT a
--    `authenticated` (filtrado por RLS). `anon` queda SIN acceso: el frontend
--    accede únicamente vía polaria-wms-api (backend), nunca con la anon key.
--    Las escrituras sensibles se ejecutan por backend (postgres/service_role),
--    exentos de RLS.
-- ============================================================================
REVOKE ALL ON rol     FROM anon, authenticated;
REVOKE ALL ON empresa FROM anon, authenticated;
REVOKE ALL ON usuario FROM anon, authenticated;
REVOKE ALL ON cuenta  FROM anon, authenticated;

GRANT SELECT ON rol     TO authenticated;
GRANT SELECT ON empresa TO authenticated;
GRANT SELECT ON usuario TO authenticated;
GRANT SELECT ON cuenta  TO authenticated;

COMMENT ON SCHEMA app IS
    'Helpers de seguridad RLS (contexto del usuario autenticado). No expuesto vía PostgREST.';
