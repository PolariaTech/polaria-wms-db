-- REQ-180: soft-lock de edición concurrente en orden de venta.
-- Un operador "tiene" la OV mientras edita; otro puede abrirla solo en lectura.
-- El heartbeat refresca edit_locked_at; tras ~5 min sin latido el lock se considera caducado.

ALTER TABLE public.orden_venta
    ADD COLUMN IF NOT EXISTS edit_locked_by uuid,
    ADD COLUMN IF NOT EXISTS edit_locked_at timestamptz,
    ADD COLUMN IF NOT EXISTS edit_locked_nombre text;

COMMENT ON COLUMN public.orden_venta.edit_locked_by IS
    'Usuario que tiene el formulario de edición abierto (soft lock).';
COMMENT ON COLUMN public.orden_venta.edit_locked_at IS
    'Último heartbeat del editor; si es viejo, otro puede tomar el lock.';
COMMENT ON COLUMN public.orden_venta.edit_locked_nombre IS
    'Nombre visible del editor para presencia en listado y banner de solo lectura.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('orden_venta', 'edit_locked_by');
        PERFORM public.wms_sync_column_to_tenants('orden_venta', 'edit_locked_at');
        PERFORM public.wms_sync_column_to_tenants('orden_venta', 'edit_locked_nombre');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
