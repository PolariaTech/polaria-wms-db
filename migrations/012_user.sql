-- =====================================================================
-- 012_user.sql
-- Tabla: usuario (perfil operativo). Espejo de auth.users (Supabase Auth),
-- enlazado por id_usuario. La contrasena vive en Supabase Auth, no aqui.
--
-- Login V2:
--   1) validar empresa (codigo_empresa) existe y esta activa
--   2) validar que el usuario pertenece a esa empresa (correo/identificador)
--   3) contrasena via Supabase Auth -> sesion
--   4) cargar id_rol, tenant y permisos -> dashboard segun rol
--
-- codigo_empresa es obligatorio salvo para el configurador TI.
-- codigo_cuenta puede ser NULL (configurador, o admin sin tenant asignado);
-- su FK se agrega en 013_account.sql porque cuenta aun no existe.
-- =====================================================================

create table usuario (
  id_usuario      uuid         primary key default gen_random_uuid(),
  id_rol          wms_rol      not null references rol (id_rol),
  codigo_empresa  varchar(32)  references empresa (codigo_empresa),
  -- Tenant operativo; FK agregada en 013_account.sql.
  codigo_cuenta   varchar(32),
  id_creador      uuid         references usuario (id_usuario),
  nombre          varchar(255) not null,
  correo          citext       not null unique,
  esta_activo     boolean      not null default true,
  creado_en       timestamptz  not null default now(),

  -- codigo_empresa solo puede ser NULL para el configurador (nivel plataforma).
  constraint chk_usuario_empresa
    check (id_rol = 'configurador' or codigo_empresa is not null)
);

create index ix_usuario_empresa on usuario (codigo_empresa);
create index ix_usuario_cuenta  on usuario (codigo_cuenta);
create index ix_usuario_rol     on usuario (id_rol);

comment on table usuario is 'Perfil operativo; espejo de auth.users enlazado por id_usuario.';
comment on column usuario.codigo_empresa is 'Empresa del login; NULL solo para configurador (TI).';
comment on column usuario.codigo_cuenta is 'Tenant operativo; NULL en configurador o admin sin tenant.';

-- ---------------------------------------------------------------------
-- Cierre del FK circular empresa -> usuario (ahora que usuario existe).
-- ---------------------------------------------------------------------
alter table empresa
  add constraint fk_empresa_creador
  foreign key (id_creador) references usuario (id_usuario);
