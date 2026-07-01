-- 043 — Metadatos extendidos de catálogo en producto (admin panel / n8n).
--
-- Requerido por polaria-wms-web (CatalogoListView, productos-catalogo.service).

ALTER TABLE producto
    ADD COLUMN IF NOT EXISTS metadatos_catalogo jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN producto.metadatos_catalogo IS
    'Metadatos extendidos del catálogo (título, slug, precio, SEO, etc.).';
