-- polaria-wms-db: todas las migraciones (001-030)
-- Proyecto: zmdokvjewvqaftnvulsr
-- Generado: 2026-06-24


-- ========== 001_extensions.sql ==========
-- Extensiones requeridas para login (UUID, citext case-insensitive, gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";

-- Roles de Supabase (ya existen en producción; guarda para validación local)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
END $$;

-- Trigger reutilizable para updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- ========== 002_enums.sql ==========
-- Roles operativos del WMS (catálogo fijo, 9 valores)
CREATE TYPE wms_rol AS ENUM (
    'configurador',
    'administrador_cuenta',
    'operador_cuenta',
    'administrador_bodega',
    'jefe_bodega',
    'custodio',
    'operario',
    'procesador',
    'transportista'
);

-- Nivel de alcance del rol (plataforma / cuenta / bodega)
CREATE TYPE rol_nivel AS ENUM (
    'plataforma',
    'cuenta',
    'bodega'
);

-- ========== 010_roles.sql ==========
CREATE TABLE rol (
    id_rol wms_rol PRIMARY KEY,
    nombre varchar(255) NOT NULL,
    nivel rol_nivel NOT NULL,
    puede_crear_rol wms_rol,
    descripcion text,

    CONSTRAINT fk_rol_puede_crear
        FOREIGN KEY (puede_crear_rol)
        REFERENCES rol (id_rol)
);

CREATE INDEX ix_rol_nivel ON rol (nivel);

INSERT INTO rol (id_rol, nombre, nivel, puede_crear_rol, descripcion)
VALUES
    (
        'configurador',
        'Configurador (TI)',
        'plataforma',
        NULL,
        'Equipo TI del proveedor SaaS. Crea empresas y usuarios con cualquier rol.'
    ),
    (
        'administrador_cuenta',
        'Administrador de cuenta',
        'cuenta',
        'configurador',
        'Responsable del cliente. Gestiona tenant, catálogos y equipo.'
    ),
    (
        'operador_cuenta',
        'Operador de cuenta',
        'cuenta',
        'configurador',
        'Opera el tenant a nivel comercial (SOL, OC, OV).'
    ),
    (
        'administrador_bodega',
        'Administrador de bodega',
        'bodega',
        'configurador',
        'Responsable de la bodega asignada: configuración y supervisión.'
    ),
    (
        'jefe_bodega',
        'Jefe de bodega',
        'bodega',
        'configurador',
        'Jefe operativo: prioriza OT, alertas y override de temperatura.'
    ),
    (
        'custodio',
        'Custodio',
        'bodega',
        'configurador',
        'Recibe mercancía, valida documentos/temperatura y despacha salidas.'
    ),
    (
        'operario',
        'Operario',
        'bodega',
        'configurador',
        'Ejecuta órdenes de trabajo y movimientos de cajas/slots.'
    ),
    (
        'procesador',
        'Procesador',
        'bodega',
        'configurador',
        'Encargado de la línea de procesamiento (primario → secundario, merma).'
    ),
    (
        'transportista',
        'Transportista',
        'bodega',
        'configurador',
        'Conduce viajes TV y registra entregas con evidencias.'
    );

ALTER TABLE rol ENABLE ROW LEVEL SECURITY;

CREATE POLICY rol_select_authenticated
    ON rol
    FOR SELECT
    TO authenticated
    USING (true);

GRANT SELECT ON rol TO authenticated;

-- ========== 011_company.sql ==========
CREATE TABLE empresa (
    codigo_empresa varchar(32) PRIMARY KEY,
    razon_social varchar(255) NOT NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    id_creador uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_empresa_activa
    ON empresa (esta_activa)
    WHERE esta_activa;

CREATE TRIGGER trg_empresa_updated_at
    BEFORE UPDATE ON empresa
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE empresa ENABLE ROW LEVEL SECURITY;

-- ========== 012_user.sql ==========
CREATE TABLE usuario (
    id_usuario uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_auth uuid NOT NULL UNIQUE,
    id_rol wms_rol NOT NULL,
    codigo_empresa varchar(32),
    codigo_cuenta varchar(32),
    id_creador uuid,
    nombre varchar(255) NOT NULL,
    username citext NOT NULL,
    correo citext NOT NULL,
    esta_activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_usuario_correo UNIQUE (correo),
    CONSTRAINT uq_usuario_username UNIQUE (username),

    CONSTRAINT fk_usuario_rol
        FOREIGN KEY (id_rol)
        REFERENCES rol (id_rol),

    CONSTRAINT fk_usuario_empresa
        FOREIGN KEY (codigo_empresa)
        REFERENCES empresa (codigo_empresa),

    CONSTRAINT chk_usuario_contexto CHECK (
        (
            id_rol = 'configurador'
            AND codigo_empresa IS NULL
            AND codigo_cuenta IS NULL
        )
        OR (
            id_rol <> 'configurador'
            AND codigo_empresa IS NOT NULL
        )
    )
);

CREATE INDEX ix_usuario_id_auth ON usuario (id_auth);
CREATE INDEX ix_usuario_empresa ON usuario (codigo_empresa);
CREATE INDEX ix_usuario_cuenta ON usuario (codigo_cuenta);
CREATE INDEX ix_usuario_rol ON usuario (id_rol);
CREATE INDEX ix_usuario_login_username ON usuario (username) WHERE esta_activo;
CREATE INDEX ix_usuario_login_correo ON usuario (correo) WHERE esta_activo;

ALTER TABLE usuario
    ADD CONSTRAINT fk_usuario_creador
    FOREIGN KEY (id_creador)
    REFERENCES usuario (id_usuario);

ALTER TABLE usuario
    ADD CONSTRAINT fk_usuario_auth
    FOREIGN KEY (id_auth)
    REFERENCES auth.users (id)
    ON DELETE CASCADE;

CREATE TRIGGER trg_usuario_updated_at
    BEFORE UPDATE ON usuario
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE usuario ENABLE ROW LEVEL SECURITY;

CREATE POLICY usuario_select_own
    ON usuario
    FOR SELECT
    TO authenticated
    USING (id_auth = auth.uid());

GRANT SELECT ON usuario TO authenticated;

CREATE POLICY empresa_select_scope
    ON empresa
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM usuario u
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
              AND (
                  u.id_rol = 'configurador'
                  OR u.codigo_empresa = empresa.codigo_empresa
              )
        )
    );

GRANT SELECT ON empresa TO authenticated;

-- ========== 013_account.sql ==========
CREATE TABLE cuenta (
    codigo_cuenta varchar(32) PRIMARY KEY,
    codigo_empresa varchar(32) NOT NULL,
    nombre_comercial varchar(255) NOT NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    id_creador uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_cuenta_empresa
        FOREIGN KEY (codigo_empresa)
        REFERENCES empresa (codigo_empresa),

    CONSTRAINT fk_cuenta_creador
        FOREIGN KEY (id_creador)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_cuenta_empresa ON cuenta (codigo_empresa);
CREATE INDEX ix_cuenta_activa
    ON cuenta (esta_activa)
    WHERE esta_activa;

CREATE TRIGGER trg_cuenta_updated_at
    BEFORE UPDATE ON cuenta
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- FK diferida: usuario.codigo_cuenta requiere que cuenta exista
ALTER TABLE usuario
    ADD CONSTRAINT fk_usuario_cuenta
    FOREIGN KEY (codigo_cuenta)
    REFERENCES cuenta (codigo_cuenta);

-- FK diferida: empresa.id_creador requiere que usuario exista
ALTER TABLE empresa
    ADD CONSTRAINT fk_empresa_creador
    FOREIGN KEY (id_creador)
    REFERENCES usuario (id_usuario);

ALTER TABLE cuenta ENABLE ROW LEVEL SECURITY;

CREATE POLICY cuenta_select_scope
    ON cuenta
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM usuario u
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
              AND (
                  u.id_rol = 'configurador'
                  OR u.codigo_empresa = cuenta.codigo_empresa
              )
        )
    );

GRANT SELECT ON cuenta TO authenticated;

-- ========== 014_fix_puede_crear_rol.sql ==========
-- Corregir puede_crear_rol: solo el configurador (TI) puede dar de alta cualquier rol.
UPDATE rol
SET puede_crear_rol = 'configurador'
WHERE id_rol <> 'configurador';

UPDATE rol
SET descripcion = 'Equipo TI del proveedor SaaS. Crea empresas y usuarios con cualquier rol.'
WHERE id_rol = 'configurador';

-- ========== 015_rls_helpers.sql ==========
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

-- ========== 016_rls_cuenta_scope.sql ==========
-- POL-2: políticas RLS de fase 1 con aislamiento por codigo_cuenta (helpers 015).
--
-- Validación de activación (no CHECK en tabla; la aplican los helpers y esta política):
--   - empresa: auth_wms_puede_ver_empresa exige empresa.esta_activa.
--   - cuenta:  auth_wms_puede_ver_cuenta exige cuenta.esta_activa y empresa.esta_activa.
--   - usuario: auth_wms_usuario_actual() exige usuario.esta_activo del caller;
--     usuario_select_scope_admin no filtra esta_activo del target (admins gestionan inactivos).
--
-- Patrón UPDATE/DELETE (futuro): Postgres exige que la fila sea visible vía FOR SELECT
-- antes de aplicar UPDATE o DELETE. Al agregar políticas UPDATE, definir:
--   CREATE POLICY ... FOR UPDATE TO authenticated
--       USING  (auth_wms_puede_ver_*(...))   -- visibilidad (equivalente SELECT)
--       WITH CHECK (auth_wms_puede_ver_*(...));  -- valores nuevos válidos
-- Sin política SELECT compatible, UPDATE/DELETE no afectará filas aunque exista USING en UPDATE.

-- Ejecución interna desde políticas RLS (015 revocó EXECUTE a authenticated).
GRANT EXECUTE ON FUNCTION auth_wms_usuario_actual() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_es_configurador() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_empresa(varchar) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_cuenta(varchar) TO authenticated;

-- ---------------------------------------------------------------------------
-- empresa
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS empresa_select_scope ON empresa;

CREATE POLICY empresa_select_scope
    ON empresa
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_empresa(codigo_empresa));

-- ---------------------------------------------------------------------------
-- cuenta
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS cuenta_select_scope ON cuenta;

CREATE POLICY cuenta_select_scope
    ON cuenta
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

-- ---------------------------------------------------------------------------
-- usuario
-- ---------------------------------------------------------------------------
-- usuario_select_own: sin cambios (cada usuario ve su propia fila).

-- usuario_select_scope_admin APLICA en fase 1:
--   - configurador (TI): ve todos los usuarios de la plataforma.
--   - administrador_cuenta sin codigo_cuenta: ve usuarios de su codigo_empresa
--     (todas las cuentas del tenant).
--   - administrador_cuenta con codigo_cuenta asignado: solo usuarios de esa cuenta.
-- Roles de bodega/operador no reciben SELECT extra (solo usuario_select_own).
DROP POLICY IF EXISTS usuario_select_scope_admin ON usuario;

CREATE POLICY usuario_select_scope_admin
    ON usuario
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_es_configurador()
        OR (
            (auth_wms_usuario_actual()).id_rol = 'administrador_cuenta'
            AND usuario.codigo_empresa = (auth_wms_usuario_actual()).codigo_empresa
            AND (
                (auth_wms_usuario_actual()).codigo_cuenta IS NULL
                OR usuario.codigo_cuenta = (auth_wms_usuario_actual()).codigo_cuenta
            )
        )
    );

-- TODO (fase posterior): usuario_select_scope_bodega cuando exista asignacion_bodega
-- para que jefe_bodega/administrador_bodega vean operarios de su bodega.
-- DROP POLICY IF EXISTS usuario_select_scope_bodega ON usuario;
-- CREATE POLICY usuario_select_scope_bodega ...

-- ===========================================================================
-- Pruebas manuales (comentadas). Requiere seed con dos cuentas en la misma empresa.
-- Simular sesión: SELECT set_config('request.jwt.claim.sub', '<uuid id_auth>', true);
-- En Supabase: autenticarse como cada usuario y ejecutar los SELECT.
-- ===========================================================================
--
-- -- Setup esperado: empresa ACME, cuentas ACME-01 y ACME-02, operador en ACME-01.
--
-- -- 1) Usuario de cuenta A no ve cuenta B (misma empresa)
-- SELECT set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
-- SELECT codigo_cuenta FROM cuenta ORDER BY codigo_cuenta;
-- -- Esperado: solo ACME-01 (operador_cuenta con codigo_cuenta = ACME-01)
--
-- -- 2) Configurador ve todas las cuentas activas
-- SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
-- SELECT codigo_cuenta, codigo_empresa FROM cuenta ORDER BY codigo_cuenta;
-- -- Esperado: ACME-01, ACME-02, ... (todas las activas)
--
-- -- 3) administrador_cuenta sin codigo_cuenta ve todas las cuentas de su empresa
-- SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
-- SELECT codigo_cuenta, codigo_empresa FROM cuenta ORDER BY codigo_cuenta;
-- -- Esperado: ACME-01 y ACME-02 (ambas de ACME), no cuentas de otras empresas
--
-- -- Verificación cruzada empresa (mismo alcance por helper)
-- SELECT codigo_empresa FROM empresa ORDER BY codigo_empresa;

-- ========== 017_bodega_base.sql ==========
-- POL-2: modelo mínimo de bodega y asignación para RLS por id_bodega.
-- POL-33 ampliará el modelo operativo; aquí solo lo fundacional.
--
-- Convención tenant para tablas operativas futuras (Prisma / POL-33):
--   - codigo_cuenta varchar(32) NOT NULL FK → cuenta (aislamiento comercial)
--   - id_bodega uuid NOT NULL FK → bodega (aislamiento físico / operativo)
-- codigo_empresa se resuelve vía cuenta; no duplicar en bodega ni en hijos.

CREATE TABLE bodega (
    id_bodega uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    codigo varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_bodega_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_bodega_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta)
);

CREATE INDEX ix_bodega_cuenta ON bodega (codigo_cuenta);

CREATE TRIGGER trg_bodega_updated_at
    BEFORE UPDATE ON bodega
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE asignacion_bodega (
    id_usuario uuid NOT NULL,
    id_bodega uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (id_usuario, id_bodega),

    CONSTRAINT fk_asignacion_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
        ON DELETE CASCADE,

    CONSTRAINT fk_asignacion_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega)
        ON DELETE CASCADE
);

CREATE INDEX ix_asignacion_usuario ON asignacion_bodega (id_usuario);
CREATE INDEX ix_asignacion_bodega ON asignacion_bodega (id_bodega);

-- Alcance de bodegas según rol y asignación.
-- Configurador: todas las activas. Admin cuenta: su cuenta o toda su empresa si codigo_cuenta NULL.
-- Nivel bodega: solo asignacion_bodega. operador_cuenta: bodegas de su codigo_cuenta.
CREATE OR REPLACE FUNCTION auth_wms_puede_ver_bodega(p_id_bodega uuid)
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
        INNER JOIN bodega b ON b.id_bodega = p_id_bodega
        INNER JOIN cuenta c ON c.codigo_cuenta = b.codigo_cuenta
        INNER JOIN empresa e ON e.codigo_empresa = c.codigo_empresa
        WHERE u.id_auth = auth.uid()
          AND u.esta_activo
          AND b.esta_activa
          AND c.esta_activa
          AND e.esta_activa
          AND (
              u.id_rol = 'configurador'
              OR (
                  u.id_rol = 'administrador_cuenta'
                  AND (
                      (
                          u.codigo_cuenta IS NULL
                          AND c.codigo_empresa = u.codigo_empresa
                      )
                      OR u.codigo_cuenta = b.codigo_cuenta
                  )
              )
              OR (
                  r.nivel = 'bodega'
                  AND EXISTS (
                      SELECT 1
                      FROM asignacion_bodega ab
                      WHERE ab.id_usuario = u.id_usuario
                        AND ab.id_bodega = p_id_bodega
                  )
              )
              OR (
                  u.id_rol = 'operador_cuenta'
                  AND u.codigo_cuenta IS NOT NULL
                  AND u.codigo_cuenta = b.codigo_cuenta
              )
          )
    )
$$;

REVOKE ALL ON FUNCTION auth_wms_puede_ver_bodega(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth_wms_puede_ver_bodega(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_bodega(uuid) TO authenticated;

ALTER TABLE bodega ENABLE ROW LEVEL SECURITY;

CREATE POLICY bodega_select_scope
    ON bodega
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

GRANT SELECT ON bodega TO authenticated;

ALTER TABLE asignacion_bodega ENABLE ROW LEVEL SECURITY;

CREATE POLICY asignacion_bodega_select_scope
    ON asignacion_bodega
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

GRANT SELECT ON asignacion_bodega TO authenticated;

-- INSERT/UPDATE/DELETE: ver migración 018_rls_write_policies.sql (solo configurador).

-- ========== 018_rls_write_policies.sql ==========
-- POL-2: políticas de escritura para plataforma (solo configurador).
--
-- Backend API: conecta con DATABASE_URL (rol postgres / service) y bypass RLS.
-- Debe validar tenant (codigo_empresa, codigo_cuenta, id_bodega) en código de aplicación.
-- PostgREST (JWT authenticated): clientes solo lectura acotada; escritura plataforma = configurador TI.

-- Defensa en profundidad: revocar escritura antes de GRANTs selectivos.
REVOKE INSERT, UPDATE, DELETE ON rol FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON empresa FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON cuenta FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON usuario FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON bodega FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON asignacion_bodega FROM authenticated;

-- ---------------------------------------------------------------------------
-- empresa
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS empresa_insert_configurador ON empresa;
DROP POLICY IF EXISTS empresa_update_configurador ON empresa;

CREATE POLICY empresa_insert_configurador
    ON empresa
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_es_configurador());

CREATE POLICY empresa_update_configurador
    ON empresa
    FOR UPDATE
    TO authenticated
    USING (auth_wms_es_configurador())
    WITH CHECK (auth_wms_es_configurador());

GRANT INSERT, UPDATE ON empresa TO authenticated;

-- ---------------------------------------------------------------------------
-- cuenta
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS cuenta_insert_configurador ON cuenta;
DROP POLICY IF EXISTS cuenta_update_configurador ON cuenta;

CREATE POLICY cuenta_insert_configurador
    ON cuenta
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_es_configurador());

CREATE POLICY cuenta_update_configurador
    ON cuenta
    FOR UPDATE
    TO authenticated
    USING (auth_wms_es_configurador())
    WITH CHECK (auth_wms_es_configurador());

GRANT INSERT, UPDATE ON cuenta TO authenticated;

-- ---------------------------------------------------------------------------
-- usuario
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS usuario_insert_configurador ON usuario;
DROP POLICY IF EXISTS usuario_update_configurador ON usuario;

CREATE POLICY usuario_insert_configurador
    ON usuario
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_es_configurador());

CREATE POLICY usuario_update_configurador
    ON usuario
    FOR UPDATE
    TO authenticated
    USING (auth_wms_es_configurador())
    WITH CHECK (auth_wms_es_configurador());

GRANT INSERT, UPDATE ON usuario TO authenticated;

-- ---------------------------------------------------------------------------
-- bodega
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS bodega_insert_configurador ON bodega;
DROP POLICY IF EXISTS bodega_update_configurador ON bodega;

CREATE POLICY bodega_insert_configurador
    ON bodega
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_es_configurador());

CREATE POLICY bodega_update_configurador
    ON bodega
    FOR UPDATE
    TO authenticated
    USING (auth_wms_es_configurador())
    WITH CHECK (auth_wms_es_configurador());

GRANT INSERT, UPDATE ON bodega TO authenticated;

-- ---------------------------------------------------------------------------
-- asignacion_bodega
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS asignacion_bodega_insert_configurador ON asignacion_bodega;
DROP POLICY IF EXISTS asignacion_bodega_delete_configurador ON asignacion_bodega;

CREATE POLICY asignacion_bodega_insert_configurador
    ON asignacion_bodega
    FOR INSERT
    TO authenticated
    WITH CHECK (auth_wms_es_configurador());

CREATE POLICY asignacion_bodega_delete_configurador
    ON asignacion_bodega
    FOR DELETE
    TO authenticated
    USING (auth_wms_es_configurador());

GRANT INSERT, DELETE ON asignacion_bodega TO authenticated;

-- ---------------------------------------------------------------------------
-- Plantilla: tablas sensibles futuras (POL-33 / inventario)
-- No crear tablas aquí; aplicar al exponer cada tabla vía PostgREST.
-- ---------------------------------------------------------------------------
-- REVOKE INSERT, UPDATE, DELETE ON warehouse_state FROM authenticated;
-- REVOKE INSERT, UPDATE, DELETE ON inventory_counter FROM authenticated;
-- GRANT SELECT ON warehouse_state TO authenticated;  -- solo si hay política SELECT explícita
-- Mutaciones vía backend (postgres) o funciones SECURITY DEFINER controladas.

-- ========== 019_drop_legacy_usuario_select.sql ==========
-- POL-2: reemplazar política legacy usuario_select_scope (app.* / Mateo) por usuario_select_own.
-- usuario_select_scope_admin (016) cubre configurador y administrador_cuenta.
-- No toca document_chunks ni funciones app.* de Mateo.

DROP POLICY IF EXISTS usuario_select_scope ON usuario;

DROP POLICY IF EXISTS usuario_select_own ON usuario;

CREATE POLICY usuario_select_own
    ON usuario
    FOR SELECT
    TO authenticated
    USING (id_auth = auth.uid());

-- ========== 020_warehouse_layout.sql ==========
-- POL-33 Fase 1: layout de bodega (tipo_ubicacion, zona, ubicacion).
--
-- Convención tenant (017): codigo_cuenta + id_bodega en tablas operativas de layout.
-- codigo_cuenta se sincroniza desde bodega vía trigger (no duplicar codigo_empresa).
--
-- Escritura: solo backend (polaria-wms-api / rol postgres). PostgREST = SELECT acotado.
-- Ver docs/modelo-operativo-v2.md y docs/rls-politicas.md.

-- ---------------------------------------------------------------------------
-- Helpers: coherencia tenant layout ↔ bodega
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION layout_sync_codigo_cuenta_desde_bodega()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_codigo_cuenta varchar(32);
BEGIN
    SELECT b.codigo_cuenta
    INTO v_codigo_cuenta
    FROM bodega b
    WHERE b.id_bodega = NEW.id_bodega;

    IF v_codigo_cuenta IS NULL THEN
        RAISE EXCEPTION 'bodega % no existe', NEW.id_bodega;
    END IF;

    NEW.codigo_cuenta := v_codigo_cuenta;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ubicacion_validar_referencias()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id_zona IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM zona z
            WHERE z.id_zona = NEW.id_zona
              AND z.id_bodega = NEW.id_bodega
        ) THEN
            RAISE EXCEPTION 'zona % no pertenece a bodega %', NEW.id_zona, NEW.id_bodega;
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM tipo_ubicacion tu
        WHERE tu.id_tipo_ubicacion = NEW.id_tipo_ubicacion
          AND tu.id_bodega = NEW.id_bodega
    ) THEN
        RAISE EXCEPTION 'tipo_ubicacion % no pertenece a bodega %', NEW.id_tipo_ubicacion, NEW.id_bodega;
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- tipo_ubicacion — catálogo por bodega (C+B)
-- ---------------------------------------------------------------------------
CREATE TABLE tipo_ubicacion (
    id_tipo_ubicacion uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    codigo varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    es_picking boolean NOT NULL DEFAULT false,
    es_recepcion boolean NOT NULL DEFAULT false,
    es_almacenamiento boolean NOT NULL DEFAULT true,
    esta_activa boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_tipo_ubicacion_bodega_codigo UNIQUE (id_bodega, codigo),

    CONSTRAINT fk_tipo_ubicacion_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_tipo_ubicacion_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega)
);

CREATE INDEX ix_tipo_ubicacion_cuenta ON tipo_ubicacion (codigo_cuenta);
CREATE INDEX ix_tipo_ubicacion_bodega ON tipo_ubicacion (id_bodega);

CREATE TRIGGER trg_tipo_ubicacion_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON tipo_ubicacion
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_tipo_ubicacion_updated_at
    BEFORE UPDATE ON tipo_ubicacion
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE tipo_ubicacion IS
    'Catálogo de tipos de ubicación por bodega (picking, recepción, almacenamiento). POL-33.';

-- ---------------------------------------------------------------------------
-- zona — agrupación lógica dentro de una bodega
-- ---------------------------------------------------------------------------
CREATE TABLE zona (
    id_zona uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    codigo varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_zona_bodega_codigo UNIQUE (id_bodega, codigo),

    CONSTRAINT fk_zona_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_zona_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega)
);

CREATE INDEX ix_zona_cuenta ON zona (codigo_cuenta);
CREATE INDEX ix_zona_bodega ON zona (id_bodega);

CREATE TRIGGER trg_zona_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON zona
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_zona_updated_at
    BEFORE UPDATE ON zona
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE zona IS
    'Zona lógica dentro de una bodega. POL-33.';

-- ---------------------------------------------------------------------------
-- ubicacion — posición física (bin, pasillo, etc.)
-- ---------------------------------------------------------------------------
CREATE TABLE ubicacion (
    id_ubicacion uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    id_zona uuid,
    id_tipo_ubicacion uuid NOT NULL,
    codigo varchar(64) NOT NULL,
    capacidad numeric(18, 4),
    esta_activa boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_ubicacion_bodega_codigo UNIQUE (id_bodega, codigo),

    CONSTRAINT fk_ubicacion_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_ubicacion_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_ubicacion_zona
        FOREIGN KEY (id_zona)
        REFERENCES zona (id_zona),

    CONSTRAINT fk_ubicacion_tipo
        FOREIGN KEY (id_tipo_ubicacion)
        REFERENCES tipo_ubicacion (id_tipo_ubicacion)
);

CREATE INDEX ix_ubicacion_cuenta ON ubicacion (codigo_cuenta);
CREATE INDEX ix_ubicacion_bodega ON ubicacion (id_bodega);
CREATE INDEX ix_ubicacion_zona ON ubicacion (id_zona);
CREATE INDEX ix_ubicacion_tipo ON ubicacion (id_tipo_ubicacion);

CREATE TRIGGER trg_ubicacion_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON ubicacion
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_ubicacion_validar_refs
    BEFORE INSERT OR UPDATE OF id_bodega, id_zona, id_tipo_ubicacion ON ubicacion
    FOR EACH ROW
    EXECUTE FUNCTION ubicacion_validar_referencias();

CREATE TRIGGER trg_ubicacion_updated_at
    BEFORE UPDATE ON ubicacion
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE ubicacion IS
    'Ubicación física dentro de una bodega. POL-33.';

-- ---------------------------------------------------------------------------
-- RLS — lectura acotada; mutaciones solo backend (postgres bypass RLS)
-- ---------------------------------------------------------------------------
ALTER TABLE tipo_ubicacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE zona ENABLE ROW LEVEL SECURITY;
ALTER TABLE ubicacion ENABLE ROW LEVEL SECURITY;

CREATE POLICY tipo_ubicacion_select_scope
    ON tipo_ubicacion
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

CREATE POLICY zona_select_scope
    ON zona
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

CREATE POLICY ubicacion_select_scope
    ON ubicacion
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

REVOKE INSERT, UPDATE, DELETE ON tipo_ubicacion FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON zona FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON ubicacion FROM authenticated;

GRANT SELECT ON tipo_ubicacion TO authenticated;
GRANT SELECT ON zona TO authenticated;
GRANT SELECT ON ubicacion TO authenticated;

-- ========== 021_catalogos.sql ==========
-- POL-33 Fase 2: catálogos maestros por cuenta (alcance C, sin id_bodega).

--

-- Tablas: proveedor, cliente, producto, comprador, planta, camion.

-- codigo_empresa vía join cuenta; no duplicar en catálogos.

-- Ver docs/modelo-operativo-v2.md y docs/rls-politicas.md.



-- ---------------------------------------------------------------------------

-- Helper RLS: escritura de catálogos (configurador o admin de la cuenta)

-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_wms_puede_gestionar_catalogo_cuenta(p_codigo_cuenta varchar)

RETURNS boolean

LANGUAGE sql

STABLE

SECURITY DEFINER

SET search_path = public

AS $$

    SELECT

        auth_wms_es_configurador()

        OR (

            (auth_wms_usuario_actual()).id_rol = 'administrador_cuenta'

            AND auth_wms_puede_ver_cuenta(p_codigo_cuenta)

        )

$$;



REVOKE ALL ON FUNCTION auth_wms_puede_gestionar_catalogo_cuenta(varchar) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION auth_wms_puede_gestionar_catalogo_cuenta(varchar) TO authenticated;



-- ---------------------------------------------------------------------------

-- proveedor

-- ---------------------------------------------------------------------------

CREATE TABLE proveedor (

    id_proveedor uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    codigo varchar(32) NOT NULL,

    razon_social varchar(255) NOT NULL,

    esta_activo boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_proveedor_cuenta_codigo UNIQUE (codigo_cuenta, codigo),



    CONSTRAINT fk_proveedor_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta)

);



CREATE INDEX ix_proveedor_cuenta ON proveedor (codigo_cuenta);



CREATE TRIGGER trg_proveedor_updated_at

    BEFORE UPDATE ON proveedor

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE proveedor IS 'Catálogo de proveedores por cuenta. POL-33.';



-- ---------------------------------------------------------------------------

-- cliente

-- ---------------------------------------------------------------------------

CREATE TABLE cliente (

    id_cliente uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    codigo varchar(32) NOT NULL,

    nombre varchar(255) NOT NULL,

    esta_activo boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_cliente_cuenta_codigo UNIQUE (codigo_cuenta, codigo),



    CONSTRAINT fk_cliente_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta)

);



CREATE INDEX ix_cliente_cuenta ON cliente (codigo_cuenta);



CREATE TRIGGER trg_cliente_updated_at

    BEFORE UPDATE ON cliente

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE cliente IS 'Catálogo de clientes por cuenta. POL-33.';



-- ---------------------------------------------------------------------------

-- producto

-- ---------------------------------------------------------------------------

CREATE TABLE producto (

    id_producto uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    sku varchar(64) NOT NULL,

    descripcion varchar(512) NOT NULL,

    unidad_medida varchar(32) NOT NULL,

    requiere_lote boolean NOT NULL DEFAULT false,

    esta_activo boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_producto_cuenta_sku UNIQUE (codigo_cuenta, sku),



    CONSTRAINT fk_producto_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta)

);



CREATE INDEX ix_producto_cuenta ON producto (codigo_cuenta);



CREATE TRIGGER trg_producto_updated_at

    BEFORE UPDATE ON producto

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE producto IS 'Catálogo de productos por cuenta. POL-33.';



-- ---------------------------------------------------------------------------

-- comprador (docs/modelo-operativo-v2.md — catálogo auxiliar C)

-- ---------------------------------------------------------------------------

CREATE TABLE comprador (

    id_comprador uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    codigo varchar(32) NOT NULL,

    nombre varchar(255) NOT NULL,

    esta_activo boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_comprador_cuenta_codigo UNIQUE (codigo_cuenta, codigo),



    CONSTRAINT fk_comprador_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta)

);



CREATE INDEX ix_comprador_cuenta ON comprador (codigo_cuenta);



CREATE TRIGGER trg_comprador_updated_at

    BEFORE UPDATE ON comprador

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE comprador IS 'Compradores internos por cuenta. POL-33.';



-- ---------------------------------------------------------------------------

-- planta (docs/modelo-operativo-v2.md — catálogo auxiliar C)

-- ---------------------------------------------------------------------------

CREATE TABLE planta (

    id_planta uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    codigo varchar(32) NOT NULL,

    nombre varchar(255) NOT NULL,

    esta_activo boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_planta_cuenta_codigo UNIQUE (codigo_cuenta, codigo),



    CONSTRAINT fk_planta_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta)

);



CREATE INDEX ix_planta_cuenta ON planta (codigo_cuenta);



CREATE TRIGGER trg_planta_updated_at

    BEFORE UPDATE ON planta

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE planta IS 'Plantas / sitios de origen por cuenta. POL-33.';



-- ---------------------------------------------------------------------------

-- camion (docs/modelo-operativo-v2.md — catálogo auxiliar C)

-- ---------------------------------------------------------------------------

CREATE TABLE camion (

    id_camion uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    placa varchar(16) NOT NULL,

    descripcion varchar(255),

    esta_activo boolean NOT NULL DEFAULT true,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_camion_cuenta_placa UNIQUE (codigo_cuenta, placa),



    CONSTRAINT fk_camion_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta)

);



CREATE INDEX ix_camion_cuenta ON camion (codigo_cuenta);



CREATE TRIGGER trg_camion_updated_at

    BEFORE UPDATE ON camion

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE camion IS 'Flota de transporte por cuenta. POL-33.';



-- ---------------------------------------------------------------------------

-- RLS — catálogos (SELECT acotado; INSERT/UPDATE admin; DELETE solo configurador)

-- ---------------------------------------------------------------------------

ALTER TABLE proveedor ENABLE ROW LEVEL SECURITY;

ALTER TABLE cliente ENABLE ROW LEVEL SECURITY;

ALTER TABLE producto ENABLE ROW LEVEL SECURITY;

ALTER TABLE comprador ENABLE ROW LEVEL SECURITY;

ALTER TABLE planta ENABLE ROW LEVEL SECURITY;

ALTER TABLE camion ENABLE ROW LEVEL SECURITY;



-- proveedor

CREATE POLICY proveedor_select_scope

    ON proveedor FOR SELECT TO authenticated

    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));



CREATE POLICY proveedor_insert_cuenta

    ON proveedor FOR INSERT TO authenticated

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY proveedor_update_cuenta

    ON proveedor FOR UPDATE TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)

    )

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY proveedor_delete_configurador

    ON proveedor FOR DELETE TO authenticated

    USING (auth_wms_es_configurador());



-- cliente

CREATE POLICY cliente_select_scope

    ON cliente FOR SELECT TO authenticated

    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));



CREATE POLICY cliente_insert_cuenta

    ON cliente FOR INSERT TO authenticated

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY cliente_update_cuenta

    ON cliente FOR UPDATE TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)

    )

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY cliente_delete_configurador

    ON cliente FOR DELETE TO authenticated

    USING (auth_wms_es_configurador());



-- producto

CREATE POLICY producto_select_scope

    ON producto FOR SELECT TO authenticated

    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));



CREATE POLICY producto_insert_cuenta

    ON producto FOR INSERT TO authenticated

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY producto_update_cuenta

    ON producto FOR UPDATE TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)

    )

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY producto_delete_configurador

    ON producto FOR DELETE TO authenticated

    USING (auth_wms_es_configurador());



-- comprador

CREATE POLICY comprador_select_scope

    ON comprador FOR SELECT TO authenticated

    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));



CREATE POLICY comprador_insert_cuenta

    ON comprador FOR INSERT TO authenticated

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY comprador_update_cuenta

    ON comprador FOR UPDATE TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)

    )

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY comprador_delete_configurador

    ON comprador FOR DELETE TO authenticated

    USING (auth_wms_es_configurador());



-- planta

CREATE POLICY planta_select_scope

    ON planta FOR SELECT TO authenticated

    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));



CREATE POLICY planta_insert_cuenta

    ON planta FOR INSERT TO authenticated

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY planta_update_cuenta

    ON planta FOR UPDATE TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)

    )

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY planta_delete_configurador

    ON planta FOR DELETE TO authenticated

    USING (auth_wms_es_configurador());



-- camion

CREATE POLICY camion_select_scope

    ON camion FOR SELECT TO authenticated

    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));



CREATE POLICY camion_insert_cuenta

    ON camion FOR INSERT TO authenticated

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY camion_update_cuenta

    ON camion FOR UPDATE TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)

    )

    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));



CREATE POLICY camion_delete_configurador

    ON camion FOR DELETE TO authenticated

    USING (auth_wms_es_configurador());



-- GRANTs mínimos

REVOKE INSERT, UPDATE, DELETE ON proveedor FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON cliente FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON producto FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON comprador FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON planta FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON camion FROM authenticated;



GRANT SELECT, INSERT, UPDATE ON proveedor TO authenticated;

GRANT SELECT, INSERT, UPDATE ON cliente TO authenticated;

GRANT SELECT, INSERT, UPDATE ON producto TO authenticated;

GRANT SELECT, INSERT, UPDATE ON comprador TO authenticated;

GRANT SELECT, INSERT, UPDATE ON planta TO authenticated;

GRANT SELECT, INSERT, UPDATE ON camion TO authenticated;



GRANT DELETE ON proveedor TO authenticated;

GRANT DELETE ON cliente TO authenticated;

GRANT DELETE ON producto TO authenticated;

GRANT DELETE ON comprador TO authenticated;

GRANT DELETE ON planta TO authenticated;

GRANT DELETE ON camion TO authenticated;



-- ===========================================================================

-- Seed de ejemplo (comentado) — requiere cuenta ACME-01 del seed de validación

-- ===========================================================================

--

-- INSERT INTO proveedor (codigo_cuenta, codigo, razon_social)

-- VALUES ('ACME-01', 'PROV-001', 'Distribuidora Andina S.A.');

--

-- INSERT INTO cliente (codigo_cuenta, codigo, nombre)

-- VALUES ('ACME-01', 'CLI-001', 'Supermercados del Norte');

--

-- INSERT INTO producto (codigo_cuenta, sku, descripcion, unidad_medida, requiere_lote)

-- VALUES ('ACME-01', 'SKU-ARROZ-1KG', 'Arroz grano largo 1 kg', 'UN', true);

--

-- INSERT INTO comprador (codigo_cuenta, codigo, nombre)

-- VALUES ('ACME-01', 'COMP-01', 'María Compras');

--

-- INSERT INTO planta (codigo_cuenta, codigo, nombre)

-- VALUES ('ACME-01', 'PLT-01', 'Planta Procesamiento Norte');

--

-- INSERT INTO camion (codigo_cuenta, placa, descripcion)

-- VALUES ('ACME-01', 'ABC-123', 'Camión refrigerado 8 ton');


-- ========== 022_compras.sql ==========
-- POL-33 Fase 3: compras — solicitud de compra (SOL) y orden de compra (OC).

--

-- Esta estructura desbloquea POL-5 (ingreso / recepción contra OC).

-- Sin triggers de inventario (warehouse_state en migración posterior).

--

-- Mutaciones (cabeceras, líneas, cambios de estado): polaria-wms-api (NestJS, rol postgres).

-- PostgREST (authenticated): solo SELECT acotado por cuenta / bodega.

-- Ver docs/modelo-operativo-v2.md y docs/rls-politicas.md.



-- ---------------------------------------------------------------------------

-- Enums

-- ---------------------------------------------------------------------------

CREATE TYPE estado_solicitud_compra AS ENUM (

    'borrador',

    'pendiente_aprobacion',

    'aprobada',

    'rechazada',

    'convertida',

    'cancelada'

);



CREATE TYPE estado_orden_compra AS ENUM (

    'borrador',

    'emitida',

    'parcialmente_recibida',

    'recibida',

    'cerrada',

    'cancelada'

);



-- ---------------------------------------------------------------------------

-- Helpers: coherencia tenant en compras

-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION compras_validar_producto_misma_cuenta()

RETURNS trigger

LANGUAGE plpgsql

AS $$

DECLARE

    v_codigo_cuenta varchar(32);

BEGIN

    IF TG_TABLE_NAME = 'solicitud_compra_linea' THEN

        SELECT sc.codigo_cuenta

        INTO v_codigo_cuenta

        FROM solicitud_compra sc

        WHERE sc.id_solicitud_compra = NEW.id_solicitud_compra;

    ELSE

        SELECT oc.codigo_cuenta

        INTO v_codigo_cuenta

        FROM orden_compra oc

        WHERE oc.id_orden_compra = NEW.id_orden_compra;

    END IF;



    IF v_codigo_cuenta IS NULL THEN

        RAISE EXCEPTION 'documento padre no existe';

    END IF;



    IF NOT EXISTS (

        SELECT 1

        FROM producto p

        WHERE p.id_producto = NEW.id_producto

          AND p.codigo_cuenta = v_codigo_cuenta

    ) THEN

        RAISE EXCEPTION 'producto % no pertenece a la cuenta del documento', NEW.id_producto;

    END IF;



    RETURN NEW;

END;

$$;



CREATE OR REPLACE FUNCTION compras_validar_orden_compra_referencias()

RETURNS trigger

LANGUAGE plpgsql

AS $$

BEGIN

    IF NEW.id_proveedor IS NOT NULL THEN

        IF NOT EXISTS (

            SELECT 1

            FROM proveedor pr

            WHERE pr.id_proveedor = NEW.id_proveedor

              AND pr.codigo_cuenta = NEW.codigo_cuenta

        ) THEN

            RAISE EXCEPTION 'proveedor % no pertenece a la cuenta %', NEW.id_proveedor, NEW.codigo_cuenta;

        END IF;

    END IF;



    IF NEW.id_solicitud_compra IS NOT NULL THEN

        IF NOT EXISTS (

            SELECT 1

            FROM solicitud_compra sc

            WHERE sc.id_solicitud_compra = NEW.id_solicitud_compra

              AND sc.codigo_cuenta = NEW.codigo_cuenta

              AND sc.id_bodega = NEW.id_bodega

        ) THEN

            RAISE EXCEPTION 'solicitud % no coincide con cuenta/bodega de la OC', NEW.id_solicitud_compra;

        END IF;

    END IF;



    RETURN NEW;

END;

$$;



-- ---------------------------------------------------------------------------

-- solicitud_compra (SOL) — alcance C+B

-- ---------------------------------------------------------------------------

CREATE TABLE solicitud_compra (

    id_solicitud_compra uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    id_bodega uuid NOT NULL,

    codigo varchar(32) NOT NULL,

    estado estado_solicitud_compra NOT NULL DEFAULT 'borrador',

    id_solicitante uuid NOT NULL,

    observaciones text,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_solicitud_compra_cuenta_codigo UNIQUE (codigo_cuenta, codigo),



    CONSTRAINT fk_solicitud_compra_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta),



    CONSTRAINT fk_solicitud_compra_bodega

        FOREIGN KEY (id_bodega)

        REFERENCES bodega (id_bodega),



    CONSTRAINT fk_solicitud_compra_solicitante

        FOREIGN KEY (id_solicitante)

        REFERENCES usuario (id_usuario)

);



CREATE INDEX ix_solicitud_compra_cuenta ON solicitud_compra (codigo_cuenta);

CREATE INDEX ix_solicitud_compra_bodega ON solicitud_compra (id_bodega);

CREATE INDEX ix_solicitud_compra_estado ON solicitud_compra (codigo_cuenta, estado);

CREATE INDEX ix_solicitud_compra_solicitante ON solicitud_compra (id_solicitante);



CREATE TRIGGER trg_solicitud_compra_sync_cuenta

    BEFORE INSERT OR UPDATE OF id_bodega ON solicitud_compra

    FOR EACH ROW

    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();



CREATE TRIGGER trg_solicitud_compra_updated_at

    BEFORE UPDATE ON solicitud_compra

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE solicitud_compra IS

    'Solicitud de compra (SOL). Desbloquea flujo POL-5 vía orden_compra. POL-33.';



-- ---------------------------------------------------------------------------

-- solicitud_compra_linea

-- ---------------------------------------------------------------------------

CREATE TABLE solicitud_compra_linea (

    id_linea_solicitud_compra uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    id_solicitud_compra uuid NOT NULL,

    id_producto uuid NOT NULL,

    cantidad numeric(18, 4) NOT NULL,



    CONSTRAINT chk_solicitud_linea_cantidad_positiva CHECK (cantidad > 0),



    CONSTRAINT fk_solicitud_linea_solicitud

        FOREIGN KEY (id_solicitud_compra)

        REFERENCES solicitud_compra (id_solicitud_compra)

        ON DELETE CASCADE,



    CONSTRAINT fk_solicitud_linea_producto

        FOREIGN KEY (id_producto)

        REFERENCES producto (id_producto)

);



CREATE INDEX ix_solicitud_linea_solicitud ON solicitud_compra_linea (id_solicitud_compra);

CREATE INDEX ix_solicitud_linea_producto ON solicitud_compra_linea (id_producto);



CREATE TRIGGER trg_solicitud_linea_validar_producto

    BEFORE INSERT OR UPDATE OF id_solicitud_compra, id_producto ON solicitud_compra_linea

    FOR EACH ROW

    EXECUTE FUNCTION compras_validar_producto_misma_cuenta();



COMMENT ON TABLE solicitud_compra_linea IS

    'Líneas de SOL. Mutaciones solo backend (NestJS). POL-33.';



-- ---------------------------------------------------------------------------

-- orden_compra (OC) — alcance C+B

-- ---------------------------------------------------------------------------

CREATE TABLE orden_compra (

    id_orden_compra uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    id_bodega uuid NOT NULL,

    id_proveedor uuid NOT NULL,

    id_solicitud_compra uuid,

    codigo varchar(32) NOT NULL,

    estado estado_orden_compra NOT NULL DEFAULT 'borrador',

    fecha_emision date NOT NULL DEFAULT CURRENT_DATE,

    observaciones text,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_orden_compra_cuenta_codigo UNIQUE (codigo_cuenta, codigo),



    CONSTRAINT fk_orden_compra_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta),



    CONSTRAINT fk_orden_compra_bodega

        FOREIGN KEY (id_bodega)

        REFERENCES bodega (id_bodega),



    CONSTRAINT fk_orden_compra_proveedor

        FOREIGN KEY (id_proveedor)

        REFERENCES proveedor (id_proveedor),



    CONSTRAINT fk_orden_compra_solicitud

        FOREIGN KEY (id_solicitud_compra)

        REFERENCES solicitud_compra (id_solicitud_compra)

        ON DELETE SET NULL

);



CREATE INDEX ix_orden_compra_cuenta ON orden_compra (codigo_cuenta);

CREATE INDEX ix_orden_compra_bodega ON orden_compra (id_bodega);

CREATE INDEX ix_orden_compra_proveedor ON orden_compra (id_proveedor);

CREATE INDEX ix_orden_compra_estado ON orden_compra (codigo_cuenta, estado);

CREATE INDEX ix_orden_compra_solicitud ON orden_compra (id_solicitud_compra);



CREATE TRIGGER trg_orden_compra_sync_cuenta

    BEFORE INSERT OR UPDATE OF id_bodega ON orden_compra

    FOR EACH ROW

    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();



CREATE TRIGGER trg_orden_compra_validar_refs

    BEFORE INSERT OR UPDATE OF codigo_cuenta, id_bodega, id_proveedor, id_solicitud_compra

        ON orden_compra

    FOR EACH ROW

    EXECUTE FUNCTION compras_validar_orden_compra_referencias();



CREATE TRIGGER trg_orden_compra_updated_at

    BEFORE UPDATE ON orden_compra

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE orden_compra IS

    'Orden de compra (OC). Base para ingreso POL-5 (recepción). POL-33.';



-- ---------------------------------------------------------------------------

-- orden_compra_linea

-- ---------------------------------------------------------------------------

CREATE TABLE orden_compra_linea (

    id_linea_orden_compra uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    id_orden_compra uuid NOT NULL,

    id_producto uuid NOT NULL,

    cantidad numeric(18, 4) NOT NULL,

    precio_unitario numeric(18, 4) NOT NULL DEFAULT 0,

    cantidad_recibida numeric(18, 4) NOT NULL DEFAULT 0,



    CONSTRAINT chk_orden_linea_cantidad_positiva CHECK (cantidad > 0),

    CONSTRAINT chk_orden_linea_precio_no_negativo CHECK (precio_unitario >= 0),

    CONSTRAINT chk_orden_linea_recibida_no_negativa CHECK (cantidad_recibida >= 0),

    CONSTRAINT chk_orden_linea_recibida_max CHECK (cantidad_recibida <= cantidad),



    CONSTRAINT fk_orden_linea_orden

        FOREIGN KEY (id_orden_compra)

        REFERENCES orden_compra (id_orden_compra)

        ON DELETE CASCADE,



    CONSTRAINT fk_orden_linea_producto

        FOREIGN KEY (id_producto)

        REFERENCES producto (id_producto)

);



CREATE INDEX ix_orden_linea_orden ON orden_compra_linea (id_orden_compra);

CREATE INDEX ix_orden_linea_producto ON orden_compra_linea (id_producto);



CREATE TRIGGER trg_orden_linea_validar_producto

    BEFORE INSERT OR UPDATE OF id_orden_compra, id_producto ON orden_compra_linea

    FOR EACH ROW

    EXECUTE FUNCTION compras_validar_producto_misma_cuenta();



COMMENT ON TABLE orden_compra_linea IS

    'Líneas de OC. cantidad_recibida alimenta POL-5; mutaciones solo backend. POL-33.';



-- ---------------------------------------------------------------------------

-- RLS — SELECT acotado; sin INSERT/UPDATE/DELETE vía PostgREST

-- ---------------------------------------------------------------------------

ALTER TABLE solicitud_compra ENABLE ROW LEVEL SECURITY;

ALTER TABLE solicitud_compra_linea ENABLE ROW LEVEL SECURITY;

ALTER TABLE orden_compra ENABLE ROW LEVEL SECURITY;

ALTER TABLE orden_compra_linea ENABLE ROW LEVEL SECURITY;



CREATE POLICY solicitud_compra_select_scope

    ON solicitud_compra

    FOR SELECT

    TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND auth_wms_puede_ver_bodega(id_bodega)

    );



CREATE POLICY solicitud_compra_linea_select_scope

    ON solicitud_compra_linea

    FOR SELECT

    TO authenticated

    USING (

        EXISTS (

            SELECT 1

            FROM solicitud_compra sc

            WHERE sc.id_solicitud_compra = solicitud_compra_linea.id_solicitud_compra

              AND auth_wms_puede_ver_cuenta(sc.codigo_cuenta)

              AND auth_wms_puede_ver_bodega(sc.id_bodega)

        )

    );



CREATE POLICY orden_compra_select_scope

    ON orden_compra

    FOR SELECT

    TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND auth_wms_puede_ver_bodega(id_bodega)

    );



CREATE POLICY orden_compra_linea_select_scope

    ON orden_compra_linea

    FOR SELECT

    TO authenticated

    USING (

        EXISTS (

            SELECT 1

            FROM orden_compra oc

            WHERE oc.id_orden_compra = orden_compra_linea.id_orden_compra

              AND auth_wms_puede_ver_cuenta(oc.codigo_cuenta)

              AND auth_wms_puede_ver_bodega(oc.id_bodega)

        )

    );



REVOKE INSERT, UPDATE, DELETE ON solicitud_compra FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON solicitud_compra_linea FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON orden_compra FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON orden_compra_linea FROM authenticated;



GRANT SELECT ON solicitud_compra TO authenticated;

GRANT SELECT ON solicitud_compra_linea TO authenticated;

GRANT SELECT ON orden_compra TO authenticated;

GRANT SELECT ON orden_compra_linea TO authenticated;


-- ========== 023_warehouse_state.sql ==========
-- POL-33 Fase 4: warehouse_state — inventario en vivo / mapa de bodega.

--

-- Crítico para POL-6 (mapa tiempo real vía Supabase Realtime).

-- Patrón sensible (018_rls_write_policies.sql): REVOKE escritura a authenticated;

-- SELECT acotado por bodega; mutaciones solo backend (postgres / service role).

-- Complementa docs/rls-politicas.md § tablas sensibles (warehouse_state).

--

-- Sin triggers de movimiento_inventario (migración posterior).



-- ---------------------------------------------------------------------------

-- lote — mínimo para FK nullable en warehouse_state (trazabilidad V2.1)

-- ---------------------------------------------------------------------------

CREATE TABLE lote (

    id_lote uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    id_bodega uuid NOT NULL,

    id_producto uuid NOT NULL,

    codigo_lote varchar(64) NOT NULL,

    fecha_vencimiento date,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_lote_bodega_producto_codigo UNIQUE (id_bodega, id_producto, codigo_lote),



    CONSTRAINT fk_lote_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta),



    CONSTRAINT fk_lote_bodega

        FOREIGN KEY (id_bodega)

        REFERENCES bodega (id_bodega),



    CONSTRAINT fk_lote_producto

        FOREIGN KEY (id_producto)

        REFERENCES producto (id_producto)

);



CREATE INDEX ix_lote_cuenta ON lote (codigo_cuenta);

CREATE INDEX ix_lote_bodega ON lote (id_bodega);

CREATE INDEX ix_lote_producto ON lote (id_producto);



CREATE TRIGGER trg_lote_sync_cuenta

    BEFORE INSERT OR UPDATE OF id_bodega ON lote

    FOR EACH ROW

    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();



CREATE TRIGGER trg_lote_updated_at

    BEFORE UPDATE ON lote

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE lote IS

    'Lote mínimo para warehouse_state.id_lote. Ampliación (estado_lote) en migración futura. POL-33.';



-- ---------------------------------------------------------------------------

-- Helpers: coherencia warehouse_state ↔ bodega / ubicación / producto / lote

-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION warehouse_state_validar_referencias()

RETURNS trigger

LANGUAGE plpgsql

AS $$

BEGIN

    IF NOT EXISTS (

        SELECT 1

        FROM ubicacion u

        WHERE u.id_ubicacion = NEW.id_ubicacion

          AND u.id_bodega = NEW.id_bodega

          AND u.codigo_cuenta = NEW.codigo_cuenta

    ) THEN

        RAISE EXCEPTION 'ubicacion % no pertenece a bodega/cuenta del stock', NEW.id_ubicacion;

    END IF;



    IF NOT EXISTS (

        SELECT 1

        FROM producto p

        WHERE p.id_producto = NEW.id_producto

          AND p.codigo_cuenta = NEW.codigo_cuenta

    ) THEN

        RAISE EXCEPTION 'producto % no pertenece a la cuenta %', NEW.id_producto, NEW.codigo_cuenta;

    END IF;



    IF NEW.id_lote IS NOT NULL THEN

        IF NOT EXISTS (

            SELECT 1

            FROM lote l

            WHERE l.id_lote = NEW.id_lote

              AND l.id_bodega = NEW.id_bodega

              AND l.id_producto = NEW.id_producto

              AND l.codigo_cuenta = NEW.codigo_cuenta

        ) THEN

            RAISE EXCEPTION 'lote % no coincide con bodega/producto/cuenta', NEW.id_lote;

        END IF;

    END IF;



    IF NEW.locked_by IS NOT NULL AND NEW.locked_at IS NULL THEN

        RAISE EXCEPTION 'locked_at requerido cuando locked_by está definido';

    END IF;



    IF NEW.locked_by IS NULL AND NEW.locked_at IS NOT NULL THEN

        RAISE EXCEPTION 'locked_by requerido cuando locked_at está definido';

    END IF;



    RETURN NEW;

END;

$$;



CREATE OR REPLACE FUNCTION warehouse_state_bump_version()

RETURNS trigger

LANGUAGE plpgsql

AS $$

BEGIN

    NEW.version := OLD.version + 1;

    RETURN NEW;

END;

$$;



-- ---------------------------------------------------------------------------

-- warehouse_state — foto de stock por ubicación × producto × lote (opcional)

-- ---------------------------------------------------------------------------

CREATE TABLE warehouse_state (

    id_warehouse_state uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    id_bodega uuid NOT NULL,

    id_ubicacion uuid NOT NULL,

    id_producto uuid NOT NULL,

    id_lote uuid,

    cantidad numeric(18, 4) NOT NULL,

    temperatura numeric(8, 2),

    locked_by uuid,

    locked_at timestamptz,

    version integer NOT NULL DEFAULT 1,

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT chk_warehouse_state_cantidad_no_negativa CHECK (cantidad >= 0),



    CONSTRAINT uq_warehouse_state_slot UNIQUE NULLS NOT DISTINCT (

        id_ubicacion,

        id_producto,

        id_lote

    ),



    CONSTRAINT fk_warehouse_state_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta),



    CONSTRAINT fk_warehouse_state_bodega

        FOREIGN KEY (id_bodega)

        REFERENCES bodega (id_bodega),



    CONSTRAINT fk_warehouse_state_ubicacion

        FOREIGN KEY (id_ubicacion)

        REFERENCES ubicacion (id_ubicacion),



    CONSTRAINT fk_warehouse_state_producto

        FOREIGN KEY (id_producto)

        REFERENCES producto (id_producto),



    CONSTRAINT fk_warehouse_state_lote

        FOREIGN KEY (id_lote)

        REFERENCES lote (id_lote),



    CONSTRAINT fk_warehouse_state_locked_by

        FOREIGN KEY (locked_by)

        REFERENCES usuario (id_usuario)

);



CREATE INDEX ix_warehouse_state_bodega ON warehouse_state (id_bodega);

CREATE INDEX ix_warehouse_state_ubicacion ON warehouse_state (id_ubicacion);

CREATE INDEX ix_warehouse_state_producto ON warehouse_state (id_producto);

CREATE INDEX ix_warehouse_state_cuenta ON warehouse_state (codigo_cuenta);

CREATE INDEX ix_warehouse_state_lote ON warehouse_state (id_lote)

    WHERE id_lote IS NOT NULL;



CREATE TRIGGER trg_warehouse_state_sync_cuenta

    BEFORE INSERT OR UPDATE OF id_bodega ON warehouse_state

    FOR EACH ROW

    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();



CREATE TRIGGER trg_warehouse_state_validar_refs

    BEFORE INSERT OR UPDATE OF codigo_cuenta, id_bodega, id_ubicacion, id_producto, id_lote, locked_by, locked_at

        ON warehouse_state

    FOR EACH ROW

    EXECUTE FUNCTION warehouse_state_validar_referencias();



CREATE TRIGGER trg_warehouse_state_bump_version

    BEFORE UPDATE ON warehouse_state

    FOR EACH ROW

    EXECUTE FUNCTION warehouse_state_bump_version();



CREATE TRIGGER trg_warehouse_state_updated_at

    BEFORE UPDATE ON warehouse_state

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE warehouse_state IS

    'Stock en vivo por slot (ubicación × producto × lote). Lectura Realtime POL-6; escritura solo backend. POL-33.';



COMMENT ON COLUMN warehouse_state.version IS

    'Optimistic locking: backend debe enviar version esperada en UPDATE.';



-- ---------------------------------------------------------------------------

-- RLS — lote y warehouse_state: solo lectura vía PostgREST

-- ---------------------------------------------------------------------------

ALTER TABLE lote ENABLE ROW LEVEL SECURITY;

ALTER TABLE warehouse_state ENABLE ROW LEVEL SECURITY;



CREATE POLICY lote_select_scope

    ON lote

    FOR SELECT

    TO authenticated

    USING (auth_wms_puede_ver_bodega(id_bodega));



CREATE POLICY warehouse_state_select_scope

    ON warehouse_state

    FOR SELECT

    TO authenticated

    USING (auth_wms_puede_ver_bodega(id_bodega));



REVOKE INSERT, UPDATE, DELETE ON lote FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON warehouse_state FROM authenticated;



GRANT SELECT ON lote TO authenticated;

GRANT SELECT ON warehouse_state TO authenticated;



-- ---------------------------------------------------------------------------

-- Supabase Realtime (POL-6 mapa). Omitir si la publicación no existe.

-- ---------------------------------------------------------------------------

DO $$

BEGIN

    IF EXISTS (

        SELECT 1

        FROM pg_publication

        WHERE pubname = 'supabase_realtime'

    ) THEN

        ALTER PUBLICATION supabase_realtime ADD TABLE warehouse_state;

    ELSE

        RAISE NOTICE

            'Publicación supabase_realtime no encontrada. '

            'Para POL-6 ejecutar manualmente: '

            'ALTER PUBLICATION supabase_realtime ADD TABLE warehouse_state;';

    END IF;

EXCEPTION

    WHEN duplicate_object THEN

        RAISE NOTICE 'warehouse_state ya está en supabase_realtime';

END;

$$;


-- ========== 024_movimientos.sql ==========
-- POL-33 Fase 5: movimiento_inventario — historial append-only de trazabilidad.
--
-- Depende de warehouse_state (023). Sin triggers automáticos a stock en vivo;
-- el backend (POL-5+) ejecutará transacciones atómicas movimiento + warehouse_state.
--
-- RLS (docs/modelo-operativo-v2.md): SELECT acotado por bodega; escritura **B** (solo backend).
-- Complementa docs/rls-politicas.md § tablas sensibles (movimientos).

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE tipo_movimiento AS ENUM (
    'entrada',
    'salida',
    'recepcion',
    'despacho',
    'transferencia',
    'ajuste_positivo',
    'ajuste_negativo',
    'merma',
    'reserva',
    'liberacion_reserva',
    'consumo_ot',
    'produccion_ot'
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION movimiento_inventario_validar_referencias()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id_ubicacion_origen IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM ubicacion u
            WHERE u.id_ubicacion = NEW.id_ubicacion_origen
              AND u.id_bodega = NEW.id_bodega
              AND u.codigo_cuenta = NEW.codigo_cuenta
        ) THEN
            RAISE EXCEPTION 'ubicacion origen % no pertenece a bodega/cuenta', NEW.id_ubicacion_origen;
        END IF;
    END IF;

    IF NEW.id_ubicacion_destino IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM ubicacion u
            WHERE u.id_ubicacion = NEW.id_ubicacion_destino
              AND u.id_bodega = NEW.id_bodega
              AND u.codigo_cuenta = NEW.codigo_cuenta
        ) THEN
            RAISE EXCEPTION 'ubicacion destino % no pertenece a bodega/cuenta', NEW.id_ubicacion_destino;
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM producto p
        WHERE p.id_producto = NEW.id_producto
          AND p.codigo_cuenta = NEW.codigo_cuenta
    ) THEN
        RAISE EXCEPTION 'producto % no pertenece a la cuenta %', NEW.id_producto, NEW.codigo_cuenta;
    END IF;

    IF NEW.id_lote IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM lote l
            WHERE l.id_lote = NEW.id_lote
              AND l.id_bodega = NEW.id_bodega
              AND l.id_producto = NEW.id_producto
              AND l.codigo_cuenta = NEW.codigo_cuenta
        ) THEN
            RAISE EXCEPTION 'lote % no coincide con bodega/producto/cuenta', NEW.id_lote;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION movimiento_inventario_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'movimiento_inventario es append-only; no UPDATE ni DELETE';
END;
$$;

-- ---------------------------------------------------------------------------
-- movimiento_inventario — ledger de inventario (sin updated_at)
-- ---------------------------------------------------------------------------
CREATE TABLE movimiento_inventario (
    id_movimiento_inventario uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    id_ubicacion_origen uuid,
    id_ubicacion_destino uuid,
    id_producto uuid NOT NULL,
    id_lote uuid,
    cantidad numeric(18, 4) NOT NULL,
    tipo_movimiento tipo_movimiento NOT NULL,
    id_usuario uuid NOT NULL,
    id_referencia uuid,
    tipo_referencia varchar(32),
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_movimiento_cantidad_positiva CHECK (cantidad > 0),

    CONSTRAINT chk_movimiento_ubicacion_presente CHECK (
        id_ubicacion_origen IS NOT NULL
        OR id_ubicacion_destino IS NOT NULL
    ),

    CONSTRAINT chk_movimiento_referencia_par CHECK (
        (tipo_referencia IS NULL AND id_referencia IS NULL)
        OR (tipo_referencia IS NOT NULL AND id_referencia IS NOT NULL)
    ),

    CONSTRAINT chk_movimiento_tipo_referencia CHECK (
        tipo_referencia IS NULL
        OR tipo_referencia IN (
            'orden_compra',
            'orden_trabajo',
            'orden_venta',
            'solicitud_compra',
            'manual'
        )
    ),

    CONSTRAINT fk_movimiento_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_movimiento_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_movimiento_ubicacion_origen
        FOREIGN KEY (id_ubicacion_origen)
        REFERENCES ubicacion (id_ubicacion),

    CONSTRAINT fk_movimiento_ubicacion_destino
        FOREIGN KEY (id_ubicacion_destino)
        REFERENCES ubicacion (id_ubicacion),

    CONSTRAINT fk_movimiento_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto),

    CONSTRAINT fk_movimiento_lote
        FOREIGN KEY (id_lote)
        REFERENCES lote (id_lote),

    CONSTRAINT fk_movimiento_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_movimiento_cuenta ON movimiento_inventario (codigo_cuenta);
CREATE INDEX ix_movimiento_bodega ON movimiento_inventario (id_bodega);
CREATE INDEX ix_movimiento_bodega_created ON movimiento_inventario (id_bodega, created_at DESC);
CREATE INDEX ix_movimiento_producto ON movimiento_inventario (id_producto);
CREATE INDEX ix_movimiento_lote ON movimiento_inventario (id_lote)
    WHERE id_lote IS NOT NULL;
CREATE INDEX ix_movimiento_tipo ON movimiento_inventario (id_bodega, tipo_movimiento);
CREATE INDEX ix_movimiento_referencia ON movimiento_inventario (tipo_referencia, id_referencia)
    WHERE id_referencia IS NOT NULL;
CREATE INDEX ix_movimiento_usuario ON movimiento_inventario (id_usuario);

CREATE TRIGGER trg_movimiento_sync_cuenta
    BEFORE INSERT ON movimiento_inventario
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_movimiento_validar_refs
    BEFORE INSERT ON movimiento_inventario
    FOR EACH ROW
    EXECUTE FUNCTION movimiento_inventario_validar_referencias();

CREATE TRIGGER trg_movimiento_append_only
    BEFORE UPDATE OR DELETE ON movimiento_inventario
    FOR EACH ROW
    EXECUTE FUNCTION movimiento_inventario_append_only();

COMMENT ON TABLE movimiento_inventario IS
    'Historial append-only de movimientos de inventario. Escritura solo backend. POL-33.';

COMMENT ON COLUMN movimiento_inventario.tipo_referencia IS
    'Documento origen: orden_compra | orden_trabajo | orden_venta | solicitud_compra | manual';

COMMENT ON COLUMN movimiento_inventario.metadata IS
    'Payload extensible (motivo ajuste, temperatura, id línea OC, etc.)';

-- ---------------------------------------------------------------------------
-- RLS — SELECT acotado (doc V2); escritura solo postgres / service role
-- ---------------------------------------------------------------------------
ALTER TABLE movimiento_inventario ENABLE ROW LEVEL SECURITY;

CREATE POLICY movimiento_inventario_select_scope
    ON movimiento_inventario
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

REVOKE INSERT, UPDATE, DELETE ON movimiento_inventario FROM authenticated;

GRANT SELECT ON movimiento_inventario TO authenticated;

-- Decisión documentada: SELECT vía PostgREST para operadores con alcance de bodega
-- (historial en UI). INSERT/UPDATE/DELETE revocados; el backend NestJS persiste
-- movimientos en transacción con warehouse_state (POL-5+).

-- ========== 025_contadores.sql ==========
-- POL-33 Fase 6a: contador — secuencias numéricas por cuenta / bodega.

--

-- Alcance: codigo_cuenta + id_bodega nullable (NULL = secuencia a nivel cuenta).

-- docs/modelo-operativo-v2.md: sin SELECT PostgREST (**—**); escritura **B** (solo backend).

-- Complementa docs/rls-politicas.md § tablas sensibles.



-- ---------------------------------------------------------------------------

-- contador

-- ---------------------------------------------------------------------------

CREATE TABLE contador (

    id_contador uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    id_bodega uuid,

    clave varchar(32) NOT NULL,

    valor bigint NOT NULL DEFAULT 0,

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_contador_cuenta_bodega_clave UNIQUE NULLS NOT DISTINCT (

        codigo_cuenta,

        id_bodega,

        clave

    ),



    CONSTRAINT chk_contador_valor_no_negativo CHECK (valor >= 0),



    CONSTRAINT fk_contador_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta),



    CONSTRAINT fk_contador_bodega

        FOREIGN KEY (id_bodega)

        REFERENCES bodega (id_bodega)

);



CREATE INDEX ix_contador_cuenta ON contador (codigo_cuenta);

CREATE INDEX ix_contador_bodega ON contador (id_bodega)

    WHERE id_bodega IS NOT NULL;



CREATE TRIGGER trg_contador_updated_at

    BEFORE UPDATE ON contador

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE contador IS

    'Secuencias atómicas (OC, SOL, OT, …). id_bodega NULL = ámbito cuenta. Solo backend. POL-33.';



COMMENT ON COLUMN contador.clave IS

    'Identificador lógico: OC, SOL, OT, OV, lote, movimiento_inventario, etc.';



-- PK surrogate: id_bodega nullable impide PK compuesta (codigo_cuenta, id_bodega, clave).

-- Unicidad de negocio vía uq_contador_cuenta_bodega_clave (NULLS NOT DISTINCT).



-- ---------------------------------------------------------------------------

-- RLS — sin exposición a authenticated (doc V2: SELECT **—**)

-- ---------------------------------------------------------------------------

ALTER TABLE contador ENABLE ROW LEVEL SECURITY;



REVOKE ALL ON contador FROM authenticated;



-- Sin políticas para authenticated: acceso exclusivo vía postgres / service role (backend).


-- ========== 026_auditoria_operativa.sql ==========
-- POL-33 Fase 6b: auditoria_operacion — registro append-only de acciones WMS.

--

-- docs/modelo-operativo-v2.md: SELECT acotado; INSERT/UPDATE/DELETE **B** (solo backend).

-- Complementa docs/rls-politicas.md § tablas sensibles.



-- ---------------------------------------------------------------------------

-- Enum

-- ---------------------------------------------------------------------------

CREATE TYPE tipo_auditoria AS ENUM (

    'creacion',

    'actualizacion',

    'eliminacion',

    'cambio_estado',

    'movimiento_inventario',

    'acceso_denegado'

);



-- ---------------------------------------------------------------------------

-- auditoria_operacion

-- ---------------------------------------------------------------------------

CREATE TABLE auditoria_operacion (

    id_auditoria uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    id_bodega uuid,

    id_usuario uuid,

    accion tipo_auditoria NOT NULL,

    entidad varchar(64) NOT NULL,

    entidad_id uuid,

    payload jsonb,

    created_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT fk_auditoria_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta),



    CONSTRAINT fk_auditoria_bodega

        FOREIGN KEY (id_bodega)

        REFERENCES bodega (id_bodega),



    CONSTRAINT fk_auditoria_usuario

        FOREIGN KEY (id_usuario)

        REFERENCES usuario (id_usuario)

);



CREATE INDEX ix_auditoria_cuenta ON auditoria_operacion (codigo_cuenta);

CREATE INDEX ix_auditoria_cuenta_created ON auditoria_operacion (codigo_cuenta, created_at DESC);

CREATE INDEX ix_auditoria_bodega ON auditoria_operacion (id_bodega)

    WHERE id_bodega IS NOT NULL;

CREATE INDEX ix_auditoria_usuario ON auditoria_operacion (id_usuario)

    WHERE id_usuario IS NOT NULL;

CREATE INDEX ix_auditoria_entidad ON auditoria_operacion (entidad, entidad_id);

CREATE INDEX ix_auditoria_accion ON auditoria_operacion (codigo_cuenta, accion);



CREATE OR REPLACE FUNCTION auditoria_operacion_append_only()

RETURNS trigger

LANGUAGE plpgsql

AS $$

BEGIN

    RAISE EXCEPTION 'auditoria_operacion es append-only; no UPDATE ni DELETE';

END;

$$;



CREATE TRIGGER trg_auditoria_append_only

    BEFORE UPDATE OR DELETE ON auditoria_operacion

    FOR EACH ROW

    EXECUTE FUNCTION auditoria_operacion_append_only();



COMMENT ON TABLE auditoria_operacion IS

    'Auditoría operativa append-only. INSERT solo backend; lectura admin/configurador. POL-33.';



COMMENT ON COLUMN auditoria_operacion.id_bodega IS

    'NULL = evento a nivel cuenta (sin bodega específica).';



COMMENT ON COLUMN auditoria_operacion.payload IS

    'Detalle JSON: estados anterior/nuevo, IP, ids relacionados, etc.';



-- ---------------------------------------------------------------------------

-- RLS — SELECT admin/configurador por cuenta; escritura solo backend

-- ---------------------------------------------------------------------------

ALTER TABLE auditoria_operacion ENABLE ROW LEVEL SECURITY;



CREATE POLICY auditoria_operacion_select_admin

    ON auditoria_operacion

    FOR SELECT

    TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND (

            auth_wms_es_configurador()

            OR (auth_wms_usuario_actual()).id_rol = 'administrador_cuenta'

        )

        AND (

            id_bodega IS NULL

            OR auth_wms_puede_ver_bodega(id_bodega)

        )

    );



REVOKE INSERT, UPDATE, DELETE ON auditoria_operacion FROM authenticated;



GRANT SELECT ON auditoria_operacion TO authenticated;



-- INSERT solo backend (postgres). Operadores de bodega no ven auditoría vía PostgREST.


-- ========== 027_procesamiento.sql ==========
-- POL-33 Fase 7a: orden_trabajo (OT) — procesamiento en bodega.
--
-- Roles operario / procesador / jefe_bodega (wms_rol). Cola operativa: POL-42 futuro.
-- Mutaciones y cambios de estado: polaria-wms-api (NestJS, rol postgres).
-- PostgREST (authenticated): solo SELECT acotado por cuenta / bodega.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE estado_orden_trabajo AS ENUM (
    'planificada',
    'en_proceso',
    'pausada',
    'completada',
    'cancelada'
);

CREATE TYPE tipo_orden_trabajo AS ENUM (
    'picking',
    'merma',
    'transformacion',
    'reabasto',
    'conteo',
    'otro'
);

CREATE TYPE tipo_linea_ot AS ENUM (
    'entrada',
    'salida',
    'subproducto'
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION procesamiento_validar_linea_ot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_codigo_cuenta varchar(32);
    v_id_bodega uuid;
BEGIN
    SELECT ot.codigo_cuenta, ot.id_bodega
    INTO v_codigo_cuenta, v_id_bodega
    FROM orden_trabajo ot
    WHERE ot.id_orden_trabajo = NEW.id_orden_trabajo;

    IF v_codigo_cuenta IS NULL THEN
        RAISE EXCEPTION 'orden_trabajo % no existe', NEW.id_orden_trabajo;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM producto p
        WHERE p.id_producto = NEW.id_producto
          AND p.codigo_cuenta = v_codigo_cuenta
    ) THEN
        RAISE EXCEPTION 'producto % no pertenece a la cuenta del OT', NEW.id_producto;
    END IF;

    IF NEW.id_ubicacion IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM ubicacion u
            WHERE u.id_ubicacion = NEW.id_ubicacion
              AND u.id_bodega = v_id_bodega
              AND u.codigo_cuenta = v_codigo_cuenta
        ) THEN
            RAISE EXCEPTION 'ubicacion % no pertenece a la bodega del OT', NEW.id_ubicacion;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- orden_trabajo (OT) — alcance C+B
-- ---------------------------------------------------------------------------
CREATE TABLE orden_trabajo (
    id_orden_trabajo uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid NOT NULL,
    codigo varchar(32) NOT NULL,
    estado estado_orden_trabajo NOT NULL DEFAULT 'planificada',
    tipo tipo_orden_trabajo NOT NULL DEFAULT 'otro',
    id_asignado uuid,
    observaciones text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_orden_trabajo_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_orden_trabajo_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_orden_trabajo_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_orden_trabajo_asignado
        FOREIGN KEY (id_asignado)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_orden_trabajo_cuenta ON orden_trabajo (codigo_cuenta);
CREATE INDEX ix_orden_trabajo_bodega ON orden_trabajo (id_bodega);
CREATE INDEX ix_orden_trabajo_bodega_estado ON orden_trabajo (id_bodega, estado);
CREATE INDEX ix_orden_trabajo_cola ON orden_trabajo (id_bodega, estado, tipo, created_at)
    WHERE estado IN ('planificada', 'en_proceso', 'pausada');
CREATE INDEX ix_orden_trabajo_asignado ON orden_trabajo (id_asignado)
    WHERE id_asignado IS NOT NULL;

CREATE TRIGGER trg_orden_trabajo_sync_cuenta
    BEFORE INSERT OR UPDATE OF id_bodega ON orden_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();

CREATE TRIGGER trg_orden_trabajo_updated_at
    BEFORE UPDATE ON orden_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE orden_trabajo IS
    'Orden de trabajo (OT). Cola operativa POL-42. Mutaciones solo backend. POL-33.';

-- ---------------------------------------------------------------------------
-- orden_trabajo_linea
-- ---------------------------------------------------------------------------
CREATE TABLE orden_trabajo_linea (
    id_linea_orden_trabajo uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden_trabajo uuid NOT NULL,
    id_producto uuid NOT NULL,
    id_ubicacion uuid,
    tipo_linea tipo_linea_ot NOT NULL,
    cantidad numeric(18, 4) NOT NULL,

    CONSTRAINT chk_ot_linea_cantidad_positiva CHECK (cantidad > 0),

    CONSTRAINT fk_ot_linea_orden
        FOREIGN KEY (id_orden_trabajo)
        REFERENCES orden_trabajo (id_orden_trabajo)
        ON DELETE CASCADE,

    CONSTRAINT fk_ot_linea_producto
        FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto),

    CONSTRAINT fk_ot_linea_ubicacion
        FOREIGN KEY (id_ubicacion)
        REFERENCES ubicacion (id_ubicacion)
);

CREATE INDEX ix_ot_linea_orden ON orden_trabajo_linea (id_orden_trabajo);
CREATE INDEX ix_ot_linea_producto ON orden_trabajo_linea (id_producto);
CREATE INDEX ix_ot_linea_ubicacion ON orden_trabajo_linea (id_ubicacion)
    WHERE id_ubicacion IS NOT NULL;

CREATE TRIGGER trg_ot_linea_validar
    BEFORE INSERT OR UPDATE OF id_orden_trabajo, id_producto, id_ubicacion
        ON orden_trabajo_linea
    FOR EACH ROW
    EXECUTE FUNCTION procesamiento_validar_linea_ot();

COMMENT ON TABLE orden_trabajo_linea IS
    'Líneas de OT (entrada/salida/subproducto). Mutaciones solo backend. POL-33.';

-- ---------------------------------------------------------------------------
-- RLS — SELECT acotado; cambios de estado solo backend
-- ---------------------------------------------------------------------------
ALTER TABLE orden_trabajo ENABLE ROW LEVEL SECURITY;
ALTER TABLE orden_trabajo_linea ENABLE ROW LEVEL SECURITY;

CREATE POLICY orden_trabajo_select_scope
    ON orden_trabajo
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_ver_bodega(id_bodega)
    );

CREATE POLICY orden_trabajo_linea_select_scope
    ON orden_trabajo_linea
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM orden_trabajo ot
            WHERE ot.id_orden_trabajo = orden_trabajo_linea.id_orden_trabajo
              AND auth_wms_puede_ver_cuenta(ot.codigo_cuenta)
              AND auth_wms_puede_ver_bodega(ot.id_bodega)
        )
    );

REVOKE INSERT, UPDATE, DELETE ON orden_trabajo FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON orden_trabajo_linea FROM authenticated;

GRANT SELECT ON orden_trabajo TO authenticated;
GRANT SELECT ON orden_trabajo_linea TO authenticated;

-- ========== 028_ventas.sql ==========
-- POL-33 Fase 7b: orden_venta (OV) — despacho / ventas.

--

-- Mutaciones y cambios de estado: polaria-wms-api (NestJS, rol postgres).

-- PostgREST (authenticated): solo SELECT acotado por cuenta / bodega origen.

-- Índices de cola operativa preparados para POL-42 futuro.



-- ---------------------------------------------------------------------------

-- Enum

-- ---------------------------------------------------------------------------

CREATE TYPE estado_orden_venta AS ENUM (

    'borrador',

    'confirmada',

    'en_preparacion',

    'parcialmente_despachada',

    'despachada',

    'cerrada',

    'cancelada'

);



-- ---------------------------------------------------------------------------

-- Helpers

-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ventas_validar_orden_venta_referencias()

RETURNS trigger

LANGUAGE plpgsql

AS $$

BEGIN

    IF NOT EXISTS (

        SELECT 1

        FROM cliente c

        WHERE c.id_cliente = NEW.id_cliente

          AND c.codigo_cuenta = NEW.codigo_cuenta

    ) THEN

        RAISE EXCEPTION 'cliente % no pertenece a la cuenta %', NEW.id_cliente, NEW.codigo_cuenta;

    END IF;



    RETURN NEW;

END;

$$;



CREATE OR REPLACE FUNCTION ventas_validar_linea_ov()

RETURNS trigger

LANGUAGE plpgsql

AS $$

DECLARE

    v_codigo_cuenta varchar(32);

BEGIN

    SELECT ov.codigo_cuenta

    INTO v_codigo_cuenta

    FROM orden_venta ov

    WHERE ov.id_orden_venta = NEW.id_orden_venta;



    IF v_codigo_cuenta IS NULL THEN

        RAISE EXCEPTION 'orden_venta % no existe', NEW.id_orden_venta;

    END IF;



    IF NOT EXISTS (

        SELECT 1

        FROM producto p

        WHERE p.id_producto = NEW.id_producto

          AND p.codigo_cuenta = v_codigo_cuenta

    ) THEN

        RAISE EXCEPTION 'producto % no pertenece a la cuenta de la OV', NEW.id_producto;

    END IF;



    RETURN NEW;

END;

$$;



-- ---------------------------------------------------------------------------

-- orden_venta (OV) — alcance C+B (bodega origen / despacho)

-- ---------------------------------------------------------------------------

CREATE TABLE orden_venta (

    id_orden_venta uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    id_bodega uuid NOT NULL,

    id_cliente uuid NOT NULL,

    codigo varchar(32) NOT NULL,

    estado estado_orden_venta NOT NULL DEFAULT 'borrador',

    fecha_pedido date NOT NULL DEFAULT CURRENT_DATE,

    observaciones text,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_orden_venta_cuenta_codigo UNIQUE (codigo_cuenta, codigo),



    CONSTRAINT fk_orden_venta_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta),



    CONSTRAINT fk_orden_venta_bodega

        FOREIGN KEY (id_bodega)

        REFERENCES bodega (id_bodega),



    CONSTRAINT fk_orden_venta_cliente

        FOREIGN KEY (id_cliente)

        REFERENCES cliente (id_cliente)

);



CREATE INDEX ix_orden_venta_cuenta ON orden_venta (codigo_cuenta);

CREATE INDEX ix_orden_venta_bodega ON orden_venta (id_bodega);

CREATE INDEX ix_orden_venta_cliente ON orden_venta (id_cliente);

CREATE INDEX ix_orden_venta_bodega_estado ON orden_venta (id_bodega, estado);

CREATE INDEX ix_orden_venta_cola ON orden_venta (id_bodega, estado, created_at)

    WHERE estado IN ('confirmada', 'en_preparacion', 'parcialmente_despachada');

CREATE INDEX ix_orden_venta_cuenta_estado ON orden_venta (codigo_cuenta, estado);



CREATE TRIGGER trg_orden_venta_sync_cuenta

    BEFORE INSERT OR UPDATE OF id_bodega ON orden_venta

    FOR EACH ROW

    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();



CREATE TRIGGER trg_orden_venta_validar_refs

    BEFORE INSERT OR UPDATE OF codigo_cuenta, id_cliente ON orden_venta

    FOR EACH ROW

    EXECUTE FUNCTION ventas_validar_orden_venta_referencias();



CREATE TRIGGER trg_orden_venta_updated_at

    BEFORE UPDATE ON orden_venta

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE orden_venta IS

    'Orden de venta (OV). Bodega origen = despacho. Cola POL-42. Mutaciones solo backend. POL-33.';



-- ---------------------------------------------------------------------------

-- orden_venta_linea

-- ---------------------------------------------------------------------------

CREATE TABLE orden_venta_linea (

    id_linea_orden_venta uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    id_orden_venta uuid NOT NULL,

    id_producto uuid NOT NULL,

    cantidad_pedida numeric(18, 4) NOT NULL,

    cantidad_despachada numeric(18, 4) NOT NULL DEFAULT 0,



    CONSTRAINT chk_ov_linea_pedida_positiva CHECK (cantidad_pedida > 0),

    CONSTRAINT chk_ov_linea_despachada_no_negativa CHECK (cantidad_despachada >= 0),

    CONSTRAINT chk_ov_linea_despachada_max CHECK (cantidad_despachada <= cantidad_pedida),



    CONSTRAINT fk_ov_linea_orden

        FOREIGN KEY (id_orden_venta)

        REFERENCES orden_venta (id_orden_venta)

        ON DELETE CASCADE,



    CONSTRAINT fk_ov_linea_producto

        FOREIGN KEY (id_producto)

        REFERENCES producto (id_producto)

);



CREATE INDEX ix_ov_linea_orden ON orden_venta_linea (id_orden_venta);

CREATE INDEX ix_ov_linea_producto ON orden_venta_linea (id_producto);



CREATE TRIGGER trg_ov_linea_validar

    BEFORE INSERT OR UPDATE OF id_orden_venta, id_producto ON orden_venta_linea

    FOR EACH ROW

    EXECUTE FUNCTION ventas_validar_linea_ov();



COMMENT ON TABLE orden_venta_linea IS

    'Líneas de OV. Mutaciones solo backend. POL-33.';



-- ---------------------------------------------------------------------------

-- RLS — SELECT acotado; cambios de estado solo backend

-- ---------------------------------------------------------------------------

ALTER TABLE orden_venta ENABLE ROW LEVEL SECURITY;

ALTER TABLE orden_venta_linea ENABLE ROW LEVEL SECURITY;



CREATE POLICY orden_venta_select_scope

    ON orden_venta

    FOR SELECT

    TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND auth_wms_puede_ver_bodega(id_bodega)

    );



CREATE POLICY orden_venta_linea_select_scope

    ON orden_venta_linea

    FOR SELECT

    TO authenticated

    USING (

        EXISTS (

            SELECT 1

            FROM orden_venta ov

            WHERE ov.id_orden_venta = orden_venta_linea.id_orden_venta

              AND auth_wms_puede_ver_cuenta(ov.codigo_cuenta)

              AND auth_wms_puede_ver_bodega(ov.id_bodega)

        )

    );



REVOKE INSERT, UPDATE, DELETE ON orden_venta FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON orden_venta_linea FROM authenticated;



GRANT SELECT ON orden_venta TO authenticated;

GRANT SELECT ON orden_venta_linea TO authenticated;


-- ========== 029_transporte.sql ==========
-- POL-33 Fase 8: transporte — viaje (TV), guía de envío y evidencias.

--

-- Rol transportista (wms_rol). Evidencias: URLs Cloudinary únicamente (sin blobs en BD).

-- Cierre de viaje, guías y evidencias: polaria-wms-api (NestJS, rol postgres).

-- PostgREST (authenticated): solo SELECT acotado por cuenta / bodega.



-- ---------------------------------------------------------------------------

-- Enums

-- ---------------------------------------------------------------------------

CREATE TYPE estado_viaje_transporte AS ENUM (

    'programado',

    'en_ruta',

    'entregado',

    'cancelado'

);



CREATE TYPE estado_guia_envio AS ENUM (

    'generada',

    'asignada',

    'en_transito',

    'entregada',

    'anulada'

);



CREATE TYPE tipo_evidencia_transporte AS ENUM (

    'foto',

    'firma'

);



-- ---------------------------------------------------------------------------

-- Helpers

-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION transporte_validar_guia_envio()

RETURNS trigger

LANGUAGE plpgsql

AS $$

DECLARE

    v_codigo_cuenta varchar(32);

    v_id_bodega uuid;

BEGIN

    SELECT vt.codigo_cuenta, vt.id_bodega

    INTO v_codigo_cuenta, v_id_bodega

    FROM viaje_transporte vt

    WHERE vt.id_viaje = NEW.id_viaje;



    IF v_codigo_cuenta IS NULL THEN

        RAISE EXCEPTION 'viaje_transporte % no existe', NEW.id_viaje;

    END IF;



    NEW.codigo_cuenta := v_codigo_cuenta;



    IF NEW.id_orden_venta IS NOT NULL THEN

        IF NOT EXISTS (

            SELECT 1

            FROM orden_venta ov

            WHERE ov.id_orden_venta = NEW.id_orden_venta

              AND ov.codigo_cuenta = v_codigo_cuenta

              AND ov.id_bodega = v_id_bodega

        ) THEN

            RAISE EXCEPTION 'orden_venta % no coincide con cuenta/bodega del viaje', NEW.id_orden_venta;

        END IF;

    END IF;



    RETURN NEW;

END;

$$;



CREATE OR REPLACE FUNCTION transporte_validar_evidencia()

RETURNS trigger

LANGUAGE plpgsql

AS $$

BEGIN

    IF NOT EXISTS (

        SELECT 1

        FROM guia_envio g

        INNER JOIN viaje_transporte vt ON vt.id_viaje = g.id_viaje

        WHERE g.id_guia = NEW.id_guia

    ) THEN

        RAISE EXCEPTION 'guia_envio % no existe', NEW.id_guia;

    END IF;



    IF NEW.url_cloudinary IS NULL OR btrim(NEW.url_cloudinary) = '' THEN

        RAISE EXCEPTION 'url_cloudinary es obligatoria';

    END IF;



    RETURN NEW;

END;

$$;



CREATE OR REPLACE FUNCTION transporte_evidencia_append_only()

RETURNS trigger

LANGUAGE plpgsql

AS $$

BEGIN

    RAISE EXCEPTION 'evidencia_transporte es append-only; no UPDATE ni DELETE';

END;

$$;



-- ---------------------------------------------------------------------------

-- viaje_transporte (TV) — alcance C+B (bodega origen)

-- ---------------------------------------------------------------------------

CREATE TABLE viaje_transporte (

    id_viaje uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    id_bodega uuid NOT NULL,

    codigo varchar(32) NOT NULL,

    estado estado_viaje_transporte NOT NULL DEFAULT 'programado',

    id_transportista uuid,

    fecha_programada date NOT NULL DEFAULT CURRENT_DATE,

    fecha_salida timestamptz,

    fecha_cierre timestamptz,

    observaciones text,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_viaje_cuenta_codigo UNIQUE (codigo_cuenta, codigo),



    CONSTRAINT fk_viaje_cuenta

        FOREIGN KEY (codigo_cuenta)

        REFERENCES cuenta (codigo_cuenta),



    CONSTRAINT fk_viaje_bodega

        FOREIGN KEY (id_bodega)

        REFERENCES bodega (id_bodega),



    CONSTRAINT fk_viaje_transportista

        FOREIGN KEY (id_transportista)

        REFERENCES usuario (id_usuario)

);



CREATE INDEX ix_viaje_cuenta ON viaje_transporte (codigo_cuenta);

CREATE INDEX ix_viaje_bodega ON viaje_transporte (id_bodega);

CREATE INDEX ix_viaje_bodega_estado ON viaje_transporte (id_bodega, estado);

CREATE INDEX ix_viaje_transportista ON viaje_transporte (id_transportista)

    WHERE id_transportista IS NOT NULL;

CREATE INDEX ix_viaje_cola ON viaje_transporte (id_bodega, estado, fecha_programada)

    WHERE estado IN ('programado', 'en_ruta');



CREATE TRIGGER trg_viaje_sync_cuenta

    BEFORE INSERT OR UPDATE OF id_bodega ON viaje_transporte

    FOR EACH ROW

    EXECUTE FUNCTION layout_sync_codigo_cuenta_desde_bodega();



CREATE TRIGGER trg_viaje_updated_at

    BEFORE UPDATE ON viaje_transporte

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE viaje_transporte IS

    'Viaje de transporte (TV). Cierre y estados solo backend. POL-33.';



-- ---------------------------------------------------------------------------

-- guia_envio

-- ---------------------------------------------------------------------------

CREATE TABLE guia_envio (

    id_guia uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    codigo_cuenta varchar(32) NOT NULL,

    id_viaje uuid NOT NULL,

    id_orden_venta uuid,

    codigo varchar(32) NOT NULL,

    destino varchar(512) NOT NULL,

    estado estado_guia_envio NOT NULL DEFAULT 'generada',

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT uq_guia_cuenta_codigo UNIQUE (codigo_cuenta, codigo),



    CONSTRAINT fk_guia_viaje

        FOREIGN KEY (id_viaje)

        REFERENCES viaje_transporte (id_viaje)

        ON DELETE CASCADE,



    CONSTRAINT fk_guia_orden_venta

        FOREIGN KEY (id_orden_venta)

        REFERENCES orden_venta (id_orden_venta)

        ON DELETE SET NULL

);



CREATE INDEX ix_guia_viaje ON guia_envio (id_viaje);

CREATE INDEX ix_guia_orden_venta ON guia_envio (id_orden_venta)

    WHERE id_orden_venta IS NOT NULL;

CREATE INDEX ix_guia_cuenta_estado ON guia_envio (codigo_cuenta, estado);

CREATE INDEX ix_guia_viaje_estado ON guia_envio (id_viaje, estado);



CREATE TRIGGER trg_guia_validar

    BEFORE INSERT OR UPDATE OF id_viaje, id_orden_venta ON guia_envio

    FOR EACH ROW

    EXECUTE FUNCTION transporte_validar_guia_envio();



CREATE TRIGGER trg_guia_updated_at

    BEFORE UPDATE ON guia_envio

    FOR EACH ROW

    EXECUTE FUNCTION public.set_updated_at();



COMMENT ON TABLE guia_envio IS

    'Guía de envío asociada a un viaje y opcionalmente a una OV. POL-33.';



-- ---------------------------------------------------------------------------

-- evidencia_transporte — URLs Cloudinary (sin integración ni blobs en BD)

-- ---------------------------------------------------------------------------

CREATE TABLE evidencia_transporte (

    id_evidencia uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    id_guia uuid NOT NULL,

    tipo tipo_evidencia_transporte NOT NULL,

    url_cloudinary text NOT NULL,

    created_at timestamptz NOT NULL DEFAULT now(),



    CONSTRAINT fk_evidencia_guia

        FOREIGN KEY (id_guia)

        REFERENCES guia_envio (id_guia)

        ON DELETE CASCADE

);



CREATE INDEX ix_evidencia_guia ON evidencia_transporte (id_guia);

CREATE INDEX ix_evidencia_tipo ON evidencia_transporte (id_guia, tipo);



CREATE TRIGGER trg_evidencia_validar

    BEFORE INSERT ON evidencia_transporte

    FOR EACH ROW

    EXECUTE FUNCTION transporte_validar_evidencia();



CREATE TRIGGER trg_evidencia_append_only

    BEFORE UPDATE OR DELETE ON evidencia_transporte

    FOR EACH ROW

    EXECUTE FUNCTION transporte_evidencia_append_only();



COMMENT ON TABLE evidencia_transporte IS

    'Evidencias de entrega (foto/firma). Solo URL Cloudinary; upload vía backend/app. POL-33.';



COMMENT ON COLUMN evidencia_transporte.url_cloudinary IS

    'URL pública o firmada de Cloudinary. No almacenar binarios en PostgreSQL.';



-- ---------------------------------------------------------------------------

-- RLS — SELECT acotado; cierre de viaje y evidencias solo backend

-- ---------------------------------------------------------------------------

ALTER TABLE viaje_transporte ENABLE ROW LEVEL SECURITY;

ALTER TABLE guia_envio ENABLE ROW LEVEL SECURITY;

ALTER TABLE evidencia_transporte ENABLE ROW LEVEL SECURITY;



CREATE POLICY viaje_transporte_select_scope

    ON viaje_transporte

    FOR SELECT

    TO authenticated

    USING (

        auth_wms_puede_ver_cuenta(codigo_cuenta)

        AND auth_wms_puede_ver_bodega(id_bodega)

    );



CREATE POLICY guia_envio_select_scope

    ON guia_envio

    FOR SELECT

    TO authenticated

    USING (

        EXISTS (

            SELECT 1

            FROM viaje_transporte vt

            WHERE vt.id_viaje = guia_envio.id_viaje

              AND auth_wms_puede_ver_cuenta(vt.codigo_cuenta)

              AND auth_wms_puede_ver_bodega(vt.id_bodega)

        )

    );



CREATE POLICY evidencia_transporte_select_scope

    ON evidencia_transporte

    FOR SELECT

    TO authenticated

    USING (

        EXISTS (

            SELECT 1

            FROM guia_envio g

            INNER JOIN viaje_transporte vt ON vt.id_viaje = g.id_viaje

            WHERE g.id_guia = evidencia_transporte.id_guia

              AND auth_wms_puede_ver_cuenta(vt.codigo_cuenta)

              AND auth_wms_puede_ver_bodega(vt.id_bodega)

        )

    );



REVOKE INSERT, UPDATE, DELETE ON viaje_transporte FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON guia_envio FROM authenticated;

REVOKE INSERT, UPDATE, DELETE ON evidencia_transporte FROM authenticated;



GRANT SELECT ON viaje_transporte TO authenticated;

GRANT SELECT ON guia_envio TO authenticated;

GRANT SELECT ON evidencia_transporte TO authenticated;


-- ========== 030_rls_operativo_consolidacion.sql ==========
-- POL-33 Fase 9: consolidación RLS operativo.
--
-- Las políticas SELECT/REVOKE/GRANT de tablas operativas (020–029) ya están aplicadas
-- en cada migración de dominio. Este archivo NO duplica políticas.
--
-- Añade helper combinado para filas C+B (cuenta + bodega) en migraciones futuras
-- o refactors de políticas sin alterar firmas de auth_wms_* existentes.

CREATE OR REPLACE FUNCTION auth_wms_puede_ver_fila_operativa(
    p_codigo_cuenta varchar,
    p_id_bodega uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        auth_wms_puede_ver_cuenta(p_codigo_cuenta)
        AND (
            p_id_bodega IS NULL
            OR auth_wms_puede_ver_bodega(p_id_bodega)
        )
$$;

COMMENT ON FUNCTION auth_wms_puede_ver_fila_operativa(varchar, uuid) IS
    'Alcance SELECT estándar tablas operativas C+B (POL-33). '
    'p_id_bodega NULL = solo cuenta (p. ej. auditoría a nivel tenant).';

REVOKE ALL ON FUNCTION auth_wms_puede_ver_fila_operativa(varchar, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_fila_operativa(varchar, uuid) TO authenticated;

-- Verificación
SELECT COUNT(*) AS roles FROM rol;
