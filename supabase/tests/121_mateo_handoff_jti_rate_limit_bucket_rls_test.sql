-- POL-435: prueba de la migracion 121 (RLS y permisos de mateo_handoff_jti y rate_limit_bucket).
-- Ejecutar contra una base con la migracion 121 aplicada (local o Demo, nunca produccion sin confirmacion). No escribe datos.
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/121_mateo_handoff_jti_rate_limit_bucket_rls_test.sql

BEGIN;

DO $$
DECLARE
    v_tabla text;
    v_oid oid;
    v_rol text;
    v_priv text;
    v_existentes integer := 0;
BEGIN
    FOREACH v_tabla IN ARRAY ARRAY['mateo_handoff_jti', 'rate_limit_bucket']
    LOOP
        v_oid := to_regclass(format('public.%I', v_tabla));
        IF v_oid IS NULL THEN
            RAISE NOTICE 'OMITIDA: public.% no existe en esta base', v_tabla;
            CONTINUE;
        END IF;

        v_existentes := v_existentes + 1;

        IF NOT (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = v_oid) THEN
            RAISE EXCEPTION 'FALLA 1: public.% tiene RLS apagado', v_tabla;
        END IF;

        FOREACH v_rol IN ARRAY ARRAY['anon', 'authenticated']
        LOOP
            FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE']
            LOOP
                IF has_table_privilege(v_rol, v_oid, v_priv) THEN
                    RAISE EXCEPTION 'FALLA 2: % conserva % sobre public.%', v_rol, v_priv, v_tabla;
                END IF;
            END LOOP;
        END LOOP;

        IF EXISTS (
            SELECT 1
            FROM pg_policies
            WHERE schemaname = 'public'
              AND tablename = v_tabla
        ) THEN
            RAISE EXCEPTION 'FALLA 3: public.% tiene politicas y no deberia', v_tabla;
        END IF;
    END LOOP;

    RAISE NOTICE 'OK: % tabla(s) verificadas', v_existentes;
END $$;

ROLLBACK;
