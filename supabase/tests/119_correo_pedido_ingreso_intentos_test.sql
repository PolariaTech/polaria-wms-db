-- POL-417: prueba de la migracion 119 (columna correo_pedido_ingreso.intentos).
-- Ejecutar contra una base con la migracion aplicada (local o Demo, nunca produccion sin
-- confirmacion). Todo corre dentro de una transaccion que se revierte (ROLLBACK): no deja datos.
-- Si una afirmacion falla, el bloque lanza una excepcion y el comando sale con error.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/119_correo_pedido_ingreso_intentos_test.sql

BEGIN;

DO $$
DECLARE
    tipo text;
    admite_nulos text;
    valor_por_defecto text;
    comentario text;
    esquema text;
    cantidad integer;
    resultado text;
BEGIN
    -- 1. La columna existe en public: jsonb, NOT NULL, default '[]'.
    SELECT data_type, is_nullable, column_default
      INTO tipo, admite_nulos, valor_por_defecto
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'correo_pedido_ingreso'
      AND column_name = 'intentos';
    IF tipo IS NULL THEN
        RAISE EXCEPTION 'FALLA 1: no existe public.correo_pedido_ingreso.intentos';
    END IF;
    IF tipo <> 'jsonb' THEN
        RAISE EXCEPTION 'FALLA 1: el tipo es %, se esperaba jsonb', tipo;
    END IF;
    IF admite_nulos <> 'NO' THEN
        RAISE EXCEPTION 'FALLA 1: la columna admite NULL y debe ser NOT NULL';
    END IF;
    IF valor_por_defecto IS NULL OR valor_por_defecto NOT LIKE '%[]%' THEN
        RAISE EXCEPTION 'FALLA 1: el default es %, se esperaba []', valor_por_defecto;
    END IF;

    SELECT col_description('public.correo_pedido_ingreso'::regclass, a.attnum)
      INTO comentario
    FROM pg_attribute a
    WHERE a.attrelid = 'public.correo_pedido_ingreso'::regclass
      AND a.attname = 'intentos' AND NOT a.attisdropped;
    IF comentario IS NULL
       OR comentario NOT LIKE '%iniciado_at%'
       OR comentario NOT LIKE '%terminado_at%'
       OR comentario NOT LIKE '%duracion_ms%'
       OR comentario NOT LIKE '%resultado%'
       OR comentario NOT LIKE '%vencido%' THEN
        RAISE EXCEPTION 'FALLA 1: el COMMENT ON COLUMN no documenta la forma de cada intento';
    END IF;

    -- 2. La columna se replico a template_wms (si existe) y a cada esquema emp_* con la tabla.
    FOR esquema IN
        SELECT s.schema_name
        FROM information_schema.schemata s
        WHERE s.schema_name = 'template_wms' OR s.schema_name LIKE 'emp\_%'
    LOOP
        IF EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = esquema AND table_name = 'correo_pedido_ingreso'
        ) AND NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = esquema AND table_name = 'correo_pedido_ingreso'
              AND column_name = 'intentos'
        ) THEN
            RAISE EXCEPTION 'FALLA 2: falta intentos en %.correo_pedido_ingreso', esquema;
        END IF;
    END LOOP;

    -- 3. Se puede agregar un intento con || y queda un elemento.
    CREATE TEMP TABLE ingreso_intentos_prueba (
        LIKE public.correo_pedido_ingreso INCLUDING DEFAULTS
    );
    INSERT INTO ingreso_intentos_prueba (codigo_cuenta, message_id)
    VALUES ('1YW43', 'prueba-intentos');
    UPDATE ingreso_intentos_prueba
       SET intentos = intentos || '[{"n":1}]'::jsonb;
    SELECT jsonb_array_length(intentos) INTO cantidad FROM ingreso_intentos_prueba;
    IF cantidad <> 1 THEN
        RAISE EXCEPTION 'FALLA 3: tras || el arreglo deberia tener 1 elemento y tiene %', cantidad;
    END IF;

    -- 4. jsonb_set sobre el ultimo elemento deja un solo elemento con resultado = ingresado.
    UPDATE ingreso_intentos_prueba
       SET intentos = jsonb_set(
           intentos,
           ARRAY[(jsonb_array_length(intentos) - 1)::text],
           (intentos->-1) || '{"resultado":"ingresado"}'::jsonb
       );
    SELECT jsonb_array_length(intentos), intentos->-1->>'resultado'
      INTO cantidad, resultado
    FROM ingreso_intentos_prueba;
    IF cantidad <> 1 THEN
        RAISE EXCEPTION 'FALLA 4: tras jsonb_set el arreglo deberia tener 1 elemento y tiene %', cantidad;
    END IF;
    IF resultado IS DISTINCT FROM 'ingresado' THEN
        RAISE EXCEPTION 'FALLA 4: resultado es %, se esperaba ingresado', resultado;
    END IF;

    RAISE NOTICE 'OK: migracion 119';
END $$;

ROLLBACK;
