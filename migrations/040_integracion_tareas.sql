-- Alineación v1/v2: integración Fridem y tareas de cuenta (040).

-- ---------------------------------------------------------------------------
-- solicitud_integracion — bodega externa (v1 solicitudesIntegracion)
-- ---------------------------------------------------------------------------
CREATE TABLE solicitud_integracion (
    id_solicitud_integracion uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_cliente uuid NOT NULL,
    bodega_externa_id varchar(64) NOT NULL,
    bodega_externa_nombre varchar(255) NOT NULL,
    scraping boolean NOT NULL DEFAULT false,
    api boolean NOT NULL DEFAULT false,
    csv_plano boolean NOT NULL DEFAULT false,
    estado estado_integracion NOT NULL DEFAULT 'activo',
    id_solicitante uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    finalizada_at timestamptz,

    CONSTRAINT fk_sol_int_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_sol_int_cliente
        FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente),

    CONSTRAINT fk_sol_int_solicitante
        FOREIGN KEY (id_solicitante)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_sol_int_cuenta ON solicitud_integracion (codigo_cuenta, estado);
CREATE INDEX ix_sol_int_cliente ON solicitud_integracion (id_cliente);

COMMENT ON TABLE solicitud_integracion IS
    'Solicitud de integración con bodega externa (Fridem: scraping/API/CSV).';

-- ---------------------------------------------------------------------------
-- tarea_cuenta — tareas admin cuenta (v1 tareasCuenta)
-- ---------------------------------------------------------------------------
CREATE TABLE tarea_cuenta (
    id_tarea_cuenta uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_cliente uuid NOT NULL,
    titulo varchar(255) NOT NULL,
    detalle text,
    estado estado_tarea_cuenta NOT NULL DEFAULT 'pendiente',
    id_creador uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    resuelta_at timestamptz,

    CONSTRAINT fk_tarea_cuenta_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_tarea_cuenta_cliente
        FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente),

    CONSTRAINT fk_tarea_cuenta_creador
        FOREIGN KEY (id_creador)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_tarea_cuenta_estado ON tarea_cuenta (codigo_cuenta, estado);

COMMENT ON TABLE tarea_cuenta IS
    'Tareas administrativas de cuenta (no operación de bodega).';

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE solicitud_integracion ENABLE ROW LEVEL SECURITY;
ALTER TABLE tarea_cuenta ENABLE ROW LEVEL SECURITY;

CREATE POLICY solicitud_integracion_select_scope
    ON solicitud_integracion
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

CREATE POLICY tarea_cuenta_select_scope
    ON tarea_cuenta
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

REVOKE INSERT, UPDATE, DELETE ON solicitud_integracion FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON tarea_cuenta FROM authenticated;

GRANT SELECT ON solicitud_integracion TO authenticated;
GRANT SELECT ON tarea_cuenta TO authenticated;

-- Escritura vía backend o admin cuenta (futuro); por ahora solo SELECT PostgREST.
