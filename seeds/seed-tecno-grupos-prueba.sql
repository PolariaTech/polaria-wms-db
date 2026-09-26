-- Seed TEMPORAL DE PRUEBA — solo cuenta Tecno (49M04).
-- Catálogo de grupos + asignación aleatoria en comprador.grupo.
-- Ejecutar DESPUÉS de 086_tmp_grupo_perteneciente.sql
-- NO copiar estos nombres a código de aplicación.

DO $$
DECLARE
  v_codigo_cuenta constant text := '49M04';
  v_schema text;
  v_grupos text[] := ARRAY['Hoten 1', 'Hoten 2', 'Hoten 3'];
  v_nombre text;
  v_orden integer;
BEGIN
  SELECT e.schema_name
  INTO v_schema
  FROM public.cuenta c
  JOIN public.empresa e ON e.codigo_empresa = c.codigo_empresa
  WHERE c.codigo_cuenta = v_codigo_cuenta;

  IF v_schema IS NULL THEN
    RAISE NOTICE 'Cuenta % no encontrada; seed de grupos omitido.', v_codigo_cuenta;
    RETURN;
  END IF;

  FOR v_orden IN 1..array_length(v_grupos, 1) LOOP
    v_nombre := v_grupos[v_orden];
    INSERT INTO public.tmp_grupo_perteneciente (codigo_cuenta, nombre, orden)
    VALUES (v_codigo_cuenta, v_nombre, v_orden)
    ON CONFLICT (codigo_cuenta, nombre) DO UPDATE
      SET orden = EXCLUDED.orden,
          updated_at = now();
  END LOOP;

  EXECUTE format(
    'UPDATE %I.comprador AS c
     SET grupo = (
       SELECT g.nombre
       FROM public.tmp_grupo_perteneciente g
       WHERE g.codigo_cuenta = %L
       ORDER BY random()
       LIMIT 1
     )
     WHERE c.codigo_cuenta = %L
       AND (c.grupo IS NULL OR btrim(c.grupo) = '''')',
    v_schema,
    v_codigo_cuenta,
    v_codigo_cuenta
  );

  RAISE NOTICE 'Seed grupos Tecno aplicado en schema %.', v_schema;
END $$;
