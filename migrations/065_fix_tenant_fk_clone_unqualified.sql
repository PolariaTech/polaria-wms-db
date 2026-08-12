-- Fix FK clone: REFERENCES sin schema se resolvía a public.* en vez de emp_*.
-- Repara template_wms y todos los schemas emp_* existentes.

CREATE OR REPLACE FUNCTION public.wms_clone_foreign_keys(
    p_source_schema text,
    p_dest_schema text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
    dest_ref_schema text;
    new_def text;
BEGIN
    FOR r IN
        SELECT
            c.conname,
            rel.relname AS table_name,
            pg_get_constraintdef(c.oid) AS condef,
            nref.nspname AS ref_schema,
            ref.relname AS ref_table
        FROM pg_constraint c
        JOIN pg_class rel ON rel.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = rel.relnamespace
        JOIN pg_class ref ON ref.oid = c.confrelid
        JOIN pg_namespace nref ON nref.oid = ref.relnamespace
        WHERE c.contype = 'f'
          AND n.nspname = p_source_schema
          AND public.wms_is_tenant_table(rel.relname)
    LOOP
        IF public.wms_is_platform_relation(r.ref_schema, r.ref_table)
           OR r.ref_schema = 'auth' THEN
            dest_ref_schema := r.ref_schema;
        ELSIF public.wms_is_tenant_table(r.ref_table) THEN
            dest_ref_schema := p_dest_schema;
        ELSE
            dest_ref_schema := r.ref_schema;
        END IF;

        -- Cubre REFERENCES schema.table y REFERENCES table (sin schema).
        new_def := regexp_replace(
            r.condef,
            'REFERENCES\s+(?:[a-zA-Z0-9_]+\.)?[a-zA-Z0-9_]+',
            format('REFERENCES %I.%I', dest_ref_schema, r.ref_table),
            'i'
        );

        BEGIN
            EXECUTE format(
                'ALTER TABLE %I.%I ADD CONSTRAINT %I %s',
                p_dest_schema,
                r.table_name,
                r.conname,
                new_def
            );
        EXCEPTION
            WHEN duplicate_object THEN
                NULL;
            WHEN others THEN
                RAISE NOTICE 'FK skip %.%: % (%)',
                    p_dest_schema, r.conname, SQLERRM, SQLSTATE;
        END;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.wms_clone_foreign_keys(text, text) IS
    'Clona FKs a dest; tenant→tenant usa dest schema; platform/auth quedan en public. '
    'Soporta REFERENCES con o sin schema calificado.';

-- ---------------------------------------------------------------------------
-- Reparar FKs mal apuntadas a public.* en un schema tenant/template
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wms_repair_tenant_foreign_keys(p_schema text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r record;
    dropped integer := 0;
BEGIN
    IF p_schema IS NULL OR p_schema !~ '^(emp_|template_)[a-z0-9_]+$' THEN
        RAISE EXCEPTION 'schema inválido para repair: %', p_schema;
    END IF;

    -- Quitar FKs de tablas tenant en p_schema que apuntan a public.tenant_table
    -- (deberían apuntar a p_schema.tenant_table).
    FOR r IN
        SELECT c.conname, rel.relname AS table_name
        FROM pg_constraint c
        JOIN pg_class rel ON rel.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = rel.relnamespace
        JOIN pg_class ref ON ref.oid = c.confrelid
        JOIN pg_namespace nref ON nref.oid = ref.relnamespace
        WHERE c.contype = 'f'
          AND n.nspname = p_schema
          AND public.wms_is_tenant_table(rel.relname)
          AND public.wms_is_tenant_table(ref.relname)
          AND nref.nspname = 'public'
    LOOP
        EXECUTE format(
            'ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I',
            p_schema, r.table_name, r.conname
        );
        dropped := dropped + 1;
    END LOOP;

    -- Recrear desde public (source de verdad de columnas/ON DELETE) con fix de clone.
    PERFORM public.wms_clone_foreign_keys('public', p_schema);

    RETURN dropped;
END;
$$;

REVOKE ALL ON FUNCTION public.wms_repair_tenant_foreign_keys(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.wms_repair_tenant_foreign_keys(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.wms_repair_tenant_foreign_keys(text) TO postgres;

-- Aplicar a template + todos los emp_*
DO $$
DECLARE
    r record;
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_namespace WHERE nspname = 'template_wms'
    ) THEN
        PERFORM public.wms_repair_tenant_foreign_keys('template_wms');
    END IF;

    FOR r IN
        SELECT e.schema_name
        FROM public.empresa e
        WHERE e.schema_name IS NOT NULL
          AND e.schema_name ~ '^emp_[a-z0-9_]+$'
    LOOP
        PERFORM public.wms_repair_tenant_foreign_keys(r.schema_name);
    END LOOP;
END;
$$;
