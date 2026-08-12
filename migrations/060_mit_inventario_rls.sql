-- 060_mit_inventario_rls.sql
-- Expone mit.inventario a PostgREST (solo SELECT) para la cuenta Mit (02808 / Fridem).
-- La tabla no tiene codigo_cuenta: el alcance tenant va en la política RLS.

CREATE SCHEMA IF NOT EXISTS mit;

COMMENT ON SCHEMA mit IS
    'Inventario externo Fridem sincronizado para la cuenta Mit (02808).';

GRANT USAGE ON SCHEMA mit TO anon, authenticated, service_role;

-- Lectura vía Data API / frontend autenticado. Escrituras solo service_role / postgres.
GRANT SELECT ON TABLE mit.inventario TO authenticated, service_role;
GRANT ALL ON TABLE mit.inventario TO service_role;

ALTER TABLE mit.inventario ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mit_inventario_select_cuenta_mit ON mit.inventario;

CREATE POLICY mit_inventario_select_cuenta_mit
    ON mit.inventario
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_cuenta('02808'));

COMMENT ON TABLE mit.inventario IS
    'Inventario Fridem (cuenta Mit 02808). Visible solo a usuarios con alcance sobre esa cuenta.';

-- Exponer el schema en la Data API (PostgREST), conservando los ya publicados.
ALTER ROLE authenticator SET pgrst.db_schemas = 'public, graphql_public, mateo_support, mit';
NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';
