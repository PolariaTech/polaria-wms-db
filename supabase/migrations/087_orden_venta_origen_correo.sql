-- Pedido estructurado del correo (renglones) para órdenes de trabajo hijas dentro de una OV.

ALTER TABLE public.orden_venta
    ADD COLUMN IF NOT EXISTS origen_correo jsonb;

COMMENT ON COLUMN public.orden_venta.origen_correo IS
    'JSON array de renglones del pedido por correo (Numero pedido, Almacen, Producto, etc.). '
    'Las órdenes de trabajo hijas se agrupan desde este payload.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('orden_venta', 'origen_correo');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
