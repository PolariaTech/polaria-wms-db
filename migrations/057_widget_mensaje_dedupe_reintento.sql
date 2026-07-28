-- POL-139 / POL-176:
-- Evitar duplicados de mensajes cuando el cliente reintenta el mismo append.
--
-- Estrategia:
-- - Identidad lógica del mensaje: conversación + payload + timestamp del cliente.
-- - Si llega el mismo payload con el mismo created_at, queda bloqueado por UNIQUE.
--
-- Nota: tras 055 las tablas viven en schema mateo_support.

CREATE UNIQUE INDEX IF NOT EXISTS uq_widget_mensaje_reintento
    ON mateo_support.widget_mensaje (
        id_conversacion,
        rol,
        tipo,
        es_error,
        created_at,
        md5(contenido)
    );
