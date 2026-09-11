-- Cajas y presentación por línea de OV (captura futura; no obligatorias).

ALTER TABLE public.orden_venta_linea
    ADD COLUMN IF NOT EXISTS cajas numeric(18, 4),
    ADD COLUMN IF NOT EXISTS presentacion text;

COMMENT ON COLUMN public.orden_venta_linea.cajas IS
    'Número de cajas capturado en el pedido; opcional.';
COMMENT ON COLUMN public.orden_venta_linea.presentacion IS
    'Presentación de empaque (p. ej. Caja 1.5 kg, Granel); opcional.';

DO $$
DECLARE
    col text;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        FOREACH col IN ARRAY ARRAY['cajas', 'presentacion']
        LOOP
            PERFORM public.wms_sync_column_to_tenants('orden_venta_linea', col);
        END LOOP;
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
