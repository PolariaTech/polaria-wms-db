-- Historial de fotos de surtido por OT (cada subida/reemplazo queda registrada).
CREATE TABLE IF NOT EXISTS public.orden_venta_surtido_captura_foto (
    id_foto uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden_venta uuid NOT NULL REFERENCES public.orden_venta(id_orden_venta) ON DELETE CASCADE,
    id_orden_trabajo text NOT NULL DEFAULT '',
    codigo_cuenta varchar NOT NULL,
    url_foto text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_orden_venta_surtido_captura_foto_ov_ot
    ON public.orden_venta_surtido_captura_foto (id_orden_venta, id_orden_trabajo, created_at DESC);

COMMENT ON TABLE public.orden_venta_surtido_captura_foto IS
    'Historial de fotos subidas desde el QR de surtido (incluye reemplazos).';

ALTER TABLE public.orden_venta_surtido_captura_foto ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS orden_venta_surtido_captura_foto_select
    ON public.orden_venta_surtido_captura_foto;
CREATE POLICY orden_venta_surtido_captura_foto_select
    ON public.orden_venta_surtido_captura_foto
    FOR SELECT
    TO authenticated
    USING (public.auth_wms_puede_ver_cuenta(codigo_cuenta));

-- Sembrar historial con la foto actual (si existe) para no empezar vacío.
INSERT INTO public.orden_venta_surtido_captura_foto (
    id_orden_venta,
    id_orden_trabajo,
    codigo_cuenta,
    url_foto,
    created_at
)
SELECT
    c.id_orden_venta,
    COALESCE(c.id_orden_trabajo, ''),
    c.codigo_cuenta,
    c.url_foto,
    COALESCE(c.updated_at, c.created_at, now())
FROM public.orden_venta_surtido_captura c
WHERE c.url_foto IS NOT NULL
  AND btrim(c.url_foto) <> ''
  AND NOT EXISTS (
      SELECT 1
      FROM public.orden_venta_surtido_captura_foto f
      WHERE f.id_orden_venta = c.id_orden_venta
        AND f.id_orden_trabajo = COALESCE(c.id_orden_trabajo, '')
        AND f.url_foto = c.url_foto
  );

DO $$
DECLARE
    r record;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_table_to_tenants'
    ) THEN
        PERFORM public.wms_sync_table_to_tenants('orden_venta_surtido_captura_foto');
    END IF;

    FOR r IN
        SELECT DISTINCT btrim(schema_name) AS schema_name
        FROM public.empresa
        WHERE schema_name IS NOT NULL
          AND btrim(schema_name) <> ''
          AND btrim(schema_name) <> 'public'
    LOOP
        IF to_regclass(format('%I.orden_venta_surtido_captura', r.schema_name)) IS NULL THEN
            CONTINUE;
        END IF;

        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I.orden_venta_surtido_captura_foto (
                id_foto uuid PRIMARY KEY DEFAULT gen_random_uuid(),
                id_orden_venta uuid NOT NULL,
                id_orden_trabajo text NOT NULL DEFAULT '''',
                codigo_cuenta varchar NOT NULL,
                url_foto text NOT NULL,
                created_at timestamptz NOT NULL DEFAULT now()
            )',
            r.schema_name
        );
        EXECUTE format(
            'CREATE INDEX IF NOT EXISTS idx_orden_venta_surtido_captura_foto_ov_ot
               ON %I.orden_venta_surtido_captura_foto (id_orden_venta, id_orden_trabajo, created_at DESC)',
            r.schema_name
        );
        EXECUTE format(
            'ALTER TABLE %I.orden_venta_surtido_captura_foto ENABLE ROW LEVEL SECURITY',
            r.schema_name
        );

        EXECUTE format(
            'INSERT INTO %I.orden_venta_surtido_captura_foto (
                id_orden_venta, id_orden_trabajo, codigo_cuenta, url_foto, created_at
             )
             SELECT
                c.id_orden_venta,
                COALESCE(c.id_orden_trabajo, ''''),
                c.codigo_cuenta,
                c.url_foto,
                COALESCE(c.updated_at, c.created_at, now())
             FROM %I.orden_venta_surtido_captura c
             WHERE c.url_foto IS NOT NULL
               AND btrim(c.url_foto) <> ''''
               AND NOT EXISTS (
                   SELECT 1
                   FROM %I.orden_venta_surtido_captura_foto f
                   WHERE f.id_orden_venta = c.id_orden_venta
                     AND f.id_orden_trabajo = COALESCE(c.id_orden_trabajo, '''')
                     AND f.url_foto = c.url_foto
               )',
            r.schema_name,
            r.schema_name,
            r.schema_name
        );
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
