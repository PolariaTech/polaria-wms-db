-- Datos de prueba e integridad (ejecutar tras migraciones)
BEGIN;

INSERT INTO auth.users (id, email)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'ti@polaria.dev'),
    ('22222222-2222-2222-2222-222222222222', 'admin@acme.test'),
    ('33333333-3333-3333-3333-333333333333', 'ops@acme.test');

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

INSERT INTO usuario (id_usuario, id_auth, id_rol, codigo_empresa, id_creador, nombre, username, correo)
VALUES (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '22222222-2222-2222-2222-222222222222',
    'administrador_cuenta',
    'ACME',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Admin ACME',
    'admin.acme',
    'admin@acme.test'
);

INSERT INTO cuenta (codigo_cuenta, codigo_empresa, nombre_comercial, id_creador)
VALUES ('ACME-01', 'ACME', 'ACME Operaciones', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

UPDATE usuario
SET codigo_cuenta = 'ACME-01'
WHERE id_usuario = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

INSERT INTO usuario (id_usuario, id_auth, id_rol, codigo_empresa, codigo_cuenta, id_creador, nombre, username, correo)
VALUES (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '33333333-3333-3333-3333-333333333333',
    'operador_cuenta',
    'ACME',
    'ACME-01',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Operador ACME',
    'ops.acme',
    'ops@acme.test'
);

COMMIT;

-- Verificaciones
SELECT COUNT(*) AS roles_count FROM rol;
SELECT id_rol, codigo_empresa, codigo_cuenta FROM usuario ORDER BY username;
SELECT codigo_empresa, razon_social FROM empresa;
SELECT codigo_cuenta, codigo_empresa FROM cuenta;

-- Login V2: empresa + username
SELECT u.username, u.id_rol, e.codigo_empresa
FROM usuario u
JOIN empresa e ON e.codigo_empresa = u.codigo_empresa
WHERE e.codigo_empresa = 'ACME' AND u.username = 'admin.acme';

-- Debe fallar (cliente sin empresa)
DO $$
BEGIN
    INSERT INTO usuario (id_auth, id_rol, nombre, username, correo)
    VALUES (gen_random_uuid(), 'operador_cuenta', 'Invalido', 'bad', 'bad@test.com');
    RAISE EXCEPTION 'Se esperaba violación de chk_usuario_contexto';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'OK: chk_usuario_contexto rechazó cliente sin empresa';
END $$;
