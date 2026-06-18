CREATE TABLE cuenta (
    codigo_cuenta varchar(32) PRIMARY KEY,
    codigo_empresa varchar(32) NOT NULL,
    nombre_comercial varchar(255) NOT NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    id_creador uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_cuenta_empresa
        FOREIGN KEY (codigo_empresa)
        REFERENCES empresa (codigo_empresa),

    CONSTRAINT fk_cuenta_creador
        FOREIGN KEY (id_creador)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_cuenta_empresa ON cuenta (codigo_empresa);
CREATE INDEX ix_cuenta_activa
    ON cuenta (esta_activa)
    WHERE esta_activa;

CREATE TRIGGER trg_cuenta_updated_at
    BEFORE UPDATE ON cuenta
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- FK diferida: usuario.codigo_cuenta requiere que cuenta exista
ALTER TABLE usuario
    ADD CONSTRAINT fk_usuario_cuenta
    FOREIGN KEY (codigo_cuenta)
    REFERENCES cuenta (codigo_cuenta);

-- FK diferida: empresa.id_creador requiere que usuario exista
ALTER TABLE empresa
    ADD CONSTRAINT fk_empresa_creador
    FOREIGN KEY (id_creador)
    REFERENCES usuario (id_usuario);

ALTER TABLE cuenta ENABLE ROW LEVEL SECURITY;

CREATE POLICY cuenta_select_scope
    ON cuenta
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
                  OR u.codigo_empresa = cuenta.codigo_empresa
              )
        )
    );

GRANT SELECT ON cuenta TO authenticated;
