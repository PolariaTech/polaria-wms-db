-- 081_usuario_telefono_unico.sql
-- El teléfono del perfil (usuario.telefono) es identificador de login a Mateo IA.
-- Debe ser único entre cuentas. NULL sigue permitido (sin teléfono = sin login por número).

-- Homologa formatos sueltos a E.164 antes del índice único.
UPDATE usuario
SET telefono = CASE
    WHEN telefono LIKE '+%' THEN '+' || regexp_replace(telefono, '\D', '', 'g')
    ELSE regexp_replace(telefono, '\D', '', 'g')
END
WHERE telefono IS NOT NULL
  AND btrim(telefono) <> '';

UPDATE usuario
SET telefono = '+57' || telefono
WHERE telefono ~ '^[3][0-9]{9}$';

UPDATE usuario
SET telefono = '+' || telefono
WHERE telefono ~ '^57[0-9]{10}$';

UPDATE usuario
SET telefono = NULL
WHERE telefono IS NOT NULL
  AND btrim(telefono) = '';

-- Si ya había duplicados, deja el usuario más antiguo y limpia el resto.
WITH ranked AS (
    SELECT
        id_usuario,
        row_number() OVER (
            PARTITION BY telefono
            ORDER BY created_at ASC, id_usuario ASC
        ) AS rn
    FROM usuario
    WHERE telefono IS NOT NULL
)
UPDATE usuario u
SET telefono = NULL
FROM ranked r
WHERE u.id_usuario = r.id_usuario
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_usuario_telefono
    ON usuario (telefono);

COMMENT ON COLUMN usuario.telefono IS
    'Teléfono E.164 del perfil. Único cuando está informado; identificador de login a Mateo IA.';
