-- =====================================================================
-- OPERACIÓN — ASIGNAR EL ROL ADMINISTRADOR A UN USUARIO EXISTENTE
-- No es una migración: es un dato operativo (queda registrado en auditoría).
--
-- Antes de ejecutar:
--   1. El usuario debe existir en Supabase: Authentication > Users.
--   2. Reemplace CORREO@EJEMPLO.COM (2 veces) por el correo real.
--
-- Resultado esperado: una fila con el correo, el nombre y ADMINISTRADOR.
-- Si no aparece ninguna fila, el correo no coincide con ningún usuario.
-- =====================================================================

insert into public.usuario_roles (usuario_id, rol_codigo)
select p.id, 'ADMINISTRADOR'
  from public.perfiles p
 where lower(p.email) = lower('CORREO@EJEMPLO.COM')
on conflict on constraint uq_usuario_roles do nothing;

select p.email, p.nombre_completo, p.estado, ur.rol_codigo
  from public.perfiles p
  join public.usuario_roles ur on ur.usuario_id = p.id
 where lower(p.email) = lower('CORREO@EJEMPLO.COM');
