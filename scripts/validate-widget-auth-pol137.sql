-- validate-widget-auth-pol137.sql — POL-137 aislamiento de historial widget_conversacion
--
-- Prerrequisitos: validate-phase1.sql, validate-rls-multitenant-supabase.sql,
--                 validate-rls-pol138.sql (o seed equivalente ACME/BETA)
--
-- Ejecutar en Supabase SQL Editor o: psql -f scripts/validate-widget-auth-pol137.sql

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

-- Seed mínimo (idempotente) si no corrió validate-rls-pol138.sql
BEGIN;

INSERT INTO widget_conversacion (
    id_conversacion,
    id_usuario,
    codigo_cuenta,
    titulo
)
VALUES (
    'f3000001-0001-4001-8001-000000000001',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'ACME-01',
    'Conversación admin ACME-01'
)
ON CONFLICT (id_conversacion) DO NOTHING;

COMMIT;

-- Prueba W1: operador ACME-01 NO ve conversaciones de otro usuario
DO $$
DECLARE
    v_conv bigint;
    v_ve_admin boolean;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*) INTO v_conv FROM widget_conversacion;
    SELECT EXISTS (
        SELECT 1
        FROM widget_conversacion c
        WHERE c.id_usuario = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    ) INTO v_ve_admin;

    RESET ROLE;

    PERFORM test_rls.assert_true('W1 operador no ve historial ajeno (count=0)', v_conv = 0);
    PERFORM test_rls.assert_true('W1 operador NO ve conversación de admin', NOT v_ve_admin);
END;
$$;

-- Prueba W2: operador NO puede INSERT widget con codigo_cuenta spoofeado (BETA)
DO $$
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    BEGIN
        INSERT INTO widget_conversacion (id_usuario, codigo_cuenta, titulo)
        VALUES (
            'cccccccc-cccc-cccc-cccc-cccccccccccc',
            'BETA-01',
            'Spoof tenant POL-137'
        );
        RESET ROLE;
        RAISE EXCEPTION 'FALLÓ: W2 operador pudo INSERT widget con cuenta BETA';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RESET ROLE;
            RAISE NOTICE 'OK: W2 operador bloqueado INSERT widget spoof';
        WHEN foreign_key_violation THEN
            RESET ROLE;
            RAISE NOTICE 'OK: W2 operador bloqueado INSERT widget (FK/RLS)';
        WHEN OTHERS THEN
            RESET ROLE;
            IF SQLERRM LIKE '%row-level security%' OR SQLERRM LIKE '%violates%policy%' THEN
                RAISE NOTICE 'OK: W2 operador bloqueado INSERT widget spoof (RLS)';
            ELSE
                RAISE;
            END IF;
    END;
END;
$$;

-- Prueba W3: admin empresa ACME NO ve empresa BETA (contexto chat multi-tenant)
DO $$
DECLARE
    v_ve_beta boolean;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
    SET LOCAL ROLE authenticated;

    SELECT EXISTS (
        SELECT 1 FROM empresa WHERE codigo_empresa = 'BETA'
    ) INTO v_ve_beta;

    RESET ROLE;

    PERFORM test_rls.assert_true('W3 admin ACME NO ve empresa BETA', NOT v_ve_beta);
END;
$$;

SELECT 'validate-widget-auth-pol137.sql completado' AS resultado;
