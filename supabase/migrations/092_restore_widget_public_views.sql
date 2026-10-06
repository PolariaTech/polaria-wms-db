-- Restaura vistas public.widget_* como proxy a mateo_support.
-- Prisma sin multi-schema (y PostgREST) las necesitan; 091 las había quitado.

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

NOTIFY pgrst, 'reload schema';
