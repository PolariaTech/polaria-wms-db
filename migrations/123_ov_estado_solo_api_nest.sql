-- POL-434 / score ≥9: el rol authenticated (clientes que usan Supabase directo)
-- no puede cambiar orden_venta.estado. Emitir, cancelar y avanzar estado van solo
-- por la API Nest (conexión postgres / service_role, que no envían rol authenticated).
-- El rol se lee de request.jwt.claims (JSON que envía PostgREST); si no se puede leer,
-- el error corta el UPDATE (falla cerrado). Idempotente.

CREATE OR REPLACE FUNCTION public.trg_orden_venta_emit_cancel_solo_servicio()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_role text;
BEGIN
  v_role := NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';

  IF v_role IS DISTINCT FROM 'authenticated' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.estado IS DISTINCT FROM NEW.estado THEN
    IF OLD.estado = 'por_confirmar' AND NEW.estado = 'confirmada' THEN
      RAISE EXCEPTION
        'emitir_solo_api_nest: Validar y enviar solo vía API Nest (POST emitir)';
    END IF;

    IF NEW.estado = 'cancelada' THEN
      RAISE EXCEPTION
        'cancelar_solo_api_nest: Cancelar solo vía API Nest (POST cancelar)';
    END IF;

    RAISE EXCEPTION
      'avance_estado_solo_api_nest: Cambiar estado solo vía API Nest (POST avanzar-estado)';
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.trg_orden_venta_emit_cancel_solo_servicio() IS
  'Bloquea cualquier cambio de estado OV con rol authenticated (emitir/cancelar/avance vía Nest).';

-- public (siempre).
DROP TRIGGER IF EXISTS trg_orden_venta_emit_cancel_solo_servicio ON public.orden_venta;
CREATE TRIGGER trg_orden_venta_emit_cancel_solo_servicio
  BEFORE UPDATE OF estado ON public.orden_venta
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_orden_venta_emit_cancel_solo_servicio();

-- Tenants: template_wms y cada emp_* que tenga la tabla orden_venta.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT n.nspname AS schema_name
    FROM pg_namespace n
    JOIN pg_class c ON c.relnamespace = n.oid
     AND c.relname = 'orden_venta'
     AND c.relkind = 'r'
    WHERE n.nspname = 'template_wms' OR n.nspname LIKE 'emp\_%'
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_orden_venta_emit_cancel_solo_servicio ON %I.orden_venta',
      r.schema_name
    );
    EXECUTE format(
      'CREATE TRIGGER trg_orden_venta_emit_cancel_solo_servicio
         BEFORE UPDATE OF estado ON %I.orden_venta
         FOR EACH ROW
         EXECUTE FUNCTION public.trg_orden_venta_emit_cancel_solo_servicio()',
      r.schema_name
    );
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
