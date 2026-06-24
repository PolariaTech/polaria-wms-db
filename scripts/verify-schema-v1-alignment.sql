-- verify-schema-v1-alignment.sql — comprobaciones migraciones 031–040
-- Ejecutar: npx supabase db query --linked -f scripts/verify-schema-v1-alignment.sql

-- 1) Tablas nuevas
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'solicitud_alta_bodega',
    'recepcion_compra',
    'recepcion_compra_linea',
    'solicitud_procesamiento',
    'registro_merma',
    'alerta_operativa',
    'tarea_cola',
    'solicitud_integracion',
    'tarea_cuenta'
  )
ORDER BY table_name;

-- 2) Columnas clave ampliadas
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    (table_name = 'bodega' AND column_name IN ('tipo', 'capacidad_slots', 'id_creador'))
    OR (table_name = 'asignacion_bodega' AND column_name = 'id_rol')
    OR (table_name = 'producto' AND column_name IN ('es_primario', 'es_secundario', 'codigo_almacen'))
    OR (table_name = 'ubicacion' AND column_name = 'estado_slot')
    OR (table_name = 'lote' AND column_name = 'estado_lote')
    OR (table_name = 'warehouse_state' AND column_name = 'cantidad_reservada')
    OR (table_name = 'orden_venta' AND column_name IN ('id_comprador', 'id_planta', 'id_bodega_destino'))
    OR (table_name = 'viaje_transporte' AND column_name = 'id_camion')
  )
ORDER BY table_name, column_name;

-- 3) Migraciones registradas en Supabase
SELECT version, name
FROM supabase_migrations.schema_migrations
WHERE name LIKE '%031%' OR name LIKE '%032%' OR name LIKE '%033%'
   OR name LIKE '%034%' OR name LIKE '%035%' OR name LIKE '%036%'
   OR name LIKE '%037%' OR name LIKE '%038%' OR name LIKE '%039%'
   OR name LIKE '%040%'
ORDER BY version;
