-- SLA / alertas OV por cuenta + marca de entrada al estado actual.

ALTER TABLE public.cuenta
    ADD COLUMN IF NOT EXISTS ov_sla_minutos integer NOT NULL DEFAULT 60,
    ADD COLUMN IF NOT EXISTS ov_alerta_minutos integer NOT NULL DEFAULT 45;

COMMENT ON COLUMN public.cuenta.ov_sla_minutos IS
    'Minutos máximos en la etapa actual antes de marcar la OV como atrasada (SLA).';
COMMENT ON COLUMN public.cuenta.ov_alerta_minutos IS
    'Minutos en la etapa a partir de los cuales la OV entra en riesgo (alerta), antes del SLA.';

ALTER TABLE public.orden_venta
    ADD COLUMN IF NOT EXISTS estado_desde timestamptz NOT NULL DEFAULT now();

COMMENT ON COLUMN public.orden_venta.estado_desde IS
    'Instante en que la OV entró al estado actual (para SLA/alertas).';

UPDATE public.orden_venta
SET estado_desde = COALESCE(updated_at, created_at, now());

CREATE OR REPLACE FUNCTION public.trg_orden_venta_estado_desde()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.estado IS DISTINCT FROM OLD.estado THEN
    NEW.estado_desde := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orden_venta_estado_desde ON public.orden_venta;
CREATE TRIGGER trg_orden_venta_estado_desde
    BEFORE UPDATE OF estado ON public.orden_venta
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_orden_venta_estado_desde();

DO $$
DECLARE
    r record;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants('cuenta', 'ov_sla_minutos');
        PERFORM public.wms_sync_column_to_tenants('cuenta', 'ov_alerta_minutos');
        PERFORM public.wms_sync_column_to_tenants('orden_venta', 'estado_desde');
    END IF;

    -- Trigger en cada tenant emp_* / template
    FOR r IN
        SELECT nspname AS schema_name
        FROM pg_namespace
        WHERE nspname = 'template_wms'
           OR nspname LIKE 'emp_%'
    LOOP
        EXECUTE format(
            'CREATE OR REPLACE FUNCTION %I.trg_orden_venta_estado_desde()
             RETURNS trigger LANGUAGE plpgsql AS $f$
             BEGIN
               IF TG_OP = ''UPDATE'' AND NEW.estado IS DISTINCT FROM OLD.estado THEN
                 NEW.estado_desde := now();
               END IF;
               RETURN NEW;
             END;
             $f$',
            r.schema_name
        );
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_orden_venta_estado_desde ON %I.orden_venta',
            r.schema_name
        );
        EXECUTE format(
            'CREATE TRIGGER trg_orden_venta_estado_desde
               BEFORE UPDATE OF estado ON %I.orden_venta
               FOR EACH ROW
               EXECUTE FUNCTION %I.trg_orden_venta_estado_desde()',
            r.schema_name,
            r.schema_name
        );
        EXECUTE format(
            'UPDATE %I.orden_venta
             SET estado_desde = COALESCE(updated_at, created_at, now())
             WHERE true',
            r.schema_name
        );
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
