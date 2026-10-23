-- Correo del contacto de entrega en la OV (junto a nombre y teléfono).

ALTER TABLE public.orden_venta
    ADD COLUMN IF NOT EXISTS correo_contacto text;

COMMENT ON COLUMN public.orden_venta.correo_contacto IS
    'Correo del contacto de entrega capturado en el pedido.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('orden_venta', 'correo_contacto');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
