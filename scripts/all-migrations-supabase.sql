-- polaria-wms-db: todas las migraciones fase 1 (pegar en Supabase SQL Editor)
-- Proyecto: zmdokvjewvqaftnvulsr

-- ========== 001_extensions.sql ==========
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
END $$;

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
    ('configurador', 'Configurador (TI)', 'plataforma', NULL, 'Equipo TI del proveedor SaaS. Crea empresas y administradores de cuenta.'),
    ('administrador_cuenta', 'Administrador de cuenta', 'cuenta', 'configurador', 'Responsable del cliente. Gestiona tenant, catálogos y equipo.'),
    ('operador_cuenta', 'Operador de cuenta', 'cuenta', 'administrador_cuenta', 'Opera el tenant a nivel comercial (SOL, OC, OV).'),
    ('administrador_bodega', 'Administrador de bodega', 'bodega', 'administrador_cuenta', 'Responsable de la bodega asignada: configuración y supervisión.'),
    ('jefe_bodega', 'Jefe de bodega', 'bodega', 'administrador_cuenta', 'Jefe operativo: prioriza OT, alertas y override de temperatura.'),
    ('custodio', 'Custodio', 'bodega', 'administrador_cuenta', 'Recibe mercancía, valida documentos/temperatura y despacha salidas.'),
    ('operario', 'Operario', 'bodega', 'administrador_cuenta', 'Ejecuta órdenes de trabajo y movimientos de cajas/slots.'),
    ('procesador', 'Procesador', 'bodega', 'administrador_cuenta', 'Encargado de la línea de procesamiento (primario → secundario, merma).'),
    ('transportista', 'Transportista', 'bodega', 'administrador_cuenta', 'Conduce viajes TV y registra entregas con evidencias.');

ALTER TABLE rol ENABLE ROW LEVEL SECURITY;

CREATE POLICY rol_select_authenticated
    ON rol FOR SELECT TO authenticated USING (true);

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

CREATE INDEX ix_empresa_activa ON empresa (esta_activa) WHERE esta_activa;

CREATE TRIGGER trg_empresa_updated_at
    BEFORE UPDATE ON empresa
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

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
    CONSTRAINT fk_usuario_rol FOREIGN KEY (id_rol) REFERENCES rol (id_rol),
    CONSTRAINT fk_usuario_empresa FOREIGN KEY (codigo_empresa) REFERENCES empresa (codigo_empresa),
    CONSTRAINT chk_usuario_contexto CHECK (
        (id_rol = 'configurador' AND codigo_empresa IS NULL AND codigo_cuenta IS NULL)
        OR (id_rol <> 'configurador' AND codigo_empresa IS NOT NULL)
    )
);

CREATE INDEX ix_usuario_id_auth ON usuario (id_auth);
CREATE INDEX ix_usuario_empresa ON usuario (codigo_empresa);
CREATE INDEX ix_usuario_cuenta ON usuario (codigo_cuenta);
CREATE INDEX ix_usuario_rol ON usuario (id_rol);
CREATE INDEX ix_usuario_login_username ON usuario (username) WHERE esta_activo;
CREATE INDEX ix_usuario_login_correo ON usuario (correo) WHERE esta_activo;

ALTER TABLE usuario ADD CONSTRAINT fk_usuario_creador
    FOREIGN KEY (id_creador) REFERENCES usuario (id_usuario);

ALTER TABLE usuario ADD CONSTRAINT fk_usuario_auth
    FOREIGN KEY (id_auth) REFERENCES auth.users (id) ON DELETE CASCADE;

CREATE TRIGGER trg_usuario_updated_at
    BEFORE UPDATE ON usuario
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE usuario ENABLE ROW LEVEL SECURITY;

CREATE POLICY usuario_select_own
    ON usuario FOR SELECT TO authenticated USING (id_auth = auth.uid());

GRANT SELECT ON usuario TO authenticated;

CREATE POLICY empresa_select_scope
    ON empresa FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM usuario u
            WHERE u.id_auth = auth.uid() AND u.esta_activo
              AND (u.id_rol = 'configurador' OR u.codigo_empresa = empresa.codigo_empresa)
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
    CONSTRAINT fk_cuenta_empresa FOREIGN KEY (codigo_empresa) REFERENCES empresa (codigo_empresa),
    CONSTRAINT fk_cuenta_creador FOREIGN KEY (id_creador) REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_cuenta_empresa ON cuenta (codigo_empresa);
CREATE INDEX ix_cuenta_activa ON cuenta (esta_activa) WHERE esta_activa;

CREATE TRIGGER trg_cuenta_updated_at
    BEFORE UPDATE ON cuenta
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE usuario ADD CONSTRAINT fk_usuario_cuenta
    FOREIGN KEY (codigo_cuenta) REFERENCES cuenta (codigo_cuenta);

ALTER TABLE empresa ADD CONSTRAINT fk_empresa_creador
    FOREIGN KEY (id_creador) REFERENCES usuario (id_usuario);

ALTER TABLE cuenta ENABLE ROW LEVEL SECURITY;

CREATE POLICY cuenta_select_scope
    ON cuenta FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM usuario u
            WHERE u.id_auth = auth.uid() AND u.esta_activo
              AND (u.id_rol = 'configurador' OR u.codigo_empresa = cuenta.codigo_empresa)
        )
    );

GRANT SELECT ON cuenta TO authenticated;

-- ========== 014_fix_puede_crear_rol.sql ==========
UPDATE rol
SET puede_crear_rol = 'configurador'
WHERE id_rol <> 'configurador';

UPDATE rol
SET descripcion = 'Equipo TI del proveedor SaaS. Crea empresas y usuarios con cualquier rol.'
WHERE id_rol = 'configurador';

-- ========== 015_rls_helpers.sql ==========
CREATE TYPE auth_wms_usuario_contexto AS (
    id_usuario uuid,
    id_rol wms_rol,
    nivel rol_nivel,
    codigo_empresa varchar(32),
    codigo_cuenta varchar(32),
    esta_activo boolean
);

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

REVOKE ALL ON FUNCTION auth_wms_usuario_actual() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth_wms_usuario_actual() FROM anon, authenticated;
REVOKE ALL ON FUNCTION auth_wms_es_configurador() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth_wms_es_configurador() FROM anon, authenticated;
REVOKE ALL ON FUNCTION auth_wms_puede_ver_empresa(varchar) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth_wms_puede_ver_empresa(varchar) FROM anon, authenticated;
REVOKE ALL ON FUNCTION auth_wms_puede_ver_cuenta(varchar) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth_wms_puede_ver_cuenta(varchar) FROM anon, authenticated;

-- ========== 016_rls_cuenta_scope.sql ==========
GRANT EXECUTE ON FUNCTION auth_wms_usuario_actual() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_es_configurador() TO authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_empresa(varchar) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_cuenta(varchar) TO authenticated;

DROP POLICY IF EXISTS empresa_select_scope ON empresa;
CREATE POLICY empresa_select_scope
    ON empresa FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_empresa(codigo_empresa));

DROP POLICY IF EXISTS cuenta_select_scope ON cuenta;
CREATE POLICY cuenta_select_scope
    ON cuenta FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

DROP POLICY IF EXISTS usuario_select_scope_admin ON usuario;
CREATE POLICY usuario_select_scope_admin
    ON usuario FOR SELECT TO authenticated
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

-- ========== 017_bodega_base.sql ==========
CREATE TABLE bodega (
    id_bodega uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    codigo varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_bodega_cuenta_codigo UNIQUE (codigo_cuenta, codigo),
    CONSTRAINT fk_bodega_cuenta FOREIGN KEY (codigo_cuenta) REFERENCES cuenta (codigo_cuenta)
);

CREATE INDEX ix_bodega_cuenta ON bodega (codigo_cuenta);

CREATE TRIGGER trg_bodega_updated_at
    BEFORE UPDATE ON bodega
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE asignacion_bodega (
    id_usuario uuid NOT NULL,
    id_bodega uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id_usuario, id_bodega),
    CONSTRAINT fk_asignacion_usuario FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario) ON DELETE CASCADE,
    CONSTRAINT fk_asignacion_bodega FOREIGN KEY (id_bodega) REFERENCES bodega (id_bodega) ON DELETE CASCADE
);

CREATE INDEX ix_asignacion_usuario ON asignacion_bodega (id_usuario);
CREATE INDEX ix_asignacion_bodega ON asignacion_bodega (id_bodega);

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
                      (u.codigo_cuenta IS NULL AND c.codigo_empresa = u.codigo_empresa)
                      OR u.codigo_cuenta = b.codigo_cuenta
                  )
              )
              OR (
                  r.nivel = 'bodega'
                  AND EXISTS (
                      SELECT 1 FROM asignacion_bodega ab
                      WHERE ab.id_usuario = u.id_usuario AND ab.id_bodega = p_id_bodega
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
    ON bodega FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));
GRANT SELECT ON bodega TO authenticated;

ALTER TABLE asignacion_bodega ENABLE ROW LEVEL SECURITY;
CREATE POLICY asignacion_bodega_select_scope
    ON asignacion_bodega FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));
GRANT SELECT ON asignacion_bodega TO authenticated;

-- ========== 018_rls_write_policies.sql ==========
REVOKE INSERT, UPDATE, DELETE ON rol FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON empresa FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON cuenta FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON usuario FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON bodega FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON asignacion_bodega FROM authenticated;

DROP POLICY IF EXISTS empresa_insert_configurador ON empresa;
DROP POLICY IF EXISTS empresa_update_configurador ON empresa;
CREATE POLICY empresa_insert_configurador ON empresa FOR INSERT TO authenticated
    WITH CHECK (auth_wms_es_configurador());
CREATE POLICY empresa_update_configurador ON empresa FOR UPDATE TO authenticated
    USING (auth_wms_es_configurador()) WITH CHECK (auth_wms_es_configurador());
GRANT INSERT, UPDATE ON empresa TO authenticated;

DROP POLICY IF EXISTS cuenta_insert_configurador ON cuenta;
DROP POLICY IF EXISTS cuenta_update_configurador ON cuenta;
CREATE POLICY cuenta_insert_configurador ON cuenta FOR INSERT TO authenticated
    WITH CHECK (auth_wms_es_configurador());
CREATE POLICY cuenta_update_configurador ON cuenta FOR UPDATE TO authenticated
    USING (auth_wms_es_configurador()) WITH CHECK (auth_wms_es_configurador());
GRANT INSERT, UPDATE ON cuenta TO authenticated;

DROP POLICY IF EXISTS usuario_insert_configurador ON usuario;
DROP POLICY IF EXISTS usuario_update_configurador ON usuario;
CREATE POLICY usuario_insert_configurador ON usuario FOR INSERT TO authenticated
    WITH CHECK (auth_wms_es_configurador());
CREATE POLICY usuario_update_configurador ON usuario FOR UPDATE TO authenticated
    USING (auth_wms_es_configurador()) WITH CHECK (auth_wms_es_configurador());
GRANT INSERT, UPDATE ON usuario TO authenticated;

DROP POLICY IF EXISTS bodega_insert_configurador ON bodega;
DROP POLICY IF EXISTS bodega_update_configurador ON bodega;
CREATE POLICY bodega_insert_configurador ON bodega FOR INSERT TO authenticated
    WITH CHECK (auth_wms_es_configurador());
CREATE POLICY bodega_update_configurador ON bodega FOR UPDATE TO authenticated
    USING (auth_wms_es_configurador()) WITH CHECK (auth_wms_es_configurador());
GRANT INSERT, UPDATE ON bodega TO authenticated;

DROP POLICY IF EXISTS asignacion_bodega_insert_configurador ON asignacion_bodega;
DROP POLICY IF EXISTS asignacion_bodega_delete_configurador ON asignacion_bodega;
CREATE POLICY asignacion_bodega_insert_configurador ON asignacion_bodega FOR INSERT TO authenticated
    WITH CHECK (auth_wms_es_configurador());
CREATE POLICY asignacion_bodega_delete_configurador ON asignacion_bodega FOR DELETE TO authenticated
    USING (auth_wms_es_configurador());
GRANT INSERT, DELETE ON asignacion_bodega TO authenticated;

-- Verificación
SELECT COUNT(*) AS roles FROM rol;
