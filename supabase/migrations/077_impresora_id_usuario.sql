-- Asigna impresora a un usuario de la cuenta (configuración por usuario).

ALTER TABLE public.impresora
    ADD COLUMN IF NOT EXISTS id_usuario uuid NULL;

CREATE INDEX IF NOT EXISTS idx_impresora_usuario
    ON public.impresora (id_usuario)
    WHERE id_usuario IS NOT NULL AND esta_activa;

COMMENT ON COLUMN public.impresora.id_usuario IS
    'Usuario de la cuenta al que queda asignada esta configuración de impresora.';

NOTIFY pgrst, 'reload schema';
