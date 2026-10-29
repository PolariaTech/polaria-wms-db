-- REQ-193 / REQ-190: quitar el único viejo por id_orden_venta en schemas de cliente.
-- La 088 hizo DROP INDEX IF EXISTS uq_orden_venta_surtido_captura_orden, pero en
-- emp_* el índice clonado se llama orden_venta_surtido_captura_id_orden_venta_idx,
-- así que el DROP no hizo nada y solo quedó una captura por OV.
--
-- Objetivo alineado (public, template_wms, emp_*):
--   - Sin UNIQUE solo sobre (id_orden_venta)
--   - Con UNIQUE (id_orden_venta, id_orden_trabajo) → una fila de captura por OT;
--     el historial orden_venta_surtido_captura_foto ya permite N fotos por OT.

DO $$
DECLARE
    r record;
    v_schema text;
BEGIN
    -- 1) Borrar cualquier UNIQUE cuya única columna indexada sea id_orden_venta.
    FOR r IN
        SELECT i.schemaname, i.indexname
        FROM pg_indexes i
        WHERE i.tablename = 'orden_venta_surtido_captura'
          AND i.indexdef ILIKE 'CREATE UNIQUE INDEX%'
          AND i.indexdef ~ '\(id_orden_venta\)$'
    LOOP
        EXECUTE format(
            'DROP INDEX IF EXISTS %I.%I',
            r.schemaname,
            r.indexname
        );
        RAISE NOTICE 'REQ-193: drop índice viejo %.%', r.schemaname, r.indexname;
    END LOOP;

    -- 2) Asegurar el UNIQUE correcto en public, template_wms y cada emp_*.
    FOR v_schema IN
        SELECT n.nspname
        FROM pg_namespace n
        WHERE n.nspname = 'public'
           OR n.nspname = 'template_wms'
           OR n.nspname LIKE 'emp_%'
        ORDER BY 1
    LOOP
        IF to_regclass(format('%I.orden_venta_surtido_captura', v_schema)) IS NULL THEN
            CONTINUE;
        END IF;

        -- Columna por si algún tenant viejo no la tiene.
        EXECUTE format(
            'ALTER TABLE %I.orden_venta_surtido_captura
               ADD COLUMN IF NOT EXISTS id_orden_trabajo text NOT NULL DEFAULT ''''',
            v_schema
        );

        EXECUTE format(
            'CREATE UNIQUE INDEX IF NOT EXISTS uq_orden_venta_surtido_captura_orden_ot
               ON %I.orden_venta_surtido_captura (id_orden_venta, id_orden_trabajo)',
            v_schema
        );
    END LOOP;

    -- 3) Quitar UNIQUE (ov, ot) con nombre distinto al canónico (p. ej. clones viejos).
    FOR r IN
        SELECT i.schemaname, i.indexname
        FROM pg_indexes i
        WHERE i.tablename = 'orden_venta_surtido_captura'
          AND i.indexdef ILIKE 'CREATE UNIQUE INDEX%'
          AND i.indexdef ILIKE '%id_orden_venta%'
          AND i.indexdef ILIKE '%id_orden_trabajo%'
          AND i.indexname <> 'uq_orden_venta_surtido_captura_orden_ot'
    LOOP
        EXECUTE format(
            'DROP INDEX IF EXISTS %I.%I',
            r.schemaname,
            r.indexname
        );
        RAISE NOTICE 'REQ-193: drop índice duplicado %.%', r.schemaname, r.indexname;
    END LOOP;
END $$;

COMMENT ON COLUMN public.orden_venta_surtido_captura.id_orden_trabajo IS
    'Clave de orden de trabajo hija (pedido|almacen). Vacío = captura legacy a nivel OV. '
    'UNIQUE con id_orden_venta: una captura por OT; N fotos vía orden_venta_surtido_captura_foto.';

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
