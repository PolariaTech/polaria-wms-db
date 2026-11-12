-- POL-418: varias frases por producto en comprador_producto_alias.
-- Un producto puede tener varias frases por comprador, comparadas ya normalizadas
-- (minusculas, sin tildes). El precio especial sigue en esta tabla, con un solo
-- precio por producto y comprador. La tabla esta vacia en todos los esquemas.

CREATE OR REPLACE FUNCTION public.wms_norm_alias(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $function$
  SELECT trim(both ' ' FROM regexp_replace(
    lower(translate(
      replace(replace(coalesce(p_texto, ''), '¥', 'n'), E'\uFFFD', 'n'),
      'áéíóúüñÁÉÍÓÚÜÑ*àèìòùâêîôûäëïöçÀÈÌÒÙÂÊÎÔÛÄËÏÖÇ',
      'aeiouunAEIOUUN aeiouaeiouaeiocAEIOUAEIOUAEIOC'
    )),
    '[^a-z0-9]+',
    ' ',
    'g'
  ));
$function$;

COMMENT ON FUNCTION public.wms_norm_alias(text) IS
    'Normaliza alias de comprador_producto_alias. Debe dar el mismo resultado que normalizeForMatch de polaria-wms-web (utils/match/find-closest-producto-catalogo.ts): minúsculas, sin tildes, solo letras y números separados por un espacio.';

DO $$
DECLARE
    v_schema text;
    v_constraint record;
BEGIN
    FOR v_schema IN
        SELECT n.nspname
        FROM pg_namespace n
        WHERE n.nspname = 'public'
           OR n.nspname = 'template_wms'
           OR n.nspname LIKE 'emp_%'
        ORDER BY (n.nspname <> 'public'), n.nspname
    LOOP
        IF to_regclass(format('%I.comprador_producto_alias', v_schema)) IS NULL THEN
            CONTINUE;
        END IF;

        EXECUTE format(
            'ALTER TABLE %I.comprador_producto_alias
               ADD COLUMN IF NOT EXISTS alias_normalizado text
               GENERATED ALWAYS AS (public.wms_norm_alias(alias)) STORED',
            v_schema
        );

        FOR v_constraint IN
            SELECT c.conname
            FROM pg_constraint c
            WHERE c.conrelid = format('%I.comprador_producto_alias', v_schema)::regclass
              AND c.contype = 'u'
              AND (
                  SELECT array_agg(a.attname::text ORDER BY a.attname)
                  FROM unnest(c.conkey) AS cols(attnum)
                  JOIN pg_attribute a
                    ON a.attrelid = c.conrelid
                   AND a.attnum = cols.attnum
              ) = ARRAY['id_comprador', 'id_producto']::text[]
        LOOP
            EXECUTE format(
                'ALTER TABLE %I.comprador_producto_alias DROP CONSTRAINT %I',
                v_schema,
                v_constraint.conname
            );
            RAISE NOTICE 'POL-418: drop % en %', v_constraint.conname, v_schema;
        END LOOP;

        EXECUTE format(
            'CREATE UNIQUE INDEX IF NOT EXISTS uq_comprador_producto_alias_frase
               ON %I.comprador_producto_alias (codigo_cuenta, id_comprador, alias_normalizado)
               WHERE alias_normalizado <> ''''',
            v_schema
        );

        EXECUTE format(
            'CREATE UNIQUE INDEX IF NOT EXISTS uq_comprador_producto_alias_precio
               ON %I.comprador_producto_alias (codigo_cuenta, id_comprador, id_producto)
               WHERE precio IS NOT NULL',
            v_schema
        );

        EXECUTE format(
            'CREATE UNIQUE INDEX IF NOT EXISTS uq_comprador_producto_alias_sin_frase
               ON %I.comprador_producto_alias (codigo_cuenta, id_comprador, id_producto)
               WHERE alias_normalizado = ''''',
            v_schema
        );

        EXECUTE format(
            'CREATE INDEX IF NOT EXISTS idx_comprador_producto_alias_cuenta_comprador
               ON %I.comprador_producto_alias (codigo_cuenta, id_comprador)',
            v_schema
        );
    END LOOP;
END $$;

COMMENT ON COLUMN public.comprador_producto_alias.alias_normalizado IS
    'Generada con wms_norm_alias(alias). Única por (codigo_cuenta, id_comprador) cuando no está vacía: un producto puede tener varias frases por comprador. POL-418.';

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
