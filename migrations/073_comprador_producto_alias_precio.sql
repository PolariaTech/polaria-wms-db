-- Precio de equivalencia por comprador (override de la lista default precio_producto).
-- NULL = usar el precio de la lista de precios de la cuenta.

ALTER TABLE public.comprador_producto_alias
    ADD COLUMN IF NOT EXISTS precio numeric(12, 4) NULL;

COMMENT ON COLUMN public.comprador_producto_alias.precio IS
    'Precio especial de este comprador para el producto. NULL = usar lista de precios (precio_producto).';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('comprador_producto_alias', 'precio');
    END IF;
END $$;
