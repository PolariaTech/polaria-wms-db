-- Campos de captura del pedido de venta en columnas (sin depender solo de observaciones).

ALTER TABLE public.orden_venta
    ADD COLUMN IF NOT EXISTS fecha_entrega text,
    ADD COLUMN IF NOT EXISTS ventana_desde text,
    ADD COLUMN IF NOT EXISTS ventana_hasta text,
    ADD COLUMN IF NOT EXISTS prioridad text,
    ADD COLUMN IF NOT EXISTS orden_compra_hotel text,
    ADD COLUMN IF NOT EXISTS centro_consumo text,
    ADD COLUMN IF NOT EXISTS vendedor text,
    ADD COLUMN IF NOT EXISTS moneda text,
    ADD COLUMN IF NOT EXISTS bodega_destino_label text,
    ADD COLUMN IF NOT EXISTS direccion_entrega text,
    ADD COLUMN IF NOT EXISTS anden text,
    ADD COLUMN IF NOT EXISTS contacto_entrega text,
    ADD COLUMN IF NOT EXISTS telefono_contacto text,
    ADD COLUMN IF NOT EXISTS turno text,
    ADD COLUMN IF NOT EXISTS hora_salida text,
    ADD COLUMN IF NOT EXISTS chofer text,
    ADD COLUMN IF NOT EXISTS unidad text,
    ADD COLUMN IF NOT EXISTS acepta_sustituciones text,
    ADD COLUMN IF NOT EXISTS requiere_lote text,
    ADD COLUMN IF NOT EXISTS registrar_temperatura text,
    ADD COLUMN IF NOT EXISTS origen_texto text,
    ADD COLUMN IF NOT EXISTS origen_archivos text,
    ADD COLUMN IF NOT EXISTS notas_lineas text,
    ADD COLUMN IF NOT EXISTS notas_almacen text;

COMMENT ON COLUMN public.orden_venta.fecha_entrega IS
    'Fecha de entrega capturada en el pedido.';
COMMENT ON COLUMN public.orden_venta.centro_consumo IS
    'Centro de consumo / cocina del comprador.';
COMMENT ON COLUMN public.orden_venta.notas_almacen IS
    'Notas operativas para almacén.';

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
        FOREACH col IN ARRAY ARRAY[
            'fecha_entrega','ventana_desde','ventana_hasta','prioridad','orden_compra_hotel',
            'centro_consumo','vendedor','moneda','bodega_destino_label','direccion_entrega',
            'anden','contacto_entrega','telefono_contacto','turno','hora_salida','chofer',
            'unidad','acepta_sustituciones','requiere_lote','registrar_temperatura',
            'origen_texto','origen_archivos','notas_lineas','notas_almacen'
        ]
        LOOP
            PERFORM public.wms_sync_column_to_tenants('orden_venta', col);
        END LOOP;
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
