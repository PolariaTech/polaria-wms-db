-- ─────────────────────────────────────────────────────────────────────────────
-- ENUMs del modelo 3NF — Bodega de Frío
-- Todos los dominios cerrados del sistema. Orden: RBAC → plataforma → operación
-- ─────────────────────────────────────────────────────────────────────────────

-- ── RBAC ─────────────────────────────────────────────────────────────────────

-- Los 9 roles fijos del WMS (ver wmsRoles.js y tabla rol)
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

-- Sub-conjunto de roles que pueden asignarse a una bodega específica
CREATE TYPE wms_rol_bodega AS ENUM (
  'administrador_bodega',
  'jefe_bodega',
  'custodio',
  'operario',
  'procesador',
  'transportista'
);

-- Nivel jerárquico del rol
CREATE TYPE rol_nivel AS ENUM ('plataforma', 'cuenta', 'bodega');

-- ── Plataforma / bodegas ──────────────────────────────────────────────────────

CREATE TYPE bodega_tipo AS ENUM ('interna', 'externa');

CREATE TYPE estado_solicitud_bodega AS ENUM (
  'pendiente',
  'aprobada',
  'rechazada',
  'bodega_creada',
  'cancelada'
);

-- ── Catálogos ────────────────────────────────────────────────────────────────

CREATE TYPE unidad_medida AS ENUM ('kg', 'caja', 'unidad');

-- ── Compras ──────────────────────────────────────────────────────────────────

CREATE TYPE estado_solicitud_compra AS ENUM (
  'borrador',
  'enviada',
  'aprobada',
  'rechazada'
);

CREATE TYPE estado_orden_compra AS ENUM ('iniciado', 'en_recepcion', 'cerrado');

-- ── Ventas ───────────────────────────────────────────────────────────────────

CREATE TYPE estado_orden_venta AS ENUM (
  'borrador',
  'confirmada',
  'en_preparacion',
  'en_transito',
  'cerrado_ok',
  'cerrado_no_ok'
);

-- ── Bodega en vivo ───────────────────────────────────────────────────────────

CREATE TYPE estado_slot AS ENUM ('libre', 'ocupado', 'reservado', 'en_proceso');

CREATE TYPE zona_caja AS ENUM ('inbound', 'mapa', 'outbound', 'dispatched');

CREATE TYPE tipo_orden_trabajo AS ENUM ('a_bodega', 'a_salida', 'revisar');

CREATE TYPE estado_orden_trabajo AS ENUM ('pendiente', 'en_curso', 'completada');

CREATE TYPE estado_tarea AS ENUM (
  'pendiente',
  'en_curso',
  'completada',
  'cancelada'
);

CREATE TYPE tipo_tarea AS ENUM ('movimiento', 'conteo', 'despacho', 'inspeccion');

CREATE TYPE tipo_alerta AS ENUM ('temperatura', 'demora', 'orden_reportada');

-- ── Procesamiento ────────────────────────────────────────────────────────────

CREATE TYPE estado_procesamiento AS ENUM ('pendiente', 'en_curso', 'terminado');

-- ── Transporte ───────────────────────────────────────────────────────────────

CREATE TYPE estado_viaje AS ENUM (
  'programado',
  'en_ruta',
  'entregado',
  'incidencia',
  'cancelado'
);

-- ── Historial / auditoría ────────────────────────────────────────────────────

CREATE TYPE tipo_historial_movimiento AS ENUM (
  'ingreso',
  'movimiento',
  'despacho',
  'merma'
);

CREATE TYPE prefijo_documento AS ENUM ('OC', 'OV', 'TV', 'SOL');

CREATE TYPE accion_auditoria AS ENUM (
  'insert',
  'update',
  'delete',
  'login',
  'logout'
);
