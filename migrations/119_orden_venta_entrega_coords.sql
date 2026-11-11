-- REQ-251: coordenadas de dirección de entrega (mapa) para OV y transporte.
ALTER TABLE public.orden_venta
    ADD COLUMN IF NOT EXISTS entrega_lat double precision,
    ADD COLUMN IF NOT EXISTS entrega_lng double precision;

COMMENT ON COLUMN public.orden_venta.entrega_lat IS
    'Latitud del punto de entrega (mapa / geocodificación).';
COMMENT ON COLUMN public.orden_venta.entrega_lng IS
    'Longitud del punto de entrega (mapa / geocodificación).';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('orden_venta', 'entrega_lat');
        PERFORM public.wms_sync_column_to_tenants('orden_venta', 'entrega_lng');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
