-- =====================================================================
-- 013_account.sql
-- Tabla: cuenta (tenant operativo bajo una empresa).
-- La crea el configurador TI tras crear la empresa y el administrador
-- de cuenta. Catalogos y operacion diaria siguen scoped al codigo_cuenta.
--
-- Cierra el FK circular usuario.codigo_cuenta -> cuenta.codigo_cuenta,
-- que quedo pendiente en 012_user.sql.
-- =====================================================================

create table cuenta (
  codigo_cuenta     varchar(32)  primary key,
  codigo_empresa    varchar(32)  not null references empresa (codigo_empresa),
  nombre_comercial  varchar(255) not null,
  esta_activa       boolean      not null default true,
  -- Configurador TI que dio de alta el tenant.
  id_creador        uuid         references usuario (id_usuario),
  creado_en         timestamptz  not null default now()
);

create index ix_cuenta_empresa on cuenta (codigo_empresa);
create index ix_cuenta_activa  on cuenta (esta_activa) where esta_activa;

comment on table cuenta is 'Tenant operativo bajo una empresa; alcance de catalogos y operacion.';

-- ---------------------------------------------------------------------
-- Cierre del FK circular usuario -> cuenta (ahora que cuenta existe).
-- ---------------------------------------------------------------------
alter table usuario
  add constraint fk_usuario_cuenta
  foreign key (codigo_cuenta) references cuenta (codigo_cuenta);
