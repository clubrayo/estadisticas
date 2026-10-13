-- =====================================================================
-- MIGRACIÓN 006 — RANKING GENERAL
-- Sistema de Gestión y Estadísticas de Juego — CLUB RAYO
-- Fase 12 (sección 32).
--
-- Una fila por jugador con asistencia, convocatorias, EJ/EG/EP, %, acciones y
-- puntaje separado por componente. Se calcula sobre las vistas de la
-- migración 005 (mismas exclusiones: partidos y campeonatos cancelados) y
-- respeta RLS (cada usuario ve su club).
--   p_campeonato_id nulo = histórico.
-- El mínimo de EJ para los rankings porcentuales se lee de la tabla
-- configuracion (clave minimo_ej_ranking_porcentual).
--
-- Ejecutar UNA sola vez, después de la migración 005.
-- =====================================================================

begin;

do $$
begin
    if not exists (select 1 from public.migraciones_aplicadas where version = '005') then
        raise exception 'Falta aplicar la migración 005. No se realizaron cambios.';
    end if;
    if exists (select 1 from public.migraciones_aplicadas where version = '006') then
        raise exception 'La migración 006 ya fue aplicada anteriormente. No se realizaron cambios.';
    end if;
end $$;

create function public.ranking_jugadores(p_campeonato_id uuid default null)
returns table (
    jugador_id          uuid,
    jugador             text,
    apodo               text,
    estado              text,
    asistencias         integer,
    partidos            integer,
    convocatorias       integer,
    ej                  integer,
    eg                  integer,
    ep                  integer,
    porcentaje          numeric,
    cortes              integer,
    caidas_rival        integer,
    reventones_rival    integer,
    veces_cortado       integer,
    caidas_propias      integer,
    reventones_propios  integer,
    puntos_convocatoria numeric,
    puntos_resultado    numeric,
    puntos_positivos    numeric,
    puntos_negativos    numeric,
    puntos_acciones     numeric,
    puntos_total        numeric)
language sql stable set search_path = ''
as $$
    with asis as (
        select a.jugador_id,
               count(*) as partidos,
               count(*) filter (where a.estado = 'PRESENTE') as presentes
          from public.v_est_asistencia a
         where p_campeonato_id is null or a.campeonato_id = p_campeonato_id
         group by a.jugador_id),
    conv as (
        select c.jugador_id, count(*) as n, sum(c.puntos) as puntos
          from public.v_est_convocatorias c
         where p_campeonato_id is null or c.campeonato_id = p_campeonato_id
         group by c.jugador_id),
    part as (
        select p.jugador_id,
               count(*) filter (where p.jugado)                as ej,
               count(*) filter (where p.resultado = 'GANADO')  as eg,
               count(*) filter (where p.resultado = 'PERDIDO') as ep,
               sum(p.cortes)             as cortes,
               sum(p.caidas_rival)       as caidas_rival,
               sum(p.reventones_rival)   as reventones_rival,
               sum(p.veces_cortado)      as veces_cortado,
               sum(p.caidas_propias)     as caidas_propias,
               sum(p.reventones_propios) as reventones_propios,
               sum(p.puntos_resultado)   as puntos_resultado,
               sum(p.puntos_positivos)   as puntos_positivos,
               sum(p.puntos_negativos)   as puntos_negativos
          from public.v_est_participaciones p
         where p_campeonato_id is null or p.campeonato_id = p_campeonato_id
         group by p.jugador_id),
    ids as (
        select jugador_id from asis
        union select jugador_id from conv
        union select jugador_id from part)
    select j.id,
           j.nombre_completo,
           j.apodo,
           j.estado,
           coalesce(a.presentes, 0)::integer,
           coalesce(a.partidos, 0)::integer,
           coalesce(c.n, 0)::integer,
           coalesce(p.ej, 0)::integer,
           coalesce(p.eg, 0)::integer,
           coalesce(p.ep, 0)::integer,
           round(100.0 * p.eg / nullif(p.ej, 0), 1),
           coalesce(p.cortes, 0)::integer,
           coalesce(p.caidas_rival, 0)::integer,
           coalesce(p.reventones_rival, 0)::integer,
           coalesce(p.veces_cortado, 0)::integer,
           coalesce(p.caidas_propias, 0)::integer,
           coalesce(p.reventones_propios, 0)::integer,
           coalesce(c.puntos, 0),
           coalesce(p.puntos_resultado, 0),
           coalesce(p.puntos_positivos, 0),
           coalesce(p.puntos_negativos, 0),
           coalesce(p.puntos_positivos, 0) + coalesce(p.puntos_negativos, 0),
           coalesce(c.puntos, 0) + coalesce(p.puntos_resultado, 0)
             + coalesce(p.puntos_positivos, 0) + coalesce(p.puntos_negativos, 0)
      from ids
      join public.jugadores j on j.id = ids.jugador_id
      left join asis a on a.jugador_id = ids.jugador_id
      left join conv c on c.jugador_id = ids.jugador_id
      left join part p on p.jugador_id = ids.jugador_id
     order by 23 desc, 9 desc, 2;
$$;

revoke all on function public.ranking_jugadores(uuid) from public, anon;
grant execute on function public.ranking_jugadores(uuid) to authenticated;

insert into public.migraciones_aplicadas (version, descripcion)
values ('006', 'Ranking general de jugadores por campeonato o histórico');

commit;
