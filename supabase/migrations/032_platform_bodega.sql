-- Alineación v1/v2: onboarding bodega y ampliación asignacion_bodega (032).

-- ---------------------------------------------------------------------------
-- solicitud_alta_bodega
-- ---------------------------------------------------------------------------
CREATE TABLE solicitud_alta_bodega (
    id_solicitud uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_empresa varchar(32) NOT NULL,
    codigo_cuenta varchar(32) NOT NULL,
    id_solicitante uuid NOT NULL,
    nombre_solicitado varchar(255) NOT NULL,
    tipo bodega_tipo NOT NULL DEFAULT 'interna',
    comentarios text,
    estado estado_solicitud_bodega NOT NULL DEFAULT 'pendiente',
    id_bodega uuid,
    id_atendido_por uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    atendido_en timestamptz,

    CONSTRAINT fk_sol_bodega_empresa
        FOREIGN KEY (codigo_empresa)
        REFERENCES empresa (codigo_empresa),

    CONSTRAINT fk_sol_bodega_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_sol_bodega_solicitante
        FOREIGN KEY (id_solicitante)
        REFERENCES usuario (id_usuario),

    CONSTRAINT fk_sol_bodega_atendido
        FOREIGN KEY (id_atendido_por)
        REFERENCES usuario (id_usuario),

    CONSTRAINT fk_sol_bodega_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega)
);

CREATE INDEX ix_sol_bodega_tenant ON solicitud_alta_bodega (codigo_cuenta, estado);
CREATE INDEX ix_sol_bodega_pendiente ON solicitud_alta_bodega (estado)
    WHERE estado = 'pendiente';

COMMENT ON TABLE solicitud_alta_bodega IS
    'Petición de alta de bodega por admin cuenta; atendida por configurador TI.';

-- ---------------------------------------------------------------------------
-- bodega — campos v1/v2
-- ---------------------------------------------------------------------------
ALTER TABLE bodega
    ADD COLUMN tipo bodega_tipo NOT NULL DEFAULT 'interna',
    ADD COLUMN capacidad_slots integer,
    ADD COLUMN id_solicitud_origen uuid,
    ADD COLUMN id_creador uuid;

ALTER TABLE bodega
    ADD CONSTRAINT fk_bodega_solicitud_origen
        FOREIGN KEY (id_solicitud_origen)
        REFERENCES solicitud_alta_bodega (id_solicitud),

    ADD CONSTRAINT fk_bodega_creador
        FOREIGN KEY (id_creador)
        REFERENCES usuario (id_usuario);

CREATE UNIQUE INDEX uq_bodega_solicitud_origen
    ON bodega (id_solicitud_origen)
    WHERE id_solicitud_origen IS NOT NULL;

CREATE INDEX ix_bodega_tipo ON bodega (tipo);

-- ---------------------------------------------------------------------------
-- asignacion_bodega — rol por bodega (v2 doc)
-- ---------------------------------------------------------------------------
ALTER TABLE asignacion_bodega
    ADD COLUMN id_asignacion uuid DEFAULT gen_random_uuid(),
    ADD COLUMN id_rol wms_rol,
    ADD COLUMN vigente_desde timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN esta_activa boolean NOT NULL DEFAULT true;

UPDATE asignacion_bodega ab
SET id_rol = u.id_rol
FROM usuario u
WHERE u.id_usuario = ab.id_usuario
  AND ab.id_rol IS NULL;

UPDATE asignacion_bodega
SET id_rol = 'operario'
WHERE id_rol IS NULL;

ALTER TABLE asignacion_bodega
    ALTER COLUMN id_asignacion SET NOT NULL,
    ALTER COLUMN id_rol SET NOT NULL;

ALTER TABLE asignacion_bodega DROP CONSTRAINT asignacion_bodega_pkey;

ALTER TABLE asignacion_bodega
    ADD CONSTRAINT asignacion_bodega_pkey PRIMARY KEY (id_asignacion);

ALTER TABLE asignacion_bodega
    ADD CONSTRAINT uq_asignacion_usuario_bodega UNIQUE (id_usuario, id_bodega);

ALTER TABLE asignacion_bodega
    ADD CONSTRAINT fk_asignacion_rol
        FOREIGN KEY (id_rol)
        REFERENCES rol (id_rol);

CREATE INDEX ix_asignacion_rol ON asignacion_bodega (id_rol);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE solicitud_alta_bodega ENABLE ROW LEVEL SECURITY;

CREATE POLICY solicitud_alta_bodega_select_scope
    ON solicitud_alta_bodega
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

CREATE POLICY solicitud_alta_bodega_insert_admin
    ON solicitud_alta_bodega
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND (
            auth_wms_es_configurador()
            OR (auth_wms_usuario_actual()).id_rol = 'administrador_cuenta'
        )
    );

CREATE POLICY solicitud_alta_bodega_update_configurador
    ON solicitud_alta_bodega
    FOR UPDATE
    TO authenticated
    USING (auth_wms_es_configurador())
    WITH CHECK (auth_wms_es_configurador());

REVOKE INSERT, UPDATE, DELETE ON solicitud_alta_bodega FROM authenticated;
GRANT SELECT, INSERT ON solicitud_alta_bodega TO authenticated;
GRANT UPDATE ON solicitud_alta_bodega TO authenticated;
