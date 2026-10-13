-- =====================================================================
-- VERIFICACIÓN 003 — FUNCIONES RPC Y VALIDACIONES DE JUEGO
-- Solo lectura. No modifica nada.
-- Resultado esperado: todas las filas con ok = true.
-- =====================================================================

with rpc (nombre) as (
    values ('iniciar_partido'), ('suspender_partido'), ('reanudar_partido'), ('cancelar_partido'),
           ('registrar_asistencia'), ('crear_lista'), ('guardar_lista'), ('confirmar_lista'),
           ('devolver_lista_a_edicion'), ('registrar_resultado'), ('previsualizar_correccion'),
           ('corregir_resultado'), ('reabrir_partido'), ('cerrar_revision'),
           ('activar_regla_version'), ('verificar_partido')
),
chequeos (n, chequeo, esperado, obtenido) as (
    select 1, 'Migración 003 registrada', '1',
           (select count(*)::text from public.migraciones_aplicadas where version = '003')
    union all
    select 2, 'Funciones RPC creadas', '16',
           (select count(*)::text from pg_proc p join pg_namespace s on s.oid = p.pronamespace
             where s.nspname = 'public' and p.proname in (select nombre from rpc))
    union all
    select 3, 'RPC con SECURITY DEFINER y search_path fijo', '16',
           (select count(*)::text from pg_proc p join pg_namespace s on s.oid = p.pronamespace
             where s.nspname = 'public' and p.proname in (select nombre from rpc)
               and p.prosecdef and p.proconfig is not null)
    union all
    select 4, 'RPC ejecutables por authenticated', '16',
           (select count(distinct routine_name)::text from information_schema.routine_privileges
             where routine_schema = 'public' and grantee = 'authenticated' and privilege_type = 'EXECUTE'
               and routine_name in (select nombre from rpc))
    union all
    select 5, 'RPC NO ejecutables por anon ni PUBLIC', '0',
           (select count(*)::text from information_schema.routine_privileges
             where routine_schema = 'public' and grantee in ('anon', 'PUBLIC')
               and routine_name in (select nombre from rpc))
    union all
    select 6, 'Triggers de validación entre tablas', '7',
           (select count(*)::text from pg_trigger where not tgisinternal and tgname in (
                'trg_partidos_validar_clubes', 'trg_listas_validar', 'trg_convocatorias_validar',
                'trg_participantes_validar', 'trg_resultados_validar', 'trg_acciones_validar',
                'trg_asistencias_validar'))
    union all
    select 7, 'Verificaciones diferidas (al confirmar la transacción)', '2',
           (select count(*)::text from pg_trigger where not tgisinternal and tgdeferrable and tginitdeferred
               and tgname in ('trg_enfrentamientos_coherencia', 'trg_resultados_coherencia'))
    union all
    select 8, 'Funciones privadas sin EXECUTE para anon/PUBLIC', '0',
           (select count(*)::text from information_schema.routine_privileges
             where routine_schema = 'privado' and grantee in ('anon', 'PUBLIC'))
    union all
    select 9, 'Partidos existentes sin club gestionado', '0',
           (select count(*)::text from public.partidos p
             where not exists (select 1 from public.clubes c
                                where c.id in (p.club_local_id, p.club_visitante_id) and c.es_gestionado))
)
select n, chequeo, esperado, obtenido, (esperado = obtenido) as ok
  from chequeos
 order by n;
