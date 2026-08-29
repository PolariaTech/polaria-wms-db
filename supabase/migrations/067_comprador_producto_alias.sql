-- Alias de producto por comprador (cómo ese comprador llama al ítem del catálogo).
-- No modifica public.producto: la relación vive en esta tabla.

CREATE TABLE IF NOT EXISTS public.comprador_producto_alias (
    id_alias uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_comprador uuid NOT NULL,
    id_producto uuid NOT NULL,
    alias varchar(255) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_comprador_producto_alias UNIQUE (id_comprador, id_producto),

    CONSTRAINT fk_comprador_producto_alias_cuenta
        FOREIGN KEY (codigo_cuenta) REFERENCES cuenta (codigo_cuenta),
    CONSTRAINT fk_comprador_producto_alias_comprador
        FOREIGN KEY (id_comprador) REFERENCES comprador (id_comprador) ON DELETE CASCADE,
    CONSTRAINT fk_comprador_producto_alias_producto
        FOREIGN KEY (id_producto) REFERENCES producto (id_producto) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS ix_comprador_producto_alias_cuenta
    ON public.comprador_producto_alias (codigo_cuenta);

CREATE INDEX IF NOT EXISTS ix_comprador_producto_alias_comprador
    ON public.comprador_producto_alias (id_comprador);

CREATE INDEX IF NOT EXISTS ix_comprador_producto_alias_producto
    ON public.comprador_producto_alias (id_producto);

DROP TRIGGER IF EXISTS trg_comprador_producto_alias_updated_at
    ON public.comprador_producto_alias;

CREATE TRIGGER trg_comprador_producto_alias_updated_at
    BEFORE UPDATE ON public.comprador_producto_alias
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.comprador_producto_alias IS
    'Nombre con el que un comprador conoce un producto del catálogo (ej. sandía → patilla).';

ALTER TABLE public.comprador_producto_alias ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS comprador_producto_alias_select_scope
    ON public.comprador_producto_alias;
DROP POLICY IF EXISTS comprador_producto_alias_insert_cuenta
    ON public.comprador_producto_alias;
DROP POLICY IF EXISTS comprador_producto_alias_update_cuenta
    ON public.comprador_producto_alias;
DROP POLICY IF EXISTS comprador_producto_alias_delete_configurador
    ON public.comprador_producto_alias;

CREATE POLICY comprador_producto_alias_select_scope
    ON public.comprador_producto_alias FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

CREATE POLICY comprador_producto_alias_insert_cuenta
    ON public.comprador_producto_alias FOR INSERT TO authenticated
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY comprador_producto_alias_update_cuenta
    ON public.comprador_producto_alias FOR UPDATE TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)
    )
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY comprador_producto_alias_delete_configurador
    ON public.comprador_producto_alias FOR DELETE TO authenticated
    USING (auth_wms_es_configurador());

GRANT SELECT, INSERT, UPDATE ON public.comprador_producto_alias TO authenticated;
GRANT DELETE ON public.comprador_producto_alias TO authenticated;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_table_to_tenants'
    ) THEN
        PERFORM public.wms_sync_table_to_tenants('comprador_producto_alias');
    ELSIF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'wms_tenant_tables'
    ) THEN
        INSERT INTO public.wms_tenant_tables (table_name, clone_order)
        SELECT 'comprador_producto_alias',
               COALESCE((SELECT max(clone_order) + 10 FROM public.wms_tenant_tables), 105)
        WHERE NOT EXISTS (
            SELECT 1 FROM public.wms_tenant_tables
            WHERE table_name = 'comprador_producto_alias'
        );
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
