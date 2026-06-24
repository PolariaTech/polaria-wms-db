-- Bootstrap mínimo de auth.users para validación local (no es migración de producción)
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE auth.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text,
    encrypted_password text,
    created_at timestamptz DEFAULT now()
);

-- Stub de auth.uid() para validación local (Supabase lo provee en producción).
-- validate-rls-multitenant.sql lo reemplaza para leer app.test_auth_uid o request.jwt.claim.sub.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        NULLIF(current_setting('app.test_auth_uid', true), ''),
        NULLIF(current_setting('request.jwt.claim.sub', true), '')
    )::uuid;
$$;
