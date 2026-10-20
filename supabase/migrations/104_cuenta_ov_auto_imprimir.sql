-- Autoimpresión OV al validar y enviar (por cuenta).

ALTER TABLE public.cuenta
    ADD COLUMN IF NOT EXISTS ov_auto_imprimir boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.cuenta.ov_auto_imprimir IS
    'Si true, al Validar y enviar una OV se imprime automáticamente en la impresora de la cuenta.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('cuenta', 'ov_auto_imprimir');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
