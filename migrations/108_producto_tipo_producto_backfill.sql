-- 108 — Alinear `metadatos_catalogo.tipo_producto` en todos los schemas.
--
-- 1 = producto (mercancía vendible), 3 = servicio.
-- No sobrescribe valores ya presentes (p. ej. servicios = 3).
-- Solo completa filas sin la clave o con valor vacío/null.

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT nspname AS schema_name
        FROM pg_namespace
        WHERE nspname IN ('public', 'template_wms')
           OR nspname LIKE 'emp_%'
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = r.schema_name
              AND table_name = 'producto'
        ) THEN
            CONTINUE;
        END IF;

        EXECUTE format(
            'ALTER TABLE %I.producto
               ADD COLUMN IF NOT EXISTS metadatos_catalogo jsonb NOT NULL DEFAULT ''{}''::jsonb',
            r.schema_name
        );

        EXECUTE format(
            $q$
            UPDATE %I.producto
            SET metadatos_catalogo =
                COALESCE(metadatos_catalogo, '{}'::jsonb)
                || jsonb_build_object('tipo_producto', 1)
            WHERE metadatos_catalogo IS NULL
               OR NOT (metadatos_catalogo ? 'tipo_producto')
               OR nullif(btrim(metadatos_catalogo->>'tipo_producto'), '') IS NULL
            $q$,
            r.schema_name
        );
    END LOOP;
END $$;
