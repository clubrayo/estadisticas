-- =====================================================================
-- VERIFICACIÓN 005 — ESTADÍSTICAS INDIVIDUALES
-- Solo lectura. No modifica nada.
-- Resultado esperado: todas las filas con ok = true.
-- =====================================================================

with vistas (nombre) as (
    values ('v_est_partidos'), ('v_est_asistencia'), ('v_est_convocatorias'), ('v_est_participaciones')
),
chequeos (n, chequeo, esperado, obtenido) as (
    select 1, 'Migración 005 registrada', '1',
           (select count(*)::text from public.migraciones_aplicadas where version = '005')
    union all
    select 2, 'Vistas de estadísticas creadas', '4',
           (select count(*)::text from pg_views where schemaname = 'public' and viewname in (select nombre from vistas))
    union all
    select 3, 'Vistas con security_invoker (respetan RLS)', '4',
           (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relname in (select nombre from vistas)
               and c.reloptions @> array['security_invoker=true'])
    union all
    select 4, 'Vistas legibles por authenticated y no por anon', '4|0',
           (select count(*) filter (where grantee = 'authenticated')::text || '|'
                   || count(*) filter (where grantee = 'anon')::text
              from information_schema.role_table_grants
             where table_schema = 'public' and privilege_type = 'SELECT' and table_name in (select nombre from vistas))
    union all
    select 5, 'Función estadisticas_jugador ejecutable por authenticated', '1',
           (select count(*)::text from information_schema.routine_privileges
             where routine_schema = 'public' and routine_name = 'estadisticas_jugador' and grantee = 'authenticated')
    union all
    select 6, 'Partidos que cuentan (excluye cancelados)', 'ok',
           (select case when count(*) filter (where estado = 'CANCELADO') = 0 then 'ok' else 'incluye cancelados' end
              from public.v_est_partidos)
)
select n, chequeo, esperado, obtenido, (esperado = obtenido) as ok
  from chequeos
 order by n;
