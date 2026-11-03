-- REQ-104: registro de correos ingresados como OV (manual desde el WMS).
-- Relaciona el message_id del correo (Gmail/n8n) con la OV creada. La llave unica
-- (codigo_cuenta, message_id) evita duplicados por varios clics: el api reserva la fila
-- en estado 'procesando' antes de leer el correo y la pasa a 'ingresado' o 'error'.
-- Se crea en public y se replica a template_wms y a cada emp_* con wms_sync_table_to_tenants.

CREATE TABLE IF NOT EXISTS public.correo_pedido_ingreso (
    id_correo_ingreso uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar NOT NULL,
    message_id text NOT NULL,
    hilo text,
    estado varchar(20) NOT NULL DEFAULT 'procesando'
        CHECK (estado IN ('procesando', 'ingresado', 'error')),
    id_orden_venta uuid REFERENCES public.orden_venta(id_orden_venta) ON DELETE SET NULL,
    codigo_orden_venta varchar,
    origen varchar(20) NOT NULL DEFAULT 'manual'
        CHECK (origen IN ('manual', 'workflow')),
    error text,
    ingresado_por text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_correo_pedido_ingreso_cuenta_message
    ON public.correo_pedido_ingreso (codigo_cuenta, message_id);

CREATE INDEX IF NOT EXISTS idx_correo_pedido_ingreso_cuenta_estado
    ON public.correo_pedido_ingreso (codigo_cuenta, estado, created_at DESC);

COMMENT ON TABLE public.correo_pedido_ingreso IS
    'Correos de pedido ingresados como OV. Una fila por (cuenta, message_id); evita duplicados.';
COMMENT ON COLUMN public.correo_pedido_ingreso.estado IS
    'procesando = reservado por el api; ingresado = OV creada; error = fallo (se puede reintentar).';
COMMENT ON COLUMN public.correo_pedido_ingreso.origen IS
    'manual = el operador lo ingreso desde el WMS; workflow = lo ingreso el workflow de n8n.';

ALTER TABLE public.correo_pedido_ingreso ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS correo_pedido_ingreso_select ON public.correo_pedido_ingreso;
CREATE POLICY correo_pedido_ingreso_select
    ON public.correo_pedido_ingreso
    FOR SELECT
    TO authenticated
    USING (public.auth_wms_puede_ver_cuenta(codigo_cuenta));

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_table_to_tenants'
    ) THEN
        PERFORM public.wms_sync_table_to_tenants('correo_pedido_ingreso');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
