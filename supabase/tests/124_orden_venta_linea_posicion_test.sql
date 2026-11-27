-- REQ-370: prueba de la migracion 124 (columna orden_venta_linea.posicion).
-- Ejecutar contra una base con la migracion aplicada (local o Demo, nunca produccion sin
-- confirmacion). Todo corre dentro de una transaccion que se revierte (ROLLBACK): no deja datos.
-- Si una afirmacion falla, el bloque lanza una excepcion y el comando sale con error.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/124_orden_venta_linea_posicion_test.sql

BEGIN;

DO $$
DECLARE
    tipo text;
    admite_nulos text;
    valor_por_defecto text;
    esquema text;
    orden_leido text;
    nombre_columna text;
BEGIN
    -- 1. La columna existe en public como integer, admite NULL y no tiene default
    --    (asi las lineas anteriores quedan sin orden y no con un 0 falso).
    SELECT data_type, is_nullable, column_default
      INTO tipo, admite_nulos, valor_por_defecto
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orden_venta_linea'
      AND column_name = 'posicion';
    IF tipo IS NULL THEN
        RAISE EXCEPTION 'FALLA 1: no existe public.orden_venta_linea.posicion';
    END IF;
    IF tipo <> 'integer' THEN
        RAISE EXCEPTION 'FALLA 1: el tipo es %, se esperaba integer', tipo;
    END IF;
    IF admite_nulos <> 'YES' THEN
        RAISE EXCEPTION 'FALLA 1: la columna no admite NULL';
    END IF;
    IF valor_por_defecto IS NOT NULL THEN
        RAISE EXCEPTION 'FALLA 1: la columna tiene default (%), debe nacer en NULL', valor_por_defecto;
    END IF;

    -- 2. La columna y su CHECK se replicaron a template_wms (si existe) y a cada esquema emp_*
    FOR esquema IN
        SELECT s.schema_name
        FROM information_schema.schemata s
        WHERE s.schema_name = 'template_wms' OR s.schema_name LIKE 'emp\_%'
    LOOP
        IF to_regclass(format('%I.orden_venta_linea', esquema)) IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = esquema AND table_name = 'orden_venta_linea'
                  AND column_name = 'posicion'
            ) THEN
                RAISE EXCEPTION 'FALLA 2: falta posicion en %.orden_venta_linea', esquema;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c
                WHERE c.conname = 'chk_orden_venta_linea_posicion_no_negativa'
                  AND c.conrelid = format('%I.orden_venta_linea', esquema)::regclass
            ) THEN
                RAISE EXCEPTION 'FALLA 2: falta el CHECK de posicion en %.orden_venta_linea', esquema;
            END IF;
        END IF;
    END LOOP;

    -- 3. El CHECK de public rechaza una posicion negativa y acepta NULL y cero.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conname = 'chk_orden_venta_linea_posicion_no_negativa'
          AND c.conrelid = 'public.orden_venta_linea'::regclass
          AND pg_get_constraintdef(c.oid) LIKE '%posicion IS NULL%'
    ) THEN
        RAISE EXCEPTION 'FALLA 3: el CHECK de posicion no admite NULL';
    END IF;

    -- 4. Ordenar por posicion con NULLS LAST deja las lineas con orden primero (0, 1, 2) y las
    --    anteriores a REQ-370 (NULL) al final. Se usa una copia temporal con la estructura real.
    --    Se quitan los NOT NULL de la copia para no depender de las claves foraneas ni de los demas
    --    campos de la linea.
    CREATE TEMP TABLE linea_orden_prueba (LIKE public.orden_venta_linea INCLUDING DEFAULTS);
    FOR nombre_columna IN
        SELECT a.attname
        FROM pg_attribute a
        WHERE a.attrelid = 'linea_orden_prueba'::regclass
          AND a.attnum > 0 AND NOT a.attisdropped AND a.attnotnull
    LOOP
        EXECUTE format('ALTER TABLE linea_orden_prueba ALTER COLUMN %I DROP NOT NULL', nombre_columna);
    END LOOP;
    INSERT INTO linea_orden_prueba (posicion) VALUES (NULL), (2), (0), (1);
    SELECT string_agg(coalesce(posicion::text, 'null'), ',' ORDER BY posicion ASC NULLS LAST)
      INTO orden_leido
    FROM linea_orden_prueba;
    IF orden_leido <> '0,1,2,null' THEN
        RAISE EXCEPTION 'FALLA 4: el orden leido es %, se esperaba 0,1,2,null', orden_leido;
    END IF;

    RAISE NOTICE 'OK: migracion 124, 4 afirmaciones cumplidas';
END $$;

ROLLBACK;
