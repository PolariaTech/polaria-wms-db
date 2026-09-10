-- Asegura que PostgREST exponga todos los schemas emp_* activos.
-- Sin esto, el cliente falla al consultar tenants (p. ej. emp_andino_4v053).

DO $$
DECLARE
    current_schemas text;
    next_schemas text;
    missing text;
BEGIN
    SELECT COALESCE(
        NULLIF(current_setting('pgrst.db_schemas', true), ''),
        'public'
    )
    INTO current_schemas;

    next_schemas := current_schemas;

    FOR missing IN
        SELECT e.schema_name
        FROM public.empresa e
        WHERE e.schema_name IS NOT NULL
          AND position(e.schema_name IN current_schemas) = 0
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

NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';
