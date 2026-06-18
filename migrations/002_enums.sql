-- Roles operativos del WMS (catálogo fijo, 9 valores)
CREATE TYPE wms_rol AS ENUM (
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

-- Nivel de alcance del rol (plataforma / cuenta / bodega)
CREATE TYPE rol_nivel AS ENUM (
    'plataforma',
    'cuenta',
    'bodega'
);
