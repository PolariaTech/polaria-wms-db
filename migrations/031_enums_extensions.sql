-- Alineación v1/v2: enums operativos adicionales (031).

CREATE TYPE bodega_tipo AS ENUM ('interna', 'externa');

CREATE TYPE estado_solicitud_bodega AS ENUM (
    'pendiente',
    'atendida',
    'rechazada',
    'cancelada'
);

CREATE TYPE destino_tipo AS ENUM ('interna', 'externa');

CREATE TYPE estado_slot AS ENUM (
    'libre',
    'ocupado',
    'reservado',
    'en_proceso'
);

CREATE TYPE estado_lote AS ENUM (
    'activo',
    'bloqueado',
    'vencido',
    'agotado'
);

CREATE TYPE tipo_camion AS ENUM (
    'refrigerado',
    'seco',
    'isotermico'
);

CREATE TYPE estado_procesamiento AS ENUM (
    'borrador',
    'pendiente',
    'en_proceso',
    'pendiente_cierre',
    'terminada',
    'cancelada'
);

CREATE TYPE tipo_alerta AS ENUM (
    'temperatura',
    'demora',
    'orden_reportada',
    'otro'
);

CREATE TYPE estado_alerta AS ENUM (
    'abierta',
    'cerrada'
);

CREATE TYPE tipo_tarea AS ENUM (
    'ingreso',
    'movimiento',
    'despacho',
    'procesamiento',
    'revision',
    'otro'
);

CREATE TYPE estado_tarea AS ENUM (
    'pendiente',
    'en_proceso',
    'completada',
    'cancelada'
);

CREATE TYPE estado_tarea_cuenta AS ENUM (
    'pendiente',
    'resuelta'
);

CREATE TYPE estado_integracion AS ENUM (
    'activo',
    'finalizado'
);
