-- 058_cuenta_reporte_embed_reporte_id_descripcion.sql
-- Formaliza `descripcion` (añadida manualmente en remoto) y agrega `reporte_id`.

ALTER TABLE cuenta_reporte_embed
    ADD COLUMN IF NOT EXISTS descripcion text;

ALTER TABLE cuenta_reporte_embed
    ADD COLUMN IF NOT EXISTS reporte_id uuid;

COMMENT ON COLUMN cuenta_reporte_embed.descripcion IS
    'Etiqueta / descripción legible del reporte embebido.';

COMMENT ON COLUMN cuenta_reporte_embed.reporte_id IS
    'ID del reporte (UUID Looker Studio / Data Studio), independiente de embed_url.';

-- Backfill JBR (UUID del reporting Looker Studio histórico)
UPDATE cuenta_reporte_embed
SET
    reporte_id = '8319190c-7a5c-48b2-9b1d-84701d583dd9'::uuid,
    updated_at = now()
WHERE codigo_cuenta = 'JBR'
  AND reporte_id IS NULL;
