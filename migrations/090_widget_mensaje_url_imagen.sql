-- POL-291 / widget images: URL Cloudinary en columna propia (no embebida en contenido).
-- contenido pasa a ser solo texto / pie de imagen; url_imagen guarda la secure_url.

ALTER TABLE mateo_support.widget_mensaje
    ADD COLUMN IF NOT EXISTS url_imagen text;

COMMENT ON COLUMN mateo_support.widget_mensaje.url_imagen IS
    'URL Cloudinary (secure_url) cuando tipo = image. NULL en mensajes de texto.';

COMMENT ON COLUMN mateo_support.widget_mensaje.contenido IS
    'Texto del mensaje; en tipo image es el pie (caption), no la URL.';

-- Backfill: filas image con URL (+ caption opcional) embebidos en contenido.
-- Separador del widget: E'\n<!--mateo-caption-->\n' (POL-245).
UPDATE mateo_support.widget_mensaje
SET
    url_imagen = CASE
        WHEN position(E'\n<!--mateo-caption-->\n' IN contenido) > 0
            THEN split_part(contenido, E'\n<!--mateo-caption-->\n', 1)
        ELSE contenido
    END,
    contenido = CASE
        WHEN position(E'\n<!--mateo-caption-->\n' IN contenido) > 0
            THEN split_part(contenido, E'\n<!--mateo-caption-->\n', 2)
        ELSE ''
    END
WHERE tipo = 'image'
  AND url_imagen IS NULL
  AND contenido IS NOT NULL
  AND contenido <> '';

-- Dedupe de reintentos: incluir url_imagen para no colisionar dos imágenes
-- distintas con el mismo pie y el mismo created_at.
DROP INDEX IF EXISTS mateo_support.uq_widget_mensaje_reintento;

CREATE UNIQUE INDEX uq_widget_mensaje_reintento
    ON mateo_support.widget_mensaje (
        id_conversacion,
        rol,
        tipo,
        es_error,
        created_at,
        md5(contenido),
        md5(coalesce(url_imagen, ''))
    );

-- Vista public.* = SELECT * → recargar para exponer la nueva columna.
CREATE OR REPLACE VIEW public.widget_mensaje AS
SELECT *
FROM mateo_support.widget_mensaje;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.widget_mensaje TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
