-- =====================================================================
-- 001_extensions.sql
-- Extensiones base de PostgreSQL / Supabase requeridas por el modelo.
-- Modelo: Bodega de Frío (3NF) — bloque de autenticación / login.
-- =====================================================================

-- gen_random_uuid() para las PK uuid (usuario, etc.).
create extension if not exists "pgcrypto";

-- citext: correo case-insensitive (login por correo o identificador).
create extension if not exists "citext";
