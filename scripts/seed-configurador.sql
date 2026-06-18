-- Crear un usuario configurador (TI) en Supabase.
-- Ejecutar en SQL Editor (como postgres / service role).
-- Cambia correo, username, nombre y contraseña antes de ejecutar.

DO $$
DECLARE
    v_user_id   uuid := gen_random_uuid();
    v_correo    citext := 'configuradorti@polaria.tech';
    v_username  citext := 'configurador_ti';
    v_nombre    text   := 'Super Configurador TI';
    v_password  text   := 'q5D8#b26&~c8';
BEGIN
    -- 1) Credenciales en Supabase Auth (contraseña NO va en public.usuario)
    INSERT INTO auth.users (
        id,
        instance_id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at
    ) VALUES (
        v_user_id,
        '00000000-0000-0000-0000-000000000000',
        'authenticated',
        'authenticated',
        v_correo::text,
        crypt(v_password, gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{}'::jsonb,
        now(),
        now()
    );

    INSERT INTO auth.identities (
        id,
        user_id,
        provider_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
    ) VALUES (
        gen_random_uuid(),
        v_user_id,
        v_user_id::text,
        jsonb_build_object(
            'sub', v_user_id::text,
            'email', v_correo::text,
            'email_verified', true,
            'phone_verified', false
        ),
        'email',
        now(),
        now(),
        now()
    );

    -- 2) Perfil operativo (configurador: sin empresa ni cuenta)
    INSERT INTO public.usuario (
        id_auth,
        id_rol,
        codigo_empresa,
        codigo_cuenta,
        id_creador,
        nombre,
        username,
        correo
    ) VALUES (
        v_user_id,
        'configurador',
        NULL,
        NULL,
        NULL,
        v_nombre,
        v_username,
        v_correo
    );

    RAISE NOTICE 'Configurador creado. id_auth=%, correo=%, username=%',
        v_user_id, v_correo, v_username;
END $$;

-- Verificación
SELECT
    u.id_usuario,
    u.id_auth,
    u.id_rol,
    u.username,
    u.correo,
    u.codigo_empresa,
    u.codigo_cuenta,
    u.esta_activo
FROM public.usuario u
WHERE u.id_rol = 'configurador';
