-- POL-410: prueba de la migracion 117 (tabla public.correo_pedido_entrada).
-- Ejecutar contra una base con la migracion aplicada (local o Demo, nunca produccion sin
-- confirmacion). Todo corre dentro de una transaccion que se revierte (ROLLBACK): no deja datos.
-- Si una afirmacion falla, el bloque lanza una excepcion y el comando sale con error.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/117_correo_pedido_entrada_test.sql

BEGIN;

DO $$
DECLARE
    rls_activo boolean;
    filas integer;
    columna text;
BEGIN
    -- 1. La tabla existe con RLS activo
    SELECT c.relrowsecurity INTO rls_activo
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'correo_pedido_entrada';
    IF rls_activo IS NULL THEN
        RAISE EXCEPTION 'FALLA 1: no existe public.correo_pedido_entrada';
    END IF;
    IF NOT rls_activo THEN
        RAISE EXCEPTION 'FALLA 1: RLS no esta activo en correo_pedido_entrada';
    END IF;

    -- 2. Existe la politica de lectura y el indice unico
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'correo_pedido_entrada'
          AND policyname = 'correo_pedido_entrada_select' AND cmd = 'SELECT'
    ) THEN
        RAISE EXCEPTION 'FALLA 2: falta la politica correo_pedido_entrada_select';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'uq_correo_pedido_entrada_cuenta_message'
    ) THEN
        RAISE EXCEPTION 'FALLA 2: falta el indice unico uq_correo_pedido_entrada_cuenta_message';
    END IF;

    -- 3. Estan todas las columnas del contrato CorreoFilaDto (R2)
    FOREACH columna IN ARRAY ARRAY[
        'codigo_cuenta', 'message_id', 'recibido_en', 'de', 'para', 'asunto', 'hilo',
        'adjunto', 'nuevo_pedido', 'motivo', 'resultado', 'confianza', 'tipo',
        'codigo_orden_venta', 'created_at', 'updated_at'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'correo_pedido_entrada'
              AND column_name = columna
        ) THEN
            RAISE EXCEPTION 'FALLA 3: falta la columna %', columna;
        END IF;
    END LOOP;

    -- 4. Un correo es una sola fila por cuenta: el upsert por message_id no duplica (R1, R4)
    INSERT INTO public.correo_pedido_entrada (codigo_cuenta, message_id, asunto)
    VALUES ('PRUEBA117', 'msg-prueba-117', 'primero');
    INSERT INTO public.correo_pedido_entrada (codigo_cuenta, message_id, asunto)
    VALUES ('PRUEBA117', 'msg-prueba-117', 'segundo')
    ON CONFLICT (codigo_cuenta, message_id) DO UPDATE SET asunto = EXCLUDED.asunto;
    SELECT count(*) INTO filas FROM public.correo_pedido_entrada
    WHERE codigo_cuenta = 'PRUEBA117' AND message_id = 'msg-prueba-117';
    IF filas <> 1 THEN
        RAISE EXCEPTION 'FALLA 4: el upsert dejo % filas para el mismo correo', filas;
    END IF;
    BEGIN
        INSERT INTO public.correo_pedido_entrada (codigo_cuenta, message_id)
        VALUES ('PRUEBA117', 'msg-prueba-117');
        RAISE EXCEPTION 'FALLA 4: se permitio duplicar el mismo correo en la misma cuenta';
    EXCEPTION WHEN unique_violation THEN
        NULL; -- esperado
    END;

    -- 5. El mismo correo si puede existir en otra cuenta, y cada cuenta ve solo lo suyo
    INSERT INTO public.correo_pedido_entrada (codigo_cuenta, message_id)
    VALUES ('PRUEBA117-B', 'msg-prueba-117');
    SELECT count(*) INTO filas FROM public.correo_pedido_entrada
    WHERE codigo_cuenta = 'PRUEBA117';
    IF filas <> 1 THEN
        RAISE EXCEPTION 'FALLA 5: el filtro por cuenta devolvio % filas, se esperaba 1', filas;
    END IF;

    -- 6. resultado y confianza solo aceptan sus valores; null es valido (filas antiguas, CA5)
    BEGIN
        INSERT INTO public.correo_pedido_entrada (codigo_cuenta, message_id, resultado)
        VALUES ('PRUEBA117', 'msg-resultado-malo', 'otro');
        RAISE EXCEPTION 'FALLA 6: se acepto un resultado invalido';
    EXCEPTION WHEN check_violation THEN
        NULL; -- esperado
    END;
    BEGIN
        INSERT INTO public.correo_pedido_entrada (codigo_cuenta, message_id, confianza)
        VALUES ('PRUEBA117', 'msg-confianza-mala', 'otra');
        RAISE EXCEPTION 'FALLA 6: se acepto una confianza invalida';
    EXCEPTION WHEN check_violation THEN
        NULL; -- esperado
    END;
    IF NOT EXISTS (
        SELECT 1 FROM public.correo_pedido_entrada
        WHERE codigo_cuenta = 'PRUEBA117' AND message_id = 'msg-prueba-117'
          AND resultado IS NULL AND confianza IS NULL AND tipo IS NULL
          AND codigo_orden_venta IS NULL AND nuevo_pedido IS NULL
    ) THEN
        RAISE EXCEPTION 'FALLA 6: una fila sin resultado debe quedar con esos campos en null';
    END IF;

    -- 7. Los cinco resultados del workflow son validos
    INSERT INTO public.correo_pedido_entrada (codigo_cuenta, message_id, resultado)
    SELECT 'PRUEBA117', 'msg-resultado-' || r, r
    FROM unnest(ARRAY['recibido', 'ingresado', 'duplicado', 'error', 'no_es_pedido']) AS r;

    -- 8. La tabla se replico a template_wms
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'template_wms' AND table_name = 'correo_pedido_entrada'
    ) THEN
        RAISE EXCEPTION 'FALLA 8: no se replico correo_pedido_entrada a template_wms';
    END IF;

    RAISE NOTICE 'OK: 117_correo_pedido_entrada, 8 afirmaciones';
END $$;

ROLLBACK;
