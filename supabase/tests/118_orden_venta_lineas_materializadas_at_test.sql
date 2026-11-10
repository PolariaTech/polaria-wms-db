-- REQ-280 / REQ-299: prueba de la migracion 118 (columna orden_venta.lineas_materializadas_at).
-- Ejecutar contra una base con la migracion aplicada (local o Demo, nunca produccion sin
-- confirmacion). Todo corre dentro de una transaccion que se revierte (ROLLBACK): no deja datos.
-- Si una afirmacion falla, el bloque lanza una excepcion y el comando sale con error.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/118_orden_venta_lineas_materializadas_at_test.sql

BEGIN;

DO $$
DECLARE
    tipo text;
    admite_nulos text;
    valor_por_defecto text;
    esquema text;
    filas integer;
BEGIN
    -- 1. La columna existe en public con el tipo correcto, admite NULL y no tiene default
    --    (asi las OV existentes no se marcan como reservadas).
    SELECT data_type, is_nullable, column_default
      INTO tipo, admite_nulos, valor_por_defecto
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orden_venta'
      AND column_name = 'lineas_materializadas_at';
    IF tipo IS NULL THEN
        RAISE EXCEPTION 'FALLA 1: no existe public.orden_venta.lineas_materializadas_at';
    END IF;
    IF tipo <> 'timestamp with time zone' THEN
        RAISE EXCEPTION 'FALLA 1: el tipo es %, se esperaba timestamptz', tipo;
    END IF;
    IF admite_nulos <> 'YES' THEN
        RAISE EXCEPTION 'FALLA 1: la columna no admite NULL';
    END IF;
    IF valor_por_defecto IS NOT NULL THEN
        RAISE EXCEPTION 'FALLA 1: la columna tiene default (%), debe nacer en NULL', valor_por_defecto;
    END IF;

    -- 2. La columna se replico a template_wms (si existe) y a cada esquema emp_*
    FOR esquema IN
        SELECT s.schema_name
        FROM information_schema.schemata s
        WHERE s.schema_name = 'template_wms' OR s.schema_name LIKE 'emp\_%'
    LOOP
        IF EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = esquema AND table_name = 'orden_venta'
        ) AND NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = esquema AND table_name = 'orden_venta'
              AND column_name = 'lineas_materializadas_at'
        ) THEN
            RAISE EXCEPTION 'FALLA 2: falta lineas_materializadas_at en %.orden_venta', esquema;
        END IF;
    END LOOP;

    -- 3. La reserva es atomica: el UPDATE condicional gana una sola vez.
    --    Se usa una tabla temporal con el mismo tipo de la columna real, para no depender
    --    de las claves foraneas de orden_venta.
    EXECUTE format(
        'CREATE TEMP TABLE orden_reserva_prueba (id integer PRIMARY KEY, lineas_materializadas_at %s)',
        'timestamptz'
    );
    INSERT INTO orden_reserva_prueba (id) VALUES (1);

    UPDATE orden_reserva_prueba SET lineas_materializadas_at = now()
    WHERE id = 1 AND lineas_materializadas_at IS NULL;
    GET DIAGNOSTICS filas = ROW_COUNT;
    IF filas <> 1 THEN
        RAISE EXCEPTION 'FALLA 3: la primera reserva deberia ganar 1 fila y gano %', filas;
    END IF;

    UPDATE orden_reserva_prueba SET lineas_materializadas_at = now()
    WHERE id = 1 AND lineas_materializadas_at IS NULL;
    GET DIAGNOSTICS filas = ROW_COUNT;
    IF filas <> 0 THEN
        RAISE EXCEPTION 'FALLA 3: la segunda reserva deberia perder (0 filas) y gano %', filas;
    END IF;

    -- 4. Una reserva vencida (mas de 2 minutos) se puede retomar
    UPDATE orden_reserva_prueba SET lineas_materializadas_at = now() - interval '3 minutes'
    WHERE id = 1;
    UPDATE orden_reserva_prueba SET lineas_materializadas_at = now()
    WHERE id = 1
      AND (lineas_materializadas_at IS NULL
           OR lineas_materializadas_at < now() - interval '2 minutes');
    GET DIAGNOSTICS filas = ROW_COUNT;
    IF filas <> 1 THEN
        RAISE EXCEPTION 'FALLA 4: una reserva vencida deberia poder retomarse y gano % filas', filas;
    END IF;

    RAISE NOTICE 'OK: migracion 118, 4 afirmaciones cumplidas';
END $$;

ROLLBACK;
