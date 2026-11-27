-- REQ-439 / POL-453: prueba de la migración 125 (latido_at y correo_ot_trabajo).
-- Ejecutar contra una base con la migración aplicada (local o Demo, nunca producción sin
-- confirmación). Todo corre dentro de una transacción que se revierte (ROLLBACK): no deja datos.
-- Si una afirmación falla, el bloque lanza una excepción y el comando sale con error.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/125_correo_ingreso_latido_y_trabajos_ot_test.sql

BEGIN;

DO $$
DECLARE
    tipo text;
    admite_nulo text;
    rls boolean;
    permiso boolean;
    rol text;
    nombre_esquema text;
BEGIN
    -- 1. latido_at existe en public, es timestamptz y admite NULL (filas anteriores a la 125).
    SELECT data_type, is_nullable INTO tipo, admite_nulo
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'correo_pedido_ingreso'
      AND column_name = 'latido_at';
    IF tipo IS NULL THEN
        RAISE EXCEPTION 'FALLA 1: no existe public.correo_pedido_ingreso.latido_at';
    END IF;
    IF tipo <> 'timestamp with time zone' THEN
        RAISE EXCEPTION 'FALLA 1: latido_at es %, se esperaba timestamptz', tipo;
    END IF;
    IF admite_nulo <> 'YES' THEN
        RAISE EXCEPTION 'FALLA 1: latido_at no admite NULL y las filas anteriores a la 125 lo tienen';
    END IF;

    -- 1b. latido_at llegó a template_wms (si existe) y a cada esquema emp_* que tenga la tabla:
    -- la API lo lee en el esquema de cada empresa.
    FOR nombre_esquema IN
        SELECT s.schema_name
        FROM information_schema.schemata s
        WHERE s.schema_name = 'template_wms' OR s.schema_name LIKE 'emp\_%'
    LOOP
        IF EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = nombre_esquema AND table_name = 'correo_pedido_ingreso'
        ) AND NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = nombre_esquema AND table_name = 'correo_pedido_ingreso'
              AND column_name = 'latido_at'
        ) THEN
            RAISE EXCEPTION 'FALLA 1b: falta latido_at en %.correo_pedido_ingreso', nombre_esquema;
        END IF;
    END LOOP;

    -- 2. correo_ot_trabajo existe con RLS activo.
    SELECT c.relrowsecurity INTO rls
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'correo_ot_trabajo';
    IF rls IS NULL THEN
        RAISE EXCEPTION 'FALLA 2: no existe public.correo_ot_trabajo';
    END IF;
    IF NOT rls THEN
        RAISE EXCEPTION 'FALLA 2: RLS no está activo en correo_ot_trabajo';
    END IF;

    -- 3. anon y authenticated no tienen ningún permiso sobre la tabla nueva.
    FOREACH rol IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        SELECT bool_or(has_table_privilege(rol, 'public.correo_ot_trabajo', privilegio))
          INTO permiso
        FROM unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE']) AS privilegio;
        IF permiso THEN
            RAISE EXCEPTION 'FALLA 3: % tiene permisos sobre correo_ot_trabajo', rol;
        END IF;
    END LOOP;

    -- 4. Un trabajo "procesando" por (esquema, OV, usuario): el segundo choca.
    INSERT INTO public.correo_ot_trabajo (esquema, id_orden_venta, id_usuario, request_id)
    VALUES ('emp_prueba', 'ov-1', 'usr-1', 'req-1');
    BEGIN
        INSERT INTO public.correo_ot_trabajo (esquema, id_orden_venta, id_usuario, request_id)
        VALUES ('emp_prueba', 'ov-1', 'usr-1', 'req-2');
        RAISE EXCEPTION 'FALLA 4: se aceptó un segundo trabajo en curso para la misma OV y usuario';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    -- 5. Otro usuario u otra OV sí puede tener su propio trabajo en curso.
    INSERT INTO public.correo_ot_trabajo (esquema, id_orden_venta, id_usuario, request_id)
    VALUES ('emp_prueba', 'ov-1', 'usr-2', 'req-3'), ('emp_prueba', 'ov-2', 'usr-1', 'req-4');

    -- 6. Un trabajo terminado no bloquea uno nuevo para la misma OV y usuario.
    UPDATE public.correo_ot_trabajo
       SET estado = 'listo', propuesta = '{}'::jsonb, terminado_at = now()
     WHERE esquema = 'emp_prueba' AND id_orden_venta = 'ov-1' AND id_usuario = 'usr-1';
    INSERT INTO public.correo_ot_trabajo (esquema, id_orden_venta, id_usuario, request_id)
    VALUES ('emp_prueba', 'ov-1', 'usr-1', 'req-5');

    -- 7. Coherencia: terminado sin terminado_at, o procesando con terminado_at, se rechaza.
    BEGIN
        INSERT INTO public.correo_ot_trabajo (esquema, id_orden_venta, id_usuario, request_id, estado)
        VALUES ('emp_prueba', 'ov-3', 'usr-1', 'req-6', 'error');
        RAISE EXCEPTION 'FALLA 7: se aceptó estado error sin terminado_at';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
    BEGIN
        INSERT INTO public.correo_ot_trabajo (esquema, id_orden_venta, id_usuario, request_id, terminado_at)
        VALUES ('emp_prueba', 'ov-4', 'usr-1', 'req-7', now());
        RAISE EXCEPTION 'FALLA 7: se aceptó estado procesando con terminado_at';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

ROLLBACK;

SELECT 'migracion 125: todas las pruebas pasaron' AS resultado;
