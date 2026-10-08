-- Código OV canónico: OV-00000001, OV-00000002, …
-- El trigger anterior forzaba OV-YYYYMMDD-HHMMSS y pisaba el consecutivo de la UI.

CREATE OR REPLACE FUNCTION public.generar_codigo_orden_venta(
    p_codigo_cuenta text,
    p_created_at timestamptz DEFAULT now()
)
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
  v_max bigint := 0;
  v_next bigint;
  v_codigo text;
BEGIN
  -- Solo cuenta el formato secuencial OV-######## (ignora legados OV-YYYYMMDD-HHMMSS).
  SELECT COALESCE(MAX(substring(ov.codigo from 4)::bigint), 0)
  INTO v_max
  FROM public.orden_venta ov
  WHERE ov.codigo_cuenta = p_codigo_cuenta
    AND ov.codigo ~ '^OV-[0-9]{8}$';

  v_next := v_max + 1;
  IF v_next > 99999999 THEN
    RAISE EXCEPTION 'Se agotó el consecutivo de órdenes de venta (8 dígitos).';
  END IF;

  v_codigo := 'OV-' || lpad(v_next::text, 8, '0');
  RETURN v_codigo;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_orden_venta_codigo_estandar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Conserva OV-00000001 (y el numérico puro 00000001 → lo normaliza).
  -- Conserva legados OV-YYYYMMDD-HHMMSS.
  -- Solo genera si viene vacío o en formato desconocido.
  IF NEW.codigo IS NULL OR btrim(NEW.codigo) = '' THEN
    NEW.codigo := public.generar_codigo_orden_venta(
      NEW.codigo_cuenta,
      COALESCE(NEW.created_at, now())
    );
  ELSIF NEW.codigo ~ '^[0-9]{8}$' THEN
    NEW.codigo := 'OV-' || NEW.codigo;
  ELSIF NEW.codigo ~ '^OV-[0-9]{8}$' THEN
    NULL;
  ELSIF NEW.codigo ~ '^OV-[0-9]{8}-[0-9]{6}$' THEN
    NULL;
  ELSE
    NEW.codigo := public.generar_codigo_orden_venta(
      NEW.codigo_cuenta,
      COALESCE(NEW.created_at, now())
    );
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.generar_codigo_orden_venta(text, timestamptz) IS
  'Consecutivo OV-00000001 por cuenta (ignora códigos legados por fecha).';

COMMENT ON FUNCTION public.trg_orden_venta_codigo_estandar() IS
  'Normaliza codigo OV al formato secuencial OV-######## sin pisar el valor válido de la UI.';
