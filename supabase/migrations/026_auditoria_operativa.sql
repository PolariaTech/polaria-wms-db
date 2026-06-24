-- POL-33 Fase 6b: auditoria_operacion — registro append-only de acciones WMS.
--
-- docs/modelo-operativo-v2.md: SELECT acotado; INSERT/UPDATE/DELETE **B** (solo backend).
-- Complementa docs/rls-politicas.md § tablas sensibles.

-- ---------------------------------------------------------------------------
-- Enum
-- ---------------------------------------------------------------------------
CREATE TYPE tipo_auditoria AS ENUM (
    'creacion',
    'actualizacion',
    'eliminacion',
    'cambio_estado',
    'movimiento_inventario',
    'acceso_denegado'
);

-- ---------------------------------------------------------------------------
-- auditoria_operacion
-- ---------------------------------------------------------------------------
CREATE TABLE auditoria_operacion (
    id_auditoria uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    id_bodega uuid,
    id_usuario uuid,
    accion tipo_auditoria NOT NULL,
    entidad varchar(64) NOT NULL,
    entidad_id uuid,
    payload jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_auditoria_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta),

    CONSTRAINT fk_auditoria_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega),

    CONSTRAINT fk_auditoria_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
);

CREATE INDEX ix_auditoria_cuenta ON auditoria_operacion (codigo_cuenta);
CREATE INDEX ix_auditoria_cuenta_created ON auditoria_operacion (codigo_cuenta, created_at DESC);
CREATE INDEX ix_auditoria_bodega ON auditoria_operacion (id_bodega)
    WHERE id_bodega IS NOT NULL;
CREATE INDEX ix_auditoria_usuario ON auditoria_operacion (id_usuario)
    WHERE id_usuario IS NOT NULL;
CREATE INDEX ix_auditoria_entidad ON auditoria_operacion (entidad, entidad_id);
CREATE INDEX ix_auditoria_accion ON auditoria_operacion (codigo_cuenta, accion);

CREATE OR REPLACE FUNCTION auditoria_operacion_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'auditoria_operacion es append-only; no UPDATE ni DELETE';
END;
$$;

CREATE TRIGGER trg_auditoria_append_only
    BEFORE UPDATE OR DELETE ON auditoria_operacion
    FOR EACH ROW
    EXECUTE FUNCTION auditoria_operacion_append_only();

COMMENT ON TABLE auditoria_operacion IS
    'Auditoría operativa append-only. INSERT solo backend; lectura admin/configurador. POL-33.';

COMMENT ON COLUMN auditoria_operacion.id_bodega IS
    'NULL = evento a nivel cuenta (sin bodega específica).';

COMMENT ON COLUMN auditoria_operacion.payload IS
    'Detalle JSON: estados anterior/nuevo, IP, ids relacionados, etc.';

-- ---------------------------------------------------------------------------
-- RLS — SELECT admin/configurador por cuenta; escritura solo backend
-- ---------------------------------------------------------------------------
ALTER TABLE auditoria_operacion ENABLE ROW LEVEL SECURITY;

CREATE POLICY auditoria_operacion_select_admin
    ON auditoria_operacion
    FOR SELECT
    TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND (
            auth_wms_es_configurador()
            OR (auth_wms_usuario_actual()).id_rol = 'administrador_cuenta'
        )
        AND (
            id_bodega IS NULL
            OR auth_wms_puede_ver_bodega(id_bodega)
        )
    );

REVOKE INSERT, UPDATE, DELETE ON auditoria_operacion FROM authenticated;

GRANT SELECT ON auditoria_operacion TO authenticated;

-- INSERT solo backend (postgres). Operadores de bodega no ven auditoría vía PostgREST.
