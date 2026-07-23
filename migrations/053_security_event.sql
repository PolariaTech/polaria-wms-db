-- 053_security_event.sql — eventos de seguridad append-only (POL seguridad V2)
--
-- Registro server-side de intentos de auth, rate limits y accesos denegados.
-- Sin acceso PostgREST para authenticated/anon.

CREATE TABLE IF NOT EXISTS security_event (
    id_security_event uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type varchar(64) NOT NULL,
    subject text,
    ip_address inet,
    user_agent text,
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_security_event_type_created
    ON security_event (event_type, created_at DESC);

COMMENT ON TABLE security_event IS
    'Eventos de seguridad append-only. Solo backend (postgres/service role).';

CREATE OR REPLACE FUNCTION security_event_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'security_event es append-only; no UPDATE ni DELETE';
END;
$$;

DROP TRIGGER IF EXISTS trg_security_event_append_only ON security_event;
CREATE TRIGGER trg_security_event_append_only
    BEFORE UPDATE OR DELETE ON security_event
    FOR EACH ROW
    EXECUTE FUNCTION security_event_append_only();

ALTER TABLE security_event ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON security_event FROM authenticated, anon;
GRANT SELECT, INSERT ON security_event TO postgres;
