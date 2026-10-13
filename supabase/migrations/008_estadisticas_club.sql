-- =====================================================================
-- MIGRACIÓN 008 — ESTADÍSTICAS DEL CLUB (DASHBOARD)
-- Sistema de Gestión y Estadísticas de Juego — CLUB RAYO
-- Fase 14 (sección 33).
--
-- Reglas de cómputo (mismas exclusiones de la migración 005: no cuentan
-- partidos ni campeonatos CANCELADOS):
--   - Jugadores activos: jugadores del club en estado ACTIVO hoy (no depende
--     del campeonato elegido).
--   - Partidos jugados: FINALIZADO o EN_REVISION (tienen ganador).
--     Ganados / perdidos según el ganador. Los EN_CURSO y SUSPENDIDO se
--     informan aparte como "en curso".
--   - Efectividad: partidos ganados / partidos jugados.
--   - Listas disputadas: listas oficiales con al menos un enfrentamiento jugado.
--   - Puntos oficiales: puntos del marcador del club (a favor y en contra),
--     incluidos los partidos en curso.
--   - Individuales / duplas / tríos: enfrentamientos jugados y ganados por el
--     club en cada modalidad (uno por enfrentamiento, no por jugador).
--   - Acciones: totales de todos los jugadores del club.
--
-- Seguridad: función SQL sin security definer: se aplican las políticas RLS,
-- por lo que un usuario solo obtiene datos de los clubes que puede ver.
--
-- Ejecutar UNA sola vez, después de la migración 007.
-- =====================================================================

begin;

do $$
begin
    if not exists (select 1 from public.migraciones_aplicadas where version = '007') then
        raise exception 'Falta aplicar la migración 007. No se realizaron cambios.';
    end if;
    if exists (select 1 from public.migraciones_aplicadas where version = '008') then
        raise exception 'La migración 008 ya fue aplicada anteriormente. No se realizaron cambios.';
    end if;
end $$;

-- p_campeonato_id nulo = histórico.
create function public.estadisticas_club(p_club_id uuid, p_campeonato_id uuid default null)
returns jsonb
language sql stable set search_path = ''
as $$
    with par as (
        select vp.estado,
               case when p.club_local_id = p_club_id then p.puntaje_local else p.puntaje_visitante end as a_favor,
               case when p.club_local_id = p_club_id then p.puntaje_visitante else p.puntaje_local end as en_contra,
               p.ganador_club_id
          from public.v_est_partidos vp
          join public.partidos p on p.id = vp.partido_id
         where p_club_id in (vp.club_local_id, vp.club_visitante_id)
           and (p_campeonato_id is null or vp.campeonato_id = p_campeonato_id)),
    part as (
        select * from public.v_est_participaciones
         where club_id = p_club_id
           and (p_campeonato_id is null or campeonato_id = p_campeonato_id)),
    -- Una fila por enfrentamiento del club.
    enf as (
        select enfrentamiento_id, modalidad_codigo, lista_id,
               bool_and(jugado) as jugado, min(resultado) as resultado
          from part
         group by enfrentamiento_id, modalidad_codigo, lista_id)
    select jsonb_build_object(
        'jugadores_activos', (
            select count(*) from public.jugadores
             where club_id = p_club_id and estado = 'ACTIVO'),
        'partidos', (
            select jsonb_build_object(
                'jugados',     count(*) filter (where estado in ('FINALIZADO', 'EN_REVISION')),
                'ganados',     count(*) filter (where estado in ('FINALIZADO', 'EN_REVISION') and ganador_club_id = p_club_id),
                'perdidos',    count(*) filter (where estado in ('FINALIZADO', 'EN_REVISION') and ganador_club_id <> p_club_id),
                'en_curso',    count(*) filter (where estado in ('EN_CURSO', 'SUSPENDIDO')),
                'efectividad', round(100.0 * count(*) filter (where estado in ('FINALIZADO', 'EN_REVISION') and ganador_club_id = p_club_id)
                                     / nullif(count(*) filter (where estado in ('FINALIZADO', 'EN_REVISION')), 0), 1))
              from par),
        'listas_disputadas', (
            select count(distinct lista_id) from enf where jugado),
        'puntos', (
            select jsonb_build_object('a_favor', coalesce(sum(a_favor), 0), 'en_contra', coalesce(sum(en_contra), 0))
              from par),
        'por_modalidad', (
            select coalesce(jsonb_agg(jsonb_build_object(
                       'modalidad', m.codigo, 'nombre', m.nombre,
                       'ej', x.ej, 'eg', x.eg, 'ep', x.ej - x.eg,
                       'porcentaje', round(100.0 * x.eg / nullif(x.ej, 0), 1)) order by m.orden), '[]'::jsonb)
              from public.modalidades m
             cross join lateral (
                   select count(*) filter (where e.jugado) as ej,
                          count(*) filter (where e.resultado = 'GANADO') as eg
                     from enf e where e.modalidad_codigo = m.codigo) x),
        'acciones', (
            select jsonb_build_object(
                'cortes',             coalesce(sum(cortes), 0),
                'veces_cortado',      coalesce(sum(veces_cortado), 0),
                'caidas_rival',       coalesce(sum(caidas_rival), 0),
                'caidas_propias',     coalesce(sum(caidas_propias), 0),
                'reventones_rival',   coalesce(sum(reventones_rival), 0),
                'reventones_propios', coalesce(sum(reventones_propios), 0))
              from part where jugado));
$$;

comment on function public.estadisticas_club(uuid, uuid) is
    'Dashboard del club (sección 33). Campeonato nulo = histórico. Respeta RLS.';

revoke all on function public.estadisticas_club(uuid, uuid) from public, anon;
grant execute on function public.estadisticas_club(uuid, uuid) to authenticated;

insert into public.migraciones_aplicadas (version, descripcion)
values ('008', 'Estadísticas del club: dashboard');

commit;
