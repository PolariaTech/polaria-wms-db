-- ─────────────────────────────────────────────────────────────────────────────
-- Tabla 0 (orden de lectura ER) — rol
-- Catálogo fijo de 9 roles del WMS. No lo modifica el cliente; es seed de TI.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rol (
  id_rol          wms_rol      PRIMARY KEY,
  nombre          varchar(255) NOT NULL,
  nivel           rol_nivel    NOT NULL,
  -- Qué rol puede dar de alta este perfil (NULL = nadie puede crearlo externamente)
  puede_crear_rol wms_rol      NULL REFERENCES rol(id_rol),
  descripcion     text         NULL
);

CREATE INDEX IF NOT EXISTS ix_rol_nivel ON rol (nivel);

-- ── Seed: 9 roles fijos ──────────────────────────────────────────────────────
-- ON CONFLICT DO NOTHING permite re-ejecutar la migración de forma idempotente

INSERT INTO rol (id_rol, nombre, nivel, puede_crear_rol, descripcion)
VALUES
  (
    'configurador',
    'Configurador (TI)',
    'plataforma',
    NULL,
    'Equipo TI del proveedor SaaS con credenciales propias (Supabase Auth). '
    'Inicia sesión en el panel de plataforma, crea empresas y asigna el '
    'administrador de cuenta de cada cliente.'
  ),
  (
    'administrador_cuenta',
    'Administrador de cuenta',
    'cuenta',
    'configurador',
    'Responsable del cliente, creado por TI y vinculado a codigo_empresa. '
    'Ingresa con login V2 (empresa + usuario + contraseña). '
    'Gestiona tenant, catálogos y equipo.'
  ),
  (
    'operador_cuenta',
    'Operador de cuenta',
    'cuenta',
    'administrador_cuenta',
    'Opera el tenant a nivel comercial: solicitudes, órdenes de compra y ventas. '
    'Lo crea el administrador de cuenta.'
  ),
  (
    'administrador_bodega',
    'Administrador de bodega',
    'bodega',
    'administrador_cuenta',
    'Responsable de la bodega asignada a la empresa: '
    'configuración operativa y supervisión.'
  ),
  (
    'jefe_bodega',
    'Jefe de bodega',
    'bodega',
    'administrador_cuenta',
    'Jefe operativo de la bodega: prioriza órdenes de trabajo, '
    'alertas y override de temperatura.'
  ),
  (
    'custodio',
    'Custodio',
    'bodega',
    'administrador_cuenta',
    'Recibe mercancía, valida documentos y temperatura, '
    'y despacha salidas en muelle.'
  ),
  (
    'operario',
    'Operario',
    'bodega',
    'administrador_cuenta',
    'Ejecuta órdenes de trabajo y movimientos de cajas/slots en la bodega.'
  ),
  (
    'procesador',
    'Procesador',
    'bodega',
    'administrador_cuenta',
    'Encargado de la línea de procesamiento (primario → secundario, merma).'
  ),
  (
    'transportista',
    'Transportista',
    'bodega',
    'administrador_cuenta',
    'Conduce viajes TV, registra entregas y evidencias (foto, firma, GPS).'
  )
ON CONFLICT (id_rol) DO NOTHING;
