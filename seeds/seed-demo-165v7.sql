-- =============================================================================
-- seed-demo-165v7.sql — Datos mínimos de demo para cuenta 165V7 (P0)
-- =============================================================================
--
-- README — Cómo ejecutar
-- ----------------------
-- Prerrequisitos:
--   • Migraciones 001–041 aplicadas en el proyecto Supabase.
--   • Tenant existente: cuenta `165V7`, admin username `675PB`,
--     operador cuenta `operador@polaria.tech`, operador bodega `WXM6M`.
--   • Este script NO crea usuarios ni la cuenta; solo catálogo, layout y stock.
--
-- Supabase SQL Editor:
--   1. Dashboard → SQL → New query.
--   2. Pegar este archivo completo y ejecutar como rol postgres (por defecto).
--   3. Revisar mensajes NOTICE al final; no debe haber ERROR.
--
-- Supabase CLI (remoto enlazado):
--   npx supabase db query --linked -f seeds/seed-demo-165v7.sql
--
-- Idempotencia:
--   • Usa INSERT … ON CONFLICT DO NOTHING / UPDATE condicional.
--   • No borra ni modifica filas de otras cuentas (p. ej. ACME-01).
--   • Re-ejecutar es seguro: completa solo lo que falte.
--
-- Contenido mínimo:
--   • 1 bodega interna DEMO-INT
--   • Layout: tipo_ubicacion, zona, ubicación
--   • 1 proveedor, 1 cliente, 1 comprador
--   • 2 productos (primario + secundario con reglas de conversión)
--   • warehouse_state con stock > 0 del primario
--   • asignacion_bodega de WXM6M → bodega demo (si el usuario existe)
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_codigo_cuenta   constant varchar := '165V7';
    v_bodega_codigo   constant varchar := 'DEMO-INT';

    v_id_bodega       uuid;
    v_id_tipo         uuid := '16570002-0001-4001-8001-000000000001';
    v_id_zona         uuid := '16570003-0001-4001-8001-000000000001';
    v_id_ubicacion    uuid := '16570004-0001-4001-8001-000000000001';
    v_id_proveedor    uuid := '16570005-0001-4001-8001-000000000001';
    v_id_cliente      uuid := '16570006-0001-4001-8001-000000000001';
    v_id_comprador    uuid := '16570007-0001-4001-8001-000000000001';
    v_id_prod_pri     uuid := '16570010-0001-4001-8001-000000000001';
    v_id_prod_sec     uuid := '16570011-0001-4001-8001-000000000001';
    v_id_stock        uuid := '16570020-0001-4001-8001-000000000001';

    v_id_admin        uuid;
    v_id_oper_bodega  uuid;
    v_stock           numeric;
BEGIN
    -- -------------------------------------------------------------------------
    -- Validaciones previas (tenant y usuarios de referencia)
    -- -------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM cuenta c
        WHERE c.codigo_cuenta = v_codigo_cuenta AND c.esta_activa
    ) THEN
        RAISE EXCEPTION
            'Cuenta % no existe o está inactiva. Crear tenant antes del seed.',
            v_codigo_cuenta;
    END IF;

    SELECT u.id_usuario INTO v_id_admin
    FROM usuario u
    WHERE u.username = '675PB'
      AND u.codigo_cuenta = v_codigo_cuenta
      AND u.esta_activo
    LIMIT 1;

    IF v_id_admin IS NULL THEN
        RAISE WARNING
            'Admin 675PB no encontrado en %; bodega se crea sin id_creador.',
            v_codigo_cuenta;
    END IF;

    SELECT u.id_usuario INTO v_id_oper_bodega
    FROM usuario u
    WHERE u.username = 'WXM6M'
      AND u.esta_activo
    LIMIT 1;

    IF v_id_oper_bodega IS NULL THEN
        RAISE WARNING
            'Operador bodega WXM6M no encontrado; se omite asignacion_bodega.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM usuario u
        WHERE u.correo = 'operador@polaria.tech'
          AND u.codigo_cuenta = v_codigo_cuenta
          AND u.esta_activo
    ) THEN
        RAISE WARNING
            'operador@polaria.tech no encontrado en %; seed continúa igualmente.',
            v_codigo_cuenta;
    END IF;

    -- -------------------------------------------------------------------------
    -- Bodega interna
    -- -------------------------------------------------------------------------
    INSERT INTO bodega (
        id_bodega,
        codigo_cuenta,
        codigo,
        nombre,
        tipo,
        esta_activa,
        id_creador
    ) VALUES (
        '16570001-0001-4001-8001-000000000001',
        v_codigo_cuenta,
        v_bodega_codigo,
        'Bodega demo 165V7',
        'interna',
        true,
        v_id_admin
    )
    ON CONFLICT (codigo_cuenta, codigo) DO NOTHING;

    SELECT b.id_bodega INTO v_id_bodega
    FROM bodega b
    WHERE b.codigo_cuenta = v_codigo_cuenta
      AND b.codigo = v_bodega_codigo;

    -- -------------------------------------------------------------------------
    -- Layout mínimo
    -- -------------------------------------------------------------------------
    INSERT INTO tipo_ubicacion (
        id_tipo_ubicacion, codigo_cuenta, id_bodega, codigo, nombre,
        es_almacenamiento
    ) VALUES (
        v_id_tipo, v_codigo_cuenta, v_id_bodega, 'ALM', 'Almacenamiento demo', true
    )
    ON CONFLICT (id_bodega, codigo) DO NOTHING;

    INSERT INTO zona (
        id_zona, codigo_cuenta, id_bodega, codigo, nombre
    ) VALUES (
        v_id_zona, v_codigo_cuenta, v_id_bodega, 'Z-DEMO', 'Zona demo'
    )
    ON CONFLICT (id_bodega, codigo) DO NOTHING;

    INSERT INTO ubicacion (
        id_ubicacion, codigo_cuenta, id_bodega, id_zona, id_tipo_ubicacion, codigo
    ) VALUES (
        v_id_ubicacion, v_codigo_cuenta, v_id_bodega, v_id_zona, v_id_tipo, 'A-01'
    )
    ON CONFLICT (id_bodega, codigo) DO NOTHING;

    -- -------------------------------------------------------------------------
    -- Catálogos mínimos
    -- -------------------------------------------------------------------------
    INSERT INTO proveedor (
        id_proveedor, codigo_cuenta, codigo, razon_social
    ) VALUES (
        v_id_proveedor, v_codigo_cuenta, 'DEMO-PROV', 'Proveedor demo 165V7'
    )
    ON CONFLICT (codigo_cuenta, codigo) DO NOTHING;

    INSERT INTO cliente (
        id_cliente, codigo_cuenta, codigo, nombre
    ) VALUES (
        v_id_cliente, v_codigo_cuenta, 'DEMO-CLI', 'Cliente demo 165V7'
    )
    ON CONFLICT (codigo_cuenta, codigo) DO NOTHING;

    INSERT INTO comprador (
        id_comprador, codigo_cuenta, codigo, nombre
    ) VALUES (
        v_id_comprador, v_codigo_cuenta, 'DEMO-COMP', 'Comprador demo 165V7'
    )
    ON CONFLICT (codigo_cuenta, codigo) DO NOTHING;

    -- -------------------------------------------------------------------------
    -- Productos: primario + secundario con conversión
    -- -------------------------------------------------------------------------
    INSERT INTO producto (
        id_producto,
        codigo_cuenta,
        sku,
        descripcion,
        unidad_medida,
        id_cliente,
        es_primario,
        es_secundario,
        codigo_almacen,
        unidad_visualizacion
    ) VALUES (
        v_id_prod_pri,
        v_codigo_cuenta,
        'DEMO-PRI-SALMON',
        'Salmón entero demo (primario)',
        'KG',
        v_id_cliente,
        true,
        false,
        'PRI-01',
        'peso'
    )
    ON CONFLICT (codigo_cuenta, sku) DO NOTHING;

    INSERT INTO producto (
        id_producto,
        codigo_cuenta,
        sku,
        descripcion,
        unidad_medida,
        id_cliente,
        es_primario,
        es_secundario,
        codigo_almacen,
        id_producto_primario,
        regla_conversion_cantidad_primario,
        regla_conversion_unidades_secundario,
        merma_pct,
        unidad_visualizacion
    ) VALUES (
        v_id_prod_sec,
        v_codigo_cuenta,
        'DEMO-SEC-FILETE',
        'Filete demo (secundario)',
        'UN',
        v_id_cliente,
        false,
        true,
        'SEC-01',
        v_id_prod_pri,
        1.0000,
        10.0000,
        5.00,
        'cantidad'
    )
    ON CONFLICT (codigo_cuenta, sku) DO NOTHING;

    -- En re-ejecución: asegurar vínculo primario→secundario si faltaba
    UPDATE producto p
    SET
        es_secundario = true,
        id_producto_primario = v_id_prod_pri,
        regla_conversion_cantidad_primario = 1.0000,
        regla_conversion_unidades_secundario = 10.0000,
        merma_pct = 5.00,
        id_cliente = v_id_cliente
    WHERE p.codigo_cuenta = v_codigo_cuenta
      AND p.sku = 'DEMO-SEC-FILETE'
      AND (
          p.id_producto_primario IS NULL
          OR p.regla_conversion_cantidad_primario IS NULL
      );

    -- -------------------------------------------------------------------------
    -- Stock del primario en bodega demo
    -- -------------------------------------------------------------------------
    INSERT INTO warehouse_state (
        id_warehouse_state,
        codigo_cuenta,
        id_bodega,
        id_ubicacion,
        id_producto,
        cantidad
    ) VALUES (
        v_id_stock,
        v_codigo_cuenta,
        v_id_bodega,
        v_id_ubicacion,
        v_id_prod_pri,
        500.0000
    )
    ON CONFLICT (id_ubicacion, id_producto, id_lote)
    DO UPDATE SET cantidad = GREATEST(warehouse_state.cantidad, EXCLUDED.cantidad);

    -- -------------------------------------------------------------------------
    -- Asignación bodega → operador WXM6M (roles nivel bodega)
    -- -------------------------------------------------------------------------
    IF v_id_oper_bodega IS NOT NULL THEN
        INSERT INTO asignacion_bodega (id_usuario, id_bodega, id_rol, esta_activa)
        SELECT v_id_oper_bodega, v_id_bodega, u.id_rol, true
        FROM usuario u
        WHERE u.id_usuario = v_id_oper_bodega
        ON CONFLICT (id_usuario, id_bodega) DO NOTHING;
    END IF;

    SELECT ws.cantidad INTO v_stock
    FROM warehouse_state ws
    WHERE ws.id_warehouse_state = v_id_stock;

    RAISE NOTICE 'seed-demo-165v7 OK | cuenta=% | bodega=% (%) | stock primario=% kg',
        v_codigo_cuenta, v_bodega_codigo, v_id_bodega, v_stock;
END;
$$;

COMMIT;

-- Verificación rápida (solo cuenta 165V7)
SELECT 'bodega' AS entidad, codigo, nombre
FROM bodega
WHERE codigo_cuenta = '165V7'
ORDER BY codigo;

SELECT 'producto' AS entidad, sku, es_primario, es_secundario,
       regla_conversion_cantidad_primario, regla_conversion_unidades_secundario
FROM producto
WHERE codigo_cuenta = '165V7'
  AND sku LIKE 'DEMO-%'
ORDER BY sku;

SELECT 'stock' AS entidad, p.sku, ws.cantidad, u.codigo AS ubicacion
FROM warehouse_state ws
JOIN producto p ON p.id_producto = ws.id_producto
JOIN ubicacion u ON u.id_ubicacion = ws.id_ubicacion
WHERE ws.codigo_cuenta = '165V7';

SELECT 'asignacion' AS entidad, u.username, b.codigo AS bodega, ab.id_rol
FROM asignacion_bodega ab
JOIN usuario u ON u.id_usuario = ab.id_usuario
JOIN bodega b ON b.id_bodega = ab.id_bodega
WHERE b.codigo_cuenta = '165V7'
  AND u.username = 'WXM6M';
