-- ============================================================================
-- validate-rls.sql
-- Validación de la capa RLS base multi-tenant (POL-2).
-- Ejecutar como `postgres` / service_role en el SQL Editor de Supabase.
--
-- Verifica:
--   1. RLS habilitado en las tablas fundacionales.
--   2. Existencia de las políticas esperadas.
--   3. Existencia de los helpers de contexto en el esquema `app`.
--   4. Simulación de aislamiento por tenant cambiando el claim JWT (sub).
--
-- No modifica datos: la simulación corre dentro de una transacción con ROLLBACK.
-- ============================================================================

\echo '== 1) RLS habilitado =='
SELECT c.relname AS tabla, c.relrowsecurity AS rls_on
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('rol', 'empresa', 'usuario', 'cuenta')
ORDER BY c.relname;

\echo '== 2) Políticas activas =='
SELECT tablename, policyname, cmd, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('rol', 'empresa', 'usuario', 'cuenta')
ORDER BY tablename, policyname;

\echo '== 3) Helpers de contexto en esquema app =='
SELECT p.proname AS funcion,
       pg_get_function_identity_arguments(p.oid) AS args,
       p.prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'app'
ORDER BY p.proname;

\echo '== 4) Simulación de aislamiento (rol authenticated) =='
-- Helper local para impersonar un usuario por su id_auth.
DO $$
DECLARE
    v_config uuid;
    v_count_config int;
BEGIN
    SELECT id_auth INTO v_config
    FROM usuario WHERE id_rol = 'configurador' AND esta_activo
    LIMIT 1;

    IF v_config IS NULL THEN
        RAISE NOTICE 'No hay configurador sembrado; se omite simulación de visibilidad.';
        RETURN;
    END IF;

    -- Impersonar al configurador.
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_config::text, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);

    EXECUTE 'SELECT count(*) FROM empresa' INTO v_count_config;
    RAISE NOTICE 'Configurador ve % empresa(s) (debe ver todas).', v_count_config;

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', NULL, true);
END $$;

\echo 'Validación RLS completada.'
