-- REQ-439 / POL-453: con dos copias de la API durante un despliegue no se debe duplicar una OV
-- al reintentar un correo, ni perder una corrección de OT. Hoy ese estado vive en la memoria de
-- cada copia. Esta migración lo pasa a la base:
--   1. correo_pedido_ingreso.latido_at: señal de vida de la copia que procesa el ingreso.
--   2. public.correo_ot_trabajo: trabajos de corrección de OT (antes un Map en memoria).
-- correo_ot_trabajo queda con RLS activo, sin políticas y sin permisos para anon ni authenticated:
-- el api la usa por Prisma (conexión directa a Postgres), no por la API REST. latido_at hereda el
-- RLS y la política SELECT de correo_pedido_ingreso (migración 114); no es un dato sensible.
-- Es idempotente. Va antes del despliegue del código de la API (v2.13.53 o posterior).

-- 1. Señal de vida del ingreso de correo.
ALTER TABLE public.correo_pedido_ingreso
    ADD COLUMN IF NOT EXISTS latido_at timestamptz;

COMMENT ON COLUMN public.correo_pedido_ingreso.latido_at IS
    'REQ-439: última señal de vida de la copia de la API que procesa el ingreso (cada 15 s). Pasados 60 s sin actualizarse, el ingreso se considera abandonado y se puede reintentar. NULL en filas anteriores a la 125: se usa updated_at.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants(
            'correo_pedido_ingreso',
            'latido_at'
        );
    END IF;
END $$;

-- 2. Trabajos de corrección de OT desde el correo.
CREATE TABLE IF NOT EXISTS public.correo_ot_trabajo (
    id_trabajo uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    esquema text NOT NULL,
    id_orden_venta text NOT NULL,
    id_usuario text NOT NULL,
    request_id text NOT NULL,
    estado text NOT NULL DEFAULT 'procesando'
        CHECK (estado IN ('procesando', 'listo', 'error')),
    propuesta jsonb,
    error_http_status integer,
    error_cuerpo jsonb,
    latido_at timestamptz NOT NULL DEFAULT now(),
    creado_at timestamptz NOT NULL DEFAULT now(),
    terminado_at timestamptz,
    CONSTRAINT correo_ot_trabajo_terminado_coherente
        CHECK ((estado = 'procesando') = (terminado_at IS NULL))
);

-- Un solo trabajo en curso por (esquema, OV, usuario): cada corrida cuesta tokens de IA.
CREATE UNIQUE INDEX IF NOT EXISTS uq_correo_ot_trabajo_en_curso
    ON public.correo_ot_trabajo (esquema, id_orden_venta, id_usuario)
    WHERE estado = 'procesando';

CREATE INDEX IF NOT EXISTS idx_correo_ot_trabajo_terminado
    ON public.correo_ot_trabajo (terminado_at)
    WHERE terminado_at IS NOT NULL;

COMMENT ON TABLE public.correo_ot_trabajo IS
    'REQ-439: trabajo de corrección de OT desde el correo. Lo ve solo quien lo creó (esquema, OV, usuario). latido_at lo actualiza la copia que lo ejecuta; si se detiene, el trabajo pasa a error.';

ALTER TABLE public.correo_ot_trabajo ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.correo_ot_trabajo FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';
