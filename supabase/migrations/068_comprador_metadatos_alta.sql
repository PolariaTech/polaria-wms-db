-- Ficha de alta del comprador (fiscal, domicilios, contactos, reglas).
-- Nombre, teléfono y equivalencias siguen en columnas / tabla propias.

ALTER TABLE comprador
    ADD COLUMN IF NOT EXISTS metadatos_alta jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN comprador.metadatos_alta IS
    'Ficha de alta del comprador (datos fiscales, comerciales, centros, contactos y reglas).';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('comprador', 'metadatos_alta');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
