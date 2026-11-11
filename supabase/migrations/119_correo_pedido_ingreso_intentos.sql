-- POL-417: registro de tiempos de cada ingreso manual de correo (base de POL-415).
--
-- Hoy created_at no cambia y updated_at se pisa en cada reintento, asi que no se
-- puede medir cuanto tarda un ingreso. El arreglo jsonb `intentos` guarda inicio,
-- fin, duracion y resultado de cada intento, igual que `tiempos` en la migracion 115.

ALTER TABLE public.correo_pedido_ingreso
    ADD COLUMN IF NOT EXISTS intentos jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.correo_pedido_ingreso.intentos IS
    'Arreglo de intentos de ingreso manual. Cada elemento: { "n": entero, "iniciado_at": ISO-8601 UTC, "terminado_at": ISO-8601 UTC o null, "duracion_ms": entero o null, "resultado": "procesando" | "ingresado" | "error" | "vencido", "error": texto de max. 500 caracteres o null }. Sin CHECK: la forma la escribe el api.';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'wms_sync_column_to_tenants'
    ) THEN
        PERFORM public.wms_sync_column_to_tenants(
            'correo_pedido_ingreso',
            'intentos'
        );
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';
