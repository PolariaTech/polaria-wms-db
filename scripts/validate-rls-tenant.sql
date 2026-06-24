-- Validación POL-2: RLS por codigo_cuenta e id_bodega.
-- Ejecutar tras migraciones y, en local, tras scripts/bootstrap-auth.sql.

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(
    actual bigint,
    expected bigint,
    message text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF actual <> expected THEN
        RAISE EXCEPTION '%: esperado %, recibido %', message, expected, actual;
    END IF;

    RAISE NOTICE 'OK: %', message;
END;
$$;

INSERT INTO auth.users (id, email)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'ti@polaria.dev'),
    ('22222222-2222-2222-2222-222222222222', 'admin-a@acme.test'),
    ('33333333-3333-3333-3333-333333333333', 'admin-b@acme.test'),
    ('44444444-4444-4444-4444-444444444444', 'jefe-a1@acme.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO usuario (id_usuario, id_auth, id_rol, nombre, username, correo)
VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    'configurador',
    'Configurador TI',
    'ti.config',
    'ti@polaria.dev'
);

INSERT INTO empresa (codigo_empresa, razon_social, id_creador)
VALUES ('ACME', 'ACME Alimentos S.A.', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

INSERT INTO cuenta (codigo_cuenta, codigo_empresa, nombre_comercial, id_creador)
VALUES
    ('ACME-A', 'ACME', 'ACME Cuenta A', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    ('ACME-B', 'ACME', 'ACME Cuenta B', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

INSERT INTO usuario (
    id_usuario,
    id_auth,
    id_rol,
    codigo_empresa,
    codigo_cuenta,
    id_creador,
    nombre,
    username,
    correo
)
VALUES
    (
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        '22222222-2222-2222-2222-222222222222',
        'administrador_cuenta',
        'ACME',
        'ACME-A',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'Admin ACME A',
        'admin.acme.a',
        'admin-a@acme.test'
    ),
    (
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        '33333333-3333-3333-3333-333333333333',
        'administrador_cuenta',
        'ACME',
        'ACME-B',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'Admin ACME B',
        'admin.acme.b',
        'admin-b@acme.test'
    ),
    (
        'dddddddd-dddd-dddd-dddd-dddddddddddd',
        '44444444-4444-4444-4444-444444444444',
        'jefe_bodega',
        'ACME',
        'ACME-A',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'Jefe Bodega A1',
        'jefe.acme.a1',
        'jefe-a1@acme.test'
    );

INSERT INTO bodega (id_bodega, codigo_cuenta, codigo_bodega, nombre, id_creador)
VALUES
    (
        'e1111111-1111-1111-1111-111111111111',
        'ACME-A',
        'A-FRIO-01',
        'ACME A Frio 01',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    ),
    (
        'e2222222-2222-2222-2222-222222222222',
        'ACME-A',
        'A-FRIO-02',
        'ACME A Frio 02',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    ),
    (
        'e3333333-3333-3333-3333-333333333333',
        'ACME-B',
        'B-FRIO-01',
        'ACME B Frio 01',
        'cccccccc-cccc-cccc-cccc-cccccccccccc'
    );

INSERT INTO asignacion_bodega (id_usuario, id_bodega, id_creador)
VALUES (
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'e1111111-1111-1111-1111-111111111111',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
);

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT pg_temp.assert_eq((SELECT COUNT(*) FROM cuenta), 2, 'configurador ve todas las cuentas');
SELECT pg_temp.assert_eq((SELECT COUNT(*) FROM bodega), 3, 'configurador ve todas las bodegas');

SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT pg_temp.assert_eq((SELECT COUNT(*) FROM cuenta), 1, 'admin cuenta A ve solo su cuenta');
SELECT pg_temp.assert_eq((SELECT COUNT(*) FROM bodega), 2, 'admin cuenta A ve bodegas de su cuenta');
SELECT pg_temp.assert_eq(
    (SELECT COUNT(*) FROM cuenta WHERE codigo_cuenta = 'ACME-B'),
    0,
    'admin cuenta A no ve cuenta B de la misma empresa'
);

SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
SELECT pg_temp.assert_eq((SELECT COUNT(*) FROM cuenta), 1, 'rol bodega conserva visibilidad de su cuenta');
SELECT pg_temp.assert_eq((SELECT COUNT(*) FROM bodega), 1, 'rol bodega ve solo bodegas asignadas');
SELECT pg_temp.assert_eq(
    (SELECT COUNT(*) FROM bodega WHERE codigo_bodega = 'A-FRIO-02'),
    0,
    'rol bodega no ve otra bodega del mismo tenant sin asignacion'
);

DO $$
BEGIN
    INSERT INTO cuenta (codigo_cuenta, codigo_empresa, nombre_comercial)
    VALUES ('ACME-X', 'ACME', 'Intento cliente');

    RAISE EXCEPTION 'Se esperaba bloqueo de escritura para authenticated';
EXCEPTION
    WHEN insufficient_privilege OR check_violation THEN
        RAISE NOTICE 'OK: authenticated no puede escribir por RLS/permisos';
END $$;

ROLLBACK;
