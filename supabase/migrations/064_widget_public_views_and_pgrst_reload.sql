-- Vistas public para widget (tablas viven en mateo_support).
-- Prisma sin multi-schema busca public.widget_*; estas vistas auto-actualizables lo permiten.

CREATE OR REPLACE VIEW public.widget_conversacion AS
SELECT *
FROM mateo_support.widget_conversacion;

CREATE OR REPLACE VIEW public.widget_mensaje AS
SELECT *
FROM mateo_support.widget_mensaje;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.widget_conversacion TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.widget_mensaje TO anon, authenticated, service_role;

COMMENT ON VIEW public.widget_conversacion IS
    'Compat Prisma/PostgREST: proxy a mateo_support.widget_conversacion';
COMMENT ON VIEW public.widget_mensaje IS
    'Compat Prisma/PostgREST: proxy a mateo_support.widget_mensaje';

-- Asegurar schemas emp_* actuales en PostgREST (tras renames).
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT e.schema_name
        FROM public.empresa e
        WHERE e.schema_name IS NOT NULL
    LOOP
        PERFORM public.wms_expose_schema_postgrest(r.schema_name);
    END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
