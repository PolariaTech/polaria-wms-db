-- =====================================================================
-- 010_roles.sql
-- Tabla 0 del modelo: rol (catalogo fijo de perfiles del WMS).
-- Es la primera tabla a leer/crear. No depende de ninguna otra.
-- Semilla: 9 roles acordados con el negocio (wmsRoles.js).
-- =====================================================================

create table rol (
  id_rol           wms_rol     primary key,
  nombre           varchar(255) not null,
  nivel            rol_nivel    not null,
  -- Rol que puede dar de alta este perfil (jerarquia de creacion).
  puede_crear_rol  wms_rol,
  descripcion      text
);

create index ix_rol_nivel on rol (nivel);

comment on table rol is 'Catalogo fijo de perfiles del WMS (3NF, tabla 0).';
comment on column rol.puede_crear_rol is 'Rol con permiso para crear este perfil; NULL = no lo crea otro rol.';

-- ---------------------------------------------------------------------
-- Semilla de roles (orden por jerarquia de creacion)
-- ---------------------------------------------------------------------
insert into rol (id_rol, nombre, nivel, puede_crear_rol, descripcion) values
  ('configurador',         'Configurador (TI)',         'plataforma', null,
   'Equipo TI del proveedor SaaS con credenciales propias (Supabase Auth). Crea empresas y asigna el administrador de cuenta de cada cliente.'),
  ('administrador_cuenta', 'Administrador de cuenta',   'cuenta',     'configurador',
   'Responsable del cliente, creado por TI y vinculado a codigo_empresa. Gestiona tenant, catalogos y equipo.'),
  ('operador_cuenta',      'Operador de cuenta',        'cuenta',     'administrador_cuenta',
   'Opera el tenant a nivel comercial: SOL, OC, OV. Lo crea el administrador de cuenta.'),
  ('administrador_bodega', 'Administrador de bodega',   'bodega',     'administrador_cuenta',
   'Responsable de la bodega asignada: configuracion operativa y supervision.'),
  ('jefe_bodega',          'Jefe de bodega',            'bodega',     'administrador_cuenta',
   'Jefe operativo de la bodega: prioriza ordenes de trabajo, alertas, override de temperatura.'),
  ('custodio',             'Custodio',                  'bodega',     'administrador_cuenta',
   'Recibe mercancia, valida documentos y temperatura, y despacha salidas en muelle.'),
  ('operario',             'Operario',                  'bodega',     'administrador_cuenta',
   'Ejecuta ordenes de trabajo y movimientos de cajas/slots en la bodega.'),
  ('procesador',           'Procesador',                'bodega',     'administrador_cuenta',
   'Encargado de la linea de procesamiento (primario -> secundario, merma).'),
  ('transportista',        'Transportista',             'bodega',     'administrador_cuenta',
   'Conduce viajes TV, registra entregas y evidencias (foto, firma, GPS).');
