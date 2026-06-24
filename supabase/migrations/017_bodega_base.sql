-- POL-2: modelo mínimo de bodega y asignación para RLS por id_bodega.
-- POL-33 ampliará el modelo operativo; aquí solo lo fundacional.
--
-- Convención tenant para tablas operativas futuras (Prisma / POL-33):
--   - codigo_cuenta varchar(32) NOT NULL FK → cuenta (aislamiento comercial)
--   - id_bodega uuid NOT NULL FK → bodega (aislamiento físico / operativo)
-- codigo_empresa se resuelve vía cuenta; no duplicar en bodega ni en hijos.

CREATE TABLE bodega (
    id_bodega uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    codigo varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_bodega_cuenta_codigo UNIQUE (codigo_cuenta, codigo),

    CONSTRAINT fk_bodega_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES cuenta (codigo_cuenta)
);

CREATE INDEX ix_bodega_cuenta ON bodega (codigo_cuenta);

CREATE TRIGGER trg_bodega_updated_at
    BEFORE UPDATE ON bodega
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE asignacion_bodega (
    id_usuario uuid NOT NULL,
    id_bodega uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (id_usuario, id_bodega),

    CONSTRAINT fk_asignacion_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
        ON DELETE CASCADE,

    CONSTRAINT fk_asignacion_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES bodega (id_bodega)
        ON DELETE CASCADE
);

CREATE INDEX ix_asignacion_usuario ON asignacion_bodega (id_usuario);
CREATE INDEX ix_asignacion_bodega ON asignacion_bodega (id_bodega);

-- Alcance de bodegas según rol y asignación.
-- Configurador: todas las activas. Admin cuenta: su cuenta o toda su empresa si codigo_cuenta NULL.
-- Nivel bodega: solo asignacion_bodega. operador_cuenta: bodegas de su codigo_cuenta.
CREATE OR REPLACE FUNCTION auth_wms_puede_ver_bodega(p_id_bodega uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM usuario u
        INNER JOIN rol r ON r.id_rol = u.id_rol
        INNER JOIN bodega b ON b.id_bodega = p_id_bodega
        INNER JOIN cuenta c ON c.codigo_cuenta = b.codigo_cuenta
        INNER JOIN empresa e ON e.codigo_empresa = c.codigo_empresa
        WHERE u.id_auth = auth.uid()
          AND u.esta_activo
          AND b.esta_activa
          AND c.esta_activa
          AND e.esta_activa
          AND (
              u.id_rol = 'configurador'
              OR (
                  u.id_rol = 'administrador_cuenta'
                  AND (
                      (
                          u.codigo_cuenta IS NULL
                          AND c.codigo_empresa = u.codigo_empresa
                      )
                      OR u.codigo_cuenta = b.codigo_cuenta
                  )
              )
              OR (
                  r.nivel = 'bodega'
                  AND EXISTS (
                      SELECT 1
                      FROM asignacion_bodega ab
                      WHERE ab.id_usuario = u.id_usuario
                        AND ab.id_bodega = p_id_bodega
                  )
              )
              OR (
                  u.id_rol = 'operador_cuenta'
                  AND u.codigo_cuenta IS NOT NULL
                  AND u.codigo_cuenta = b.codigo_cuenta
              )
          )
    )
$$;

REVOKE ALL ON FUNCTION auth_wms_puede_ver_bodega(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth_wms_puede_ver_bodega(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION auth_wms_puede_ver_bodega(uuid) TO authenticated;

ALTER TABLE bodega ENABLE ROW LEVEL SECURITY;

CREATE POLICY bodega_select_scope
    ON bodega
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

GRANT SELECT ON bodega TO authenticated;

ALTER TABLE asignacion_bodega ENABLE ROW LEVEL SECURITY;

CREATE POLICY asignacion_bodega_select_scope
    ON asignacion_bodega
    FOR SELECT
    TO authenticated
    USING (auth_wms_puede_ver_bodega(id_bodega));

GRANT SELECT ON asignacion_bodega TO authenticated;

-- INSERT/UPDATE/DELETE: ver migración 018_rls_write_policies.sql (solo configurador).
