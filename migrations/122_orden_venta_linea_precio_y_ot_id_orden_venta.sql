-- POL-434: columnas que el API usa y ninguna migración creaba (desfase código vs DB).
--   - orden_venta_linea.precio_unitario: la 097 (bot materializar OV) ya la inserta.
--   - orden_trabajo.id_orden_venta: el repositorio de OT la usa al crear, emitir y cancelar.
-- Idempotente: seguro en bases que ya tengan las columnas (e2e parchea lo mismo con IF NOT EXISTS).
-- wms_sync_column_to_tenants copia tipo, default y NOT NULL, pero no FKs ni CHECKs; por eso
-- las restricciones se agregan aquí, en public y en cada schema emp_*.

ALTER TABLE public.orden_venta_linea
    ADD COLUMN IF NOT EXISTS precio_unitario numeric(18, 4) NOT NULL DEFAULT 0;

ALTER TABLE public.orden_trabajo
    ADD COLUMN IF NOT EXISTS id_orden_venta uuid;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('orden_venta_linea', 'precio_unitario');
        PERFORM public.wms_sync_column_to_tenants('orden_trabajo', 'id_orden_venta');
    END IF;
END $$;

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT n.nspname AS schema_name
        FROM pg_namespace n
        WHERE n.nspname = 'public'
           OR n.nspname = 'template_wms'
           OR n.nspname IN (SELECT e.schema_name FROM public.empresa e WHERE e.schema_name IS NOT NULL)
    LOOP
        IF to_regclass(format('%I.orden_venta_linea', r.schema_name)) IS NOT NULL
           AND NOT EXISTS (
               SELECT 1 FROM pg_constraint c
               WHERE c.conname = 'chk_orden_venta_linea_precio_no_negativo'
                 AND c.conrelid = format('%I.orden_venta_linea', r.schema_name)::regclass
           ) THEN
            EXECUTE format(
                'ALTER TABLE %I.orden_venta_linea ADD CONSTRAINT chk_orden_venta_linea_precio_no_negativo CHECK (precio_unitario >= 0)',
                r.schema_name
            );
        END IF;

        IF r.schema_name <> 'template_wms'
           AND to_regclass(format('%I.orden_trabajo', r.schema_name)) IS NOT NULL
           AND NOT EXISTS (
               SELECT 1 FROM pg_constraint c
               WHERE c.conname = 'orden_trabajo_id_orden_venta_fkey'
                 AND c.conrelid = format('%I.orden_trabajo', r.schema_name)::regclass
           ) THEN
            EXECUTE format(
                'ALTER TABLE %I.orden_trabajo ADD CONSTRAINT orden_trabajo_id_orden_venta_fkey FOREIGN KEY (id_orden_venta) REFERENCES %I.orden_venta (id_orden_venta) ON DELETE SET NULL',
                r.schema_name, r.schema_name
            );
        END IF;
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
