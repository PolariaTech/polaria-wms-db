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
UPDATE rol SET puede_crear_rol = 'configurador' WHERE id_rol <> 'configurador';
UPDATE rol SET descripcion = 'Equipo TI del proveedor SaaS. Crea empresas y usuarios con cualquier rol.'
WHERE id_rol = 'configurador';

-- ========== 015_rls_base.sql ==========
CREATE SCHEMA IF NOT EXISTS app;

CREATE OR REPLACE FUNCTION app.current_rol()
RETURNS wms_rol LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT u.id_rol FROM usuario u WHERE u.id_auth = auth.uid() AND u.esta_activo LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION app.is_configurador()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT EXISTS (SELECT 1 FROM usuario u WHERE u.id_auth = auth.uid() AND u.esta_activo AND u.id_rol = 'configurador');
$$;

CREATE OR REPLACE FUNCTION app.current_codigo_empresa()
RETURNS varchar LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT u.codigo_empresa FROM usuario u WHERE u.id_auth = auth.uid() AND u.esta_activo LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION app.current_codigo_cuenta()
RETURNS varchar LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT u.codigo_cuenta FROM usuario u WHERE u.id_auth = auth.uid() AND u.esta_activo LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION app.has_empresa_access(p_codigo_empresa varchar)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT app.is_configurador() OR (p_codigo_empresa IS NOT NULL AND p_codigo_empresa = app.current_codigo_empresa());
$$;

CREATE OR REPLACE FUNCTION app.has_cuenta_access(p_codigo_cuenta varchar)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT app.is_configurador() OR (p_codigo_cuenta IS NOT NULL AND p_codigo_cuenta = app.current_codigo_cuenta());
$$;

GRANT USAGE ON SCHEMA app TO authenticated;
GRANT EXECUTE ON FUNCTION app.current_rol(), app.is_configurador(), app.current_codigo_empresa(),
    app.current_codigo_cuenta(), app.has_empresa_access(varchar), app.has_cuenta_access(varchar) TO authenticated;

DROP POLICY IF EXISTS usuario_select_own ON usuario;
DROP POLICY IF EXISTS usuario_select_scope ON usuario;
CREATE POLICY usuario_select_scope ON usuario FOR SELECT TO authenticated USING (
    id_auth = auth.uid()
    OR app.is_configurador()
    OR (usuario.codigo_cuenta IS NOT NULL AND usuario.codigo_cuenta = app.current_codigo_cuenta())
    OR (app.current_codigo_cuenta() IS NULL AND usuario.codigo_empresa IS NOT NULL AND usuario.codigo_empresa = app.current_codigo_empresa())
);

DROP POLICY IF EXISTS empresa_select_scope ON empresa;
CREATE POLICY empresa_select_scope ON empresa FOR SELECT TO authenticated
    USING (app.has_empresa_access(empresa.codigo_empresa));

DROP POLICY IF EXISTS cuenta_select_scope ON cuenta;
CREATE POLICY cuenta_select_scope ON cuenta FOR SELECT TO authenticated
    USING (app.has_empresa_access(cuenta.codigo_empresa));

REVOKE ALL ON rol     FROM anon, authenticated;
REVOKE ALL ON empresa FROM anon, authenticated;
REVOKE ALL ON usuario FROM anon, authenticated;
REVOKE ALL ON cuenta  FROM anon, authenticated;
GRANT SELECT ON rol     TO authenticated;
GRANT SELECT ON empresa TO authenticated;
GRANT SELECT ON usuario TO authenticated;
GRANT SELECT ON cuenta  TO authenticated;

COMMENT ON SCHEMA app IS 'Helpers de seguridad RLS (contexto del usuario autenticado). No expuesto via PostgREST.';

-- Verificación
SELECT COUNT(*) AS roles FROM rol;
