-- Validar y enviar (por_confirmar → confirmada) SOLO lo hace un humano
-- vía API/UI. El bot/Mateo no puede emitir ni confirmar OV.

CREATE OR REPLACE FUNCTION public.bot_emitir_orden_venta(p_id_orden_venta uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  -- Deshabilitado a propósito: no hay auto-emit desde bot/triggers/n8n.
  RETURN jsonb_build_object(
    'ok', false,
    'error', 'emitir_solo_humano',
    'mensaje', 'Validar y enviar solo lo puede hacer un operador en Polaria WMS.',
    'id_orden_venta', p_id_orden_venta
  );
END;
$function$;

COMMENT ON FUNCTION public.bot_emitir_orden_venta(uuid) IS
  'Deshabilitado: emitir/confirmada solo por humano (API POST …/emitir).';

CREATE OR REPLACE FUNCTION public.bot_verificar_orden_venta(p_id_orden_venta uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_ov orden_venta%ROWTYPE;
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
  FROM orden_venta
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
    FROM solicitud_compra sc
    WHERE sc.codigo_cuenta = v_ov.codigo_cuenta
      AND sc.observaciones ILIKE '%' || v_ov.codigo || '%'
  ) THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true, 'reason', 'ya_tiene_solicitud');
  END IF;

  FOR v_linea IN
    SELECT ovl.id_producto,
           ovl.cantidad_pedida::numeric AS cantidad_pedida,
           COALESCE(p.descripcion, p.sku, 'producto') AS descripcion
    FROM orden_venta_linea ovl
    LEFT JOIN producto p ON p.id_producto = ovl.id_producto
    WHERE ovl.id_orden_venta = v_ov.id_orden_venta
  LOOP
    v_lineas := v_lineas + 1;
    v_pedida := v_linea.cantidad_pedida;

    SELECT COALESCE(SUM((ws.cantidad - ws.cantidad_reservada)::numeric), 0)
    INTO v_disp
    FROM warehouse_state ws
    JOIN ubicacion u ON u.id_ubicacion = ws.id_ubicacion AND u.esta_activa = true
    JOIN tipo_ubicacion tu ON tu.id_tipo_ubicacion = u.id_tipo_ubicacion AND tu.es_almacenamiento = true
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

  -- Con stock: NO emitir. Queda por_confirmar hasta Validar y enviar (humano).
  IF v_hay_stock THEN
    RETURN jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'emitir_solo_humano',
      'accion', 'esperar_humano',
      'id_orden_venta', v_ov.id_orden_venta,
      'codigo', v_ov.codigo
    );
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

COMMENT ON FUNCTION public.bot_verificar_orden_venta(uuid) IS
  'Revisa stock en por_confirmar. Nunca emite; con stock espera Validar y enviar humano. Sin stock puede crear solicitud.';

-- Reaplica wrapper schema-aware en tenants si existe el helper.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'wms_make_fn_tenant_schema_aware'
  ) THEN
    PERFORM public.wms_make_fn_tenant_schema_aware('bot_emitir_orden_venta');
    PERFORM public.wms_make_fn_tenant_schema_aware('bot_verificar_orden_venta');
  END IF;
END $$;
