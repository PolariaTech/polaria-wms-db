-- Extensiones requeridas por el modelo de datos
-- uuid_generate_v4() para PKs automáticos
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- citext: texto case-insensitive para correos (evita duplicados por capitalización)
CREATE EXTENSION IF NOT EXISTS "citext";
