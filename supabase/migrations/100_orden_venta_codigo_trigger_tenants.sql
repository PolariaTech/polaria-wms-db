-- Consecutivo OV-######## en schemas emp_* (no solo public).
-- Inserts externos/bot al tenant llegaban sin codigo: el trigger
-- trg_orden_venta_codigo_estandar solo existía en public.orden_venta,
-- y generar_codigo_orden_venta leía solo public.orden_venta.

-- Reemplaza la firma de 2 args (solo public) por 3 args con schema.
DROP FUNCTION IF EXISTS public.generar_codigo_orden_venta(text, timestamptz);

CREATE OR REPLACE FUNCTION public.generar_codigo_orden_venta(
    p_codigo_cuenta text,
    p_created_at timestamptz DEFAULT now(),
    p_schema text DEFAULT 'public'
)
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
  v_schema text := coalesce(nullif(btrim(p_schema), ''), 'public');
  v_max bigint := 0;
  v_next bigint;
  v_codigo text;
BEGIN
  IF v_schema !~ '^(public|template_wms|emp_[a-z0-9_]+)$' THEN
    RAISE EXCEPTION 'schema no permitido para generar codigo OV: %', v_schema;
  END IF;

  EXECUTE format(
    $q$
      SELECT COALESCE(MAX(substring(ov.codigo from 4)::bigint), 0)
      FROM %I.orden_venta ov
      WHERE ov.codigo_cuenta = $1
        AND ov.codigo ~ '^OV-[0-9]{8}$'
    $q$,
    v_schema
  )
  INTO v_max
  USING p_codigo_cuenta;

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
      COALESCE(NEW.created_at, now()),
      TG_TABLE_SCHEMA
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
      COALESCE(NEW.created_at, now()),
      TG_TABLE_SCHEMA
    );
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.generar_codigo_orden_venta(text, timestamptz, text) IS
  'Consecutivo OV-00000001 por cuenta en el schema indicado (ignora códigos legados por fecha).';

COMMENT ON FUNCTION public.trg_orden_venta_codigo_estandar() IS
  'Normaliza codigo OV al formato secuencial OV-######## usando TG_TABLE_SCHEMA (public o emp_*).';

CREATE OR REPLACE FUNCTION public.wms_attach_orden_venta_codigo_trigger(p_schema text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_schema IS NULL OR btrim(p_schema) = '' THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = p_schema
      AND c.relname = 'orden_venta'
      AND c.relkind = 'r'
  ) THEN
    RETURN;
  END IF;

  EXECUTE format(
    'DROP TRIGGER IF EXISTS trg_orden_venta_codigo_estandar ON %I.orden_venta',
    p_schema
  );
  EXECUTE format(
    'CREATE TRIGGER trg_orden_venta_codigo_estandar
       BEFORE INSERT ON %I.orden_venta
       FOR EACH ROW
       EXECUTE FUNCTION public.trg_orden_venta_codigo_estandar()',
    p_schema
  );
END;
$$;

COMMENT ON FUNCTION public.wms_attach_orden_venta_codigo_trigger(text) IS
  'Instala trg_orden_venta_codigo_estandar en orden_venta del schema (public/emp_*/template).';

-- Schemas existentes
DO $$
DECLARE
  r record;
BEGIN
  PERFORM public.wms_attach_orden_venta_codigo_trigger('public');

  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'template_wms') THEN
    PERFORM public.wms_attach_orden_venta_codigo_trigger('template_wms');
  END IF;

  FOR r IN
    SELECT nspname
    FROM pg_namespace
    WHERE nspname LIKE 'emp_%'
    ORDER BY 1
  LOOP
    PERFORM public.wms_attach_orden_venta_codigo_trigger(r.nspname);
  END LOOP;
END $$;

-- Backfill filas ya insertadas sin codigo
DO $$
DECLARE
  r record;
  ov record;
  v_codigo text;
BEGIN
  FOR r IN
    SELECT n.nspname
    FROM pg_namespace n
    JOIN pg_class c
      ON c.relnamespace = n.oid
     AND c.relname = 'orden_venta'
     AND c.relkind = 'r'
    WHERE n.nspname = 'public'
       OR n.nspname LIKE 'emp_%'
    ORDER BY 1
  LOOP
    FOR ov IN EXECUTE format(
      $q$
        SELECT id_orden_venta, codigo_cuenta, created_at
        FROM %I.orden_venta
        WHERE codigo IS NULL OR btrim(codigo) = ''
        ORDER BY created_at NULLS LAST, id_orden_venta
      $q$,
      r.nspname
    )
    LOOP
      v_codigo := public.generar_codigo_orden_venta(
        ov.codigo_cuenta,
        coalesce(ov.created_at, now()),
        r.nspname
      );
      EXECUTE format(
        'UPDATE %I.orden_venta SET codigo = $1 WHERE id_orden_venta = $2',
        r.nspname
      )
      USING v_codigo, ov.id_orden_venta;
    END LOOP;
  END LOOP;
END $$;

-- Provision de empresas nuevas: mismo trigger en el tenant
CREATE OR REPLACE FUNCTION public.wms_provision_empresa_schema(p_codigo_empresa text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_codigo text := trim(p_codigo_empresa);
    v_razon text;
    v_schema text;
    t text;
BEGIN
    IF v_codigo IS NULL OR v_codigo = '' THEN
        RAISE EXCEPTION 'codigo_empresa es obligatorio';
    END IF;

    SELECT e.razon_social
    INTO v_razon
    FROM public.empresa e
    WHERE e.codigo_empresa = v_codigo;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'empresa % no existe', v_codigo;
    END IF;

    v_schema := public.wms_normalize_schema_name(v_codigo, v_razon);

    IF EXISTS (
        SELECT 1 FROM public.empresa e
        WHERE e.schema_name = v_schema
          AND e.codigo_empresa <> v_codigo
    ) THEN
        RAISE EXCEPTION 'schema_name % ya asignado a otra empresa', v_schema;
    END IF;

    PERFORM public.wms_refresh_template_wms();

    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', v_schema);
    EXECUTE format(
        'COMMENT ON SCHEMA %I IS %L',
        v_schema,
        format('Tenant WMS empresa %s (%s)', v_codigo, coalesce(v_razon, v_codigo))
    );

    FOR t IN
        SELECT table_name FROM public.wms_tenant_tables ORDER BY clone_order
    LOOP
        EXECUTE format('DROP TABLE IF EXISTS %I.%I CASCADE', v_schema, t);
        PERFORM public.wms_clone_table_structure('template_wms', v_schema, t);
    END LOOP;

    PERFORM public.wms_clone_foreign_keys('template_wms', v_schema);
    PERFORM public.wms_clone_updated_at_triggers('template_wms', v_schema);
    PERFORM public.wms_attach_orden_venta_codigo_trigger(v_schema);
    PERFORM public.wms_apply_tenant_rls(v_schema, v_codigo);
    PERFORM public.wms_expose_schema_postgrest(v_schema);

    UPDATE public.empresa
    SET schema_name = v_schema,
        updated_at = now()
    WHERE codigo_empresa = v_codigo;

    RETURN v_schema;
END;
$function$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
