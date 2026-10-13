-- =====================================================================
-- VERIFICACIÓN 004 — ACCIONES POR INTEGRANTE Y RESULTADO POR SECRETARÍA
-- Solo lectura. No modifica nada.
-- Resultado esperado: todas las filas con ok = true.
-- =====================================================================

with chequeos (n, chequeo, esperado, obtenido) as (
    select 1, 'Migración 004 registrada', '1',
           (select count(*)::text from public.migraciones_aplicadas where version = '004')
    union all
    select 2, 'Columnas por_secretaria y motivo_secretaria', '2',
           (select count(*)::text from information_schema.columns
             where table_schema = 'public' and table_name = 'resultados_enfrentamiento'
               and column_name in ('por_secretaria', 'motivo_secretaria'))
    union all
    select 3, 'Eliminada la restricción de una sola acción por resultado', '0',
           (select count(*)::text from pg_constraint where conname = 'uq_acciones_resultado_v1')
    union all
    select 4, 'Verificaciones diferidas de reglas de acciones', '2',
           (select count(*)::text from pg_trigger where not tgisinternal and tgdeferrable and tginitdeferred
               and tgname in ('trg_resultados_reglas_acciones', 'trg_acciones_reglas'))
    union all
    select 5, 'Funciones de reglas creadas', '4',
           (select count(*)::text from pg_proc p join pg_namespace s on s.oid = p.pronamespace
             where s.nspname = 'privado'
               and p.proname in ('problemas_acciones', 'firma_acciones', 'firma_entrada', 'insertar_acciones'))
    union all
    select 6, 'Firmas nuevas de registrar/corregir (con p_acciones jsonb)', '2',
           (select count(*)::text from pg_proc p join pg_namespace s on s.oid = p.pronamespace
             where s.nspname = 'public' and p.proname in ('registrar_resultado', 'corregir_resultado')
               and pg_get_function_identity_arguments(p.oid) like '%p_acciones jsonb%')
    union all
    select 7, 'Firmas antiguas eliminadas', '0',
           (select count(*)::text from pg_proc p join pg_namespace s on s.oid = p.pronamespace
             where s.nspname = 'public' and p.proname in ('registrar_resultado', 'corregir_resultado')
               and pg_get_function_identity_arguments(p.oid) not like '%p_acciones jsonb%')
    union all
    select 8, 'Nuevas RPC ejecutables por authenticated y no por anon/PUBLIC', '2|0',
           (select count(*) filter (where grantee = 'authenticated')::text || '|'
                   || count(*) filter (where grantee in ('anon', 'PUBLIC'))::text
              from information_schema.routine_privileges
             where routine_schema = 'public' and routine_name in ('registrar_resultado', 'corregir_resultado'))
    union all
    select 9, 'Funciones privadas sin EXECUTE para anon/PUBLIC', '0',
           (select count(*)::text from information_schema.routine_privileges
             where routine_schema = 'privado' and grantee in ('anon', 'PUBLIC'))
)
select n, chequeo, esperado, obtenido, (esperado = obtenido) as ok
  from chequeos
 order by n;
