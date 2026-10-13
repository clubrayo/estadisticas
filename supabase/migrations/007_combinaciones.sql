-- =====================================================================
-- MIGRACIÓN 007 — ESTADÍSTICAS DE DUPLAS Y TRÍOS (COMBINACIONES)
-- Sistema de Gestión y Estadísticas de Juego — CLUB RAYO
-- Fase 13 (sección 31).
--
-- Una combinación es el conjunto de jugadores que jugó junto un mismo
-- enfrentamiento. El orden de las posiciones (A, B, C) no importa: Víctor +
-- Antonio es la misma dupla que Antonio + Víctor.
-- Se calcula sobre v_est_participaciones (migración 005), con sus mismas
-- exclusiones (partidos y campeonatos cancelados) y respetando RLS.
--
-- Ejecutar UNA sola vez, después de la migración 006.
-- =====================================================================

begin;

do $$
begin
    if not exists (select 1 from public.migraciones_aplicadas where version = '006') then
        raise exception 'Falta aplicar la migración 006. No se realizaron cambios.';
    end if;
    if exists (select 1 from public.migraciones_aplicadas where version = '007') then
        raise exception 'La migración 007 ya fue aplicada anteriormente. No se realizaron cambios.';
    end if;
end $$;

-- Una fila por enfrentamiento de dupla o trío, con sus integrantes ordenados.
create view public.v_est_combinaciones
with (security_invoker = true) as
select p.enfrentamiento_id,
       p.modalidad_codigo,
       p.partido_id,
       p.campeonato_id,
       p.club_id,
       p.fecha,
       array_agg(p.jugador_id order by p.jugador_id) as integrantes,
       bool_and(p.jugado)                             as jugado,
       min(p.resultado)                               as resultado,
       sum(p.cortes)                                  as cortes,
       sum(p.puntos_positivos + p.puntos_negativos)   as puntos_acciones
  from public.v_est_participaciones p
 group by p.enfrentamiento_id, p.modalidad_codigo, p.partido_id, p.campeonato_id, p.club_id, p.fecha
having count(*) > 1;

comment on view public.v_est_combinaciones is
    'Duplas y tríos: una fila por enfrentamiento con el conjunto ordenado de sus integrantes.';

-- Rendimiento de cada combinación de una modalidad (DUPLA o TRIO).
-- p_campeonato_id nulo = histórico. Solo combinaciones con al menos un EJ.
create function public.combinaciones(p_modalidad text, p_campeonato_id uuid default null)
returns table (
    integrantes     uuid[],
    nombres         text[],
    ej              integer,
    eg              integer,
    ep              integer,
    porcentaje      numeric,
    cortes          integer,
    puntos_acciones numeric)
language sql stable set search_path = ''
as $$
    -- integrantes y nombres van en el mismo orden (alfabético por nombre).
    select (select array_agg(j.id order by j.nombre_completo, j.id)
              from public.jugadores j where j.id = any (c.integrantes)),
           (select array_agg(j.nombre_completo order by j.nombre_completo, j.id)
              from public.jugadores j where j.id = any (c.integrantes)),
           count(*) filter (where c.jugado)::integer,
           count(*) filter (where c.resultado = 'GANADO')::integer,
           count(*) filter (where c.resultado = 'PERDIDO')::integer,
           round(100.0 * count(*) filter (where c.resultado = 'GANADO') / nullif(count(*) filter (where c.jugado), 0), 1),
           coalesce(sum(c.cortes) filter (where c.jugado), 0)::integer,
           coalesce(sum(c.puntos_acciones) filter (where c.jugado), 0)
      from public.v_est_combinaciones c
     where c.modalidad_codigo = p_modalidad
       and (p_campeonato_id is null or c.campeonato_id = p_campeonato_id)
     group by c.integrantes
    having count(*) filter (where c.jugado) > 0
     order by 6 desc nulls last, 4 desc, 3 desc, 2;
$$;

revoke all on public.v_est_combinaciones from public, anon;
grant select on public.v_est_combinaciones to authenticated;
revoke all on function public.combinaciones(text, uuid) from public, anon;
grant execute on function public.combinaciones(text, uuid) to authenticated;

insert into public.migraciones_aplicadas (version, descripcion)
values ('007', 'Estadísticas de combinaciones: mejores duplas y tríos');

commit;
