-- Paridad emp_* ≈ public (triggers de negocio + funciones schema-aware).
-- Las funciones permanecen en public; usan TG_TABLE_SCHEMA vía search_path.
-- Nuevas empresas: wms_clone_business_triggers en provision.
-- Emp existentes: repair al final de esta migración.

-- TG_* solo existe en el cuerpo del trigger; el helper recibe el schema explícito.
CREATE OR REPLACE FUNCTION public.wms_use_trigger_schema(p_schema text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF p_schema IS NULL OR btrim(p_schema) = '' THEN
    RETURN;
  END IF;
  PERFORM set_config(
    'search_path',
    quote_ident(p_schema) || ', public',
    true
  );
END;
$fn$;

COMMENT ON FUNCTION public.wms_use_trigger_schema(text) IS
  'Fija search_path al schema del trigger (emp_*|public) + public. Pasar TG_TABLE_SCHEMA.';

CREATE OR REPLACE FUNCTION public.wms_make_fn_tenant_schema_aware(p_proname text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_def text;
  v_new text;
  t text;
  v_is_trigger boolean;
  v_pos int;
  v_begin_rel int;
  v_begin_abs int;
  v_inject text;
BEGIN
  SELECT pg_get_functiondef(p.oid)
  INTO v_def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = p_proname
  LIMIT 1;

  IF v_def IS NULL THEN
    RAISE NOTICE 'wms_make_fn_tenant_schema_aware: % no existe', p_proname;
    RETURN;
  END IF;

  v_new := v_def;
  v_is_trigger := position('returns trigger' in lower(v_new)) > 0;

  v_new := replace(v_new, 'SET search_path TO ''public''', '');
  v_new := replace(
    v_new,
    'PERFORM public.wms_use_trigger_schema();',
    'PERFORM public.wms_use_trigger_schema(TG_TABLE_SCHEMA);'
  );

  FOR t IN
    SELECT table_name FROM public.wms_tenant_tables ORDER BY length(table_name) DESC
  LOOP
    v_new := replace(v_new, 'public.' || t, t);
  END LOOP;

  IF v_is_trigger AND position('wms_use_trigger_schema(TG_TABLE_SCHEMA)' in v_new) = 0 THEN
    v_pos := position('$function$' in v_new);
    IF v_pos > 0 THEN
      v_begin_rel := position('BEGIN' in substring(v_new from v_pos));
      IF v_begin_rel > 0 THEN
        v_begin_abs := v_pos + v_begin_rel - 1;
        v_inject := E'BEGIN\n  PERFORM public.wms_use_trigger_schema(TG_TABLE_SCHEMA);';
        v_new := overlay(v_new placing v_inject from v_begin_abs for 5);
      END IF;
    END IF;
  END IF;

  EXECUTE v_new;
END;
$fn$;

DO $do$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT p.proname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE n.nspname = 'public'
      AND NOT t.tgisinternal
      AND public.wms_is_tenant_table(c.relname)
      AND p.proname <> 'set_updated_at'
  LOOP
    PERFORM public.wms_make_fn_tenant_schema_aware(r.proname);
  END LOOP;

  PERFORM public.wms_make_fn_tenant_schema_aware('bot_materializar_ov_desde_origen');
  PERFORM public.wms_make_fn_tenant_schema_aware('bot_verificar_orden_venta');
  PERFORM public.wms_make_fn_tenant_schema_aware('bot_emitir_orden_venta');
  PERFORM public.wms_make_fn_tenant_schema_aware('bot_crear_solicitud_faltante');
  PERFORM public.wms_make_fn_tenant_schema_aware('comprador_resolve_codigo');
END;
$do$;

CREATE OR REPLACE FUNCTION public.wms_clone_business_triggers(
    p_source_schema text,
    p_dest_schema text
)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
  r record;
  v_def text;
BEGIN
  IF p_source_schema IS NULL OR p_dest_schema IS NULL THEN
    RAISE EXCEPTION 'schemas requeridos';
  END IF;

  FOR r IN
    SELECT t.tgname,
           c.relname AS table_name,
           pg_get_triggerdef(t.oid) AS tdef
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = p_source_schema
      AND NOT t.tgisinternal
      AND public.wms_is_tenant_table(c.relname)
    ORDER BY c.relname, t.tgname
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_class c2
      JOIN pg_namespace n2 ON n2.oid = c2.relnamespace
      WHERE n2.nspname = p_dest_schema
        AND c2.relname = r.table_name
        AND c2.relkind = 'r'
    ) THEN
      CONTINUE;
    END IF;

    EXECUTE format(
      'DROP TRIGGER IF EXISTS %I ON %I.%I',
      r.tgname, p_dest_schema, r.table_name
    );

    v_def := r.tdef;
    v_def := regexp_replace(
      v_def,
      'ON\s+(?:[a-zA-Z0-9_"]+\.)?' || r.table_name || '\y',
      format('ON %I.%I', p_dest_schema, r.table_name),
      'i'
    );
    v_def := regexp_replace(
      v_def,
      'EXECUTE\s+(FUNCTION|PROCEDURE)\s+(?!public\.)([a-zA-Z0-9_]+)',
      'EXECUTE FUNCTION public.\2',
      'i'
    );

    BEGIN
      EXECUTE v_def;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE NOTICE 'trigger skip %.%.%: %', p_dest_schema, r.table_name, r.tgname, SQLERRM;
    END;
  END LOOP;
END;
$fn$;

COMMENT ON FUNCTION public.wms_clone_business_triggers(text, text) IS
  'Copia todos los triggers de tablas tenant de source→dest (funciones en public).';

CREATE OR REPLACE FUNCTION public.wms_clone_updated_at_triggers(
    p_source_schema text,
    p_dest_schema text
)
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  PERFORM public.wms_clone_business_triggers(p_source_schema, p_dest_schema);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.wms_repair_tenant_schema(p_schema text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_codigo text;
BEGIN
  IF p_schema IS NULL OR btrim(p_schema) = '' THEN
    RAISE EXCEPTION 'schema requerido';
  END IF;

  IF p_schema = 'template_wms' THEN
    PERFORM public.wms_refresh_template_wms();
    RETURN;
  END IF;

  IF p_schema !~ '^emp_' THEN
    RAISE EXCEPTION 'solo emp_* o template_wms: %', p_schema;
  END IF;

  SELECT e.codigo_empresa INTO v_codigo
  FROM public.empresa e
  WHERE e.schema_name = p_schema
  LIMIT 1;

  PERFORM public.wms_clone_business_triggers('public', p_schema);

  IF v_codigo IS NOT NULL THEN
    PERFORM public.wms_apply_tenant_rls(p_schema, v_codigo);
  END IF;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.wms_refresh_template_wms()
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
    t text;
BEGIN
    CREATE SCHEMA IF NOT EXISTS template_wms;
    COMMENT ON SCHEMA template_wms IS
        'Plantilla estructural WMS (sin datos). Fuente para provisionar emp_*.';

    FOR t IN
        SELECT table_name FROM public.wms_tenant_tables ORDER BY clone_order
    LOOP
        EXECUTE format('DROP TABLE IF EXISTS template_wms.%I CASCADE', t);
        PERFORM public.wms_clone_table_structure('public', 'template_wms', t);
    END LOOP;

    PERFORM public.wms_clone_foreign_keys('public', 'template_wms');
    PERFORM public.wms_clone_business_triggers('public', 'template_wms');

    REVOKE ALL ON SCHEMA template_wms FROM PUBLIC;
    GRANT USAGE ON SCHEMA template_wms TO postgres;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.wms_provision_empresa_schema(p_codigo_empresa text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
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
    PERFORM public.wms_clone_business_triggers('template_wms', v_schema);
    PERFORM public.wms_clone_business_triggers('public', v_schema);
    PERFORM public.wms_apply_tenant_rls(v_schema, v_codigo);
    PERFORM public.wms_expose_schema_postgrest(v_schema);

    UPDATE public.empresa
    SET schema_name = v_schema,
        updated_at = now()
    WHERE codigo_empresa = v_codigo;

    RETURN v_schema;
END;
$fn$;

DO $do$
DECLARE
  r record;
BEGIN
  PERFORM public.wms_refresh_template_wms();

  FOR r IN
    SELECT nspname
    FROM pg_namespace
    WHERE nspname LIKE 'emp_%'
    ORDER BY 1
  LOOP
    PERFORM public.wms_clone_business_triggers('public', r.nspname);
  END LOOP;
END;
$do$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
