-- Precio vigente por producto (fuente de verdad para ventas).
-- La tabla ya puede existir en entornos con seed; IF NOT EXISTS hace el alta idempotente.

CREATE TABLE IF NOT EXISTS public.precio_producto (
    id_precio uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_producto uuid NOT NULL,
    precio numeric(12, 4) NOT NULL,
    moneda varchar(3) NOT NULL DEFAULT 'MXN',
    fecha_aplicacion timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_precio_cuenta
        FOREIGN KEY (codigo_cuenta) REFERENCES public.cuenta (codigo_cuenta),
    CONSTRAINT fk_precio_producto
        FOREIGN KEY (id_producto) REFERENCES public.producto (id_producto) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS ix_precio_producto_cuenta_producto
    ON public.precio_producto (codigo_cuenta, id_producto, fecha_aplicacion DESC);

COMMENT ON TABLE public.precio_producto IS
    'Precio de venta por producto. El vigente es la fila con fecha_aplicacion más reciente.';

ALTER TABLE public.precio_producto ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS precio_producto_select_scope ON public.precio_producto;

CREATE POLICY precio_producto_select_scope
    ON public.precio_producto
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

GRANT SELECT ON public.precio_producto TO authenticated;

INSERT INTO public.wms_tenant_tables (table_name, clone_order)
SELECT 'precio_producto', COALESCE((SELECT max(clone_order) + 10 FROM public.wms_tenant_tables), 400)
WHERE EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'wms_tenant_tables'
)
AND NOT EXISTS (
    SELECT 1 FROM public.wms_tenant_tables WHERE table_name = 'precio_producto'
);
