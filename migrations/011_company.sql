-- ─────────────────────────────────────────────────────────────────────────────
-- Tabla empresa — cliente SaaS
-- La crea el configurador TI. Punto de partida del login V2: el usuario escribe
-- su codigoEmpresa y el sistema valida que exista y esté activa antes de
-- continuar con la autenticación.
--
-- NOTA sobre dependencia circular:
--   empresa.id_creador → usuario.id_usuario
--   usuario.codigo_empresa → empresa.codigo_empresa
-- Se resuelve creando la tabla sin esa FK y añadiéndola en 012_user.sql
-- una vez que la tabla usuario ya existe.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS empresa (
  codigo_empresa  varchar(32)  PRIMARY KEY,
  razon_social    varchar(255) NOT NULL,
  esta_activa     boolean      NOT NULL DEFAULT true,
  -- id_creador se enlaza a usuario en 012_user.sql (dependencia circular)
  id_creador      uuid         NULL,
  creado_en       timestamptz  NOT NULL DEFAULT now()
);

-- Índice parcial: sólo filas activas (frecuente en validación de login V2)
CREATE INDEX IF NOT EXISTS ix_empresa_activa
  ON empresa (esta_activa)
  WHERE esta_activa;
