-- 061_cuenta_reporte_embed_jbr_clase_calibre.sql
-- Agrega reportes Looker Studio «Consolidado por clase» y «Consolidado por Calibre» para JBR.

INSERT INTO cuenta_reporte_embed (
    codigo_cuenta,
    embed_url,
    esta_activo,
    descripcion,
    reporte_id
)
SELECT
    'JBR',
    'https://datastudio.google.com/s/glbL0j5pvdE',
    true,
    'Consolidado por clase',
    'f0ab9d64-204b-4645-a06c-07b35b37c364'::uuid
WHERE NOT EXISTS (
    SELECT 1
    FROM cuenta_reporte_embed
    WHERE codigo_cuenta = 'JBR'
      AND (
          embed_url = 'https://datastudio.google.com/s/glbL0j5pvdE'
          OR reporte_id = 'f0ab9d64-204b-4645-a06c-07b35b37c364'::uuid
          OR lower(btrim(descripcion)) = 'consolidado por clase'
      )
);

INSERT INTO cuenta_reporte_embed (
    codigo_cuenta,
    embed_url,
    esta_activo,
    descripcion,
    reporte_id
)
SELECT
    'JBR',
    'https://datastudio.google.com/s/vXFEsYBr_iw',
    true,
    'Consolidado por Calibre',
    '408d4759-81bc-4f5d-875f-bb2854df6c2c'::uuid
WHERE NOT EXISTS (
    SELECT 1
    FROM cuenta_reporte_embed
    WHERE codigo_cuenta = 'JBR'
      AND (
          embed_url = 'https://datastudio.google.com/s/vXFEsYBr_iw'
          OR reporte_id = '408d4759-81bc-4f5d-875f-bb2854df6c2c'::uuid
          OR lower(btrim(descripcion)) = 'consolidado por calibre'
      )
);

-- Backfill si ya existían filas sin reporte_id
UPDATE cuenta_reporte_embed
SET
    reporte_id = 'f0ab9d64-204b-4645-a06c-07b35b37c364'::uuid,
    updated_at = now()
WHERE codigo_cuenta = 'JBR'
  AND reporte_id IS NULL
  AND (
      embed_url = 'https://datastudio.google.com/s/glbL0j5pvdE'
      OR lower(btrim(descripcion)) = 'consolidado por clase'
  );

UPDATE cuenta_reporte_embed
SET
    reporte_id = '408d4759-81bc-4f5d-875f-bb2854df6c2c'::uuid,
    updated_at = now()
WHERE codigo_cuenta = 'JBR'
  AND reporte_id IS NULL
  AND (
      embed_url = 'https://datastudio.google.com/s/vXFEsYBr_iw'
      OR lower(btrim(descripcion)) = 'consolidado por calibre'
  );
