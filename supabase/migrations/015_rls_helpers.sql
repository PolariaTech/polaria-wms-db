-- Helpers SECURITY DEFINER para políticas RLS multi-tenant (POL-2).
-- Uso interno en políticas; no exponer como RPC público.

-- Contexto del usuario autenticado (campos usados por políticas).
CREATE TYPE auth_wms_usuario_contexto AS (
    id_usuario uuid,
    id_rol wms_rol,
    nivel rol_nivel,
    codigo_empresa varchar(32),
    codigo_cuenta varchar(32),
    esta_activo boolean
);

-- Retorna la fila de contexto del usuario activo vinculado a auth.uid().
-- NULL si no hay sesión o el usuario está inactivo.
CREATE OR REPLACE FUNCTION auth_wms_usuario_actual()
RETURNS auth_wms_usuario_contexto
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        u.id_usuario,
        u.id_rol,
        r.nivel,
        u.codigo_empresa,
        u.codigo_cuenta,
        u.esta_activo
    FROM usuario u
    INNER JOIN rol r ON r.id_rol = u.id_rol
    WHERE u.id_auth = auth.uid()
      AND u.esta_activo
    LIMIT 1
$$;

-- Indica si el usuario activo es configurador (TI / plataforma).
CREATE OR REPLACE FUNCTION auth_wms_es_configurador()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM usuario u
        WHERE u.id_auth = auth.uid()
          AND u.esta_activo
          AND u.id_rol = 'configurador'
    )
$$;

-- Configurador ve cualquier empresa activa; demás roles solo la suya.
-- Requiere usuario activo y empresa activa.
CREATE OR REPLACE FUNCTION auth_wms_puede_ver_empresa(p_codigo_empresa varchar)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM usuario u
        INNER JOIN empresa e ON e.codigo_empresa = p_codigo_empresa
        WHERE u.id_auth = auth.uid()
          AND u.esta_activo
          AND e.esta_activa
          AND (
              u.id_rol = 'configurador'
              OR u.codigo_empresa = p_codigo_empresa
          )
    )
$$;

-- Alcance de cuentas según rol y asignación del usuario.
-- Configurador: todas las cuentas activas. Admin cuenta sin codigo_cuenta: todas de su empresa.
-- Nivel bodega: cuentas de su empresa (hasta migración asignacion_bodega).
-- Usuario con codigo_cuenta: solo esa cuenta en su empresa.
CREATE OR REPLACE FUNCTION auth_wms_puede_ver_cuenta(p_codigo_cuenta varchar)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM usuario u
        INNER JOIN rol r ON r.id_rol = u.id_rol
        INNER JOIN cuenta c ON c.codigo_cuenta = p_codigo_cuenta
        INNER JOIN empresa e ON e.codigo_empresa = c.codigo_empresa
        WHERE u.id_auth = auth.uid()
          AND u.esta_activo
          AND c.esta_activa
          AND e.esta_activa
          AND (
              u.id_rol = 'configurador'
              OR (
                  u.id_rol = 'administrador_cuenta'
                  AND u.codigo_cuenta IS NULL
                  AND c.codigo_empresa = u.codigo_empresa
              )
              OR (
                  r.nivel = 'bodega'
                  AND c.codigo_empresa = u.codigo_empresa
              )
              OR (
                  u.codigo_cuenta IS NOT NULL
                  AND u.codigo_cuenta = p_codigo_cuenta
                  AND c.codigo_empresa = u.codigo_empresa
              )
          )
    )
$$;

-- Revocar ejecución pública: solo uso interno vía políticas RLS.
REVOKE ALL ON FUNCTION auth_wms_usuario_actual() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth_wms_usuario_actual() FROM anon, authenticated;

REVOKE ALL ON FUNCTION auth_wms_es_configurador() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth_wms_es_configurador() FROM anon, authenticated;

REVOKE ALL ON FUNCTION auth_wms_puede_ver_empresa(varchar) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth_wms_puede_ver_empresa(varchar) FROM anon, authenticated;

REVOKE ALL ON FUNCTION auth_wms_puede_ver_cuenta(varchar) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth_wms_puede_ver_cuenta(varchar) FROM anon, authenticated;
