-- 085_tmp_producto_mas_vendido.sql
-- TABLA TEMPORAL DE PRUEBA — se puede borrar cuando se defina el modelo real.
-- Ranking inventado de "productos más vendidos" por cuenta (filtro de exportación de precios).

CREATE TABLE IF NOT EXISTS public.tmp_producto_mas_vendido (
    id_tmp_producto_mas_vendido uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_producto uuid NOT NULL,
    ranking integer NOT NULL DEFAULT 1,
    unidades_vendidas numeric(14, 2) NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_tmp_producto_mas_vendido_cuenta_producto
        UNIQUE (codigo_cuenta, id_producto),

    CONSTRAINT ck_tmp_producto_mas_vendido_ranking
        CHECK (ranking >= 1),

    CONSTRAINT fk_tmp_producto_mas_vendido_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES public.cuenta (codigo_cuenta)
        ON DELETE CASCADE,

    CONSTRAINT fk_tmp_producto_mas_vendido_producto
        FOREIGN KEY (id_producto)
        REFERENCES public.producto (id_producto)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tmp_producto_mas_vendido_cuenta
    ON public.tmp_producto_mas_vendido (codigo_cuenta);

CREATE INDEX IF NOT EXISTS idx_tmp_producto_mas_vendido_cuenta_ranking
    ON public.tmp_producto_mas_vendido (codigo_cuenta, ranking);

DROP TRIGGER IF EXISTS trg_tmp_producto_mas_vendido_updated_at
    ON public.tmp_producto_mas_vendido;

CREATE TRIGGER trg_tmp_producto_mas_vendido_updated_at
    BEFORE UPDATE ON public.tmp_producto_mas_vendido
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.tmp_producto_mas_vendido IS
    'TEMPORAL DE PRUEBA: productos más vendidos por cuenta para filtros de exportación de precios. Borrar cuando exista el modelo definitivo.';

COMMENT ON COLUMN public.tmp_producto_mas_vendido.ranking IS
    '1 = más vendido. Orden de presentación en la UI de filtros.';

COMMENT ON COLUMN public.tmp_producto_mas_vendido.unidades_vendidas IS
    'Volumen inventado para pruebas; no es métrica operativa real.';

ALTER TABLE public.tmp_producto_mas_vendido ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tmp_producto_mas_vendido_select_scope
    ON public.tmp_producto_mas_vendido;

CREATE POLICY tmp_producto_mas_vendido_select_scope
    ON public.tmp_producto_mas_vendido
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

GRANT SELECT ON public.tmp_producto_mas_vendido TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tmp_producto_mas_vendido TO service_role;

INSERT INTO public.wms_tenant_tables (table_name, clone_order)
SELECT 'tmp_producto_mas_vendido',
       COALESCE((SELECT max(clone_order) + 10 FROM public.wms_tenant_tables), 400)
WHERE EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'wms_tenant_tables'
)
AND NOT EXISTS (
    SELECT 1 FROM public.wms_tenant_tables WHERE table_name = 'tmp_producto_mas_vendido'
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
        PERFORM public.wms_sync_table_to_tenants('tmp_producto_mas_vendido');
    END IF;
END $$;
