-- 086_tmp_grupo_perteneciente.sql
-- TABLA TEMPORAL DE PRUEBA — catálogo de grupos pertenecientes por cuenta
-- (dropdown crear/editar comprador y filtros de exportación de precios).
-- Se puede borrar cuando exista el modelo definitivo de marcas/grupos.

CREATE TABLE IF NOT EXISTS public.tmp_grupo_perteneciente (
    id_tmp_grupo_perteneciente uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    nombre text NOT NULL,
    orden integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_tmp_grupo_perteneciente_cuenta_nombre
        UNIQUE (codigo_cuenta, nombre),

    CONSTRAINT ck_tmp_grupo_perteneciente_nombre
        CHECK (length(btrim(nombre)) > 0),

    CONSTRAINT ck_tmp_grupo_perteneciente_orden
        CHECK (orden >= 1),

    CONSTRAINT fk_tmp_grupo_perteneciente_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES public.cuenta (codigo_cuenta)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tmp_grupo_perteneciente_cuenta
    ON public.tmp_grupo_perteneciente (codigo_cuenta);

CREATE INDEX IF NOT EXISTS idx_tmp_grupo_perteneciente_cuenta_orden
    ON public.tmp_grupo_perteneciente (codigo_cuenta, orden);

DROP TRIGGER IF EXISTS trg_tmp_grupo_perteneciente_updated_at
    ON public.tmp_grupo_perteneciente;

CREATE TRIGGER trg_tmp_grupo_perteneciente_updated_at
    BEFORE UPDATE ON public.tmp_grupo_perteneciente
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.tmp_grupo_perteneciente IS
    'TEMPORAL DE PRUEBA: catálogo de grupos pertenecientes por cuenta. Borrar cuando exista el modelo definitivo.';

COMMENT ON COLUMN public.tmp_grupo_perteneciente.nombre IS
    'Etiqueta que se guarda en comprador.grupo y se muestra en filtros/exportación.';

COMMENT ON COLUMN public.tmp_grupo_perteneciente.orden IS
    'Orden de presentación en el dropdown (1 = primero).';

ALTER TABLE public.tmp_grupo_perteneciente ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tmp_grupo_perteneciente_select_scope
    ON public.tmp_grupo_perteneciente;

CREATE POLICY tmp_grupo_perteneciente_select_scope
    ON public.tmp_grupo_perteneciente
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

GRANT SELECT ON public.tmp_grupo_perteneciente TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tmp_grupo_perteneciente TO service_role;

INSERT INTO public.wms_tenant_tables (table_name, clone_order)
SELECT 'tmp_grupo_perteneciente',
       COALESCE((SELECT max(clone_order) + 10 FROM public.wms_tenant_tables), 410)
WHERE EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'wms_tenant_tables'
)
AND NOT EXISTS (
    SELECT 1 FROM public.wms_tenant_tables WHERE table_name = 'tmp_grupo_perteneciente'
);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_table_to_tenants'
    ) THEN
        PERFORM public.wms_sync_table_to_tenants('tmp_grupo_perteneciente');
    END IF;
END $$;
