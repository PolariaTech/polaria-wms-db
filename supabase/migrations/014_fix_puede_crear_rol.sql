-- Corregir puede_crear_rol: solo el configurador (TI) puede dar de alta cualquier rol.
UPDATE rol
SET puede_crear_rol = 'configurador'
WHERE id_rol <> 'configurador';

UPDATE rol
SET descripcion = 'Equipo TI del proveedor SaaS. Crea empresas y usuarios con cualquier rol.'
WHERE id_rol = 'configurador';
