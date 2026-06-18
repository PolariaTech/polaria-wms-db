-- =====================================================================
-- 011_company.sql
-- Tabla: empresa (cliente juridico del SaaS).
-- La crea el configurador TI tras iniciar sesion en la plataforma.
-- Es el punto de entrada del Login V2 (paso 1: validar codigo_empresa).
--
-- Nota sobre el FK circular:
--   empresa.id_creador -> usuario.id_usuario
--   usuario.codigo_empresa -> empresa.codigo_empresa
-- La tabla usuario aun no existe en este punto, por lo que la FK
-- empresa.id_creador se agrega en 012_user.sql (ALTER TABLE).
-- =====================================================================

create table empresa (
  codigo_empresa  varchar(32)  primary key,
  razon_social    varchar(255) not null,
  esta_activa     boolean      not null default true,
  -- Configurador TI que registro la empresa (FK agregada en 012_user.sql).
  id_creador      uuid,
  creado_en       timestamptz  not null default now()
);

-- Solo empresas activas se consultan en el login -> indice parcial.
create index ix_empresa_activa on empresa (esta_activa) where esta_activa;

comment on table empresa is 'Cliente juridico del SaaS; punto de entrada del Login V2 (codigo_empresa).';
comment on column empresa.id_creador is 'Configurador TI que registro la empresa (FK a usuario.id_usuario).';
