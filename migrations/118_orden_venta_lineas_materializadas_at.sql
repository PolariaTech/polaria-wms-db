-- REQ-280 / REQ-299: evita que la OV quede con cada línea duplicada (x2).
--
-- La web materializa las líneas desde origen_correo al abrir la OV
-- (consulta "¿hay líneas?" y luego inserta, sin candado). Si dos aperturas
-- coinciden (lista + modal, dos pestañas, dos usuarios), las dos ven "sin
-- líneas" e insertan: OV-00001507 quedó con 36 líneas de 18 productos.
--
-- Solución: una marca en la cabecera que el primero en llegar reserva con un
-- UPDATE condicional (`... WHERE lineas_materializadas_at IS NULL`), que es
-- atómico por fila. Solo quien logra la reserva inserta las líneas.
--
-- La columna nace en NULL. Las OV que ya tienen líneas no la necesitan: la web
-- sigue comprobando primero que no haya líneas.

ALTER TABLE public.orden_venta
    ADD COLUMN IF NOT EXISTS lineas_materializadas_at timestamptz;

COMMENT ON COLUMN public.orden_venta.lineas_materializadas_at IS
    'Reserva atómica de la materialización de líneas desde origen_correo. NULL = nadie la ha reservado; con valor, una sesión ya las insertó o las está insertando.';

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
            'orden_venta',
            'lineas_materializadas_at'
        );
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
