-- 059_cuenta_reporte_embed_multi.sql
-- Permite varios reportes por cuenta (deja de usar codigo_cuenta como PK)
-- y agrega el reporte «Consolidado por Cliente» para JBR.

ALTER TABLE cuenta_reporte_embed
    ADD COLUMN IF NOT EXISTS id_cuenta_reporte_embed uuid NOT NULL DEFAULT gen_random_uuid();

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.cuenta_reporte_embed'::regclass
          AND conname = 'cuenta_reporte_embed_pkey'
          AND contype = 'p'
    ) THEN
        ALTER TABLE cuenta_reporte_embed
            DROP CONSTRAINT cuenta_reporte_embed_pkey;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.cuenta_reporte_embed'::regclass
          AND conname = 'cuenta_reporte_embed_pkey'
    ) THEN
        ALTER TABLE cuenta_reporte_embed
            ADD CONSTRAINT cuenta_reporte_embed_pkey
            PRIMARY KEY (id_cuenta_reporte_embed);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_cuenta_reporte_embed_cuenta
    ON cuenta_reporte_embed (codigo_cuenta);

CREATE UNIQUE INDEX IF NOT EXISTS uq_cuenta_reporte_embed_cuenta_reporte
    ON cuenta_reporte_embed (codigo_cuenta, reporte_id)
    WHERE reporte_id IS NOT NULL;

COMMENT ON COLUMN cuenta_reporte_embed.id_cuenta_reporte_embed IS
    'Identificador del embed (varios reportes por cuenta).';

INSERT INTO cuenta_reporte_embed (
    codigo_cuenta,
    embed_url,
    esta_activo,
    descripcion,
    reporte_id
)
SELECT
    'JBR',
    'https://datastudio.google.com/embed/u/0/reporting/c588da2b-5525-4bb4-a257-483fb95acb47/page/RMmyF',
    true,
    'Consolidado por Cliente',
    'c588da2b-5525-4bb4-a257-483fb95acb47'::uuid
WHERE NOT EXISTS (
    SELECT 1
    FROM cuenta_reporte_embed
    WHERE codigo_cuenta = 'JBR'
      AND reporte_id = 'c588da2b-5525-4bb4-a257-483fb95acb47'::uuid
);

UPDATE cuenta_reporte_embed
SET
    embed_url = 'https://datastudio.google.com/embed/u/0/reporting/c588da2b-5525-4bb4-a257-483fb95acb47/page/RMmyF',
    descripcion = 'Consolidado por Cliente',
    esta_activo = true,
    updated_at = now()
WHERE codigo_cuenta = 'JBR'
  AND reporte_id = 'c588da2b-5525-4bb4-a257-483fb95acb47'::uuid;
