-- =====================================================================
-- VERIFICACIÓN 002 — SEGURIDAD, RLS Y AUDITORÍA
-- Solo lectura. No modifica nada.
-- Resultado esperado: todas las filas con ok = true.
-- =====================================================================

with chequeos (n, chequeo, esperado, obtenido) as (
    select 1, 'Migración 002 registrada', '1',
           (select count(*)::text from public.migraciones_aplicadas where version = '002')
    union all
    select 2, 'Tablas nuevas', 'auditoria,perfiles,roles,usuario_roles',
           (select string_agg(table_name, ',' order by table_name) from information_schema.tables
             where table_schema = 'public'
               and table_name in ('perfiles', 'roles', 'usuario_roles', 'auditoria'))
    union all
    select 3, 'Tablas de public SIN RLS', '0',
           (select count(*)::text from pg_tables where schemaname = 'public' and not rowsecurity)
    union all
    select 4, 'Roles cargados', 'ADMINISTRADOR,DIRECTIVA,CAPITAN,CONSULTA',
           (select string_agg(codigo, ',' order by orden) from public.roles)
    union all
    select 5, 'Esquema privado creado', '1',
           (select count(*)::text from pg_namespace where nspname = 'privado')
    union all
    select 6, 'Funciones de apoyo ejecutables por authenticated', '11',
           (select count(*)::text from information_schema.routine_privileges
             where routine_schema = 'privado' and grantee = 'authenticated' and privilege_type = 'EXECUTE')
    union all
    select 7, 'anon sin privilegios sobre tablas de public', '0',
           (select count(*)::text from information_schema.role_table_grants
             where table_schema = 'public' and grantee = 'anon')
    union all
    select 8, 'anon sin privilegios sobre funciones de public y privado', '0',
           (select count(*)::text from information_schema.routine_privileges
             where routine_schema in ('public', 'privado') and grantee in ('anon', 'PUBLIC'))
    union all
    select 9, 'authenticated: única tabla con DELETE', 'usuario_roles',
           (select coalesce(string_agg(table_name, ','), '-') from information_schema.role_table_grants
             where table_schema = 'public' and grantee = 'authenticated' and privilege_type = 'DELETE')
    union all
    select 10, 'authenticated: sin INSERT/UPDATE en tablas operativas', '0',
           (select count(*)::text from information_schema.column_privileges
             where table_schema = 'public' and grantee = 'authenticated'
               and privilege_type in ('INSERT', 'UPDATE')
               and table_name in ('asistencias', 'listas_juego', 'convocatorias', 'enfrentamientos',
                                  'participantes_enfrentamiento', 'resultados_enfrentamiento',
                                  'acciones_resultado', 'auditoria', 'migraciones_aplicadas'))
    union all
    select 11, 'Partidos: columnas editables por authenticated', 'fecha,lugar,observaciones',
           (select string_agg(column_name, ',' order by column_name) from information_schema.column_privileges
             where table_schema = 'public' and table_name = 'partidos'
               and grantee = 'authenticated' and privilege_type = 'UPDATE')
    union all
    select 12, 'Políticas RLS en public', '37',
           (select count(*)::text from pg_policies where schemaname = 'public')
    union all
    select 13, 'Triggers de auditoría', '21',
           (select count(*)::text from pg_trigger where tgname = 'trg_auditoria' and not tgisinternal)
    union all
    select 14, 'Triggers que bloquean DELETE', '16',
           (select count(*)::text from pg_trigger where tgname = 'trg_bloquear_borrado' and not tgisinternal)
    union all
    select 15, 'Triggers que bloquean TRUNCATE', '22',
           (select count(*)::text from pg_trigger where tgname = 'trg_bloquear_truncate' and not tgisinternal)
    union all
    select 16, 'Protecciones específicas instaladas', '10',
           (select count(*)::text from pg_trigger where not tgisinternal and tgname in (
                'trg_convocatorias_proteger_borrado', 'trg_participantes_proteger_borrado',
                'trg_auditoria_inmutable', 'trg_reglas_valores_proteger', 'trg_reglas_versiones_proteger',
                'trg_perfiles_proteger', 'trg_usuario_roles_validar', 'trg_usuario_roles_admin_restante_del',
                'trg_usuario_roles_admin_restante_upd', 'trg_perfiles_admin_restante'))
    union all
    select 17, 'Trigger de perfil automático en auth.users', '1',
           (select count(*)::text from pg_trigger where tgname = 'trg_auth_users_crear_perfil' and not tgisinternal)
    union all
    select 18, 'Usuarios de Auth sin perfil', '0',
           (select count(*)::text from auth.users u where not exists (select 1 from public.perfiles p where p.id = u.id))
    union all
    select 19, 'Privilegios por defecto para anon/authenticated en public', '0',
           (select count(*)::text
              from pg_default_acl d
              cross join lateral aclexplode(d.defaclacl) a
             where d.defaclrole = 'postgres'::regrole
               and d.defaclnamespace = 'public'::regnamespace
               and a.grantee in ('anon'::regrole, 'authenticated'::regrole))
)
select n, chequeo, esperado, obtenido, (esperado = obtenido) as ok
  from chequeos
 order by n;
