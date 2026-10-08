-- Materializa también entrega (ventana, dirección, teléfono, andén, notas, prioridad)
-- desde origen_correo cuando el tercero/IA las deja en el JSON.

CREATE OR REPLACE FUNCTION public.bot_materializar_ov_desde_origen(p_id_orden_venta uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ov public.orden_venta%ROWTYPE;
  v_nombre_cliente text;
  v_id_comprador uuid;
  v_oc text;
  v_centro text;
  v_contacto text;
  v_fecha text;
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

  SELECT NULLIF(trim(r.elem->>'Nombre cliente'), '')
  INTO v_nombre_cliente
  FROM jsonb_array_elements(v_ov.origen_correo) AS r(elem)
  WHERE NULLIF(trim(r.elem->>'Nombre cliente'), '') IS NOT NULL
  LIMIT 1;

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
        ORDER BY length(c.nombre)
        LIMIT 1;
        EXIT WHEN v_id_comprador IS NOT NULL;
      END LOOP;
    END IF;
  END IF;

  SELECT mode() WITHIN GROUP (ORDER BY NULLIF(trim(r.elem->>'Numero pedido'), ''))
  INTO v_oc FROM jsonb_array_elements(v_ov.origen_correo) AS r(elem);

  SELECT mode() WITHIN GROUP (ORDER BY NULLIF(trim(r.elem->>'Almacen'), ''))
  INTO v_centro FROM jsonb_array_elements(v_ov.origen_correo) AS r(elem);

  SELECT mode() WITHIN GROUP (ORDER BY NULLIF(trim(r.elem->>'Responsable externo'), ''))
  INTO v_contacto FROM jsonb_array_elements(v_ov.origen_correo) AS r(elem);

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
     OR (NULLIF(trim(v_ov.fecha_entrega), '') IS NULL AND v_fecha IS NOT NULL)
     OR (NULLIF(trim(v_ov.ventana_desde), '') IS NULL)
     OR (NULLIF(trim(v_ov.ventana_hasta), '') IS NULL)
     OR (NULLIF(trim(v_ov.direccion_entrega), '') IS NULL)
     OR (NULLIF(trim(v_ov.anden), '') IS NULL)
     OR (NULLIF(trim(v_ov.telefono_contacto), '') IS NULL)
     OR (NULLIF(trim(v_ov.prioridad), '') IS NULL)
     OR (NULLIF(trim(v_ov.notas_almacen), '') IS NULL) THEN
    UPDATE public.orden_venta ov
    SET
      id_comprador = COALESCE(ov.id_comprador, v_id_comprador),
      orden_compra_hotel = COALESCE(NULLIF(trim(ov.orden_compra_hotel), ''), v_oc),
      centro_consumo = COALESCE(NULLIF(trim(ov.centro_consumo), ''), v_centro),
      contacto_entrega = COALESCE(NULLIF(trim(ov.contacto_entrega), ''), v_contacto),
      fecha_entrega = COALESCE(NULLIF(trim(ov.fecha_entrega), ''), v_fecha),
      ventana_desde = COALESCE(
        NULLIF(trim(ov.ventana_desde), ''),
        NULLIF(trim(v_ov.origen_correo->0->>'Ventana desde'), '')
      ),
      ventana_hasta = COALESCE(
        NULLIF(trim(ov.ventana_hasta), ''),
        NULLIF(trim(v_ov.origen_correo->0->>'Ventana hasta'), '')
      ),
      direccion_entrega = COALESCE(
        NULLIF(trim(ov.direccion_entrega), ''),
        NULLIF(trim(v_ov.origen_correo->0->>'Direccion entrega'), ''),
        NULLIF(trim(v_ov.origen_correo->0->>'Destino'), '')
      ),
      anden = COALESCE(
        NULLIF(trim(ov.anden), ''),
        NULLIF(trim(v_ov.origen_correo->0->>'Anden'), '')
      ),
      telefono_contacto = COALESCE(
        NULLIF(trim(ov.telefono_contacto), ''),
        NULLIF(trim(v_ov.origen_correo->0->>'Telefono contacto'), '')
      ),
      prioridad = COALESCE(
        NULLIF(trim(ov.prioridad), ''),
        NULLIF(trim(v_ov.origen_correo->0->>'Prioridad'), '')
      ),
      notas_almacen = COALESCE(
        NULLIF(trim(ov.notas_almacen), ''),
        NULLIF(trim(v_ov.origen_correo->0->>'Notas generales'), '')
      ),
      updated_at = now()
    WHERE ov.id_orden_venta = v_ov.id_orden_venta;
    v_header_patched := true;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'materializado', v_header_patched,
    'lineas_insertadas', 0,
    'header_patched', v_header_patched,
    'reason', 'solo_cabecera_mateo_lineas'
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$function$;

COMMENT ON FUNCTION public.bot_materializar_ov_desde_origen(uuid) IS
  'Rellena cabecera (incl. entrega) de OV por_confirmar desde origen_correo. Las líneas las interpreta Mateo al abrir.';
