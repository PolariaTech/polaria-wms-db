-- Unidad de venta capturada por línea de OV (LTR, PZA, KGM, etc.).
-- Antes solo existía en UI/catálogo; al confirmar se perdía y se veía kg.

ALTER TABLE public.orden_venta_linea
    ADD COLUMN IF NOT EXISTS unidad_medida varchar(32);

COMMENT ON COLUMN public.orden_venta_linea.unidad_medida IS
    'Unidad de la línea al confirmar (LTR, PZA, KGM, kg, …). Si es null, '
    'consumidores pueden caer al catálogo del producto.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('orden_venta_linea', 'unidad_medida');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
