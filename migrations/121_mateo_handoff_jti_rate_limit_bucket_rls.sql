-- POL-435: cierra el acceso por la API REST de Supabase a las tablas de la
-- migracion 093 de polaria-wms-api (mateo_handoff_jti y rate_limit_bucket).
-- El backend las usa por Prisma (conexion directa a Postgres), no por la API REST.
-- Activa RLS sin politicas y quita los permisos de anon y authenticated.
-- No usa FORCE ROW LEVEL SECURITY. Idempotente. Si las tablas no existen en esta
-- base (se crean con la 093 de la API), no hace nada.

DO $$
DECLARE
    v_tabla text;
BEGIN
    FOREACH v_tabla IN ARRAY ARRAY['mateo_handoff_jti', 'rate_limit_bucket']
    LOOP
        IF to_regclass(format('public.%I', v_tabla)) IS NOT NULL THEN
            EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_tabla);
            EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', v_tabla);
        END IF;
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
