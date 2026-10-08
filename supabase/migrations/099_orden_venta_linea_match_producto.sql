-- Auditoría de matching de producto por línea de OV:
-- texto del cliente, sugerencia de Mateo y elección del usuario.

ALTER TABLE public.orden_venta_linea
    ADD COLUMN IF NOT EXISTS match_producto jsonb;

COMMENT ON COLUMN public.orden_venta_linea.match_producto IS
    'JSON: { textoCliente, sugeridoMateo: {idProducto,nombre,codigo}|null, '
    'elegidoUsuario: {idProducto,nombre,codigo} }. Auditoría del matching Mateo.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('orden_venta_linea', 'match_producto');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
