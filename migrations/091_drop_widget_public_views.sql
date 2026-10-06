-- El widget vive en mateo_support. Las vistas public.widget_* (064/090)
-- sombreaban las tablas cuando search_path empieza en public y se
-- desactualizan al agregar columnas (url_imagen).

DROP VIEW IF EXISTS public.widget_mensaje;
DROP VIEW IF EXISTS public.widget_conversacion;

NOTIFY pgrst, 'reload schema';
