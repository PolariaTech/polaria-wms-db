-- Materializa cabecera + líneas de OV por_confirmar cuando el tercero
-- deja origen_correo (JSON) sin líneas / sin campos de captura.
-- Así la OV llega llena al listado, no solo al abrir el detalle.

CREATE OR REPLACE FUNCTION public.bot_norm_texto(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT trim(both ' ' FROM regexp_replace(
    lower(translate(
      replace(replace(coalesce(p_texto, ''), '¥', 'n'), E'\uFFFD', 'n'),
      'áéíóúüñÁÉÍÓÚÜÑ*',
      'aeiouunAEIOUUN '
    )),
    '[^a-z0-9]+',
    ' ',
    'g'
  ));
$function$;

COMMENT ON FUNCTION public.bot_norm_texto(text) IS
  'Normaliza texto de origen_correo / catálogo para matching (acentos, *, mojibake).';

CREATE OR REPLACE FUNCTION public.bot_materializar_ov_desde_origen(p_id_orden_venta uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ov public.orden_venta%ROWTYPE;
  v_row jsonb;
  v_nombre_cliente text;
  v_id_comprador uuid;
  v_oc text;
  v_centro text;
  v_contacto text;
  v_fecha text;
  v_producto text;
  v_codigo_prod text;
  v_qty numeric;
  v_precio numeric;
  v_id_producto uuid;
  v_precio_cat numeric;
  v_qnorm text;
  v_first text;
  v_lineas_antes int := 0;
  v_lineas_ins int := 0;
  v_header_patched boolean := false;
  v_tok text;
BEGIN
  IF p_id_orden_venta IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'id_orden_venta requerido');
  END IF;

  SELECT * INTO v_ov
  FROM public.orden_venta
  WHERE id_orden_venta = p_id_orden_venta
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'OV no existe');
  END IF;

  IF v_ov.estado IS DISTINCT FROM 'por_confirmar' THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_por_confirmar');
  END IF;

  IF v_ov.origen_correo IS NULL
     OR jsonb_typeof(v_ov.origen_correo) IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_ov.origen_correo) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true, 'reason', 'sin_origen');
  END IF;

  SELECT COUNT(*)::int INTO v_lineas_antes
  FROM public.orden_venta_linea
  WHERE id_orden_venta = v_ov.id_orden_venta;

  -- Nombre cliente (primer renglón con valor).
  SELECT NULLIF(trim(r.elem->>'Nombre cliente'), '')
  INTO v_nombre_cliente
  FROM jsonb_array_elements(v_ov.origen_correo) AS r(elem)
  WHERE NULLIF(trim(r.elem->>'Nombre cliente'), '') IS NOT NULL
  LIMIT 1;

  -- Comprador: exacto / contiene token distintivo (>=6) / prefijo.
  IF v_ov.id_comprador IS NULL AND v_nombre_cliente IS NOT NULL THEN
    SELECT c.id_comprador INTO v_id_comprador
    FROM public.comprador c
    WHERE c.codigo_cuenta = v_ov.codigo_cuenta
      AND c.esta_activo
      AND public.bot_norm_texto(c.nombre) = public.bot_norm_texto(v_nombre_cliente)
    LIMIT 1;

    IF v_id_comprador IS NULL THEN
      FOR v_tok IN
        SELECT t
        FROM unnest(string_to_array(public.bot_norm_texto(v_nombre_cliente), ' ')) AS t
        WHERE length(t) >= 6
        ORDER BY length(t) DESC
      LOOP
        SELECT c.id_comprador INTO v_id_comprador
        FROM public.comprador c
        WHERE c.codigo_cuenta = v_ov.codigo_cuenta
          AND c.esta_activo
          AND (
            public.bot_norm_texto(c.nombre) LIKE '%' || v_tok || '%'
            OR public.bot_norm_texto(c.codigo) LIKE '%' || v_tok || '%'
          )
        ORDER BY
          CASE
            WHEN public.bot_norm_texto(c.nombre) LIKE '%' || v_tok || '%' THEN 0
            ELSE 1
          END,
          length(c.nombre)
        LIMIT 1;
        EXIT WHEN v_id_comprador IS NOT NULL;
      END LOOP;
    END IF;
  END IF;

  -- Campos de cabecera más frecuentes en origen.
  SELECT mode() WITHIN GROUP (ORDER BY NULLIF(trim(r.elem->>'Numero pedido'), ''))
  INTO v_oc
  FROM jsonb_array_elements(v_ov.origen_correo) AS r(elem);

  SELECT mode() WITHIN GROUP (ORDER BY NULLIF(trim(r.elem->>'Almacen'), ''))
  INTO v_centro
  FROM jsonb_array_elements(v_ov.origen_correo) AS r(elem);

  SELECT mode() WITHIN GROUP (ORDER BY NULLIF(trim(r.elem->>'Responsable externo'), ''))
  INTO v_contacto
  FROM jsonb_array_elements(v_ov.origen_correo) AS r(elem);

  SELECT CASE
    WHEN NULLIF(trim(r.elem->>'Fecha'), '') ~ '^\d{4}-\d{2}-\d{2}'
      THEN substring(trim(r.elem->>'Fecha') from 1 for 10)
    ELSE NULL
  END
  INTO v_fecha
  FROM jsonb_array_elements(v_ov.origen_correo) AS r(elem)
  WHERE NULLIF(trim(r.elem->>'Fecha'), '') IS NOT NULL
  LIMIT 1;

  IF (v_ov.id_comprador IS NULL AND v_id_comprador IS NOT NULL)
     OR (NULLIF(trim(v_ov.orden_compra_hotel), '') IS NULL AND v_oc IS NOT NULL)
     OR (NULLIF(trim(v_ov.centro_consumo), '') IS NULL AND v_centro IS NOT NULL)
     OR (NULLIF(trim(v_ov.contacto_entrega), '') IS NULL AND v_contacto IS NOT NULL)
     OR (NULLIF(trim(v_ov.fecha_entrega), '') IS NULL AND v_fecha IS NOT NULL) THEN
    UPDATE public.orden_venta
    SET
      id_comprador = COALESCE(id_comprador, v_id_comprador),
      orden_compra_hotel = COALESCE(NULLIF(trim(orden_compra_hotel), ''), v_oc),
      centro_consumo = COALESCE(NULLIF(trim(centro_consumo), ''), v_centro),
      contacto_entrega = COALESCE(NULLIF(trim(contacto_entrega), ''), v_contacto),
      fecha_entrega = COALESCE(NULLIF(trim(fecha_entrega), ''), v_fecha),
      updated_at = now()
    WHERE id_orden_venta = v_ov.id_orden_venta;
    v_header_patched := true;
  END IF;

  IF v_lineas_antes > 0 THEN
    RETURN jsonb_build_object(
      'ok', true,
      'materializado', v_header_patched,
      'lineas_insertadas', 0,
      'reason', 'ya_tenia_lineas'
    );
  END IF;

  -- Evita que trg_bot_verificar_ov_lineas auto-emita al materializar.
  PERFORM set_config('polaria.skip_bot_verificar', '1', true);

  FOR v_row IN
    SELECT elem
    FROM jsonb_array_elements(v_ov.origen_correo) AS t(elem)
  LOOP
    v_producto := NULLIF(trim(v_row->>'Producto'), '');
    v_codigo_prod := NULLIF(trim(v_row->>'Codigo producto'), '');
    BEGIN
      v_qty := NULLIF(replace(trim(coalesce(v_row->>'Cantidad', '')), ',', '.'), '')::numeric;
    EXCEPTION WHEN OTHERS THEN
      v_qty := 0;
    END;
    BEGIN
      v_precio := NULLIF(replace(trim(coalesce(v_row->>'Precio', '')), ',', '.'), '')::numeric;
    EXCEPTION WHEN OTHERS THEN
      v_precio := NULL;
    END;

    IF v_qty IS NULL OR v_qty <= 0 THEN
      CONTINUE;
    END IF;
    IF v_producto IS NULL AND v_codigo_prod IS NULL THEN
      CONTINUE;
    END IF;

    v_qnorm := public.bot_norm_texto(coalesce(v_producto, v_codigo_prod));
    v_first := split_part(v_qnorm, ' ', 1);
    v_id_producto := NULL;

    -- 1) SKU exacto
    IF v_codigo_prod IS NOT NULL THEN
      SELECT p.id_producto, COALESCE(p.precio, 0)
      INTO v_id_producto, v_precio_cat
      FROM public.producto p
      WHERE p.codigo_cuenta = v_ov.codigo_cuenta
        AND p.esta_activo
        AND lower(trim(p.sku)) = lower(v_codigo_prod)
      LIMIT 1;
    END IF;

    -- 2) Nombre exacto / contiene / prefijo truncado (AGUAC → AGUACATE)
    IF v_id_producto IS NULL AND v_qnorm <> '' THEN
      SELECT p.id_producto, COALESCE(p.precio, 0)
      INTO v_id_producto, v_precio_cat
      FROM public.producto p
      WHERE p.codigo_cuenta = v_ov.codigo_cuenta
        AND p.esta_activo
      ORDER BY
        CASE
          WHEN public.bot_norm_texto(p.descripcion) = v_qnorm THEN 100
          WHEN public.bot_norm_texto(p.descripcion) LIKE v_qnorm || '%' THEN 90
          WHEN v_qnorm LIKE public.bot_norm_texto(p.descripcion) || '%' THEN 85
          WHEN length(v_first) >= 4
            AND public.bot_norm_texto(p.descripcion) LIKE v_first || '%' THEN 80
          WHEN public.bot_norm_texto(p.descripcion) LIKE '%' || v_qnorm || '%' THEN 70
          WHEN length(v_first) >= 4
            AND public.bot_norm_texto(p.descripcion) LIKE '%' || v_first || '%' THEN 60
          ELSE 0
        END DESC,
        length(p.descripcion)
      LIMIT 1;

      -- Umbral mínimo: si el mejor score quedó 0, descartar.
      IF v_id_producto IS NOT NULL THEN
        IF NOT EXISTS (
          SELECT 1
          FROM public.producto p
          WHERE p.id_producto = v_id_producto
            AND (
              public.bot_norm_texto(p.descripcion) = v_qnorm
              OR public.bot_norm_texto(p.descripcion) LIKE v_qnorm || '%'
              OR v_qnorm LIKE public.bot_norm_texto(p.descripcion) || '%'
              OR (length(v_first) >= 4 AND public.bot_norm_texto(p.descripcion) LIKE v_first || '%')
              OR public.bot_norm_texto(p.descripcion) LIKE '%' || v_qnorm || '%'
              OR (length(v_first) >= 4 AND public.bot_norm_texto(p.descripcion) LIKE '%' || v_first || '%')
            )
        ) THEN
          v_id_producto := NULL;
        END IF;
      END IF;
    END IF;

    IF v_id_producto IS NULL THEN
      CONTINUE;
    END IF;

    INSERT INTO public.orden_venta_linea (
      id_orden_venta,
      id_producto,
      cantidad_pedida,
      precio_unitario,
      cajas,
      presentacion
    ) VALUES (
      v_ov.id_orden_venta,
      v_id_producto,
      v_qty,
      COALESCE(NULLIF(v_precio, 0), v_precio_cat, 0),
      NULL,
      NULL
    );
    v_lineas_ins := v_lineas_ins + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'materializado', v_header_patched OR v_lineas_ins > 0,
    'lineas_insertadas', v_lineas_ins,
    'header_patched', v_header_patched
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$function$;

COMMENT ON FUNCTION public.bot_materializar_ov_desde_origen(uuid) IS
  'Rellena cabecera y líneas de una OV por_confirmar a partir de origen_correo.';

-- El bot de stock no debe auto-emitir cuando materializamos desde origen.
CREATE OR REPLACE FUNCTION public.bot_trg_verificar_ov_por_lineas()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r record;
BEGIN
  IF current_setting('polaria.skip_bot_verificar', true) = '1' THEN
    RETURN NULL;
  END IF;

  FOR r IN
    SELECT DISTINCT id_orden_venta
    FROM new_table
  LOOP
    PERFORM public.bot_verificar_orden_venta(r.id_orden_venta);
  END LOOP;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bot_trg_materializar_ov_origen()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.origen_correo IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.origen_correo IS NOT DISTINCT FROM OLD.origen_correo THEN
    RETURN NEW;
  END IF;

  IF jsonb_typeof(NEW.origen_correo) IS DISTINCT FROM 'array'
     OR jsonb_array_length(NEW.origen_correo) = 0 THEN
    RETURN NEW;
  END IF;

  IF NEW.estado IS DISTINCT FROM 'por_confirmar' THEN
    RETURN NEW;
  END IF;

  PERFORM public.bot_materializar_ov_desde_origen(NEW.id_orden_venta);
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_bot_materializar_ov_origen ON public.orden_venta;
CREATE TRIGGER trg_bot_materializar_ov_origen
  AFTER INSERT OR UPDATE OF origen_correo
  ON public.orden_venta
  FOR EACH ROW
  EXECUTE FUNCTION public.bot_trg_materializar_ov_origen();

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
