-- validate-widget-conversaciones-pol180.sql
-- POL-180: pruebas de aislamiento y continuidad de historial de chat por empresa/usuario.
--
-- Prerrequisitos:
-- - Migraciones aplicadas hasta 057.
-- - Seed base de pruebas (validate-phase1 + validate-rls-pol138).
--
-- Ejecutar:
--   psql -f scripts/validate-widget-conversaciones-pol180.sql
--   o en Supabase SQL Editor.

SET search_path TO public, mateo_support, test_rls;

CREATE SCHEMA IF NOT EXISTS test_rls;

CREATE OR REPLACE FUNCTION test_rls.assert_true(p_label text, p_ok boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT p_ok THEN
        RAISE EXCEPTION 'FALLÓ: %', p_label;
    END IF;
    RAISE NOTICE 'OK: %', p_label;
END;
$$;

-- IDs fijos para poder reejecutar el script sin ambigüedades.
DO $$
BEGIN
    INSERT INTO mateo_support.widget_conversacion (
        id_conversacion,
        id_usuario,
        codigo_cuenta,
        titulo
    )
    VALUES (
        'f3000001-0001-4001-8001-00000000a001',
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'ACME-01',
        'POL-180 continuidad A'
    )
    ON CONFLICT (id_conversacion) DO NOTHING;

    INSERT INTO mateo_support.widget_mensaje (
        id_mensaje,
        id_conversacion,
        rol,
        tipo,
        contenido,
        es_error,
        created_at
    )
    VALUES (
        'f3000001-0001-4001-8001-00000000b001',
        'f3000001-0001-4001-8001-00000000a001',
        'user',
        'text',
        'Mensaje continuidad POL-180',
        false,
        '2026-07-28T12:00:00.000Z'::timestamptz
    )
    ON CONFLICT (id_mensaje) DO NOTHING;
END;
$$;

-- P1: continuidad de conversación para mismo usuario.
DO $$
DECLARE
    v_count bigint;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true); -- operador ACME-01
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*)
      INTO v_count
      FROM mateo_support.widget_mensaje m
      JOIN mateo_support.widget_conversacion c
        ON c.id_conversacion = m.id_conversacion
     WHERE c.id_usuario = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
       AND c.id_conversacion = 'f3000001-0001-4001-8001-00000000a001';

    RESET ROLE;

    PERFORM test_rls.assert_true('P1 continuidad: usuario dueño recupera su historial', v_count >= 1);
END;
$$;

-- P2: aislamiento por usuario/empresa (usuario B no ve historial de A).
DO $$
DECLARE
    v_cross_count bigint;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '66666666-6666-6666-6666-666666666666', true); -- admin BETA
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*)
      INTO v_cross_count
      FROM mateo_support.widget_mensaje m
      JOIN mateo_support.widget_conversacion c
        ON c.id_conversacion = m.id_conversacion
     WHERE c.id_conversacion = 'f3000001-0001-4001-8001-00000000a001';

    RESET ROLE;

    PERFORM test_rls.assert_true('P2 aislamiento: usuario BETA no ve historial ACME', v_cross_count = 0);
END;
$$;

-- P3: dedupe por reintento normal (mismo payload + created_at).
DO $$
DECLARE
    v_dupe_ok boolean := false;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    BEGIN
        INSERT INTO mateo_support.widget_mensaje (
            id_conversacion,
            rol,
            tipo,
            contenido,
            es_error,
            created_at
        )
        VALUES (
            'f3000001-0001-4001-8001-00000000a001',
            'user',
            'text',
            'Mensaje continuidad POL-180',
            false,
            '2026-07-28T12:00:00.000Z'::timestamptz
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_dupe_ok := true;
    END;

    RESET ROLE;

    PERFORM test_rls.assert_true('P3 dedupe: reintento duplicado bloqueado por índice único', v_dupe_ok);
END;
$$;

SELECT 'validate-widget-conversaciones-pol180.sql completado' AS resultado;
