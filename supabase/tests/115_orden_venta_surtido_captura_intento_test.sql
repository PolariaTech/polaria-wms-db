-- REQ-247: prueba de la migracion 115 (tabla public.orden_venta_surtido_captura_intento).
-- Ejecutar contra un proyecto con la migracion aplicada. Todo corre dentro de una
-- transaccion que se revierte (ROLLBACK): no deja datos. Si una afirmacion falla,
-- el bloque lanza una excepcion y el comando sale con error.
-- Las afirmaciones 5 a 8 necesitan una OV real de public (la tabla tiene llave foranea);
-- si public.orden_venta esta vacia se omiten con un aviso.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/115_orden_venta_surtido_captura_intento_test.sql

BEGIN;

DO $$
DECLARE
    rls_activo boolean;
    v_ov uuid;
    v_fila public.orden_venta_surtido_captura_intento%ROWTYPE;
    v_borrado_cascada boolean;
BEGIN
    -- 1. La tabla existe con RLS activo
    SELECT c.relrowsecurity INTO rls_activo
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'orden_venta_surtido_captura_intento';
    IF rls_activo IS NULL THEN
        RAISE EXCEPTION 'FALLA 1: no existe public.orden_venta_surtido_captura_intento';
    END IF;
    IF NOT rls_activo THEN
        RAISE EXCEPTION 'FALLA 1: RLS no esta activo en orden_venta_surtido_captura_intento';
    END IF;

    -- 2. Existe la politica de lectura
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'orden_venta_surtido_captura_intento'
          AND policyname = 'orden_venta_surtido_captura_intento_select' AND cmd = 'SELECT'
    ) THEN
        RAISE EXCEPTION 'FALLA 2: falta la politica orden_venta_surtido_captura_intento_select';
    END IF;

    -- 3. Existen los dos indices (por OV y OT, y el parcial de intentos en curso)
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname = 'idx_orden_venta_surtido_captura_intento_ov_ot'
    ) THEN
        RAISE EXCEPTION 'FALLA 3: falta idx_orden_venta_surtido_captura_intento_ov_ot';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname = 'idx_orden_venta_surtido_captura_intento_en_curso'
          AND indexdef ILIKE '%WHERE%'
    ) THEN
        RAISE EXCEPTION 'FALLA 3: falta el indice parcial de intentos en curso';
    END IF;

    -- 4. La llave foranea a orden_venta borra en cascada
    SELECT (con.confdeltype = 'c') INTO v_borrado_cascada
    FROM pg_constraint con
    WHERE con.conrelid = 'public.orden_venta_surtido_captura_intento'::regclass
      AND con.contype = 'f'
      AND con.confrelid = 'public.orden_venta'::regclass;
    IF v_borrado_cascada IS NULL THEN
        RAISE EXCEPTION 'FALLA 4: falta la llave foranea a public.orden_venta';
    END IF;
    IF NOT v_borrado_cascada THEN
        RAISE EXCEPTION 'FALLA 4: la llave foranea a orden_venta no es ON DELETE CASCADE';
    END IF;

    SELECT id_orden_venta INTO v_ov FROM public.orden_venta LIMIT 1;
    IF v_ov IS NULL THEN
        RAISE NOTICE 'AVISO: public.orden_venta esta vacia; se omiten las afirmaciones 5 a 8';
    ELSE
        -- 5. Valores por defecto: nace 'recibida', primer intento, sin tiempos ni cierre
        INSERT INTO public.orden_venta_surtido_captura_intento (id_orden_venta, codigo_cuenta)
        VALUES (v_ov, 'PRUEBA115')
        RETURNING * INTO v_fila;
        IF v_fila.estado <> 'recibida' OR v_fila.numero_intento <> 1
           OR v_fila.tiempos <> '{}'::jsonb OR v_fila.terminado_at IS NOT NULL
           OR v_fila.id_orden_trabajo <> '' THEN
            RAISE EXCEPTION 'FALLA 5: los valores por defecto no son recibida / 1 / {} / sin cierre / OT vacia';
        END IF;

        -- 6. El estado solo acepta sus cuatro valores
        BEGIN
            INSERT INTO public.orden_venta_surtido_captura_intento (id_orden_venta, codigo_cuenta, estado)
            VALUES (v_ov, 'PRUEBA115', 'otro');
            RAISE EXCEPTION 'FALLA 6: se acepto un estado invalido';
        EXCEPTION WHEN check_violation THEN
            NULL; -- esperado
        END;
        UPDATE public.orden_venta_surtido_captura_intento
           SET estado = 'procesando' WHERE id_intento = v_fila.id_intento;
        UPDATE public.orden_venta_surtido_captura_intento
           SET estado = 'lista', terminado_at = now() WHERE id_intento = v_fila.id_intento;
        UPDATE public.orden_venta_surtido_captura_intento
           SET estado = 'fallo', codigo_error = 'foto_mala' WHERE id_intento = v_fila.id_intento;

        -- 7. El numero de intento no puede ser menor que 1
        BEGIN
            INSERT INTO public.orden_venta_surtido_captura_intento (id_orden_venta, codigo_cuenta, numero_intento)
            VALUES (v_ov, 'PRUEBA115', 0);
            RAISE EXCEPTION 'FALLA 7: se acepto numero_intento = 0';
        EXCEPTION WHEN check_violation THEN
            NULL; -- esperado
        END;

        -- 8. Varias fotos de la misma OV y OT conviven (a diferencia de la captura, no hay llave unica)
        INSERT INTO public.orden_venta_surtido_captura_intento (id_orden_venta, id_orden_trabajo, codigo_cuenta)
        VALUES (v_ov, 'pedido:1|almacen:a', 'PRUEBA115'), (v_ov, 'pedido:1|almacen:a', 'PRUEBA115');
        IF (SELECT count(*) FROM public.orden_venta_surtido_captura_intento
            WHERE id_orden_venta = v_ov AND id_orden_trabajo = 'pedido:1|almacen:a'
              AND codigo_cuenta = 'PRUEBA115') <> 2 THEN
            RAISE EXCEPTION 'FALLA 8: no se pudieron guardar dos intentos de la misma OT';
        END IF;
    END IF;

    -- 9. La tabla se replico a template_wms
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'template_wms' AND table_name = 'orden_venta_surtido_captura_intento'
    ) THEN
        RAISE EXCEPTION 'FALLA 9: no se replico orden_venta_surtido_captura_intento a template_wms';
    END IF;

    RAISE NOTICE 'OK: 115_orden_venta_surtido_captura_intento';
END $$;

ROLLBACK;
