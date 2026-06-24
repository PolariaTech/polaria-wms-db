-- validate-rls-multitenant.sql — POL-2 aislamiento multi-tenant
--
-- Prerrequisitos: migraciones 001–018, bootstrap-auth.sql, validate-phase1.sql
--
-- Simulación de sesión (local o Supabase SQL Editor):
--   SET LOCAL ROLE authenticated;
--   SELECT set_config('app.test_auth_uid', '<id_auth>', true);
-- auth.uid() lee app.test_auth_uid o request.jwt.claim.sub (ver bootstrap-auth.sql).
--
-- Supabase sin SET ROLE: autenticarse en la app con cada usuario de prueba y ejecutar
-- los SELECT documentados al final de cada bloque de prueba.
--
-- IMPORTANTE: las pruebas usan SET LOCAL ROLE authenticated dentro de transacciones.
-- Ejecutar conectado como postgres (o rol con GRANT authenticated).

CREATE SCHEMA IF NOT EXISTS test_rls;

-- ---------------------------------------------------------------------------
-- auth.uid() de prueba (idempotente)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Seed extendido para RLS (idempotente)
-- ---------------------------------------------------------------------------
BEGIN;

INSERT INTO auth.users (id, email)
VALUES
    ('44444444-4444-4444-4444-444444444444', 'admin.empresa@acme.test'),
    ('55555555-5555-5555-5555-555555555555', 'custodio@acme.test'),
    ('66666666-6666-6666-6666-666666666666', 'ops2@acme.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO cuenta (codigo_cuenta, codigo_empresa, nombre_comercial, id_creador)
VALUES ('ACME-02', 'ACME', 'ACME Secundaria', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
ON CONFLICT (codigo_cuenta) DO NOTHING;

INSERT INTO empresa (codigo_empresa, razon_social, id_creador)
VALUES ('BETA', 'BETA Foods Ltda.', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
ON CONFLICT (codigo_empresa) DO NOTHING;

INSERT INTO cuenta (codigo_cuenta, codigo_empresa, nombre_comercial, id_creador)
VALUES ('BETA-01', 'BETA', 'BETA Operaciones', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
ON CONFLICT (codigo_cuenta) DO NOTHING;

INSERT INTO usuario (id_usuario, id_auth, id_rol, codigo_empresa, codigo_cuenta, id_creador, nombre, username, correo)
VALUES (
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    '44444444-4444-4444-4444-444444444444',
    'administrador_cuenta',
    'ACME',
    NULL,
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Admin Empresa ACME',
    'admin.empresa.acme',
    'admin.empresa@acme.test'
)
ON CONFLICT (id_usuario) DO NOTHING;

INSERT INTO usuario (id_usuario, id_auth, id_rol, codigo_empresa, codigo_cuenta, id_creador, nombre, username, correo)
VALUES (
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    '55555555-5555-5555-5555-555555555555',
    'custodio',
    'ACME',
    'ACME-01',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Custodio ACME Central',
    'custodio.acme',
    'custodio@acme.test'
)
ON CONFLICT (id_usuario) DO NOTHING;

INSERT INTO usuario (id_usuario, id_auth, id_rol, codigo_empresa, codigo_cuenta, id_creador, nombre, username, correo)
VALUES (
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
    '66666666-6666-6666-6666-666666666666',
    'operador_cuenta',
    'ACME',
    'ACME-02',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Operador ACME-02',
    'ops.acme02',
    'ops2@acme.test'
)
ON CONFLICT (id_usuario) DO NOTHING;

INSERT INTO bodega (id_bodega, codigo_cuenta, codigo, nombre)
VALUES
    (
        'b1111111-1111-1111-1111-111111111111',
        'ACME-01',
        'CENTRAL',
        'Bodega Central ACME-01'
    ),
    (
        'b2222222-2222-2222-2222-222222222222',
        'ACME-01',
        'SUR',
        'Bodega Sur ACME-01'
    )
ON CONFLICT (id_bodega) DO NOTHING;

INSERT INTO asignacion_bodega (id_usuario, id_bodega)
VALUES (
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    'b1111111-1111-1111-1111-111111111111'
)
ON CONFLICT (id_usuario, id_bodega) DO NOTHING;

COMMIT;

-- ---------------------------------------------------------------------------
-- Utilidad: fallar si condición no se cumple
-- ---------------------------------------------------------------------------
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
-- Prueba 1: Configurador ve todas las empresas y cuentas
-- id_auth: 11111111-1111-1111-1111-111111111111
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_empresas bigint;
    v_cuentas bigint;
BEGIN
    PERFORM set_config('app.test_auth_uid', '11111111-1111-1111-1111-111111111111', true);
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*) INTO v_empresas FROM empresa;
    SELECT COUNT(*) INTO v_cuentas FROM cuenta;

    RESET ROLE;

    PERFORM test_rls.assert_true(
        '1 configurador ve >=2 empresas (ACME, BETA)',
        v_empresas >= 2
    );
    PERFORM test_rls.assert_true(
        '1 configurador ve >=3 cuentas (ACME-01, ACME-02, BETA-01)',
        v_cuentas >= 3
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 2: Operador ACME-01 NO ve cuenta ACME-02
-- id_auth: 33333333-3333-3333-3333-333333333333
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_cuentas bigint;
    v_ve_acme02 boolean;
BEGIN
    PERFORM set_config('app.test_auth_uid', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*) INTO v_cuentas FROM cuenta;
    SELECT EXISTS (
        SELECT 1 FROM cuenta WHERE codigo_cuenta = 'ACME-02'
    ) INTO v_ve_acme02;

    RESET ROLE;

    PERFORM test_rls.assert_true('2 operador ACME-01 ve exactamente 1 cuenta', v_cuentas = 1);
    PERFORM test_rls.assert_true('2 operador ACME-01 NO ve ACME-02', NOT v_ve_acme02);
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 3: administrador_cuenta sin codigo_cuenta ve todas las cuentas de su empresa
-- id_auth: 44444444-4444-4444-4444-444444444444
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_cuentas_acme bigint;
    v_ve_beta boolean;
BEGIN
    PERFORM set_config('app.test_auth_uid', '44444444-4444-4444-4444-444444444444', true);
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*) INTO v_cuentas_acme
    FROM cuenta
    WHERE codigo_empresa = 'ACME';

    SELECT EXISTS (
        SELECT 1 FROM cuenta WHERE codigo_cuenta = 'BETA-01'
    ) INTO v_ve_beta;

    RESET ROLE;

    PERFORM test_rls.assert_true(
        '3 admin empresa ve ACME-01 y ACME-02',
        v_cuentas_acme = 2
    );
    PERFORM test_rls.assert_true('3 admin empresa NO ve cuentas BETA', NOT v_ve_beta);
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 4: Custodio con asignacion_bodega solo ve su bodega (misma cuenta)
-- id_auth: 55555555-5555-5555-5555-555555555555
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_bodegas bigint;
    v_ve_sur boolean;
BEGIN
    PERFORM set_config('app.test_auth_uid', '55555555-5555-5555-5555-555555555555', true);
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*) INTO v_bodegas FROM bodega;
    SELECT EXISTS (
        SELECT 1 FROM bodega WHERE codigo = 'SUR'
    ) INTO v_ve_sur;

    RESET ROLE;

    PERFORM test_rls.assert_true('4 custodio ve exactamente 1 bodega', v_bodegas = 1);
    PERFORM test_rls.assert_true('4 custodio NO ve bodega SUR', NOT v_ve_sur);
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 5: Operador authenticated NO puede INSERT en bodega
-- id_auth: 33333333-3333-3333-3333-333333333333
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM set_config('app.test_auth_uid', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    BEGIN
        INSERT INTO bodega (codigo_cuenta, codigo, nombre)
        VALUES ('ACME-01', 'HACK', 'Inyección RLS');
        RESET ROLE;
        RAISE EXCEPTION 'FALLÓ: 5 operador pudo INSERT en bodega';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RESET ROLE;
            RAISE NOTICE 'OK: 5 operador bloqueado (insufficient_privilege)';
        WHEN OTHERS THEN
            RESET ROLE;
            IF SQLERRM LIKE '%row-level security%' OR SQLERRM LIKE '%violates%policy%' THEN
                RAISE NOTICE 'OK: 5 operador bloqueado (RLS: %)', SQLERRM;
            ELSE
                RAISE;
            END IF;
    END;
END;
$$;

-- ---------------------------------------------------------------------------
-- Prueba 6: usuario_select_own — operador A no ve fila de usuario B
-- id_auth A: 33333333... (ops ACME-01) | B existe: ffffffff... (ops ACME-02)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_usuarios bigint;
    v_ve_otro boolean;
BEGIN
    PERFORM set_config('app.test_auth_uid', '33333333-3333-3333-3333-333333333333', true);
    SET LOCAL ROLE authenticated;

    SELECT COUNT(*) INTO v_usuarios FROM usuario;
    SELECT EXISTS (
        SELECT 1 FROM usuario WHERE id_usuario = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
    ) INTO v_ve_otro;

    RESET ROLE;

    PERFORM test_rls.assert_true('6 operador A ve solo su fila (count=1)', v_usuarios = 1);
    PERFORM test_rls.assert_true('6 operador A NO ve operador B', NOT v_ve_otro);
END;
$$;

-- ---------------------------------------------------------------------------
-- Resumen
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '=== validate-rls-multitenant: 6 pruebas completadas ===';
END;
$$;

-- Limpieza opcional del helper de test (descomentar si no se desea dejar en BD):
-- DROP FUNCTION IF EXISTS test_rls.assert_true(text, boolean);
