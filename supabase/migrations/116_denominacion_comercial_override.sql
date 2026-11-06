-- REQ-241: override de denominación comercial (no lo pisa el sync de `apodo`).
-- Valor editado en crear/editar OV; el `apodo` sigue siendo el del tercero.

ALTER TABLE public.comprador
    ADD COLUMN IF NOT EXISTS denominacion_comercial_override text;

ALTER TABLE public.orden_venta
    ADD COLUMN IF NOT EXISTS denominacion_comercial_override text;

COMMENT ON COLUMN public.comprador.denominacion_comercial_override IS
    'Denominación comercial editada en WMS. Si tiene valor, sustituye a apodo (sync) al mostrar/seleccionar cliente.';

COMMENT ON COLUMN public.orden_venta.denominacion_comercial_override IS
    'Snapshot de denominación comercial editada en esta OV. Si es null, se usa override del comprador o apodo.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants(
            'comprador',
            'denominacion_comercial_override'
        );
        PERFORM public.wms_sync_column_to_tenants(
            'orden_venta',
            'denominacion_comercial_override'
        );
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
