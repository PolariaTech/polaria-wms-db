-- Re-expone todos los emp_* activos en PostgREST (Aguacates, Andino, etc.).
-- Sin esto, el configurador no lista cuentas/bodegas de esos tenants (406 Invalid schema).

DO $$
DECLARE
    current_schemas text;
    next_schemas text;
    missing text;
BEGIN
    SELECT COALESCE(
        NULLIF(
            (
                SELECT substring(cfg FROM 'pgrst\.db_schemas=(.*)$')
                FROM unnest(COALESCE((SELECT rolconfig FROM pg_roles WHERE rolname = 'authenticator'), ARRAY[]::text[])) AS cfg
                WHERE cfg LIKE 'pgrst.db_schemas=%'
                LIMIT 1
            ),
            ''
        ),
        NULLIF(current_setting('pgrst.db_schemas', true), ''),
        'public, graphql_public, mateo_support'
    )
    INTO current_schemas;

    next_schemas := current_schemas;

    FOR missing IN
        SELECT e.schema_name
        FROM public.empresa e
        JOIN pg_namespace n ON n.nspname = e.schema_name
        WHERE e.schema_name IS NOT NULL
          AND position(e.schema_name IN next_schemas) = 0
        ORDER BY e.schema_name
    LOOP
        next_schemas := next_schemas || ', ' || missing;
    END LOOP;

    IF next_schemas IS DISTINCT FROM current_schemas THEN
        BEGIN
            EXECUTE format(
                'ALTER ROLE authenticator SET pgrst.db_schemas = %L',
                next_schemas
            );
        EXCEPTION
            WHEN undefined_object THEN
                RAISE NOTICE 'Rol authenticator no existe; se omite pgrst.db_schemas';
        END;
    END IF;
END $$;

DO $$
DECLARE
    sch text;
BEGIN
    FOR sch IN
        SELECT e.schema_name
        FROM public.empresa e
        JOIN pg_namespace n ON n.nspname = e.schema_name
        WHERE e.schema_name IS NOT NULL
    LOOP
        EXECUTE format('GRANT USAGE ON SCHEMA %I TO anon, authenticated, service_role', sch);
        EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO anon, authenticated, service_role', sch);
        EXECUTE format(
            'ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT ON TABLES TO anon, authenticated, service_role',
            sch
        );
    END LOOP;
END $$;

NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';
