-- Zona horaria IANA por cuenta (visualización / impresión). Instantes siguen en UTC.

ALTER TABLE public.cuenta
    ADD COLUMN IF NOT EXISTS zona_horaria text NOT NULL DEFAULT 'America/Cancun';

COMMENT ON COLUMN public.cuenta.zona_horaria IS
    'Zona IANA para mostrar e imprimir horas de esta cuenta (ej. America/Cancun). '
    'Los timestamps en BD permanecen en UTC.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('cuenta', 'zona_horaria');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
