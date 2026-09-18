-- Acceso de producto por usuario: WMS, Mateo IA, o ambos.
-- Default ambos = true para no cambiar el comportamiento de usuarios existentes.

ALTER TABLE public.usuario
    ADD COLUMN IF NOT EXISTS acceso_wms boolean NOT NULL DEFAULT true;

ALTER TABLE public.usuario
    ADD COLUMN IF NOT EXISTS acceso_mateo boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.usuario.acceso_wms IS
    'Si es true, este usuario puede operar Polaria WMS.';

COMMENT ON COLUMN public.usuario.acceso_mateo IS
    'Si es true, este usuario puede entrar a Mateo IA (botón topbar o redirect).';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_usuario_acceso_producto'
    ) THEN
        ALTER TABLE public.usuario
            ADD CONSTRAINT ck_usuario_acceso_producto
            CHECK (acceso_wms OR acceso_mateo);
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
