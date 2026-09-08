-- Captura de hoja surtida (foto + JSON extraído por IA) por orden de venta.
CREATE TABLE IF NOT EXISTS public.orden_venta_surtido_captura (
    id_captura uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden_venta uuid NOT NULL REFERENCES public.orden_venta(id_orden_venta) ON DELETE CASCADE,
    codigo_cuenta varchar NOT NULL,
    url_foto text NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    modelo text NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_orden_venta_surtido_captura_orden
    ON public.orden_venta_surtido_captura (id_orden_venta);

COMMENT ON TABLE public.orden_venta_surtido_captura IS
    'Foto de la OV impresa surtida a mano + payload flexible extraído por IA.';

ALTER TABLE public.orden_venta_surtido_captura ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS orden_venta_surtido_captura_select ON public.orden_venta_surtido_captura;
CREATE POLICY orden_venta_surtido_captura_select
    ON public.orden_venta_surtido_captura
    FOR SELECT
    TO authenticated
    USING (public.auth_wms_puede_ver_cuenta(codigo_cuenta));

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'wms_sync_table_to_tenants'
    ) THEN
        PERFORM public.wms_sync_table_to_tenants('orden_venta_surtido_captura');
    END IF;
END $$;
