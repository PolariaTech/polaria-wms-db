-- POL-33 Fase 2: catálogos maestros por cuenta (alcance C, sin id_bodega).
--
-- Tablas: proveedor, cliente, producto, comprador, planta, camion.
-- codigo_empresa vía join cuenta; no duplicar en catálogos.
-- Ver docs/modelo-operativo-v2.md y docs/rls-politicas.md.

-- ---------------------------------------------------------------------------
-- Helper RLS: escritura de catálogos (configurador o admin de la cuenta)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_wms_puede_gestionar_catalogo_cuenta(p_codigo_cuenta varchar)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        auth_wms_es_configurador()
        OR (
            (auth_wms_usuario_actual()).id_rol = 'administrador_cuenta'
            AND auth_wms_puede_ver_cuenta(p_codigo_cuenta)
        )
$$;

REVOKE ALL ON FUNCTION auth_wms_puede_gestionar_catalogo_cuenta(varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth_wms_puede_gestionar_catalogo_cuenta(varchar) TO authenticated;

-- ---------------------------------------------------------------------------
-- proveedor
-- ---------------------------------------------------------------------------
CREATE TABLE proveedor (
    id_proveedor uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    codigo varchar(32) NOT NULL,
    razon_social varchar(255) NOT NULL,
    esta_activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_proveedor_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_proveedor_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta)
);

CREATE INDEX ix_proveedor_cuenta ON proveedor (codigo_cuenta);

CREATE TRIGGER trg_proveedor_updated_at
    BEFORE UPDATE ON proveedor
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE proveedor IS 'Catálogo de proveedores por cuenta. POL-33.';

-- ---------------------------------------------------------------------------
-- cliente
-- ---------------------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    codigo varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    esta_activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_cliente_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_cliente_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta)
);

CREATE INDEX ix_cliente_cuenta ON cliente (codigo_cuenta);

CREATE TRIGGER trg_cliente_updated_at
    BEFORE UPDATE ON cliente
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE cliente IS 'Catálogo de clientes por cuenta. POL-33.';

-- ---------------------------------------------------------------------------
-- producto
-- ---------------------------------------------------------------------------
CREATE TABLE producto (
    id_producto uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    sku varchar(64) NOT NULL,
    descripcion varchar(512) NOT NULL,
    unidad_medida varchar(32) NOT NULL,
    requiere_lote boolean NOT NULL DEFAULT false,
    esta_activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_producto_cuenta_sku UNIQUE (codigo_cuenta, sku),

    CONSTRAINT fk_producto_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta)
);

CREATE INDEX ix_producto_cuenta ON producto (codigo_cuenta);

CREATE TRIGGER trg_producto_updated_at
    BEFORE UPDATE ON producto
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE producto IS 'Catálogo de productos por cuenta. POL-33.';

-- ---------------------------------------------------------------------------
-- comprador (docs/modelo-operativo-v2.md — catálogo auxiliar C)
-- ---------------------------------------------------------------------------
CREATE TABLE comprador (
    id_comprador uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    codigo varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    esta_activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_comprador_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_comprador_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta)
);

CREATE INDEX ix_comprador_cuenta ON comprador (codigo_cuenta);

CREATE TRIGGER trg_comprador_updated_at
    BEFORE UPDATE ON comprador
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE comprador IS 'Compradores internos por cuenta. POL-33.';

-- ---------------------------------------------------------------------------
-- planta (docs/modelo-operativo-v2.md — catálogo auxiliar C)
-- ---------------------------------------------------------------------------
CREATE TABLE planta (
    id_planta uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    codigo varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    esta_activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_planta_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_planta_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta)
);

CREATE INDEX ix_planta_cuenta ON planta (codigo_cuenta);

CREATE TRIGGER trg_planta_updated_at
    BEFORE UPDATE ON planta
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE planta IS 'Plantas / sitios de origen por cuenta. POL-33.';

-- ---------------------------------------------------------------------------
-- camion (docs/modelo-operativo-v2.md — catálogo auxiliar C)
-- ---------------------------------------------------------------------------
CREATE TABLE camion (
    id_camion uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    placa varchar(16) NOT NULL,
    descripcion varchar(255),
    esta_activo boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_camion_cuenta_placa UNIQUE (codigo_cuenta, placa),

    CONSTRAINT fk_camion_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta)
);

CREATE INDEX ix_camion_cuenta ON camion (codigo_cuenta);

CREATE TRIGGER trg_camion_updated_at
    BEFORE UPDATE ON camion
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE camion IS 'Flota de transporte por cuenta. POL-33.';

-- ---------------------------------------------------------------------------
-- RLS — catálogos (SELECT acotado; INSERT/UPDATE admin; DELETE solo configurador)
-- ---------------------------------------------------------------------------
ALTER TABLE proveedor ENABLE ROW LEVEL SECURITY;
ALTER TABLE cliente ENABLE ROW LEVEL SECURITY;
ALTER TABLE producto ENABLE ROW LEVEL SECURITY;
ALTER TABLE comprador ENABLE ROW LEVEL SECURITY;
ALTER TABLE planta ENABLE ROW LEVEL SECURITY;
ALTER TABLE camion ENABLE ROW LEVEL SECURITY;

-- proveedor
CREATE POLICY proveedor_select_scope
    ON proveedor FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

CREATE POLICY proveedor_insert_cuenta
    ON proveedor FOR INSERT TO authenticated
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY proveedor_update_cuenta
    ON proveedor FOR UPDATE TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)
    )
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY proveedor_delete_configurador
    ON proveedor FOR DELETE TO authenticated
    USING (auth_wms_es_configurador());

-- cliente
CREATE POLICY cliente_select_scope
    ON cliente FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

CREATE POLICY cliente_insert_cuenta
    ON cliente FOR INSERT TO authenticated
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY cliente_update_cuenta
    ON cliente FOR UPDATE TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)
    )
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY cliente_delete_configurador
    ON cliente FOR DELETE TO authenticated
    USING (auth_wms_es_configurador());

-- producto
CREATE POLICY producto_select_scope
    ON producto FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

CREATE POLICY producto_insert_cuenta
    ON producto FOR INSERT TO authenticated
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY producto_update_cuenta
    ON producto FOR UPDATE TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)
    )
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY producto_delete_configurador
    ON producto FOR DELETE TO authenticated
    USING (auth_wms_es_configurador());

-- comprador
CREATE POLICY comprador_select_scope
    ON comprador FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

CREATE POLICY comprador_insert_cuenta
    ON comprador FOR INSERT TO authenticated
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY comprador_update_cuenta
    ON comprador FOR UPDATE TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)
    )
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY comprador_delete_configurador
    ON comprador FOR DELETE TO authenticated
    USING (auth_wms_es_configurador());

-- planta
CREATE POLICY planta_select_scope
    ON planta FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

CREATE POLICY planta_insert_cuenta
    ON planta FOR INSERT TO authenticated
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY planta_update_cuenta
    ON planta FOR UPDATE TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)
    )
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY planta_delete_configurador
    ON planta FOR DELETE TO authenticated
    USING (auth_wms_es_configurador());

-- camion
CREATE POLICY camion_select_scope
    ON camion FOR SELECT TO authenticated
    USING (auth_wms_puede_ver_cuenta(codigo_cuenta));

CREATE POLICY camion_insert_cuenta
    ON camion FOR INSERT TO authenticated
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY camion_update_cuenta
    ON camion FOR UPDATE TO authenticated
    USING (
        auth_wms_puede_ver_cuenta(codigo_cuenta)
        AND auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta)
    )
    WITH CHECK (auth_wms_puede_gestionar_catalogo_cuenta(codigo_cuenta));

CREATE POLICY camion_delete_configurador
    ON camion FOR DELETE TO authenticated
    USING (auth_wms_es_configurador());

-- GRANTs mínimos
REVOKE INSERT, UPDATE, DELETE ON proveedor FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON cliente FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON producto FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON comprador FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON planta FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON camion FROM authenticated;

GRANT SELECT, INSERT, UPDATE ON proveedor TO authenticated;
GRANT SELECT, INSERT, UPDATE ON cliente TO authenticated;
GRANT SELECT, INSERT, UPDATE ON producto TO authenticated;
GRANT SELECT, INSERT, UPDATE ON comprador TO authenticated;
GRANT SELECT, INSERT, UPDATE ON planta TO authenticated;
GRANT SELECT, INSERT, UPDATE ON camion TO authenticated;

GRANT DELETE ON proveedor TO authenticated;
GRANT DELETE ON cliente TO authenticated;
GRANT DELETE ON producto TO authenticated;
GRANT DELETE ON comprador TO authenticated;
GRANT DELETE ON planta TO authenticated;
GRANT DELETE ON camion TO authenticated;

-- ===========================================================================
-- Seed de ejemplo (comentado) — requiere cuenta ACME-01 del seed de validación
-- ===========================================================================
--
-- INSERT INTO proveedor (codigo_cuenta, codigo, razon_social)
-- VALUES ('ACME-01', 'PROV-001', 'Distribuidora Andina S.A.');
--
-- INSERT INTO cliente (codigo_cuenta, codigo, nombre)
-- VALUES ('ACME-01', 'CLI-001', 'Supermercados del Norte');
--
-- INSERT INTO producto (codigo_cuenta, sku, descripcion, unidad_medida, requiere_lote)
-- VALUES ('ACME-01', 'SKU-ARROZ-1KG', 'Arroz grano largo 1 kg', 'UN', true);
--
-- INSERT INTO comprador (codigo_cuenta, codigo, nombre)
-- VALUES ('ACME-01', 'COMP-01', 'María Compras');
--
-- INSERT INTO planta (codigo_cuenta, codigo, nombre)
-- VALUES ('ACME-01', 'PLT-01', 'Planta Procesamiento Norte');
--
-- INSERT INTO camion (codigo_cuenta, placa, descripcion)
-- VALUES ('ACME-01', 'ABC-123', 'Camión refrigerado 8 ton');
