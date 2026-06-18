CREATE TABLE rol (
    id_rol wms_rol PRIMARY KEY,
    nombre varchar(255) NOT NULL,
    nivel rol_nivel NOT NULL,
    puede_crear_rol wms_rol,
    descripcion text,

    CONSTRAINT fk_rol_puede_crear
        FOREIGN KEY (puede_crear_rol)
        REFERENCES rol (id_rol)
);

CREATE INDEX ix_rol_nivel ON rol (nivel);

INSERT INTO rol (id_rol, nombre, nivel, puede_crear_rol, descripcion)
VALUES
    (
        'configurador',
        'Configurador (TI)',
        'plataforma',
        NULL,
        'Equipo TI del proveedor SaaS. Crea empresas y administradores de cuenta.'
    ),
    (
        'administrador_cuenta',
        'Administrador de cuenta',
        'cuenta',
        'configurador',
        'Responsable del cliente. Gestiona tenant, catálogos y equipo.'
    ),
    (
        'operador_cuenta',
        'Operador de cuenta',
        'cuenta',
        'administrador_cuenta',
        'Opera el tenant a nivel comercial (SOL, OC, OV).'
    ),
    (
        'administrador_bodega',
        'Administrador de bodega',
        'bodega',
        'administrador_cuenta',
        'Responsable de la bodega asignada: configuración y supervisión.'
    ),
    (
        'jefe_bodega',
        'Jefe de bodega',
        'bodega',
        'administrador_cuenta',
        'Jefe operativo: prioriza OT, alertas y override de temperatura.'
    ),
    (
        'custodio',
        'Custodio',
        'bodega',
        'administrador_cuenta',
        'Recibe mercancía, valida documentos/temperatura y despacha salidas.'
    ),
    (
        'operario',
        'Operario',
        'bodega',
        'administrador_cuenta',
        'Ejecuta órdenes de trabajo y movimientos de cajas/slots.'
    ),
    (
        'procesador',
        'Procesador',
        'bodega',
        'administrador_cuenta',
        'Encargado de la línea de procesamiento (primario → secundario, merma).'
    ),
    (
        'transportista',
        'Transportista',
        'bodega',
        'administrador_cuenta',
        'Conduce viajes TV y registra entregas con evidencias.'
    );

ALTER TABLE rol ENABLE ROW LEVEL SECURITY;

CREATE POLICY rol_select_authenticated
    ON rol
    FOR SELECT
    TO authenticated
    USING (true);

GRANT SELECT ON rol TO authenticated;
