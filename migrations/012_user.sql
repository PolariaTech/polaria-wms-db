-- ─────────────────────────────────────────────────────────────────────────────
-- Tabla usuario + sesion_auth
-- Tabla 3 (admin cuenta) y Tabla 14 (resto de usuarios) del orden de lectura ER.
--
-- Reglas clave:
--   · configurador TI → codigo_empresa = NULL, codigo_cuenta = NULL
--   · admin_cuenta    → codigo_empresa obligatorio, codigo_cuenta puede ser NULL
--                       hasta que el configurador cree el tenant
--   · resto de roles  → codigo_empresa y codigo_cuenta obligatorios
--
-- FK codigo_cuenta se añade en 013_account.sql (cuenta todavía no existe).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS usuario (
  id_usuario      uuid         PRIMARY KEY DEFAULT uuid_generate_v4(),
  id_rol          wms_rol      NOT NULL REFERENCES rol (id_rol),
  codigo_empresa  varchar(32)  NULL        REFERENCES empresa (codigo_empresa),
  -- codigo_cuenta: FK a cuenta; se añade en 013_account.sql
  codigo_cuenta   varchar(32)  NULL,
  -- Auto-referencia: quién creó a este usuario (NULL = primer configurador TI)
  id_creador      uuid         NULL        REFERENCES usuario (id_usuario),
  nombre          varchar(255) NOT NULL,
  correo          citext       NOT NULL,
  esta_activo     boolean      NOT NULL DEFAULT true,
  creado_en       timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT uq_usuario_correo UNIQUE (correo)
);

CREATE INDEX IF NOT EXISTS ix_usuario_empresa  ON usuario (codigo_empresa);
CREATE INDEX IF NOT EXISTS ix_usuario_cuenta   ON usuario (codigo_cuenta);
CREATE INDEX IF NOT EXISTS ix_usuario_rol      ON usuario (id_rol);

-- ── Cerrar la dependencia circular empresa ↔ usuario ─────────────────────────
-- Ahora que usuario existe, registramos la FK que quedó pendiente en 011.
ALTER TABLE empresa
  ADD CONSTRAINT fk_empresa_creador
  FOREIGN KEY (id_creador) REFERENCES usuario (id_usuario);

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabla sesion_auth — puente entre auth.users (Supabase) y public.usuario
--
-- Supabase gestiona las credenciales en auth.users. Esta tabla vincula el UUID
-- de auth con el perfil operativo del WMS. Usada para:
--   · Resolver el rol y tenant tras el login (paso 4 del flujo V2).
--   · Registrar el último acceso.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sesion_auth (
  -- Mismo UUID que auth.users.id en Supabase
  id_auth       uuid        PRIMARY KEY,
  id_usuario    uuid        NOT NULL UNIQUE REFERENCES usuario (id_usuario),
  correo        citext      NOT NULL,
  ultimo_acceso timestamptz NULL,
  CONSTRAINT uq_sesion_correo UNIQUE (correo)
);

-- ── Asignación bodega ─────────────────────────────────────────────────────────
-- Tabla 7 del orden de lectura ER. Se incluye aquí porque sus FKs apuntan a
-- usuario, bodega y rol. bodega se crea después (fase de plataforma), pero la
-- tabla se define ahora y la FK a bodega se añade cuando exista la tabla.
--
-- Permite que el admin de cuenta se auto-asigne a su bodega y luego asigne
-- al resto de roles operativos.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS asignacion_bodega (
  id_asignacion  uuid           PRIMARY KEY DEFAULT uuid_generate_v4(),
  id_usuario     uuid           NOT NULL REFERENCES usuario (id_usuario),
  -- id_bodega: FK a bodega; se añade cuando bodega exista
  id_bodega      varchar(64)    NOT NULL,
  id_rol         wms_rol_bodega NOT NULL,
  vigente_desde  timestamptz    NOT NULL DEFAULT now(),
  esta_activa    boolean        NOT NULL DEFAULT true,
  CONSTRAINT uq_asignacion UNIQUE (id_usuario, id_bodega, id_rol)
);

CREATE INDEX IF NOT EXISTS ix_asig_bodega  ON asignacion_bodega (id_bodega);
CREATE INDEX IF NOT EXISTS ix_asig_usuario ON asignacion_bodega (id_usuario);
