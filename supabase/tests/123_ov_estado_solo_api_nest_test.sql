-- Prueba de la migración 123: el rol authenticated no cambia orden_venta.estado
-- (ni en public ni en un tenant emp_*); el rol de servicio (API Nest, postgres) sí.
-- Simula el JWT como lo envía PostgREST (request.jwt.claims) y el rol con SET ROLE.
-- Todo corre en BEGIN/ROLLBACK. Requiere las tablas mínimas de scripts/sql-smoke.sh.

BEGIN;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.orden_venta TO authenticated;

GRANT USAGE ON SCHEMA emp_smoke TO authenticated;
GRANT SELECT, INSERT, UPDATE ON emp_smoke.orden_venta TO authenticated;

INSERT INTO public.orden_venta (id_orden_venta, estado, notas)
VALUES ('11111111-1111-1111-1111-111111111111', 'por_confirmar', 'inicial');

INSERT INTO emp_smoke.orden_venta (id_orden_venta, estado, notas)
VALUES ('22222222-2222-2222-2222-222222222222', 'por_confirmar', 'inicial');

DO $$
DECLARE
  v_bloqueado_public boolean := false;
  v_bloqueado_tenant boolean := false;
  v_msg text;
  v_estado text;
  v_notas text;
BEGIN
  -- Sesión como PostgREST con JWT de rol authenticated.
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  SET LOCAL ROLE authenticated;

  -- 1) authenticated puede cambiar una columna que el trigger no mira.
  UPDATE public.orden_venta SET notas = 'editada'
  WHERE id_orden_venta = '11111111-1111-1111-1111-111111111111';

  -- 2) authenticated no puede cambiar estado en public.
  BEGIN
    UPDATE public.orden_venta SET estado = 'confirmada'
    WHERE id_orden_venta = '11111111-1111-1111-1111-111111111111';
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
    v_bloqueado_public := v_msg LIKE '%solo_api_nest%';
  END;

  -- 3) authenticated no puede cambiar estado en un tenant emp_*.
  BEGIN
    UPDATE emp_smoke.orden_venta SET estado = 'cancelada'
    WHERE id_orden_venta = '22222222-2222-2222-2222-222222222222';
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
    v_bloqueado_tenant := v_msg LIKE '%solo_api_nest%';
  END;

  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);

  IF NOT v_bloqueado_public THEN
    RAISE EXCEPTION 'FALLA 1: authenticated pudo cambiar estado en public.orden_venta';
  END IF;

  IF NOT v_bloqueado_tenant THEN
    RAISE EXCEPTION 'FALLA 2: authenticated pudo cambiar estado en emp_smoke.orden_venta';
  END IF;

  -- 4) El rol de servicio (API Nest, sin JWT) sí cambia estado; notas quedó editada.
  UPDATE public.orden_venta SET estado = 'confirmada'
  WHERE id_orden_venta = '11111111-1111-1111-1111-111111111111';

  SELECT estado, notas INTO v_estado, v_notas
  FROM public.orden_venta WHERE id_orden_venta = '11111111-1111-1111-1111-111111111111';

  IF v_estado IS DISTINCT FROM 'confirmada' THEN
    RAISE EXCEPTION 'FALLA 3: el rol de servicio no pudo cambiar estado (quedó %)', v_estado;
  END IF;

  IF v_notas IS DISTINCT FROM 'editada' THEN
    RAISE EXCEPTION 'FALLA 4: la edición de notas por authenticated no se guardó (quedó %)', v_notas;
  END IF;

  RAISE NOTICE 'OK: 123_ov_estado_solo_api_nest, 4 afirmaciones';
END $$;

ROLLBACK;
