-- POL-418: siembra de equivalencias en comprador_producto_alias a partir del
-- historial de orden_venta_linea.match_producto.
--
-- Que hace: agrupa las lineas de OV confirmadas por (comprador, frase normalizada),
-- elige el producto ganador y guarda el textoCliente mas frecuente. No guarda precio.
--
-- Modos:
--   * Mismo esquema y misma cuenta: usa id_comprador e id_producto tal cual.
--   * Espejo (esquemas distintos): el comprador destino se busca por
--     wms_norm_alias(nombre) con coincidencia unica; el producto destino, por sku
--     igual. 0 o mas de 1 coincidencia se descarta (sin_comprador / sin_producto).
--     Si dos compradores de origen caen en el mismo (id_comprador_destino, clave),
--     todos esos pares salen como conflicto_destino y no se insertan.
--
-- Requiere la migracion 120 (wms_norm_alias, alias_normalizado e indices nuevos).
-- Pegar el archivo entero en el editor SQL de Supabase. Termina en ROLLBACK:
-- no guarda nada. Cambiar el ROLLBACK final a COMMIT solo si el reporte coincide
-- con el del modo de prueba. En el modo de prueba, insertado_filas = insertado.
--
-- Conceptos del reporte: origen, descartado_umbral, sin_comprador, sin_producto,
-- descartado_servicio, conflicto_destino, ya_existia, insertado, insertado_filas,
-- control_naranja_a_aguacate, control_servicio_insertado.
--
-- Parametros editables: la tabla siembra_parametros.

BEGIN;

CREATE TEMP TABLE siembra_parametros ON COMMIT DROP AS SELECT
  'emp_jbr_cygnus_y9ihz'::text AS esquema_origen, '023WA'::text AS cuenta_origen,
  'emp_demo_1xz77'::text      AS esquema_destino, '1YW43'::text AS cuenta_destino,
  2::int AS min_lineas, 0.80::numeric AS min_mayoria;

DO $$
DECLARE
    v_esquema_origen text;
    v_cuenta_origen text;
    v_esquema_destino text;
    v_cuenta_destino text;
    v_min_lineas int;
    v_min_mayoria numeric;
    v_espejo boolean;
    v_espejo_sql text;
    v_filas int;
BEGIN
    SELECT
        p.esquema_origen,
        p.cuenta_origen,
        p.esquema_destino,
        p.cuenta_destino,
        p.min_lineas,
        p.min_mayoria
      INTO
        v_esquema_origen,
        v_cuenta_origen,
        v_esquema_destino,
        v_cuenta_destino,
        v_min_lineas,
        v_min_mayoria
    FROM siembra_parametros p;

    IF to_regprocedure('public.wms_norm_alias(text)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.wms_norm_alias(text); se requiere la migracion 120';
    END IF;

    IF to_regclass(format('%I.orden_venta', v_esquema_origen)) IS NULL
       OR to_regclass(format('%I.orden_venta_linea', v_esquema_origen)) IS NULL THEN
        RAISE EXCEPTION 'No existe orden_venta en el esquema origen %', v_esquema_origen;
    END IF;

    IF to_regclass(format('%I.comprador_producto_alias', v_esquema_destino)) IS NULL THEN
        RAISE EXCEPTION
            'Falta %.comprador_producto_alias (se requiere la migracion 120)',
            v_esquema_destino;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = v_esquema_destino
          AND c.relname = 'comprador_producto_alias'
          AND a.attname = 'alias_normalizado'
          AND NOT a.attisdropped
    ) THEN
        RAISE EXCEPTION
            'Falta alias_normalizado en %.comprador_producto_alias (se requiere la migracion 120)',
            v_esquema_destino;
    END IF;

    v_espejo := NOT (
        v_esquema_origen = v_esquema_destino
        AND v_cuenta_origen = v_cuenta_destino
    );
    v_espejo_sql := CASE WHEN v_espejo THEN 'true' ELSE 'false' END;

    CREATE TEMP TABLE siembra_reporte (
        concepto text,
        pares int
    ) ON COMMIT DROP;

    EXECUTE format(
        $q$
        CREATE TEMP TABLE siembra_candidatos ON COMMIT DROP AS
        WITH lineas AS (
            SELECT
                o.id_comprador AS id_comprador_origen,
                public.wms_norm_alias(l.match_producto->>'textoCliente') AS clave,
                (l.match_producto->'elegidoUsuario'->>'idProducto')::uuid AS id_producto_origen,
                left(btrim(l.match_producto->>'textoCliente'), 255) AS texto_cliente
            FROM %1$I.orden_venta_linea l
            JOIN %1$I.orden_venta o USING (id_orden_venta)
            WHERE o.codigo_cuenta = %3$L
              AND o.estado = 'confirmada'
              AND o.id_comprador IS NOT NULL
              AND nullif(l.match_producto->'elegidoUsuario'->>'idProducto', '') IS NOT NULL
              AND (l.match_producto->'elegidoUsuario'->>'idProducto')
                    ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              AND public.wms_norm_alias(l.match_producto->>'textoCliente') <> ''
        ),
        total_par AS (
            SELECT id_comprador_origen, clave, count(*)::int AS total
            FROM lineas
            GROUP BY id_comprador_origen, clave
        ),
        conteo_producto AS (
            SELECT
                id_comprador_origen,
                clave,
                id_producto_origen,
                count(*)::int AS lineas_producto
            FROM lineas
            GROUP BY id_comprador_origen, clave, id_producto_origen
        ),
        ganador AS (
            SELECT DISTINCT ON (id_comprador_origen, clave)
                id_comprador_origen,
                clave,
                id_producto_origen,
                lineas_producto AS top
            FROM conteo_producto
            ORDER BY id_comprador_origen, clave, lineas_producto DESC, id_producto_origen
        ),
        conteo_texto AS (
            SELECT
                id_comprador_origen,
                clave,
                texto_cliente,
                count(*)::int AS lineas_texto
            FROM lineas
            GROUP BY id_comprador_origen, clave, texto_cliente
        ),
        alias_elegido AS (
            SELECT DISTINCT ON (id_comprador_origen, clave)
                id_comprador_origen,
                clave,
                texto_cliente AS alias
            FROM conteo_texto
            ORDER BY id_comprador_origen, clave, lineas_texto DESC, texto_cliente
        ),
        pares AS (
            SELECT
                g.id_comprador_origen,
                g.clave,
                g.id_producto_origen,
                g.top,
                t.total,
                a.alias
            FROM ganador g
            JOIN total_par t
              USING (id_comprador_origen, clave)
            JOIN alias_elegido a
              USING (id_comprador_origen, clave)
        ),
        mapeados AS (
            SELECT
                pares.clave,
                pares.top,
                pares.total,
                pares.alias,
                CASE
                    WHEN %7$s THEN comprador_dest.id_comprador
                    ELSE pares.id_comprador_origen
                END AS id_comprador_destino,
                CASE
                    WHEN %7$s THEN producto_dest.id_producto
                    ELSE pares.id_producto_origen
                END AS id_producto_destino,
                CASE
                    WHEN %7$s THEN producto_dest.categoria
                    ELSE po.categoria::text
                END AS categoria,
                CASE
                    WHEN %7$s THEN producto_dest.descripcion
                    ELSE po.descripcion
                END AS descripcion
            FROM pares
            LEFT JOIN %1$I.comprador co
              ON co.id_comprador = pares.id_comprador_origen
            LEFT JOIN %1$I.producto po
              ON po.id_producto = pares.id_producto_origen
            LEFT JOIN (
                SELECT
                    public.wms_norm_alias(c.nombre) AS nombre_norm,
                    min(c.id_comprador) AS id_comprador
                FROM %2$I.comprador c
                WHERE c.codigo_cuenta = %4$L
                GROUP BY public.wms_norm_alias(c.nombre)
                HAVING count(*) = 1
            ) comprador_dest
              ON comprador_dest.nombre_norm = public.wms_norm_alias(co.nombre)
            LEFT JOIN (
                SELECT
                    p.sku,
                    min(p.id_producto) AS id_producto,
                    min(p.descripcion) AS descripcion,
                    min(p.categoria::text) AS categoria
                FROM %2$I.producto p
                WHERE p.codigo_cuenta = %4$L
                GROUP BY p.sku
                HAVING count(*) = 1
            ) producto_dest
              ON producto_dest.sku = po.sku
        ),
        pre_clasificados AS (
            SELECT
                m.clave,
                m.top,
                m.total,
                m.alias,
                m.id_comprador_destino,
                m.id_producto_destino,
                m.categoria::text AS categoria,
                m.descripcion,
                CASE
                    WHEN m.total < %5$s
                      OR (m.top::numeric / m.total) < %6$s
                        THEN 'descartado_umbral'
                    WHEN %7$s AND m.id_comprador_destino IS NULL
                        THEN 'sin_comprador'
                    WHEN %7$s AND m.id_producto_destino IS NULL
                        THEN 'sin_producto'
                    WHEN m.categoria::text IS DISTINCT FROM 'venta'
                        THEN 'descartado_servicio'
                END AS clasificacion_previa
            FROM mapeados m
        )
        SELECT
            p.clave,
            p.top,
            p.total,
            p.alias,
            p.id_comprador_destino,
            p.id_producto_destino,
            p.categoria,
            p.descripcion,
            CASE
                WHEN p.clasificacion_previa IS NOT NULL
                    THEN p.clasificacion_previa
                WHEN count(*) FILTER (WHERE p.clasificacion_previa IS NULL)
                       OVER (PARTITION BY p.id_comprador_destino, p.clave) > 1
                    THEN 'conflicto_destino'
                WHEN EXISTS (
                    SELECT 1
                    FROM %2$I.comprador_producto_alias ya
                    WHERE ya.codigo_cuenta = %4$L
                      AND ya.id_comprador = p.id_comprador_destino
                      AND ya.alias_normalizado = p.clave
                )
                    THEN 'ya_existia'
                ELSE 'insertado'
            END AS clasificacion
        FROM pre_clasificados p
        $q$,
        v_esquema_origen,
        v_esquema_destino,
        v_cuenta_origen,
        v_cuenta_destino,
        v_min_lineas,
        v_min_mayoria,
        v_espejo_sql
    );

    EXECUTE format(
        $q$
        INSERT INTO %I.comprador_producto_alias (
            codigo_cuenta, id_comprador, id_producto, alias
        )
        SELECT %L, id_comprador_destino, id_producto_destino, alias
        FROM siembra_candidatos
        WHERE clasificacion = 'insertado'
          AND id_comprador_destino IS NOT NULL
          AND id_producto_destino IS NOT NULL
        ON CONFLICT (codigo_cuenta, id_comprador, alias_normalizado)
            WHERE alias_normalizado <> ''
        DO NOTHING
        $q$,
        v_esquema_destino,
        v_cuenta_destino
    );
    GET DIAGNOSTICS v_filas = ROW_COUNT;

    INSERT INTO siembra_reporte (concepto, pares)
    VALUES
        ('origen', (SELECT count(*)::int FROM siembra_candidatos)),
        ('descartado_umbral', (
            SELECT count(*)::int FROM siembra_candidatos
            WHERE clasificacion = 'descartado_umbral'
        )),
        ('sin_comprador', (
            SELECT count(*)::int FROM siembra_candidatos
            WHERE clasificacion = 'sin_comprador'
        )),
        ('sin_producto', (
            SELECT count(*)::int FROM siembra_candidatos
            WHERE clasificacion = 'sin_producto'
        )),
        ('descartado_servicio', (
            SELECT count(*)::int FROM siembra_candidatos
            WHERE clasificacion = 'descartado_servicio'
        )),
        ('conflicto_destino', (
            SELECT count(*)::int FROM siembra_candidatos
            WHERE clasificacion = 'conflicto_destino'
        )),
        ('ya_existia', (
            SELECT count(*)::int FROM siembra_candidatos
            WHERE clasificacion = 'ya_existia'
        )),
        ('insertado', (
            SELECT count(*)::int FROM siembra_candidatos
            WHERE clasificacion = 'insertado'
        )),
        ('insertado_filas', v_filas),
        ('control_naranja_a_aguacate', (
            SELECT count(*)::int FROM siembra_candidatos
            WHERE clasificacion = 'insertado'
              AND clave LIKE '%naranja%'
              AND descripcion ILIKE '%AGUACATE%'
        )),
        ('control_servicio_insertado', (
            SELECT count(*)::int FROM siembra_candidatos
            WHERE clasificacion = 'insertado'
              AND categoria IS DISTINCT FROM 'venta'
        ));
END $$;

SELECT * FROM siembra_reporte ORDER BY 1;
ROLLBACK;  -- Cambiar a COMMIT solo si el reporte coincide con el del modo de prueba.
