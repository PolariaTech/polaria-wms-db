-- Alinea funciones bot OV con estado por_confirmar (ya no existe borrador en el enum).

CREATE OR REPLACE FUNCTION public.bot_emitir_orden_venta(p_id_orden_venta uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ov public.orden_venta%ROWTYPE;
  v_id_usuario uuid;
  v_id_destino uuid;
  v_linea RECORD;
  v_ws RECORD;
  v_restante numeric;
  v_tomar numeric;
  v_ot_id uuid;
  v_ot_codigo text;
  v_ot_valor bigint;
  v_allocs int := 0;
  v_ots int := 0;
BEGIN
  UPDATE public.orden_venta
  SET estado = 'confirmada', updated_at = now()
  WHERE id_orden_venta = p_id_orden_venta AND estado = 'por_confirmar'
  RETURNING * INTO v_ov;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'OV no está por confirmar o no existe');
  END IF;

  v_id_usuario := COALESCE(
    v_ov.id_creador,
    (SELECT id_usuario FROM public.usuario WHERE id_rol = 'configurador' AND esta_activo LIMIT 1)
  );

  SELECT u.id_ubicacion INTO v_id_destino
  FROM public.ubicacion u
  JOIN public.tipo_ubicacion tu ON tu.id_tipo_ubicacion = u.id_tipo_ubicacion
  WHERE u.id_bodega = v_ov.id_bodega
    AND u.codigo_cuenta = v_ov.codigo_cuenta
    AND u.esta_activa = true
    AND u.estado_slot = 'libre'
    AND tu.es_picking = true
  ORDER BY u.codigo
  LIMIT 1;

  IF v_id_destino IS NULL THEN
    SELECT u.id_ubicacion INTO v_id_destino
    FROM public.ubicacion u
    JOIN public.tipo_ubicacion tu ON tu.id_tipo_ubicacion = u.id_tipo_ubicacion
    WHERE u.id_bodega = v_ov.id_bodega
      AND u.esta_activa = true
      AND tu.es_picking = true
    ORDER BY u.codigo
    LIMIT 1;
  END IF;

  IF v_id_destino IS NULL THEN
    RAISE EXCEPTION 'UBICACION_DESTINO_NOT_FOUND';
  END IF;

  FOR v_linea IN
    SELECT id_producto, cantidad_pedida::numeric AS cantidad_pedida
    FROM public.orden_venta_linea
    WHERE id_orden_venta = v_ov.id_orden_venta
  LOOP
    v_restante := v_linea.cantidad_pedida;

    FOR v_ws IN
      SELECT ws.id_warehouse_state, ws.id_ubicacion, ws.id_lote, ws.id_producto,
             (ws.cantidad - ws.cantidad_reservada)::numeric AS disponible
      FROM public.warehouse_state ws
      JOIN public.ubicacion u ON u.id_ubicacion = ws.id_ubicacion AND u.esta_activa = true
      JOIN public.tipo_ubicacion tu ON tu.id_tipo_ubicacion = u.id_tipo_ubicacion AND tu.es_almacenamiento = true
      LEFT JOIN public.lote lt ON lt.id_lote = ws.id_lote
      WHERE ws.codigo_cuenta = v_ov.codigo_cuenta
        AND ws.id_bodega = v_ov.id_bodega
        AND ws.id_producto = v_linea.id_producto
        AND (ws.cantidad - ws.cantidad_reservada) > 0
      ORDER BY lt.fecha_vencimiento NULLS LAST, ws.updated_at
    LOOP
      EXIT WHEN v_restante <= 0;
      v_tomar := LEAST(v_ws.disponible, v_restante);
      IF v_tomar <= 0 THEN
        CONTINUE;
      END IF;

      UPDATE public.warehouse_state
      SET cantidad_reservada = cantidad_reservada + v_tomar,
          version = version + 1,
          updated_at = now()
      WHERE id_warehouse_state = v_ws.id_warehouse_state;

      INSERT INTO public.movimiento_inventario (
        id_movimiento_inventario, codigo_cuenta, id_bodega, id_ubicacion_origen, id_ubicacion_destino,
        id_producto, id_lote, cantidad, tipo_movimiento, id_usuario, id_referencia, tipo_referencia, created_at
      ) VALUES (
        gen_random_uuid(), v_ov.codigo_cuenta, v_ov.id_bodega, v_ws.id_ubicacion, v_ws.id_ubicacion,
        v_ws.id_producto, v_ws.id_lote, v_tomar, 'reserva', v_id_usuario, v_ov.id_orden_venta, 'orden_venta', now()
      );

      INSERT INTO public.contador (id_contador, codigo_cuenta, id_bodega, clave, valor, updated_at)
      VALUES (gen_random_uuid(), v_ov.codigo_cuenta, v_ov.id_bodega, 'orden_trabajo', 1, now())
      ON CONFLICT (codigo_cuenta, id_bodega, clave)
      DO UPDATE SET valor = public.contador.valor + 1, updated_at = now()
      RETURNING valor INTO v_ot_valor;

      v_ot_codigo := 'OT-' || lpad(v_ot_valor::text, 6, '0');
      v_ot_id := gen_random_uuid();

      INSERT INTO public.orden_trabajo (
        id_orden_trabajo, codigo_cuenta, id_bodega, codigo, estado, tipo, id_solicitante,
        id_lote, id_ubicacion_origen, id_ubicacion_destino, id_orden_venta, observaciones, created_at, updated_at
      ) VALUES (
        v_ot_id, v_ov.codigo_cuenta, v_ov.id_bodega, v_ot_codigo, 'planificada', 'picking', v_id_usuario,
        v_ws.id_lote, v_ws.id_ubicacion, v_id_destino, v_ov.id_orden_venta,
        'flujo:a_salida|OV ' || v_ov.codigo, now(), now()
      );

      INSERT INTO public.orden_trabajo_linea (
        id_linea_orden_trabajo, id_orden_trabajo, id_producto, id_ubicacion, tipo_linea, cantidad
      ) VALUES (
        gen_random_uuid(), v_ot_id, v_linea.id_producto, v_ws.id_ubicacion, 'salida', v_tomar
      );

      INSERT INTO public.tarea_cola (
        id_tarea, codigo_cuenta, id_bodega, tipo, estado, id_orden_trabajo, titulo, descripcion, created_at, updated_at
      ) VALUES (
        gen_random_uuid(), v_ov.codigo_cuenta, v_ov.id_bodega, 'despacho', 'pendiente',
        v_ot_id, 'A salida · ' || v_ot_codigo, NULL, now(), now()
      );

      v_restante := v_restante - v_tomar;
      v_allocs := v_allocs + 1;
      v_ots := v_ots + 1;
    END LOOP;

    IF v_restante > 0 THEN
      RAISE EXCEPTION 'STOCK_INSUFICIENTE|%|%', v_linea.id_producto, (v_linea.cantidad_pedida - v_restante);
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'id_orden_venta', v_ov.id_orden_venta,
    'codigo', v_ov.codigo,
    'estado', 'confirmada',
    'allocations', v_allocs,
    'ordenes_trabajo', v_ots
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bot_verificar_orden_venta(p_id_orden_venta uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ov public.orden_venta%ROWTYPE;
  v_disp numeric;
  v_pedida numeric;
  v_faltante numeric;
  v_linea RECORD;
  v_faltantes jsonb := '[]'::jsonb;
  v_hay_stock boolean := true;
  v_lineas int := 0;
  v_result jsonb;
  v_lock_key bigint;
BEGIN
  IF p_id_orden_venta IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'id_orden_venta requerido');
  END IF;

  v_lock_key := ('x' || substr(md5(p_id_orden_venta::text), 1, 16))::bit(64)::bigint;
  IF NOT pg_try_advisory_xact_lock(v_lock_key) THEN
    RETURN jsonb_build_object('ok', false, 'skipped', true, 'reason', 'locked');
  END IF;

  SELECT * INTO v_ov
  FROM public.orden_venta
  WHERE id_orden_venta = p_id_orden_venta
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'OV no existe');
  END IF;

  IF v_ov.estado IS DISTINCT FROM 'por_confirmar' THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_por_confirmar', 'estado', v_ov.estado);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.solicitud_compra sc
    WHERE sc.codigo_cuenta = v_ov.codigo_cuenta
      AND sc.observaciones ILIKE '%' || v_ov.codigo || '%'
  ) THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true, 'reason', 'ya_tiene_solicitud');
  END IF;

  FOR v_linea IN
    SELECT ovl.id_producto,
           ovl.cantidad_pedida::numeric AS cantidad_pedida,
           COALESCE(p.descripcion, p.sku, 'producto') AS descripcion
    FROM public.orden_venta_linea ovl
    LEFT JOIN public.producto p ON p.id_producto = ovl.id_producto
    WHERE ovl.id_orden_venta = v_ov.id_orden_venta
  LOOP
    v_lineas := v_lineas + 1;
    v_pedida := v_linea.cantidad_pedida;

    SELECT COALESCE(SUM((ws.cantidad - ws.cantidad_reservada)::numeric), 0)
    INTO v_disp
    FROM public.warehouse_state ws
    JOIN public.ubicacion u ON u.id_ubicacion = ws.id_ubicacion AND u.esta_activa = true
    JOIN public.tipo_ubicacion tu ON tu.id_tipo_ubicacion = u.id_tipo_ubicacion AND tu.es_almacenamiento = true
    WHERE ws.codigo_cuenta = v_ov.codigo_cuenta
      AND ws.id_bodega = v_ov.id_bodega
      AND ws.id_producto = v_linea.id_producto;

    v_faltante := GREATEST(0, v_pedida - COALESCE(v_disp, 0));
    IF v_faltante > 0 THEN
      v_hay_stock := false;
      v_faltantes := v_faltantes || jsonb_build_array(jsonb_build_object(
        'id_producto', v_linea.id_producto,
        'cantidad', round(v_faltante, 4),
        'descripcion', v_linea.descripcion
      ));
    END IF;
  END LOOP;

  IF v_lineas = 0 THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true, 'reason', 'sin_lineas');
  END IF;

  IF v_hay_stock THEN
    v_result := public.bot_emitir_orden_venta(v_ov.id_orden_venta);
    RETURN jsonb_build_object('ok', COALESCE((v_result->>'ok')::boolean, false), 'accion', 'emitir', 'result', v_result);
  END IF;

  v_result := public.bot_crear_solicitud_faltante(
    v_ov.codigo_cuenta,
    v_ov.id_bodega,
    v_ov.id_creador,
    'Auto bot OV ' || v_ov.codigo || ': stock insuficiente',
    v_faltantes
  );

  RETURN jsonb_build_object('ok', COALESCE((v_result->>'ok')::boolean, false), 'accion', 'solicitud', 'result', v_result);
END;
$function$;
