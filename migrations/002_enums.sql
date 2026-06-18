-- =====================================================================
-- 002_enums.sql
-- Tipos ENUM del dominio RBAC (roles y niveles) necesarios para el login.
-- Otros enums (bodega_tipo, estados de orden, etc.) se agregaran en
-- migraciones posteriores cuando se creen sus tablas.
-- =====================================================================

-- Nivel del rol: define el alcance del perfil dentro del sistema.
create type rol_nivel as enum (
  'plataforma',  -- equipo TI del proveedor SaaS (configurador)
  'cuenta',      -- administrador / operador del cliente (tenant)
  'bodega'       -- equipo operativo fisico de una bodega
);

-- Rol WMS: catalogo fijo de 9 perfiles (ver tabla rol).
create type wms_rol as enum (
  'configurador',
  'administrador_cuenta',
  'operador_cuenta',
  'administrador_bodega',
  'jefe_bodega',
  'custodio',
  'operario',
  'procesador',
  'transportista'
);

-- Subconjunto de roles asignables a nivel de bodega (asignacion_bodega).
create type wms_rol_bodega as enum (
  'administrador_bodega',
  'jefe_bodega',
  'custodio',
  'operario',
  'procesador',
  'transportista'
);
