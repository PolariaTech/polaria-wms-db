-- 057_cuenta_reporte_embed_jbr.sql
-- Corrige el seed de 056: la cuenta real es JBR (023WA no existe).
-- Habilita el botón "Reportes" en inventario → bodega externa (TCI).

INSERT INTO cuenta_reporte_embed (codigo_cuenta, embed_url, esta_activo)
VALUES (
    'JBR',
    'https://datastudio.google.com/embed/reporting/8319190c-7a5c-48b2-9b1d-84701d583dd9/page/RMmyF',
    true
)
ON CONFLICT (codigo_cuenta) DO UPDATE
SET
    embed_url = EXCLUDED.embed_url,
    esta_activo = EXCLUDED.esta_activo,
    updated_at = now();
