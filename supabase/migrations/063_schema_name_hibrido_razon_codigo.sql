-- Naming hibrido de schemas: emp_<razon_social>_<codigo>
-- Ejemplo: Andino + 4V053 -> emp_andino_4v053

DROP FUNCTION IF EXISTS public.wms_normalize_schema_name(text) CASCADE;

CREATE OR REPLACE FUNCTION public.wms_slugify_identifier(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT trim(both '_' FROM
        regexp_replace(
            regexp_replace(lower(trim(coalesce(p_text, ''))), '[^a-z0-9]+', '_', 'g'),
            '_+',
            '_',
            'g'
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.wms_normalize_schema_name(
    p_codigo text,
    p_razon_social text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_codigo text := public.wms_slugify_identifier(p_codigo);
    v_razon text := public.wms_slugify_identifier(p_razon_social);
    v_name text;
BEGIN
    IF v_codigo IS NULL OR v_codigo = '' THEN
        RAISE EXCEPTION 'codigo_empresa es obligatorio para schema_name';
    END IF;

    IF v_razon IS NOT NULL AND v_razon <> '' THEN
        v_name := 'emp_' || v_razon || '_' || v_codigo;
    ELSE
        v_name := 'emp_' || v_codigo;
    END IF;

    -- Límite Postgres: 63 bytes
    IF length(v_name) > 63 THEN
        v_name := left(v_name, greatest(0, 63 - 1 - length(v_codigo)))
            || '_'
            || v_codigo;
        v_name := left(v_name, 63);
    END IF;

    RETURN v_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.wms_provision_empresa_schema(p_codigo_empresa text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    PERFORM public.wms_apply_tenant_rls(v_schema, v_codigo);
    PERFORM public.wms_expose_schema_postgrest(v_schema);

    UPDATE public.empresa
    SET schema_name = v_schema,
        updated_at = now()
    WHERE codigo_empresa = v_codigo;

    RETURN v_schema;
END;
$$;

-- Renombrar schemas legacy emp_<codigo> -> emp_<razon>_<codigo>
DO $$
DECLARE
    r record;
    v_new text;
    v_current text;
    v_next text;
BEGIN
    FOR r IN
        SELECT e.codigo_empresa, e.razon_social, e.schema_name
        FROM public.empresa e
        WHERE e.schema_name IS NOT NULL
    LOOP
        v_new := public.wms_normalize_schema_name(r.codigo_empresa, r.razon_social);
        IF v_new = r.schema_name THEN
            CONTINUE;
        END IF;

        IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = v_new) THEN
            RAISE NOTICE 'Schema destino % ya existe; se omite rename de %',
                v_new, r.schema_name;
            CONTINUE;
        END IF;

        IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = r.schema_name) THEN
            EXECUTE format('ALTER SCHEMA %I RENAME TO %I', r.schema_name, v_new);
        END IF;

        UPDATE public.empresa
        SET schema_name = v_new,
            updated_at = now()
        WHERE codigo_empresa = r.codigo_empresa;

        -- Actualizar lista PostgREST si el rol existe
        BEGIN
            SELECT COALESCE(
                NULLIF(current_setting('pgrst.db_schemas', true), ''),
                'public, graphql_public, mateo_support, mit'
            )
            INTO v_current;

            v_next := replace(v_current, r.schema_name, v_new);
            IF position(v_new IN v_next) = 0 THEN
                v_next := v_next || ', ' || v_new;
            END IF;

            EXECUTE format(
                'ALTER ROLE authenticator SET pgrst.db_schemas = %L',
                v_next
            );
            PERFORM pg_notify('pgrst', 'reload config');
            PERFORM pg_notify('pgrst', 'reload schema');
        EXCEPTION
            WHEN undefined_object THEN
                NULL;
        END;
    END LOOP;
END;
$$;
