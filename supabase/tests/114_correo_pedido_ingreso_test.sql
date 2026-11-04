-- REQ-104: prueba de la migracion 114 (tabla public.correo_pedido_ingreso).
-- Ejecutar contra un proyecto con la migracion aplicada. Todo corre dentro de una
-- transaccion que se revierte (ROLLBACK): no deja datos. Si una afirmacion falla,
-- el bloque lanza una excepcion y el comando sale con error.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/114_correo_pedido_ingreso_test.sql

BEGIN;

DO $$
DECLARE
    rls_activo boolean;
BEGIN
    -- 1. La tabla existe con RLS activo
    SELECT c.relrowsecurity INTO rls_activo
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'correo_pedido_ingreso';
    IF rls_activo IS NULL THEN
        RAISE EXCEPTION 'FALLA 1: no existe public.correo_pedido_ingreso';
    END IF;
    IF NOT rls_activo THEN
        RAISE EXCEPTION 'FALLA 1: RLS no esta activo en correo_pedido_ingreso';
    END IF;

    -- 2. Existe la politica de lectura y el indice unico
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'correo_pedido_ingreso'
          AND policyname = 'correo_pedido_ingreso_select' AND cmd = 'SELECT'
    ) THEN
        RAISE EXCEPTION 'FALLA 2: falta la politica correo_pedido_ingreso_select';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'uq_correo_pedido_ingreso_cuenta_message'
    ) THEN
        RAISE EXCEPTION 'FALLA 2: falta el indice unico uq_correo_pedido_ingreso_cuenta_message';
    END IF;

    -- 3. Un correo se reserva una sola vez por cuenta (evita OV duplicadas con varios clics)
    INSERT INTO public.correo_pedido_ingreso (codigo_cuenta, message_id)
    VALUES ('PRUEBA114', 'msg-prueba-114');
    BEGIN
        INSERT INTO public.correo_pedido_ingreso (codigo_cuenta, message_id)
        VALUES ('PRUEBA114', 'msg-prueba-114');
        RAISE EXCEPTION 'FALLA 3: se permitio reservar dos veces el mismo correo en la misma cuenta';
    EXCEPTION WHEN unique_violation THEN
        NULL; -- esperado
    END;

    -- 4. El mismo correo si puede existir en otra cuenta
    INSERT INTO public.correo_pedido_ingreso (codigo_cuenta, message_id)
    VALUES ('PRUEBA114-B', 'msg-prueba-114');

    -- 5. El estado y el origen solo aceptan sus valores
    BEGIN
        INSERT INTO public.correo_pedido_ingreso (codigo_cuenta, message_id, estado)
        VALUES ('PRUEBA114', 'msg-estado-malo', 'otro');
        RAISE EXCEPTION 'FALLA 5: se acepto un estado invalido';
    EXCEPTION WHEN check_violation THEN
        NULL; -- esperado
    END;
    BEGIN
        INSERT INTO public.correo_pedido_ingreso (codigo_cuenta, message_id, origen)
        VALUES ('PRUEBA114', 'msg-origen-malo', 'otro');
        RAISE EXCEPTION 'FALLA 5: se acepto un origen invalido';
    EXCEPTION WHEN check_violation THEN
        NULL; -- esperado
    END;

    -- 6. Valores por defecto: nace en 'procesando' y como 'manual'
    IF NOT EXISTS (
        SELECT 1 FROM public.correo_pedido_ingreso
        WHERE codigo_cuenta = 'PRUEBA114' AND message_id = 'msg-prueba-114'
          AND estado = 'procesando' AND origen = 'manual'
    ) THEN
        RAISE EXCEPTION 'FALLA 6: los valores por defecto no son procesando/manual';
    END IF;

    -- 7. La tabla se replico a template_wms
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'template_wms' AND table_name = 'correo_pedido_ingreso'
    ) THEN
        RAISE EXCEPTION 'FALLA 7: no se replico correo_pedido_ingreso a template_wms';
    END IF;

    RAISE NOTICE 'OK: 114_correo_pedido_ingreso, 7 afirmaciones';
END $$;

ROLLBACK;
