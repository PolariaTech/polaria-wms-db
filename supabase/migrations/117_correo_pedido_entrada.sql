-- POL-410: tabla de correos de pedidos recibidos (hoy es el datatable `correos_aguacates_entrada`
-- de n8n). Una fila por (cuenta, correo): el flujo de n8n la escribe con upsert por
-- (codigo_cuenta, message_id) y el api la lee en lugar de pasar por el Puente de n8n.
-- Las columnas son las de CorreoFilaDto (REQ-104 / REQ-275). `resultado`, `confianza`, `tipo`,
-- `codigo_orden_venta` y `nuevo_pedido` pueden ser null: son las filas anteriores a que el
-- workflow anotara el resultado.
-- Se crea en public y se replica a template_wms y a cada emp_* con wms_sync_table_to_tenants.
-- La RLS del esquema de la empresa aisla por empresa, no por cuenta: toda lectura del api
-- tambien filtra por codigo_cuenta.

CREATE TABLE IF NOT EXISTS public.correo_pedido_entrada (
    id_correo_entrada uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar NOT NULL,
    message_id text NOT NULL,
    recibido_en timestamptz,
    de text,
    para text,
    asunto text,
    hilo text,
    adjunto text,
    nuevo_pedido boolean,
    motivo text,
    resultado varchar(20)
        CHECK (resultado IS NULL OR resultado IN ('recibido', 'ingresado', 'duplicado', 'error', 'no_es_pedido')),
    confianza varchar(10)
        CHECK (confianza IS NULL OR confianza IN ('alta', 'media', 'baja')),
    tipo text,
    codigo_orden_venta text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_correo_pedido_entrada_cuenta_message
    ON public.correo_pedido_entrada (codigo_cuenta, message_id);

CREATE INDEX IF NOT EXISTS idx_correo_pedido_entrada_cuenta_recibido
    ON public.correo_pedido_entrada (codigo_cuenta, recibido_en DESC);

COMMENT ON TABLE public.correo_pedido_entrada IS
    'Correos de pedidos recibidos (antes datatable de n8n). Una fila por (cuenta, message_id).';
COMMENT ON COLUMN public.correo_pedido_entrada.nuevo_pedido IS
    'false = el workflow lo descarto; true = lo tomo como pedido; null = aun sin marcar.';
COMMENT ON COLUMN public.correo_pedido_entrada.resultado IS
    'Que hizo el workflow: recibido, ingresado, duplicado, error o no_es_pedido. null en filas antiguas.';
COMMENT ON COLUMN public.correo_pedido_entrada.codigo_orden_venta IS
    'OV en que se convirtio el correo; varias separadas por coma si salieron mas de una.';

ALTER TABLE public.correo_pedido_entrada ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS correo_pedido_entrada_select ON public.correo_pedido_entrada;
CREATE POLICY correo_pedido_entrada_select
    ON public.correo_pedido_entrada
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
        PERFORM public.wms_sync_table_to_tenants('correo_pedido_entrada');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
