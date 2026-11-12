-- POL-418: prueba de la migracion 120 (varias frases por producto en comprador_producto_alias).
-- Ejecutar contra una base con la migracion aplicada (local o Demo, nunca produccion sin
-- confirmacion). Todo corre dentro de una transaccion que se revierte (ROLLBACK): no deja datos.
-- Si una afirmacion falla, el bloque lanza una excepcion y el comando sale con error.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/120_comprador_producto_alias_varias_frases_test.sql

BEGIN;

DO $$
DECLARE
    texto_normalizado text;
    esquema text;
    es_generada text;
    id_comprador_prueba uuid;
    id_producto_uno uuid;
    id_producto_dos uuid;
    alias_normalizado_fila text;
BEGIN
    -- 1. wms_norm_alias coincide con los casos de POL-418.
    IF to_regprocedure('public.wms_norm_alias(text)') IS NULL THEN
        RAISE EXCEPTION 'FALLA 1: no existe public.wms_norm_alias(text)';
    END IF;

    texto_normalizado := public.wms_norm_alias('Ajó  en BOTE ');
    IF texto_normalizado IS DISTINCT FROM 'ajo en bote' THEN
        RAISE EXCEPTION 'FALLA 1: Ajó  en BOTE → %', texto_normalizado;
    END IF;

    texto_normalizado := public.wms_norm_alias('Ñame');
    IF texto_normalizado IS DISTINCT FROM 'name' THEN
        RAISE EXCEPTION 'FALLA 1: Ñame → %', texto_normalizado;
    END IF;

    texto_normalizado := public.wms_norm_alias('MANZANA-VERDE');
    IF texto_normalizado IS DISTINCT FROM 'manzana verde' THEN
        RAISE EXCEPTION 'FALLA 1: MANZANA-VERDE → %', texto_normalizado;
    END IF;

    texto_normalizado := public.wms_norm_alias('Crème brûlée');
    IF texto_normalizado IS DISTINCT FROM 'creme brulee' THEN
        RAISE EXCEPTION 'FALLA 1: Crème brûlée → %', texto_normalizado;
    END IF;

    texto_normalizado := public.wms_norm_alias('Aguacate Hass (de primera)');
    IF texto_normalizado IS DISTINCT FROM 'aguacate hass de primera' THEN
        RAISE EXCEPTION 'FALLA 1: Aguacate Hass (de primera) → %', texto_normalizado;
    END IF;

    texto_normalizado := public.wms_norm_alias('');
    IF texto_normalizado IS DISTINCT FROM '' THEN
        RAISE EXCEPTION 'FALLA 1: cadena vacia → %', texto_normalizado;
    END IF;

    texto_normalizado := public.wms_norm_alias(NULL);
    IF texto_normalizado IS DISTINCT FROM '' THEN
        RAISE EXCEPTION 'FALLA 1: NULL → %', texto_normalizado;
    END IF;

    -- 2. Estructura en public, template_wms y cada emp_* que tenga la tabla.
    FOR esquema IN
        SELECT n.nspname
        FROM pg_namespace n
        WHERE n.nspname = 'public'
           OR n.nspname = 'template_wms'
           OR n.nspname LIKE 'emp_%'
        ORDER BY (n.nspname <> 'public'), n.nspname
    LOOP
        IF to_regclass(format('%I.comprador_producto_alias', esquema)) IS NULL THEN
            CONTINUE;
        END IF;

        SELECT a.attgenerated::text
          INTO es_generada
        FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = esquema
          AND c.relname = 'comprador_producto_alias'
          AND a.attname = 'alias_normalizado'
          AND NOT a.attisdropped;

        IF es_generada IS DISTINCT FROM 's' THEN
            RAISE EXCEPTION
                'FALLA 2: alias_normalizado no es columna generada stored en %',
                esquema;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM pg_constraint c
            WHERE c.conrelid = format('%I.comprador_producto_alias', esquema)::regclass
              AND c.contype = 'u'
              AND (
                  SELECT array_agg(a.attname::text ORDER BY a.attname)
                  FROM unnest(c.conkey) AS cols(attnum)
                  JOIN pg_attribute a
                    ON a.attrelid = c.conrelid
                   AND a.attnum = cols.attnum
              ) = ARRAY['id_comprador', 'id_producto']::text[]
        ) THEN
            RAISE EXCEPTION
                'FALLA 2: sigue el UNIQUE (id_comprador, id_producto) en %',
                esquema;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = esquema
              AND tablename = 'comprador_producto_alias'
              AND indexname = 'uq_comprador_producto_alias_frase'
        ) THEN
            RAISE EXCEPTION 'FALLA 2: falta uq_comprador_producto_alias_frase en %', esquema;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = esquema
              AND tablename = 'comprador_producto_alias'
              AND indexname = 'uq_comprador_producto_alias_precio'
        ) THEN
            RAISE EXCEPTION 'FALLA 2: falta uq_comprador_producto_alias_precio en %', esquema;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = esquema
              AND tablename = 'comprador_producto_alias'
              AND indexname = 'uq_comprador_producto_alias_sin_frase'
        ) THEN
            RAISE EXCEPTION 'FALLA 2: falta uq_comprador_producto_alias_sin_frase en %', esquema;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = esquema
              AND tablename = 'comprador_producto_alias'
              AND indexname = 'idx_comprador_producto_alias_cuenta_comprador'
        ) THEN
            RAISE EXCEPTION
                'FALLA 2: falta idx_comprador_producto_alias_cuenta_comprador en %',
                esquema;
        END IF;
    END LOOP;

    -- 3. Comportamiento en emp_demo_1xz77, cuenta 1YW43.
    IF to_regclass('emp_demo_1xz77.comprador') IS NULL
       OR to_regclass('emp_demo_1xz77.producto') IS NULL
       OR to_regclass('emp_demo_1xz77.comprador_producto_alias') IS NULL THEN
        RAISE EXCEPTION 'FALLA 3: sin datos de Demo';
    END IF;

    SELECT c.id_comprador
      INTO id_comprador_prueba
    FROM emp_demo_1xz77.comprador c
    WHERE c.codigo_cuenta = '1YW43'
    LIMIT 1;

    SELECT p.id_producto
      INTO id_producto_uno
    FROM emp_demo_1xz77.producto p
    WHERE p.codigo_cuenta = '1YW43'
    LIMIT 1;

    SELECT p.id_producto
      INTO id_producto_dos
    FROM emp_demo_1xz77.producto p
    WHERE p.codigo_cuenta = '1YW43'
      AND p.id_producto <> id_producto_uno
    LIMIT 1;

    IF id_comprador_prueba IS NULL
       OR id_producto_uno IS NULL
       OR id_producto_dos IS NULL THEN
        RAISE EXCEPTION 'FALLA 3: sin datos de Demo';
    END IF;

    -- (a) Dos frases distintas del mismo producto entran.
    INSERT INTO emp_demo_1xz77.comprador_producto_alias (
        codigo_cuenta, id_comprador, id_producto, alias
    ) VALUES (
        '1YW43', id_comprador_prueba, id_producto_uno, 'manzana verde'
    );

    INSERT INTO emp_demo_1xz77.comprador_producto_alias (
        codigo_cuenta, id_comprador, id_producto, alias
    ) VALUES (
        '1YW43', id_comprador_prueba, id_producto_uno, 'MANZANA  VERDE de primera'
    );

    -- (b) La misma frase, con otra tilde, en el otro producto choca.
    BEGIN
        INSERT INTO emp_demo_1xz77.comprador_producto_alias (
            codigo_cuenta, id_comprador, id_producto, alias
        ) VALUES (
            '1YW43', id_comprador_prueba, id_producto_dos, 'Manzána Verde'
        );
        RAISE EXCEPTION 'FALLA 3: se esperaba unique_violation al repetir la frase';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;

    -- (c) Un solo precio por producto y comprador.
    UPDATE emp_demo_1xz77.comprador_producto_alias
       SET precio = 10
     WHERE codigo_cuenta = '1YW43'
       AND id_comprador = id_comprador_prueba
       AND id_producto = id_producto_uno
       AND alias = 'manzana verde';

    BEGIN
        UPDATE emp_demo_1xz77.comprador_producto_alias
           SET precio = 12
         WHERE codigo_cuenta = '1YW43'
           AND id_comprador = id_comprador_prueba
           AND id_producto = id_producto_uno
           AND alias = 'MANZANA  VERDE de primera';
        RAISE EXCEPTION 'FALLA 3: se esperaba unique_violation al segundo precio';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;

    -- (d) Fila sin frase con precio: una por producto; la segunda choca.
    INSERT INTO emp_demo_1xz77.comprador_producto_alias (
        codigo_cuenta, id_comprador, id_producto, alias, precio
    ) VALUES (
        '1YW43', id_comprador_prueba, id_producto_dos, '', 8
    );

    BEGIN
        INSERT INTO emp_demo_1xz77.comprador_producto_alias (
            codigo_cuenta, id_comprador, id_producto, alias, precio
        ) VALUES (
            '1YW43', id_comprador_prueba, id_producto_dos, '', 9
        );
        RAISE EXCEPTION 'FALLA 3: se esperaba unique_violation en fila sin frase';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;

    -- (e) La columna generada de (a) queda en manzana verde.
    SELECT a.alias_normalizado
      INTO alias_normalizado_fila
    FROM emp_demo_1xz77.comprador_producto_alias a
    WHERE a.codigo_cuenta = '1YW43'
      AND a.id_comprador = id_comprador_prueba
      AND a.id_producto = id_producto_uno
      AND a.alias = 'manzana verde';

    IF alias_normalizado_fila IS DISTINCT FROM 'manzana verde' THEN
        RAISE EXCEPTION 'FALLA 3: alias_normalizado es %', alias_normalizado_fila;
    END IF;

    RAISE NOTICE 'OK: migracion 120';
END $$;

ROLLBACK;
