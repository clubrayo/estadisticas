-- =====================================================================
-- MIGRACIÓN 005 — ESTADÍSTICAS INDIVIDUALES
-- Sistema de Gestión y Estadísticas de Juego — CLUB RAYO
-- Fase 11 (secciones 29, 30, 34 y 38).
--
-- Todo se CALCULA a partir de los registros (no se guardan totales). Los
-- puntajes salen de los snapshots guardados en cada registro, de modo que un
-- cambio futuro de reglas no altera estadísticas pasadas.
--
-- Reglas de cómputo:
--   - Se excluyen los partidos CANCELADOS y los partidos de campeonatos
--     CANCELADOS (decisión 2026-10-13).
--   - Convocatoria: convocatorias VIGENTES de listas oficiales (no BORRADOR).
--   - EJ / EG / EP: solo enfrentamientos que cuentan como jugados (DISPUTADO),
--     incluidos los resueltos por secretaría. NO_DISPUTADO_FIN_PARTIDO no cuenta.
--   - Puntaje = convocatoria + resultado + acciones positivas + penalizaciones.
--   - % asistencia = presentes / registros de asistencia (JUSTIFICADO cuenta
--     como inasistencia). % victorias = EG / EJ.
--
-- Seguridad: las vistas usan security_invoker, por lo que aplican las mismas
-- políticas RLS que las tablas (cada usuario ve solo su club).
--
-- Ejecutar UNA sola vez, después de la migración 004.
-- =====================================================================

begin;

do $$
begin
    if not exists (select 1 from public.migraciones_aplicadas where version = '004') then
        raise exception 'Falta aplicar la migración 004. No se realizaron cambios.';
    end if;
    if exists (select 1 from public.migraciones_aplicadas where version = '005') then
        raise exception 'La migración 005 ya fue aplicada anteriormente. No se realizaron cambios.';
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. VISTAS BASE
-- ---------------------------------------------------------------------

-- Partidos que cuentan para estadísticas.
create view public.v_est_partidos
with (security_invoker = true) as
select p.id            as partido_id,
       p.campeonato_id,
       ca.nombre       as campeonato,
       p.fecha,
       p.club_local_id,
       p.club_visitante_id,
       p.estado
  from public.partidos p
  join public.campeonatos ca on ca.id = p.campeonato_id
 where p.estado <> 'CANCELADO'
   and ca.estado <> 'CANCELADO';

comment on view public.v_est_partidos is
    'Partidos considerados en estadísticas: excluye partidos y campeonatos cancelados.';

-- Una fila por registro de asistencia.
create view public.v_est_asistencia
with (security_invoker = true) as
select a.jugador_id,
       a.partido_id,
       vp.campeonato_id,
       vp.fecha,
       a.estado
  from public.asistencias a
  join public.v_est_partidos vp on vp.partido_id = a.partido_id;

-- Una fila por convocatoria oficial (una por jugador y lista).
create view public.v_est_convocatorias
with (security_invoker = true) as
select c.id         as convocatoria_id,
       c.jugador_id,
       c.club_id,
       l.partido_id,
       vp.campeonato_id,
       l.id         as lista_id,
       l.numero     as lista_numero,
       c.puntos
  from public.convocatorias c
  join public.listas_juego l on l.id = c.lista_id and l.estado <> 'BORRADOR'
  join public.v_est_partidos vp on vp.partido_id = l.partido_id
 where c.estado = 'VIGENTE';

-- Una fila por participación de un jugador en un enfrentamiento de una lista oficial.
create view public.v_est_participaciones
with (security_invoker = true) as
select pe.id                        as participante_id,
       c.jugador_id,
       c.club_id,
       vp.partido_id,
       vp.campeonato_id,
       vp.campeonato,
       vp.fecha,
       rv.id                        as rival_id,
       rv.nombre_corto              as rival,
       l.id                         as lista_id,
       l.numero                     as lista_numero,
       e.id                         as enfrentamiento_id,
       e.modalidad_codigo,
       e.numero                     as enfrentamiento_numero,
       e.orden_juego,
       e.estado_codigo,
       ee.cuenta_como_ej            as jugado,
       case when ee.cuenta_como_ej then
            case when r.ganador_club_id = c.club_id then 'GANADO' else 'PERDIDO' end
       end                          as resultado,
       coalesce(r.por_secretaria, false) as por_secretaria,
       case when ee.cuenta_como_ej then
            case when r.ganador_club_id = c.club_id then r.puntos_victoria else r.puntos_derrota end
            else 0 end              as puntos_resultado,
       coalesce(ac.puntos_positivos, 0)   as puntos_positivos,
       coalesce(ac.puntos_negativos, 0)   as puntos_negativos,
       coalesce(ac.cortes, 0)             as cortes,
       coalesce(ac.caidas_rival, 0)       as caidas_rival,
       coalesce(ac.reventones_rival, 0)   as reventones_rival,
       coalesce(ac.veces_cortado, 0)      as veces_cortado,
       coalesce(ac.caidas_propias, 0)     as caidas_propias,
       coalesce(ac.reventones_propios, 0) as reventones_propios,
       coalesce(ac.acciones, '{}')        as acciones,
       coalesce((select array_agg(j2.nombre_completo order by pe2.posicion)
                   from public.participantes_enfrentamiento pe2
                   join public.convocatorias c2 on c2.id = pe2.convocatoria_id
                   join public.jugadores j2 on j2.id = c2.jugador_id
                  where pe2.enfrentamiento_id = e.id and pe2.id <> pe.id), '{}') as companeros
  from public.participantes_enfrentamiento pe
  join public.convocatorias c on c.id = pe.convocatoria_id and c.estado = 'VIGENTE'
  join public.listas_juego l on l.id = pe.lista_id and l.estado <> 'BORRADOR'
  join public.v_est_partidos vp on vp.partido_id = l.partido_id
  join public.clubes rv on rv.id = case when vp.club_local_id = c.club_id then vp.club_visitante_id else vp.club_local_id end
  join public.enfrentamientos e on e.id = pe.enfrentamiento_id
  join public.estados_enfrentamiento ee on ee.codigo = e.estado_codigo
  left join public.resultados_enfrentamiento r
         on r.enfrentamiento_id = e.id and r.vigente and ee.cuenta_como_ej
  left join lateral (
        select sum(a.puntos) filter (where t.polaridad = 'POSITIVA')      as puntos_positivos,
               sum(a.puntos) filter (where t.polaridad = 'NEGATIVA')      as puntos_negativos,
               count(*) filter (where a.tipo_accion_codigo = 'CORTO')           as cortes,
               count(*) filter (where a.tipo_accion_codigo = 'CAIDA_RIVAL')     as caidas_rival,
               count(*) filter (where a.tipo_accion_codigo = 'REVENTON_RIVAL')  as reventones_rival,
               count(*) filter (where a.tipo_accion_codigo = 'LO_CORTARON')     as veces_cortado,
               count(*) filter (where a.tipo_accion_codigo = 'CAIDA_PROPIA')    as caidas_propias,
               count(*) filter (where a.tipo_accion_codigo = 'REVENTON_PROPIO') as reventones_propios,
               array_agg(a.tipo_accion_codigo order by a.created_at)            as acciones
          from public.acciones_resultado a
          join public.tipos_accion t on t.codigo = a.tipo_accion_codigo
         where a.resultado_id = r.id and a.participante_id = pe.id
       ) ac on r.id is not null;

comment on view public.v_est_participaciones is
    'Una fila por jugador y enfrentamiento de listas oficiales, con resultado, puntajes (snapshots) y acciones.';

-- ---------------------------------------------------------------------
-- 2. FICHA ESTADÍSTICA DEL JUGADOR (secciones 29 y 30)
-- p_campeonato_id nulo = histórico completo.
-- ---------------------------------------------------------------------

create function public.estadisticas_jugador(p_jugador_id uuid, p_campeonato_id uuid default null)
returns jsonb
language sql stable set search_path = ''
as $$
    with asis as (
        select * from public.v_est_asistencia
         where jugador_id = p_jugador_id and (p_campeonato_id is null or campeonato_id = p_campeonato_id)),
    conv as (
        select * from public.v_est_convocatorias
         where jugador_id = p_jugador_id and (p_campeonato_id is null or campeonato_id = p_campeonato_id)),
    part as (
        select * from public.v_est_participaciones
         where jugador_id = p_jugador_id and (p_campeonato_id is null or campeonato_id = p_campeonato_id)),
    jug as (select * from part where jugado)
    select jsonb_build_object(
        'asistencia', (
            select jsonb_build_object(
                'partidos',     count(*),
                'presentes',    count(*) filter (where estado = 'PRESENTE'),
                'ausentes',     count(*) filter (where estado = 'AUSENTE'),
                'justificados', count(*) filter (where estado = 'JUSTIFICADO'),
                'porcentaje',   round(100.0 * count(*) filter (where estado = 'PRESENTE') / nullif(count(*), 0), 1))
              from asis),
        'convocatorias', (
            select jsonb_build_object('listas', count(*), 'puntos', coalesce(sum(puntos), 0))
              from conv),
        'participacion', (
            select jsonb_build_object(
                'ej',         count(*),
                'eg',         count(*) filter (where resultado = 'GANADO'),
                'ep',         count(*) filter (where resultado = 'PERDIDO'),
                'porcentaje', round(100.0 * count(*) filter (where resultado = 'GANADO') / nullif(count(*), 0), 1))
              from jug),
        'por_modalidad', (
            select coalesce(jsonb_agg(jsonb_build_object(
                       'modalidad', m.codigo, 'nombre', m.nombre,
                       'ej', x.ej, 'eg', x.eg, 'ep', x.ep, 'porcentaje', x.porcentaje) order by m.orden), '[]'::jsonb)
              from public.modalidades m
             cross join lateral (
                   select count(*) as ej,
                          count(*) filter (where j.resultado = 'GANADO') as eg,
                          count(*) filter (where j.resultado = 'PERDIDO') as ep,
                          round(100.0 * count(*) filter (where j.resultado = 'GANADO') / nullif(count(*), 0), 1) as porcentaje
                     from jug j where j.modalidad_codigo = m.codigo) x
             where m.activo),
        'acciones', (
            select jsonb_build_object(
                'cortes',             coalesce(sum(cortes), 0),
                'caidas_rival',       coalesce(sum(caidas_rival), 0),
                'reventones_rival',   coalesce(sum(reventones_rival), 0),
                'veces_cortado',      coalesce(sum(veces_cortado), 0),
                'caidas_propias',     coalesce(sum(caidas_propias), 0),
                'reventones_propios', coalesce(sum(reventones_propios), 0))
              from part),
        'puntos', (
            select jsonb_build_object(
                'convocatoria',   c.puntos,
                'resultado',      r.resultado,
                'positivas',      r.positivas,
                'penalizaciones', r.penalizaciones,
                'total',          c.puntos + r.resultado + r.positivas + r.penalizaciones)
              from (select coalesce(sum(puntos), 0) as puntos from conv) c,
                   (select coalesce(sum(puntos_resultado), 0) as resultado,
                           coalesce(sum(puntos_positivos), 0) as positivas,
                           coalesce(sum(puntos_negativos), 0) as penalizaciones
                      from part) r));
$$;

-- ---------------------------------------------------------------------
-- 3. PRIVILEGIOS
-- ---------------------------------------------------------------------

revoke all on public.v_est_partidos, public.v_est_asistencia, public.v_est_convocatorias, public.v_est_participaciones
    from public, anon;
grant select on public.v_est_partidos, public.v_est_asistencia, public.v_est_convocatorias, public.v_est_participaciones
    to authenticated;

revoke all on function public.estadisticas_jugador(uuid, uuid) from public, anon;
grant execute on function public.estadisticas_jugador(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4. REGISTRO DE LA MIGRACIÓN
-- ---------------------------------------------------------------------

insert into public.migraciones_aplicadas (version, descripcion)
values ('005', 'Estadísticas individuales: vistas de asistencia, convocatorias y participaciones, y ficha del jugador');

commit;
