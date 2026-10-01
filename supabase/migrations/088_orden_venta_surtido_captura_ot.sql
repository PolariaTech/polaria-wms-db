-- Captura de surtido por orden de trabajo (hija) dentro de una OV.
-- Permite QR independientes: escanear OT 6 solo actualiza esa hoja.

ALTER TABLE public.orden_venta_surtido_captura
    ADD COLUMN IF NOT EXISTS id_orden_trabajo text NOT NULL DEFAULT '';

COMMENT ON COLUMN public.orden_venta_surtido_captura.id_orden_trabajo IS
    'Clave de orden de trabajo hija (pedido|almacen). Vacío = captura legacy a nivel OV.';

DROP INDEX IF EXISTS public.uq_orden_venta_surtido_captura_orden;

CREATE UNIQUE INDEX IF NOT EXISTS uq_orden_venta_surtido_captura_orden_ot
    ON public.orden_venta_surtido_captura (id_orden_venta, id_orden_trabajo);

DO $$
DECLARE
    r record;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants(
            'orden_venta_surtido_captura',
            'id_orden_trabajo'
        );
    END IF;

    FOR r IN
        SELECT DISTINCT btrim(schema_name) AS schema_name
        FROM public.empresa
        WHERE schema_name IS NOT NULL
          AND btrim(schema_name) <> ''
          AND btrim(schema_name) <> 'public'
    LOOP
        IF to_regclass(format('%I.orden_venta_surtido_captura', r.schema_name)) IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format(
            'ALTER TABLE %I.orden_venta_surtido_captura
               ADD COLUMN IF NOT EXISTS id_orden_trabajo text NOT NULL DEFAULT ''''',
            r.schema_name
        );
        EXECUTE format(
            'DROP INDEX IF EXISTS %I.uq_orden_venta_surtido_captura_orden',
            r.schema_name
        );
        EXECUTE format(
            'CREATE UNIQUE INDEX IF NOT EXISTS uq_orden_venta_surtido_captura_orden_ot
               ON %I.orden_venta_surtido_captura (id_orden_venta, id_orden_trabajo)',
            r.schema_name
        );
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
