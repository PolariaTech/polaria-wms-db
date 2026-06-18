CREATE TABLE usuario (
    id_usuario uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_auth uuid NOT NULL UNIQUE,
    id_rol wms_rol NOT NULL,
    codigo_empresa varchar(32),
    codigo_cuenta varchar(32),
    id_creador uuid,
    nombre varchar(255) NOT NULL,
    username citext NOT NULL,
    correo citext NOT NULL,
    esta_activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_usuario_correo UNIQUE (correo),
    CONSTRAINT uq_usuario_username UNIQUE (username),

    CONSTRAINT fk_usuario_rol
        FOREIGN KEY (id_rol)
        REFERENCES rol (id_rol),

    CONSTRAINT fk_usuario_empresa
        FOREIGN KEY (codigo_empresa)
        REFERENCES empresa (codigo_empresa),

    CONSTRAINT chk_usuario_contexto CHECK (
        (
            id_rol = 'configurador'
            AND codigo_empresa IS NULL
            AND codigo_cuenta IS NULL
        )
        OR (
            id_rol <> 'configurador'
            AND codigo_empresa IS NOT NULL
        )
    )
);

CREATE INDEX ix_usuario_id_auth ON usuario (id_auth);
CREATE INDEX ix_usuario_empresa ON usuario (codigo_empresa);
CREATE INDEX ix_usuario_cuenta ON usuario (codigo_cuenta);
CREATE INDEX ix_usuario_rol ON usuario (id_rol);
CREATE INDEX ix_usuario_login_username ON usuario (username) WHERE esta_activo;
CREATE INDEX ix_usuario_login_correo ON usuario (correo) WHERE esta_activo;

ALTER TABLE usuario
    ADD CONSTRAINT fk_usuario_creador
    FOREIGN KEY (id_creador)
    REFERENCES usuario (id_usuario);

ALTER TABLE usuario
    ADD CONSTRAINT fk_usuario_auth
    FOREIGN KEY (id_auth)
    REFERENCES auth.users (id)
    ON DELETE CASCADE;

CREATE TRIGGER trg_usuario_updated_at
    BEFORE UPDATE ON usuario
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE usuario ENABLE ROW LEVEL SECURITY;

CREATE POLICY usuario_select_own
    ON usuario
    FOR SELECT
    TO authenticated
    USING (id_auth = auth.uid());

GRANT SELECT ON usuario TO authenticated;

CREATE POLICY empresa_select_scope
    ON empresa
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM usuario u
            WHERE u.id_auth = auth.uid()
              AND u.esta_activo
              AND (
                  u.id_rol = 'configurador'
                  OR u.codigo_empresa = empresa.codigo_empresa
              )
        )
    );

GRANT SELECT ON empresa TO authenticated;
