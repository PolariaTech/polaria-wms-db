-- validate-rls-operativo-supabase.sql — POL-33 RLS (variante remoto Supabase)
-- No reemplaza auth.uid(); usa request.jwt.claim.sub nativo.
-- Prerrequisitos: 001–030, validate-phase1.sql, validate-rls-multitenant-supabase.sql
-- Ejecutar: npx supabase db query --linked -f scripts/validate-rls-operativo-supabase.sql

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

-- Seed operativo mínimo (idempotente)
BEGIN;

INSERT INTO producto (id_producto, codigo_cuenta, sku, descripcion, unidad_medida)
VALUES
    (
        'a1000001-0001-4001-8001-000000000001',
        'ACME-01',
        'SKU-ACME-TEST',
        'Producto prueba ACME-01',
        'UN'
    ),
    (
        'a1000001-0001-4001-8001-000000000002',
        'BETA-01',
        'SKU-BETA-TEST',
        'Producto prueba BETA-01',
        'UN'
    )
ON CONFLICT (codigo_cuenta, sku) DO NOTHING;

INSERT INTO tipo_ubicacion (id_tipo_ubicacion, codigo_cuenta, id_bodega, codigo, nombre)
VALUES
    (
        'b1000001-0001-4001-8001-000000000001',
        'ACME-01',
        'b1111111-1111-1111-1111-111111111111',
        'ALM',
        'Almacenamiento CENTRAL test'
    ),
    (
        'b1000001-0001-4001-8001-000000000002',
        'ACME-01',
        'b2222222-2222-2222-2222-222222222222',
        'ALM',
        'Almacenamiento SUR test'
    )
ON CONFLICT (id_bodega, codigo) DO NOTHING;

INSERT INTO zona (id_zona, codigo_cuenta, id_bodega, codigo, nombre)
VALUES (
    'c1000001-0001-4001-8001-000000000001',
    'ACME-01',
    'b1111111-1111-1111-1111-111111111111',
    'Z-A',
    'Zona A test'
)
ON CONFLICT (id_bodega, codigo) DO NOTHING;

INSERT INTO ubicacion (id_ubicacion, codigo_cuenta, id_bodega, id_zona, id_tipo_ubicacion, codigo)
VALUES
    (
        'd1000001-0001-4001-8001-000000000001',
        'ACME-01',
        'b1111111-1111-1111-1111-111111111111',
        'c1000001-0001-4001-8001-000000000001',
        'b1000001-0001-4001-8001-000000000001',
        'A-01'
    ),
    (
        'd1000001-0001-4001-8001-000000000002',
        'ACME-01',
        'b2222222-2222-2222-2222-222222222222',
        NULL,
        'b1000001-0001-4001-8001-000000000002',
        'S-01'
    )
ON CONFLICT (id_bodega, codigo) DO NOTHING;

INSERT INTO warehouse_state (
    id_warehouse_state,
    codigo_cuenta,
    id_bodega,
    id_ubicacion,
    id_producto,
    cantidad
)
VALUES
    (
        'e1000001-0001-4001-8001-000000000001',
        'ACME-01',
        'b1111111-1111-1111-1111-111111111111',
        'd1000001-0001-4001-8001-000000000001',
        'a1000001-0001-4001-8001-000000000001',
        10
    ),
    (
        'e1000001-0001-4001-8001-000000000002',
        'ACME-01',
        'b2222222-2222-2222-2222-222222222222',
        'd1000001-0001-4001-8001-000000000002',
        'a1000001-0001-4001-8001-000000000001',
        5
    )
ON CONFLICT (id_ubicacion, id_producto, id_lote) DO NOTHING;

COMMIT;

-- Prueba 7
DO $$
DECLARE
    v_productos bigint;
    v_ve_beta boolean;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;
    SELECT COUNT(*) INTO v_productos FROM producto;
    SELECT EXISTS (SELECT 1 FROM producto WHERE codigo_cuenta = 'BETA-01') INTO v_ve_beta;
    RESET ROLE;
    PERFORM test_rls.assert_true('7 operador ACME-01 ve solo productos de su cuenta', v_productos = 1);
    PERFORM test_rls.assert_true('7 operador ACME-01 NO ve producto BETA', NOT v_ve_beta);
END;
$$;

-- Prueba 8
DO $$
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;
    BEGIN
        INSERT INTO warehouse_state (codigo_cuenta, id_bodega, id_ubicacion, id_producto, cantidad)
        VALUES ('ACME-01', 'b1111111-1111-1111-1111-111111111111', 'd1000001-0001-4001-8001-000000000001', 'a1000001-0001-4001-8001-000000000001', 999);
        RESET ROLE;
        RAISE EXCEPTION 'FALLÓ: 8 operador pudo INSERT en warehouse_state';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RESET ROLE;
            RAISE NOTICE 'OK: 8 operador bloqueado INSERT warehouse_state (insufficient_privilege)';
        WHEN OTHERS THEN
            RESET ROLE;
            IF SQLERRM LIKE '%row-level security%' OR SQLERRM LIKE '%violates%policy%' THEN
                RAISE NOTICE 'OK: 8 operador bloqueado INSERT warehouse_state (RLS: %)', SQLERRM;
            ELSE
                RAISE;
            END IF;
    END;
END;
$$;

-- Prueba 9
DO $$
DECLARE
    v_productos bigint;
    v_cuentas_distintas bigint;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
    SET LOCAL ROLE authenticated;
    SELECT COUNT(*) INTO v_productos FROM producto;
    SELECT COUNT(DISTINCT codigo_cuenta) INTO v_cuentas_distintas FROM producto;
    RESET ROLE;
    PERFORM test_rls.assert_true('9 configurador ve >=2 productos de prueba', v_productos >= 2);
    PERFORM test_rls.assert_true('9 configurador ve catálogos ACME y BETA', v_cuentas_distintas >= 2);
END;
$$;

-- Prueba 10
DO $$
DECLARE
    v_stock bigint;
    v_ve_sur boolean;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
    SET LOCAL ROLE authenticated;
    SELECT COUNT(*) INTO v_stock FROM warehouse_state;
    SELECT EXISTS (
        SELECT 1 FROM warehouse_state ws
        INNER JOIN bodega b ON b.id_bodega = ws.id_bodega
        WHERE b.codigo = 'SUR'
    ) INTO v_ve_sur;
    RESET ROLE;
    PERFORM test_rls.assert_true('10 custodio ve exactamente 1 fila warehouse_state', v_stock = 1);
    PERFORM test_rls.assert_true('10 custodio NO ve stock bodega SUR', NOT v_ve_sur);
END;
$$;

-- Prueba 11
DO $$
DECLARE
    v_ok boolean;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
    SET LOCAL ROLE authenticated;
    SELECT auth_wms_puede_ver_fila_operativa('ACME-01', 'b1111111-1111-1111-1111-111111111111'::uuid) INTO v_ok;
    RESET ROLE;
    PERFORM test_rls.assert_true('11 helper fila operativa OK para custodio en su bodega', v_ok);
END;
$$;

SELECT 'validate-rls-operativo-supabase.sql completado' AS resultado;
