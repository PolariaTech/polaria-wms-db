-- 054_usuario_telefono.sql — teléfono opcional en usuario (configurador)

ALTER TABLE usuario
    ADD COLUMN IF NOT EXISTS telefono varchar(32);

COMMENT ON COLUMN usuario.telefono IS
    'Teléfono en formato internacional E.164 (opcional).';
