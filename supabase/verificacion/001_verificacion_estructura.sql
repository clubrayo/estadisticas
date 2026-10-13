-- =====================================================================
-- VERIFICACIÓN 001 — ESTRUCTURA Y DATOS INICIALES
-- Solo lectura. No modifica nada.
-- Resultado esperado: todas las filas con ok = true.
-- =====================================================================

with chequeos (n, chequeo, esperado, obtenido) as (
    select 1, 'Migración 001 registrada', '1',
           (select count(*)::text from public.migraciones_aplicadas where version = '001')
    union all
    select 2, 'Tablas creadas en public', '19',
           (select count(*)::text from information_schema.tables
             where table_schema = 'public' and table_type = 'BASE TABLE'
               and table_name in ('migraciones_aplicadas','modalidades','estados_enfrentamiento',
                    'conceptos_puntuacion','tipos_accion','reglas_puntuacion_versiones',
                    'reglas_puntuacion_valores','clubes','campeonatos','configuracion','jugadores',
                    'partidos','asistencias','listas_juego','convocatorias','enfrentamientos',
                    'participantes_enfrentamiento','resultados_enfrentamiento','acciones_resultado'))
    union all
    select 3, 'Tablas con RLS activado', '19',
           (select count(*)::text from pg_tables
             where schemaname = 'public' and rowsecurity
               and tablename in ('migraciones_aplicadas','modalidades','estados_enfrentamiento',
                    'conceptos_puntuacion','tipos_accion','reglas_puntuacion_versiones',
                    'reglas_puntuacion_valores','clubes','campeonatos','configuracion','jugadores',
                    'partidos','asistencias','listas_juego','convocatorias','enfrentamientos',
                    'participantes_enfrentamiento','resultados_enfrentamiento','acciones_resultado'))
    union all
    select 4, 'Modalidades (5 ind / 3 duplas / 2 tríos)', 'DUPLA:2x3,INDIVIDUAL:1x5,TRIO:3x2',
           (select string_agg(codigo || ':' || jugadores_por_enfrentamiento || 'x' || enfrentamientos_por_lista, ',' order by codigo)
              from public.modalidades)
    union all
    select 5, 'Enfrentamientos por lista', '10',
           (select sum(enfrentamientos_por_lista)::text from public.modalidades where activo)
    union all
    select 6, 'Posiciones por lista', '17',
           (select sum(enfrentamientos_por_lista * jugadores_por_enfrentamiento)::text from public.modalidades where activo)
    union all
    select 7, 'Estados de enfrentamiento', 'DISPUTADO,NO_DISPUTADO_FIN_PARTIDO,PENDIENTE',
           (select string_agg(codigo, ',' order by codigo) from public.estados_enfrentamiento)
    union all
    select 8, 'Solo DISPUTADO cuenta como EJ', 'DISPUTADO',
           (select string_agg(codigo, ',') from public.estados_enfrentamiento where cuenta_como_ej)
    union all
    select 9, 'Tipos de acción positivas', 'CAIDA_RIVAL,CORTO,REVENTON_RIVAL',
           (select string_agg(codigo, ',' order by codigo) from public.tipos_accion where polaridad = 'POSITIVA')
    union all
    select 10, 'Tipos de acción negativas', 'CAIDA_PROPIA,LO_CORTARON,REVENTON_PROPIO',
           (select string_agg(codigo, ',' order by codigo) from public.tipos_accion where polaridad = 'NEGATIVA')
    union all
    select 11, 'Versión de reglas vigente', 'V1',
           (select string_agg(codigo, ',') from public.reglas_puntuacion_versiones where es_vigente)
    union all
    select 12, 'Valores de reglas V1',
           'CAIDA_PROPIA=-1.00,CAIDA_RIVAL=0.50,CONVOCATORIA=0.50,CORTO=1.00,DERROTA=0.00,LO_CORTARON=-0.50,REVENTON_PROPIO=-0.70,REVENTON_RIVAL=0.50,VICTORIA=1.00',
           (select string_agg(r.concepto_codigo || '=' || r.valor, ',' order by r.concepto_codigo)
              from public.reglas_puntuacion_valores r
              join public.reglas_puntuacion_versiones v on v.id = r.regla_version_id
             where v.codigo = 'V1')
    union all
    select 13, 'V1 tiene valor para todos los conceptos', '0',
           (select count(*)::text from public.conceptos_puntuacion c
             where not exists (select 1 from public.reglas_puntuacion_valores r
                                 join public.reglas_puntuacion_versiones v on v.id = r.regla_version_id
                                where v.codigo = 'V1' and r.concepto_codigo = c.codigo))
    union all
    select 14, 'Signo de acciones coherente con polaridad', '0',
           (select count(*)::text from public.tipos_accion t
              join public.reglas_puntuacion_valores r on r.concepto_codigo = t.codigo
             where (t.polaridad = 'POSITIVA' and r.valor < 0)
                or (t.polaridad = 'NEGATIVA' and r.valor > 0))
    union all
    select 15, 'Configuración inicial',
           'minimo_ej_ranking_porcentual=5,permite_jugador_repetido_en_lista=false',
           (select string_agg(clave || '=' || valor::text, ',' order by clave)
              from public.configuracion where campeonato_id is null and club_id is null)
    union all
    select 16, 'Club gestionado', 'RAYO',
           (select string_agg(nombre_corto, ',') from public.clubes where es_gestionado)
    union all
    select 17, 'Índice: un resultado vigente por enfrentamiento', '1',
           (select count(*)::text from pg_indexes
             where schemaname = 'public' and indexname = 'uq_resultados_un_vigente')
    union all
    select 18, 'Trigger: copia de puntaje objetivo', '1',
           (select count(*)::text from pg_trigger
             where tgname = 'trg_partidos_fijar_puntaje_objetivo' and not tgisinternal)
    union all
    select 19, 'Triggers updated_at', '9',
           (select count(*)::text from pg_trigger
             where tgname like 'trg\_%\_updated\_at' and not tgisinternal
               and tgrelid::regclass::text in ('clubes', 'campeonatos', 'configuracion', 'jugadores', 'partidos',
                    'asistencias', 'listas_juego', 'convocatorias', 'enfrentamientos'))
    union all
    select 20, 'Convocatoria única histórica (UNIQUE lista+jugador, sin filtro)', 'lista_id,jugador_id',
           (select string_agg(a.attname, ',' order by k.ord)
              from pg_constraint c
              cross join lateral unnest(c.conkey) with ordinality as k(attnum, ord)
              join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
             where c.conname = 'uq_convocatorias_lista_jugador' and c.contype = 'u')
    union all
    select 21, 'Trigger: coherencia jugador/club en convocatoria', '1',
           (select count(*)::text from pg_trigger
             where tgname = 'trg_convocatorias_coherencia_jugador' and not tgisinternal)
)
select n, chequeo, esperado, obtenido, (esperado = obtenido) as ok
  from chequeos
 order by n;
