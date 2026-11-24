-- POL-434: prueba de la migracion 122 (orden_venta_linea.precio_unitario y orden_trabajo.id_orden_venta).
-- Ejecutar contra una base con la migracion 122 aplicada (local o Demo, nunca produccion sin confirmacion). No escribe datos.
-- Verifica en public, en template_wms (si existe) y en cada schema de public.empresa.schema_name:
--   1. columna precio_unitario numeric NOT NULL y columna id_orden_venta uuid (precision y default 0 se
--      informan como DESFASE si la columna ya existia con otra definicion; no hacen fallar la prueba);
--   2. CHECK chk_orden_venta_linea_precio_no_negativo (precio_unitario >= 0);
--   3. FK orden_trabajo_id_orden_venta_fkey hacia orden_venta con ON DELETE SET NULL (no aplica a template_wms).
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/122_orden_venta_linea_precio_y_ot_id_orden_venta_test.sql

BEGIN;

DO $$
DECLARE
    v_schema text;
    v_tipo text;
    v_precision integer;
    v_escala integer;
    v_nulo text;
    v_default text;
    v_definicion text;
    v_accion "char";
    v_destino oid;
    v_verificados integer := 0;
BEGIN
    FOR v_schema IN
        SELECT 'public'
        UNION
        SELECT 'template_wms' WHERE to_regclass('template_wms.orden_venta_linea') IS NOT NULL
        UNION
        SELECT e.schema_name
        FROM public.empresa e
        WHERE e.schema_name IS NOT NULL
          AND to_regclass(format('%I.orden_venta_linea', e.schema_name)) IS NOT NULL
    LOOP
        -- 1a. precio_unitario: numeric(18,4) NOT NULL DEFAULT 0
        SELECT c.data_type, c.numeric_precision, c.numeric_scale, c.is_nullable, c.column_default
          INTO v_tipo, v_precision, v_escala, v_nulo, v_default
        FROM information_schema.columns c
        WHERE c.table_schema = v_schema
          AND c.table_name = 'orden_venta_linea'
          AND c.column_name = 'precio_unitario';

        IF v_tipo IS NULL THEN
            RAISE EXCEPTION 'FALLA 1: %.orden_venta_linea no tiene la columna precio_unitario', v_schema;
        END IF;
        IF v_tipo <> 'numeric' THEN
            RAISE EXCEPTION 'FALLA 2: %.orden_venta_linea.precio_unitario es % y debe ser numeric', v_schema, v_tipo;
        END IF;
        IF v_nulo <> 'NO' THEN
            RAISE EXCEPTION 'FALLA 3: %.orden_venta_linea.precio_unitario admite NULL', v_schema;
        END IF;
        -- Precision y default son lo que crea la 122 en una base nueva. Si la columna ya existia con otra
        -- definicion (Demo la tiene como numeric sin default), la 122 no la altera: se informa, no falla.
        IF v_precision IS DISTINCT FROM 18 OR v_escala IS DISTINCT FROM 4 THEN
            RAISE NOTICE 'DESFASE: %.orden_venta_linea.precio_unitario es numeric(%,%) y la 122 crea numeric(18,4)',
                v_schema, coalesce(v_precision::text, 'sin precision'), coalesce(v_escala::text, 'sin escala');
        END IF;
        IF v_default IS NULL OR v_default !~ '^0' THEN
            RAISE NOTICE 'DESFASE: %.orden_venta_linea.precio_unitario tiene default % y la 122 crea default 0',
                v_schema, coalesce(v_default, 'NULL');
        END IF;

        -- 2. CHECK de precio no negativo
        SELECT pg_get_constraintdef(k.oid)
          INTO v_definicion
        FROM pg_constraint k
        WHERE k.conname = 'chk_orden_venta_linea_precio_no_negativo'
          AND k.contype = 'c'
          AND k.conrelid = format('%I.orden_venta_linea', v_schema)::regclass;

        IF v_definicion IS NULL THEN
            RAISE EXCEPTION 'FALLA 5: %.orden_venta_linea no tiene chk_orden_venta_linea_precio_no_negativo', v_schema;
        END IF;
        IF v_definicion !~ 'precio_unitario >= \(?0' THEN
            RAISE EXCEPTION 'FALLA 6: %.chk_orden_venta_linea_precio_no_negativo es % y debe exigir precio_unitario >= 0',
                v_schema, v_definicion;
        END IF;

        -- template_wms es solo molde de columnas: sin orden_trabajo ni FK.
        CONTINUE WHEN v_schema = 'template_wms';

        -- 1b. orden_trabajo.id_orden_venta uuid
        SELECT c.data_type
          INTO v_tipo
        FROM information_schema.columns c
        WHERE c.table_schema = v_schema
          AND c.table_name = 'orden_trabajo'
          AND c.column_name = 'id_orden_venta';

        IF v_tipo IS NULL THEN
            RAISE EXCEPTION 'FALLA 7: %.orden_trabajo no tiene la columna id_orden_venta', v_schema;
        END IF;
        IF v_tipo <> 'uuid' THEN
            RAISE EXCEPTION 'FALLA 8: %.orden_trabajo.id_orden_venta es % y debe ser uuid', v_schema, v_tipo;
        END IF;

        -- 3. FK hacia orden_venta con ON DELETE SET NULL
        SELECT k.confdeltype, k.confrelid
          INTO v_accion, v_destino
        FROM pg_constraint k
        WHERE k.conname = 'orden_trabajo_id_orden_venta_fkey'
          AND k.contype = 'f'
          AND k.conrelid = format('%I.orden_trabajo', v_schema)::regclass;

        IF v_accion IS NULL THEN
            RAISE EXCEPTION 'FALLA 9: %.orden_trabajo no tiene orden_trabajo_id_orden_venta_fkey', v_schema;
        END IF;
        IF v_destino <> format('%I.orden_venta', v_schema)::regclass THEN
            RAISE EXCEPTION 'FALLA 10: la FK de %.orden_trabajo no apunta a %.orden_venta', v_schema, v_schema;
        END IF;
        IF v_accion <> 'n' THEN
            RAISE EXCEPTION 'FALLA 11: la FK de %.orden_trabajo no es ON DELETE SET NULL', v_schema;
        END IF;

        v_verificados := v_verificados + 1;
    END LOOP;

    IF v_verificados = 0 THEN
        RAISE EXCEPTION 'FALLA 12: no se verifico ningun schema con orden_trabajo (ni siquiera public)';
    END IF;

    RAISE NOTICE 'OK: % schema(s) con orden_trabajo verificados', v_verificados;
END $$;

ROLLBACK;
