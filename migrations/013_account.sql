-- ─────────────────────────────────────────────────────────────────────────────
-- Tabla cuenta — tenant operativo
-- Tabla 4 del orden de lectura ER. El configurador TI la crea después de
-- registrar la empresa y el administrador de cuenta.
--
-- La cuenta es el "salón de trabajo": catálogos, compras y ventas van
-- vinculados a codigo_cuenta, no al nombre de la empresa.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS cuenta (
  codigo_cuenta    varchar(32)  PRIMARY KEY,
  codigo_empresa   varchar(32)  NOT NULL REFERENCES empresa (codigo_empresa),
  nombre_comercial varchar(255) NOT NULL,
  esta_activa      boolean      NOT NULL DEFAULT true,
  id_creador       uuid         NULL     REFERENCES usuario (id_usuario),
  creado_en        timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_cuenta_empresa ON cuenta (codigo_empresa);
CREATE INDEX IF NOT EXISTS ix_cuenta_activa  ON cuenta (esta_activa) WHERE esta_activa;

-- ── Cerrar FK pendiente: usuario.codigo_cuenta → cuenta ─────────────────────
-- La FK no se pudo declarar en 012_user.sql porque cuenta no existía aún.
ALTER TABLE usuario
  ADD CONSTRAINT fk_usuario_cuenta
  FOREIGN KEY (codigo_cuenta) REFERENCES cuenta (codigo_cuenta);

-- ── Solicitud de alta de bodega ──────────────────────────────────────────────
-- Tabla 5 del orden ER. El admin de cuenta pide una bodega; TI la atiende.
-- Se incluye aquí porque sus FKs apuntan a empresa, cuenta y usuario,
-- que ya existen. La FK a bodega (id_bodega) se añade en la migración de bodega.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS solicitud_alta_bodega (
  id_solicitud    uuid         PRIMARY KEY DEFAULT uuid_generate_v4(),
  codigo_empresa  varchar(32)  NOT NULL REFERENCES empresa (codigo_empresa),
  codigo_cuenta   varchar(32)  NOT NULL REFERENCES cuenta (codigo_cuenta),
  id_solicitante  uuid         NOT NULL REFERENCES usuario (id_usuario),
  nombre_solicitado varchar(255) NOT NULL,
  tipo            bodega_tipo  NOT NULL,
  comentarios     text         NULL,
  estado          estado_solicitud_bodega NOT NULL DEFAULT 'pendiente',
  -- Se llena cuando TI crea la bodega (FK a bodega se añade en migración de bodega)
  id_bodega       varchar(64)  NULL,
  id_atendido_por uuid         NULL REFERENCES usuario (id_usuario),
  creado_en       timestamptz  NOT NULL DEFAULT now(),
  atendido_en     timestamptz  NULL
);

CREATE INDEX IF NOT EXISTS ix_sol_bodega_tenant
  ON solicitud_alta_bodega (codigo_cuenta, estado);

-- Índice parcial para consultas de TI (bandeja de pendientes)
CREATE INDEX IF NOT EXISTS ix_sol_bodega_pendiente
  ON solicitud_alta_bodega (estado)
  WHERE estado = 'pendiente';
