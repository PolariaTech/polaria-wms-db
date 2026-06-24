-- POL-2: base multi-tenant y RLS inicial para WMS v2.0.
-- El configurador opera a nivel plataforma; todos los demás usuarios deben
-- quedar anclados a un tenant operativo (codigo_cuenta).

ALTER TABLE public.usuario
    DROP CONSTRAINT IF EXISTS chk_usuario_contexto;

ALTER TABLE public.usuario
    ADD CONSTRAINT chk_usuario_contexto CHECK (
        (
            id_rol = 'configurador'
            AND codigo_empresa IS NULL
            AND codigo_cuenta IS NULL
        )
        OR (
            id_rol <> 'configurador'
            AND codigo_empresa IS NOT NULL
            AND codigo_cuenta IS NOT NULL
        )
    );

CREATE TABLE public.bodega (
    id_bodega uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_cuenta varchar(32) NOT NULL,
    codigo_bodega varchar(32) NOT NULL,
    nombre varchar(255) NOT NULL,
    es_externa boolean NOT NULL DEFAULT false,
    esta_activa boolean NOT NULL DEFAULT true,
    id_creador uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_bodega_cuenta
        FOREIGN KEY (codigo_cuenta)
        REFERENCES public.cuenta (codigo_cuenta),

    CONSTRAINT fk_bodega_creador
        FOREIGN KEY (id_creador)
        REFERENCES public.usuario (id_usuario),

    CONSTRAINT uq_bodega_codigo_por_cuenta
        UNIQUE (codigo_cuenta, codigo_bodega)
);

CREATE INDEX ix_bodega_cuenta ON public.bodega (codigo_cuenta);
CREATE INDEX ix_bodega_activa
    ON public.bodega (esta_activa)
    WHERE esta_activa;

CREATE TRIGGER trg_bodega_updated_at
    BEFORE UPDATE ON public.bodega
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.asignacion_bodega (
    id_asignacion uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario uuid NOT NULL,
    id_bodega uuid NOT NULL,
    esta_activa boolean NOT NULL DEFAULT true,
    id_creador uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_asignacion_bodega_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES public.usuario (id_usuario)
        ON DELETE CASCADE,

    CONSTRAINT fk_asignacion_bodega_bodega
        FOREIGN KEY (id_bodega)
        REFERENCES public.bodega (id_bodega)
        ON DELETE CASCADE,

    CONSTRAINT fk_asignacion_bodega_creador
        FOREIGN KEY (id_creador)
        REFERENCES public.usuario (id_usuario),

    CONSTRAINT uq_asignacion_bodega_usuario
        UNIQUE (id_usuario, id_bodega)
);

CREATE INDEX ix_asignacion_bodega_usuario
    ON public.asignacion_bodega (id_usuario)
    WHERE esta_activa;

CREATE INDEX ix_asignacion_bodega_bodega
    ON public.asignacion_bodega (id_bodega)
    WHERE esta_activa;

CREATE TRIGGER trg_asignacion_bodega_updated_at
    BEFORE UPDATE ON public.asignacion_bodega
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.bodega ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asignacion_bodega ENABLE ROW LEVEL SECURITY;

CREATE SCHEMA IF NOT EXISTS wms_private;
REVOKE ALL ON SCHEMA wms_private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA wms_private TO authenticated;

CREATE OR REPLACE FUNCTION wms_private.can_read_empresa(p_codigo_empresa varchar)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.usuario u
        WHERE u.id_auth = (SELECT auth.uid())
          AND u.esta_activo
          AND (
              u.id_rol = 'configurador'::public.wms_rol
              OR u.codigo_empresa = p_codigo_empresa
          )
    );
$$;

CREATE OR REPLACE FUNCTION wms_private.can_read_cuenta(p_codigo_cuenta varchar)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.usuario u
        WHERE u.id_auth = (SELECT auth.uid())
          AND u.esta_activo
          AND (
              u.id_rol = 'configurador'::public.wms_rol
              OR (
                  p_codigo_cuenta IS NOT NULL
                  AND u.codigo_cuenta = p_codigo_cuenta
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION wms_private.can_read_bodega(p_id_bodega uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.usuario u
        JOIN public.rol r
          ON r.id_rol = u.id_rol
        JOIN public.bodega b
          ON b.id_bodega = p_id_bodega
        WHERE u.id_auth = (SELECT auth.uid())
          AND u.esta_activo
          AND (
              u.id_rol = 'configurador'::public.wms_rol
              OR (
                  r.nivel = 'cuenta'::public.rol_nivel
                  AND u.codigo_cuenta = b.codigo_cuenta
              )
              OR (
                  r.nivel = 'bodega'::public.rol_nivel
                  AND EXISTS (
                      SELECT 1
                      FROM public.asignacion_bodega ab
                      WHERE ab.id_usuario = u.id_usuario
                        AND ab.id_bodega = p_id_bodega
                        AND ab.esta_activa
                  )
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION wms_private.can_read_tenant_row(
    p_codigo_cuenta varchar,
    p_id_bodega uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT
        CASE
            WHEN p_id_bodega IS NOT NULL THEN
                wms_private.can_read_bodega(p_id_bodega)
            ELSE
                EXISTS (
                    SELECT 1
                    FROM public.usuario u
                    WHERE u.id_auth = (SELECT auth.uid())
                      AND u.esta_activo
                      AND (
                          u.id_rol = 'configurador'::public.wms_rol
                          OR (
                              p_codigo_cuenta IS NOT NULL
                              AND u.codigo_cuenta = p_codigo_cuenta
                          )
                      )
                )
        END;
$$;

GRANT EXECUTE ON FUNCTION wms_private.can_read_empresa(varchar) TO authenticated;
GRANT EXECUTE ON FUNCTION wms_private.can_read_cuenta(varchar) TO authenticated;
GRANT EXECUTE ON FUNCTION wms_private.can_read_bodega(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION wms_private.can_read_tenant_row(varchar, uuid) TO authenticated;

DROP POLICY IF EXISTS usuario_select_own ON public.usuario;
DROP POLICY IF EXISTS usuario_select_scope ON public.usuario;
CREATE POLICY usuario_select_scope
    ON public.usuario
    FOR SELECT
    TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL
        AND wms_private.can_read_tenant_row(usuario.codigo_cuenta, NULL)
    );

DROP POLICY IF EXISTS empresa_select_scope ON public.empresa;
CREATE POLICY empresa_select_scope
    ON public.empresa
    FOR SELECT
    TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL
        AND wms_private.can_read_empresa(empresa.codigo_empresa)
    );

DROP POLICY IF EXISTS cuenta_select_scope ON public.cuenta;
CREATE POLICY cuenta_select_scope
    ON public.cuenta
    FOR SELECT
    TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL
        AND wms_private.can_read_cuenta(cuenta.codigo_cuenta)
    );

CREATE POLICY bodega_select_scope
    ON public.bodega
    FOR SELECT
    TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL
        AND wms_private.can_read_bodega(bodega.id_bodega)
    );

CREATE POLICY asignacion_bodega_select_scope
    ON public.asignacion_bodega
    FOR SELECT
    TO authenticated
    USING (
        (SELECT auth.uid()) IS NOT NULL
        AND wms_private.can_read_bodega(asignacion_bodega.id_bodega)
    );

-- Las escrituras operativas sensibles quedan reservadas al backend
-- (conexión directa/controlada). Los clientes autenticados solo leen por RLS.
REVOKE ALL ON TABLE
    public.rol,
    public.empresa,
    public.usuario,
    public.cuenta,
    public.bodega,
    public.asignacion_bodega
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE
    public.rol,
    public.empresa,
    public.usuario,
    public.cuenta,
    public.bodega,
    public.asignacion_bodega
TO authenticated;
