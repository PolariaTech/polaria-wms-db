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

DROP FUNCTION IF EXISTS public.wms_use_trigger_schema();

COMMENT ON FUNCTION public.wms_use_trigger_schema(text) IS
  'Fija search_path al schema del trigger (emp_*|public) + public. Pasar TG_TABLE_SCHEMA.';
