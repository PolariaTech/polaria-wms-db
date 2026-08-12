-- Schema-per-empresa: template_wms + provision + sync DDL + schema_name en empresa.
-- public se conserva (pruebas / legacy). Empresas nuevas usan emp_<codigo>.

-- ---------------------------------------------------------------------------
-- 1. Columna de mapeo en empresa
-- ---------------------------------------------------------------------------
ALTER TABLE public.empresa
    ADD COLUMN IF NOT EXISTS schema_name varchar(63);

COMMENT ON COLUMN public.empresa.schema_name IS
    'Schema Postgres del tenant (emp_*). NULL = datos legacy en public.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_empresa_schema_name
    ON public.empresa (schema_name)
    WHERE schema_name IS NOT NULL;

-- FK usuario→cuenta bloquea cuentas solo en emp_*; pasa a referencia lógica.
ALTER TABLE public.usuario
    DROP CONSTRAINT IF EXISTS fk_usuario_cuenta;

-- ---------------------------------------------------------------------------
-- 2. Catálogo de tablas de negocio a clonar (no plataforma)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wms_tenant_tables (
    table_name text PRIMARY KEY,
    clone_order integer NOT NULL
);

COMMENT ON TABLE public.wms_tenant_tables IS
    'Tablas de negocio que se clonan a cada schema emp_*. Plataforma (empresa/usuario/rol) queda en public.';

TRUNCATE public.wms_tenant_tables;

INSERT INTO public.wms_tenant_tables (table_name, clone_order) VALUES
    ('cuenta', 10),
    ('bodega', 20),
    ('asignacion_bodega', 30),
    ('tipo_ubicacion', 40),
    ('zona', 50),
    ('ubicacion', 60),
    ('proveedor', 70),
    ('cliente', 80),
    ('producto', 90),
    ('comprador', 100),
    ('planta', 110),
    ('camion', 120),
    ('solicitud_compra', 130),
    ('solicitud_compra_linea', 140),
    ('orden_compra', 150),
    ('orden_compra_linea', 160),
    ('recepcion_compra', 170),
    ('recepcion_compra_linea', 180),
    ('lote', 190),
    ('warehouse_state', 200),
    ('movimiento_inventario', 210),
    ('contador', 220),
    ('orden_trabajo', 230),
    ('orden_trabajo_linea', 240),
    ('solicitud_procesamiento', 250),
    ('registro_merma', 260),
    ('alerta_operativa', 270),
    ('tarea_cola', 280),
    ('auditoria_operacion', 290),
    ('orden_venta', 300),
    ('orden_venta_linea', 310),
    ('viaje_transporte', 320),
    ('guia_envio', 330),
    ('evidencia_transporte', 340),
    ('solicitud_integracion', 350),
    ('tarea_cuenta', 360),
    ('cuenta_reporte_embed', 370),
    ('solicitud_alta_bodega', 380);

-- Solo incluir tablas que existan en public (evita fallar si falta alguna drift).
DELETE FROM public.wms_tenant_tables t
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = t.table_name
      AND c.relkind = 'r'
);

-- ---------------------------------------------------------------------------
-- 3. Helpers de naming
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wms_normalize_schema_name(p_codigo text)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT 'emp_' || regexp_replace(lower(trim(p_codigo)), '[^a-z0-9_]', '_', 'g');
$$;

CREATE OR REPLACE FUNCTION public.wms_is_platform_relation(p_schema text, p_table text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_schema = 'public'
       AND p_table IN ('empresa', 'usuario', 'rol');
$$;

CREATE OR REPLACE FUNCTION public.wms_is_tenant_table(p_table text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.wms_tenant_tables t WHERE t.table_name = p_table
    );
$$;

-- ---------------------------------------------------------------------------
-- 4. Clonar estructura de una tabla (sin FKs; INCLUDING ALL = defaults/checks/indexes)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wms_clone_table_structure(
    p_source_schema text,
    p_dest_schema text,
    p_table text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I.%I (LIKE %I.%I INCLUDING ALL)',
        p_dest_schema, p_table, p_source_schema, p_table
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Recrear FKs: tenant→tenant en dest; tenant→plataforma → public
-- ---------------------------------------------------------------------------
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
    col_list text;
    ref_col_list text;
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
            -- Otras refs (p.ej. ya en otro schema): mantener origen
            dest_ref_schema := r.ref_schema;
        END IF;

        -- Reescribir REFERENCES schema.table
        BEGIN
            EXECUTE format(
                'ALTER TABLE %I.%I ADD CONSTRAINT %I %s',
                p_dest_schema,
                r.table_name,
                r.conname,
                regexp_replace(
                    r.condef,
                    'REFERENCES\s+[a-zA-Z0-9_\."]+\.[a-zA-Z0-9_\."]+',
                    format('REFERENCES %I.%I', dest_ref_schema, r.ref_table),
                    'i'
                )
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

-- ---------------------------------------------------------------------------
-- 6. Triggers updated_at (reutilizar public.set_updated_at)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wms_clone_updated_at_triggers(
    p_source_schema text,
    p_dest_schema text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT t.tgname, c.relname AS table_name
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_proc p ON p.oid = t.tgfoid
        WHERE n.nspname = p_source_schema
          AND NOT t.tgisinternal
          AND p.proname = 'set_updated_at'
          AND public.wms_is_tenant_table(c.relname)
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS %I ON %I.%I',
            r.tgname, p_dest_schema, r.table_name
        );
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()',
            r.tgname, p_dest_schema, r.table_name
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. RLS + grants + policy de aislamiento por codigo_empresa del schema
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wms_apply_tenant_rls(
    p_schema text,
    p_codigo_empresa text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    t text;
    pol text;
BEGIN
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO anon, authenticated, service_role', p_schema);
    EXECUTE format(
        'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO anon, authenticated, service_role',
        p_schema
    );
    EXECUTE format(
        'GRANT ALL ON ALL SEQUENCES IN SCHEMA %I TO anon, authenticated, service_role',
        p_schema
    );
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO anon, authenticated, service_role',
        p_schema
    );
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT ALL ON SEQUENCES TO anon, authenticated, service_role',
        p_schema
    );

    FOR t IN
        SELECT table_name FROM public.wms_tenant_tables ORDER BY clone_order
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = p_schema AND c.relname = t AND c.relkind = 'r'
        ) THEN
            CONTINUE;
        END IF;

        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', p_schema, t);

        pol := 'wms_tenant_isolation';
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', pol, p_schema, t);
        EXECUTE format(
            'CREATE POLICY %I ON %I.%I FOR ALL TO authenticated USING (
                public.auth_wms_es_configurador()
                OR (public.auth_wms_usuario_actual()).codigo_empresa = %L
            ) WITH CHECK (
                public.auth_wms_es_configurador()
                OR (public.auth_wms_usuario_actual()).codigo_empresa = %L
            )',
            pol, p_schema, t, p_codigo_empresa, p_codigo_empresa
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. Exponer schema en PostgREST (append a lista actual)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wms_expose_schema_postgrest(p_schema text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    current_schemas text;
    next_schemas text;
BEGIN
    SELECT COALESCE(
        NULLIF(current_setting('pgrst.db_schemas', true), ''),
        'public, graphql_public, mateo_support, mit'
    )
    INTO current_schemas;

    IF position(p_schema IN current_schemas) > 0 THEN
        PERFORM pg_notify('pgrst', 'reload schema');
        RETURN;
    END IF;

    next_schemas := current_schemas || ', ' || p_schema;

    BEGIN
        EXECUTE format(
            'ALTER ROLE authenticator SET pgrst.db_schemas = %L',
            next_schemas
        );
    EXCEPTION
        WHEN undefined_object THEN
            RAISE NOTICE 'Rol authenticator no existe; se omite pgrst.db_schemas';
            RETURN;
    END;

    PERFORM pg_notify('pgrst', 'reload config');
    PERFORM pg_notify('pgrst', 'reload schema');
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Crear / refrescar template_wms desde public
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wms_refresh_template_wms()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    t text;
BEGIN
    CREATE SCHEMA IF NOT EXISTS template_wms;
    COMMENT ON SCHEMA template_wms IS
        'Plantilla estructural WMS (sin datos). Fuente para provisionar emp_*.';

    FOR t IN
        SELECT table_name FROM public.wms_tenant_tables ORDER BY clone_order
    LOOP
        EXECUTE format('DROP TABLE IF EXISTS template_wms.%I CASCADE', t);
        PERFORM public.wms_clone_table_structure('public', 'template_wms', t);
    END LOOP;

    PERFORM public.wms_clone_foreign_keys('public', 'template_wms');
    PERFORM public.wms_clone_updated_at_triggers('public', 'template_wms');

    -- Sin datos ni exposición PostgREST del template.
    REVOKE ALL ON SCHEMA template_wms FROM PUBLIC;
    GRANT USAGE ON SCHEMA template_wms TO postgres;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. Provision schema de una empresa
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wms_provision_empresa_schema(p_codigo_empresa text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_codigo text := trim(p_codigo_empresa);
    v_schema text;
    t text;
BEGIN
    IF v_codigo IS NULL OR v_codigo = '' THEN
        RAISE EXCEPTION 'codigo_empresa es obligatorio';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.empresa e WHERE e.codigo_empresa = v_codigo) THEN
        RAISE EXCEPTION 'empresa % no existe', v_codigo;
    END IF;

    v_schema := public.wms_normalize_schema_name(v_codigo);

    IF EXISTS (
        SELECT 1 FROM public.empresa e
        WHERE e.schema_name = v_schema
          AND e.codigo_empresa <> v_codigo
    ) THEN
        RAISE EXCEPTION 'schema_name % ya asignado a otra empresa', v_schema;
    END IF;

    -- Asegurar template actualizado
    PERFORM public.wms_refresh_template_wms();

    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', v_schema);
    EXECUTE format(
        'COMMENT ON SCHEMA %I IS %L',
        v_schema,
        format('Tenant WMS empresa %s', v_codigo)
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

REVOKE ALL ON FUNCTION public.wms_provision_empresa_schema(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.wms_provision_empresa_schema(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.wms_provision_empresa_schema(text) TO postgres;

-- ---------------------------------------------------------------------------
-- 11. Sync DDL: agregar columna nueva de public/template a todos los emp_*
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wms_sync_column_to_tenants(
    p_table text,
    p_column text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r record;
    col_def text;
    applied integer := 0;
BEGIN
    IF NOT public.wms_is_tenant_table(p_table) THEN
        RAISE EXCEPTION 'tabla % no es tenant', p_table;
    END IF;

    SELECT
        format_type(a.atttypid, a.atttypmod)
            || CASE
                WHEN a.atthasdef THEN ' DEFAULT ' || pg_get_expr(ad.adbin, ad.adrelid)
                ELSE ''
               END
            || CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END
    INTO col_def
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
    WHERE n.nspname = 'public'
      AND c.relname = p_table
      AND a.attname = p_column
      AND a.attnum > 0
      AND NOT a.attisdropped;

    IF col_def IS NULL THEN
        RAISE EXCEPTION 'columna %.% no existe en public', p_table, p_column;
    END IF;

    EXECUTE format('DROP TABLE IF EXISTS template_wms.%I CASCADE', p_table);
    PERFORM public.wms_clone_table_structure('public', 'template_wms', p_table);

    FOR r IN
        SELECT e.schema_name
        FROM public.empresa e
        WHERE e.schema_name IS NOT NULL
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = r.schema_name
              AND table_name = p_table
              AND column_name = p_column
        ) THEN
            EXECUTE format(
                'ALTER TABLE %I.%I ADD COLUMN %I %s',
                r.schema_name, p_table, p_column, col_def
            );
            applied := applied + 1;
        END IF;
    END LOOP;

    RETURN applied;
END;
$$;

CREATE OR REPLACE FUNCTION public.wms_sync_table_to_tenants(p_table text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r record;
    applied integer := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = p_table AND c.relkind = 'r'
    ) THEN
        RAISE EXCEPTION 'tabla public.% no existe', p_table;
    END IF;

    INSERT INTO public.wms_tenant_tables (table_name, clone_order)
    VALUES (
        p_table,
        COALESCE((SELECT max(clone_order) + 10 FROM public.wms_tenant_tables), 10)
    )
    ON CONFLICT (table_name) DO NOTHING;

    PERFORM public.wms_refresh_template_wms();

    FOR r IN
        SELECT e.codigo_empresa, e.schema_name
        FROM public.empresa e
        WHERE e.schema_name IS NOT NULL
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = r.schema_name AND c.relname = p_table AND c.relkind = 'r'
        ) THEN
            PERFORM public.wms_clone_table_structure('template_wms', r.schema_name, p_table);
            PERFORM public.wms_apply_tenant_rls(r.schema_name, r.codigo_empresa);
            applied := applied + 1;
        END IF;
    END LOOP;

    -- Reaplicar FKs en tenants (best-effort)
    FOR r IN
        SELECT e.schema_name FROM public.empresa e WHERE e.schema_name IS NOT NULL
    LOOP
        PERFORM public.wms_clone_foreign_keys('template_wms', r.schema_name);
        PERFORM public.wms_clone_updated_at_triggers('template_wms', r.schema_name);
    END LOOP;

    RETURN applied;
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Bootstrap template inicial
-- ---------------------------------------------------------------------------
SELECT public.wms_refresh_template_wms();
