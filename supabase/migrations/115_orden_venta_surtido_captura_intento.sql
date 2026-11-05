-- REQ-247: intentos de captura de foto de surtido (cola en segundo plano).
-- El api recibe la foto, reserva una fila en estado 'recibida' y responde de inmediato;
-- la lectura con IA, el guardado y el avance de estado de la OV siguen aparte
-- (recibida -> procesando -> lista | fallo). Cada foto es una fila: deja su estado, el motivo
-- del fallo, los tiempos por etapa y la URL de la foto guardada, para reintentar sin volver
-- a tomarla. Tambien sirve para ver las fotos que fallan (REQ-207), que antes no dejaban rastro.
-- A diferencia de orden_venta_surtido_captura (una fila por OV y OT, la ultima), aqui hay una
-- fila por cada foto enviada: no tiene llave unica por OV y OT.
-- Se crea en public y se replica a template_wms y a cada emp_* con wms_sync_table_to_tenants.

CREATE TABLE IF NOT EXISTS public.orden_venta_surtido_captura_intento (
    id_intento uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_orden_venta uuid NOT NULL REFERENCES public.orden_venta(id_orden_venta) ON DELETE CASCADE,
    id_orden_trabajo text NOT NULL DEFAULT '',
    codigo_cuenta varchar NOT NULL,
    estado varchar(20) NOT NULL DEFAULT 'recibida'
        CHECK (estado IN ('recibida', 'procesando', 'lista', 'fallo')),
    url_foto text,
    codigo_error varchar(40),
    mensaje_error text,
    modelo text,
    numero_intento integer NOT NULL DEFAULT 1 CHECK (numero_intento >= 1),
    tiempos jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    terminado_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_orden_venta_surtido_captura_intento_ov_ot
    ON public.orden_venta_surtido_captura_intento (id_orden_venta, id_orden_trabajo, created_at DESC);

-- Para encontrar los intentos que siguen en curso (y los que quedaron colgados).
CREATE INDEX IF NOT EXISTS idx_orden_venta_surtido_captura_intento_en_curso
    ON public.orden_venta_surtido_captura_intento (created_at)
    WHERE estado IN ('recibida', 'procesando');

COMMENT ON TABLE public.orden_venta_surtido_captura_intento IS
    'Una fila por foto de surtido enviada desde el QR. Estado de la cola en segundo plano y rastro de fallos.';
COMMENT ON COLUMN public.orden_venta_surtido_captura_intento.estado IS
    'recibida = el api guardo la foto; procesando = leyendo con IA; lista = captura guardada; fallo = no se pudo (ver codigo_error y mensaje_error).';
COMMENT ON COLUMN public.orden_venta_surtido_captura_intento.url_foto IS
    'Foto ya guardada (Cloudinary). Permite reintentar sin volver a tomarla.';
COMMENT ON COLUMN public.orden_venta_surtido_captura_intento.numero_intento IS
    '1 la primera vez; sube en cada reintento desde la foto guardada.';
COMMENT ON COLUMN public.orden_venta_surtido_captura_intento.tiempos IS
    'Milisegundos por etapa (por ejemplo ia, cloudinary, bd, total) para medir donde se va el tiempo.';

ALTER TABLE public.orden_venta_surtido_captura_intento ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS orden_venta_surtido_captura_intento_select
    ON public.orden_venta_surtido_captura_intento;
CREATE POLICY orden_venta_surtido_captura_intento_select
    ON public.orden_venta_surtido_captura_intento
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
        PERFORM public.wms_sync_table_to_tenants('orden_venta_surtido_captura_intento');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
