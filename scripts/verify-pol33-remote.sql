-- verify-pol33-remote.sql — comprobaciones POL-33 en Supabase remoto
-- Ejecutar: npx supabase db query --linked -f scripts/verify-pol33-remote.sql

-- 1) Tablas operativas con RLS
SELECT c.relname AS tabla, c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN (
    'tipo_ubicacion', 'zona', 'ubicacion',
    'proveedor', 'cliente', 'producto', 'comprador', 'planta', 'camion',
    'solicitud_compra', 'solicitud_compra_linea', 'orden_compra', 'orden_compra_linea',
    'lote', 'warehouse_state', 'movimiento_inventario',
    'orden_trabajo', 'orden_trabajo_linea', 'orden_venta', 'orden_venta_linea',
    'viaje_transporte', 'guia_envio', 'evidencia_transporte',
    'contador', 'auditoria_operacion'
  )
ORDER BY c.relname;

-- 2) Políticas en tablas clave
SELECT tablename, policyname, cmd, roles::text
FROM pg_policies
WHERE tablename IN ('warehouse_state', 'producto', 'orden_compra')
ORDER BY tablename, policyname;

-- 3) Helper 030
SELECT proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND proname = 'auth_wms_puede_ver_fila_operativa';
