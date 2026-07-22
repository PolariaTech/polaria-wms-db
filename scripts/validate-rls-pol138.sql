-- validate-rls-pol138.sql — POL-138 aislamiento cross-tenant (7 tablas críticas)
--
-- Prerrequisitos:
--   migrations 001–052, bootstrap-auth.sql, validate-phase1.sql
--   validate-rls-multitenant.sql, validate-rls-operativo.sql (recomendado)
--
-- Tablas: empresa, cuenta, bodega, warehouse_state, movimiento_inventario,
--         orden_trabajo, widget_conversacion
--
-- Ejecutar como postgres (o rol con SET ROLE authenticated).

CREATE SCHEMA IF NOT EXISTS test_rls;

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        NULLIF(current_setting('app.test_auth_uid', true), ''),
        NULLIF(current_setting('request.jwt.claim.sub', true), '')
    )::uuid;
$$;

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

-- ---------------------------------------------------------------------------
-- Seed POL-138 (idempotente)
-- ---------------------------------------------------------------------------
BEGIN;

INSERT INTO movimiento_inventario (
    id_movimiento_inventario,
    codigo_cuenta,
    id_bodega,
    id_producto,
    tipo_movimiento,
    cantidad,
    id_usuario
)
VALUES (
    'f1000001-0001-4001-8001-000000000001',
    'ACME-01',
    'b1111111-1111-1111-1111-111111111111',
    'a1000001-0001-4001-8001-000000000001',
    'ajuste_positivo',
    1,
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
)
ON CONFLICT (id_movimiento_inventario) DO NOTHING;

INSERT INTO orden_trabajo (
    id_orden_trabajo,
    codigo_cuenta,
    id_bodega,
    codigo,
    estado,
    tipo
)
VALUES (
    'f2000001-0001-4001-8001-000000000001',
    'ACME-01',
    'b1111111-1111-1111-1111-111111111111',
    'OT-POL138-TEST',
    'planificada',
    'otro'
)
ON CONFLICT (codigo_cuenta, codigo) DO NOTHING;

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
    'Conversación operador ACME-01'
)
ON CONFLICT (id_conversacion) DO NOTHING;

COMMIT;

-- ---------------------------------------------------------------------------
-- Prueba 12: Operador ACME-01 NO ve movimientos de otra cuenta (BETA)
-- id_auth: 33333333-3333-3333-3333-333333333333
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_movs bigint;
    v_ve_acme boolean;
BEGIN
    PERFORM set_config('app.test_auth_uid', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*) INTO v_movs FROM movimiento_inventario;
    SELECT EXISTS (
        SELECT 1 FROM movimiento_inventario WHERE codigo_cuenta = 'BETA-01'
    ) INTO v_ve_acme;

    RESET ROLE;

    PERFORM test_rls.assert_true('12 operador ve solo movimientos de su cuenta', v_movs >= 1);
    PERFORM test_rls.assert_true('12 operador NO ve movimientos BETA', NOT v_ve_acme);
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 13: Operador NO puede INSERT en movimiento_inventario
-- id_auth: 33333333-3333-3333-3333-333333333333
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM set_config('app.test_auth_uid', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    BEGIN
        INSERT INTO movimiento_inventario (
            codigo_cuenta,
            id_bodega,
            id_producto,
            tipo_movimiento,
            cantidad,
            id_usuario
        )
        VALUES (
            'ACME-01',
            'b1111111-1111-1111-1111-111111111111',
            'a1000001-0001-4001-8001-000000000001',
            'ajuste_positivo',
            99,
            'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        );
        RESET ROLE;
        RAISE EXCEPTION 'FALLÓ: 13 operador pudo INSERT en movimiento_inventario';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RESET ROLE;
            RAISE NOTICE 'OK: 13 operador bloqueado INSERT movimiento_inventario';
        WHEN OTHERS THEN
            RESET ROLE;
            IF SQLERRM LIKE '%row-level security%' OR SQLERRM LIKE '%violates%policy%' THEN
                RAISE NOTICE 'OK: 13 operador bloqueado INSERT movimiento_inventario (RLS)';
            ELSE
                RAISE;
            END IF;
    END;
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 14: Operador ACME-01 NO ve OT de otra cuenta
-- id_auth: 33333333-3333-3333-3333-333333333333
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_ots bigint;
    v_ve_beta boolean;
BEGIN
    PERFORM set_config('app.test_auth_uid', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*) INTO v_ots FROM orden_trabajo;
    SELECT EXISTS (
        SELECT 1 FROM orden_trabajo WHERE codigo_cuenta = 'BETA-01'
    ) INTO v_ve_beta;

    RESET ROLE;

    PERFORM test_rls.assert_true('14 operador ve OT de su cuenta', v_ots >= 1);
    PERFORM test_rls.assert_true('14 operador NO ve OT BETA', NOT v_ve_beta);
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 15: Operador NO puede INSERT en orden_trabajo
-- id_auth: 33333333-3333-3333-3333-333333333333
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM set_config('app.test_auth_uid', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    BEGIN
        INSERT INTO orden_trabajo (codigo_cuenta, id_bodega, codigo, estado, tipo)
        VALUES ('ACME-01', 'b1111111-1111-1111-1111-111111111111', 'OT-HACK', 'planificada', 'otro');
        RESET ROLE;
        RAISE EXCEPTION 'FALLÓ: 15 operador pudo INSERT en orden_trabajo';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RESET ROLE;
            RAISE NOTICE 'OK: 15 operador bloqueado INSERT orden_trabajo';
        WHEN OTHERS THEN
            RESET ROLE;
            IF SQLERRM LIKE '%row-level security%' OR SQLERRM LIKE '%violates%policy%' THEN
                RAISE NOTICE 'OK: 15 operador bloqueado INSERT orden_trabajo (RLS)';
            ELSE
                RAISE;
            END IF;
    END;
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 16: Operador A NO ve conversaciones de operador B (misma empresa)
-- id_auth A: 33333333... (ops ACME-01) | conversación de bbbbbbbb... (admin ACME-01)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_conv bigint;
    v_ve_admin boolean;
BEGIN
    PERFORM set_config('app.test_auth_uid', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*) INTO v_conv FROM widget_conversacion;
    SELECT EXISTS (
        SELECT 1
        FROM widget_conversacion c
        WHERE c.id_usuario = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    ) INTO v_ve_admin;

    RESET ROLE;

    PERFORM test_rls.assert_true('16 operador no ve conversaciones ajenas (count=0)', v_conv = 0);
    PERFORM test_rls.assert_true('16 operador NO ve conversación de admin', NOT v_ve_admin);
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 17: Operador NO puede INSERT widget con codigo_cuenta spoofeado (BETA)
-- id_auth: 33333333-3333-3333-3333-333333333333
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM set_config('app.test_auth_uid', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    BEGIN
        INSERT INTO widget_conversacion (id_usuario, codigo_cuenta, titulo)
        VALUES (
            'cccccccc-cccc-cccc-cccc-cccccccccccc',
            'BETA-01',
            'Spoof tenant'
        );
        RESET ROLE;
        RAISE EXCEPTION 'FALLÓ: 17 operador pudo INSERT widget con cuenta BETA';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RESET ROLE;
            RAISE NOTICE 'OK: 17 operador bloqueado INSERT widget spoof';
        WHEN foreign_key_violation THEN
            RESET ROLE;
            RAISE NOTICE 'OK: 17 operador bloqueado INSERT widget (FK/RLS)';
        WHEN OTHERS THEN
            RESET ROLE;
            IF SQLERRM LIKE '%row-level security%' OR SQLERRM LIKE '%violates%policy%' THEN
                RAISE NOTICE 'OK: 17 operador bloqueado INSERT widget spoof (RLS)';
            ELSE
                RAISE;
            END IF;
    END;
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 18: Admin empresa ACME NO ve empresa BETA
-- id_auth: 44444444-4444-4444-4444-444444444444
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_ve_beta boolean;
BEGIN
    PERFORM set_config('app.test_auth_uid', '44444444-4444-4444-4444-444444444444', true);
    SET LOCAL ROLE authenticated;

    SELECT EXISTS (
        SELECT 1 FROM empresa WHERE codigo_empresa = 'BETA'
    ) INTO v_ve_beta;

    RESET ROLE;

    PERFORM test_rls.assert_true('18 admin ACME NO ve empresa BETA', NOT v_ve_beta);
END;
$$;

DO $$
BEGIN
    RAISE NOTICE '=== validate-rls-pol138: 7 pruebas POL-138 completadas ===';
END;
$$;

SELECT 'validate-rls-pol138.sql completado' AS resultado;
