-- =====================================================================
-- MIGRACIÓN 004 — ACCIONES POR INTEGRANTE Y RESULTADO POR SECRETARÍA
-- Sistema de Gestión y Estadísticas de Juego — CLUB RAYO
-- Fase 0.2 (aprobada 2026-10-12). Reemplaza la regla V1 "un enfrentamiento =
-- una acción determinante".
--
-- Reglas nuevas (cada volantín cae una sola vez; cada volantín rival
-- eliminado se atribuye a un jugador):
--   Por jugador y enfrentamiento:
--     - una o varias acciones; cada acción suma o resta su puntaje;
--     - como máximo N acciones (N = 1 individual, 2 dupla, 3 trío);
--     - como máximo UNA acción negativa.
--   Individual: exactamente una acción (positiva si gana, negativa si pierde).
--   Dupla/trío PERDIDO: cada integrante exactamente una negativa;
--                       positivas < N.
--   Dupla/trío GANADO:  al menos una positiva y como máximo N;
--                       no todos los integrantes con negativa.
--   Por secretaría: resultado oficial SIN acciones y con motivo; solo
--                   DIRECTIVA o ADMINISTRADOR; cuenta como EJ/EG/EP.
--
-- Sin cambios: punto del club (1 por enfrentamiento), +1 por victoria a cada
-- integrante, convocatoria, cierre a 30, P-1, snapshots y auditoría.
--
-- Datos existentes: no se modifican. Los resultados registrados con la regla
-- anterior que no cumplan la nueva se informan como "acciones incompletas"
-- (verificar_partido) y se completan con corregir_resultado.
--
-- Cambian las firmas de registrar_resultado y corregir_resultado: reciben
-- p_acciones jsonb = [{"jugador_id": "...", "tipo_accion": "CORTO"}, ...].
--
-- Ejecutar UNA sola vez, después de la migración 003.
-- =====================================================================

begin;

do $$
begin
    if not exists (select 1 from public.migraciones_aplicadas where version = '003') then
        raise exception 'Falta aplicar la migración 003. No se realizaron cambios.';
    end if;
    if exists (select 1 from public.migraciones_aplicadas where version = '004') then
        raise exception 'La migración 004 ya fue aplicada anteriormente. No se realizaron cambios.';
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. ESQUEMA
-- ---------------------------------------------------------------------

-- Resultado decidido por secretaría (sin acciones, con motivo).
alter table public.resultados_enfrentamiento
    add column por_secretaria    boolean not null default false,
    add column motivo_secretaria text,
    add constraint ck_resultados_secretaria
        check (por_secretaria = (nullif(btrim(motivo_secretaria), '') is not null));

-- Varias acciones por resultado.
alter table public.acciones_resultado drop constraint uq_acciones_resultado_v1;
create index ix_acciones_resultado on public.acciones_resultado (resultado_id);

-- ---------------------------------------------------------------------
-- 2. REGLAS DE ACCIONES
-- ---------------------------------------------------------------------

-- Devuelve el primer incumplimiento de las reglas de acciones de un resultado,
-- o null si es válido.
create function privado.problemas_acciones(p_resultado uuid)
returns text
language plpgsql stable set search_path = ''
as $$
declare
    v_res            public.resultados_enfrentamiento;
    v_cupo           integer;
    v_integrantes    integer;
    v_club           text;
    v_gano           boolean;
    v_total          integer;
    v_positivas      integer;
    v_con_negativa   integer;
    v_max_jugador    integer;
    v_max_neg_jugador integer;
begin
    select * into v_res from public.resultados_enfrentamiento where id = p_resultado;
    if not found then
        return null;
    end if;

    select m.jugadores_por_enfrentamiento into v_cupo
      from public.enfrentamientos e
      join public.modalidades m on m.codigo = e.modalidad_codigo
     where e.id = v_res.enfrentamiento_id;

    select count(*), min(c.club_id::text) into v_integrantes, v_club
      from public.participantes_enfrentamiento pe
      join public.convocatorias c on c.id = pe.convocatoria_id
     where pe.enfrentamiento_id = v_res.enfrentamiento_id;
    v_gano := v_res.ganador_club_id::text = v_club;

    select count(*), count(*) filter (where t.polaridad = 'POSITIVA')
      into v_total, v_positivas
      from public.acciones_resultado a
      join public.tipos_accion t on t.codigo = a.tipo_accion_codigo
     where a.resultado_id = p_resultado;

    if v_res.por_secretaria then
        return case when v_total > 0 then 'Un resultado por secretaría no lleva acciones.' end;
    end if;

    select coalesce(max(x.n), 0), coalesce(max(x.neg), 0), count(*) filter (where x.neg > 0)
      into v_max_jugador, v_max_neg_jugador, v_con_negativa
      from (select a.participante_id,
                   count(*) as n,
                   count(*) filter (where t.polaridad = 'NEGATIVA') as neg
              from public.acciones_resultado a
              join public.tipos_accion t on t.codigo = a.tipo_accion_codigo
             where a.resultado_id = p_resultado
             group by a.participante_id) x;

    if v_max_jugador > v_cupo then
        return format('Un jugador puede tener como máximo %s acción(es) en este enfrentamiento.', v_cupo);
    end if;
    if v_max_neg_jugador > 1 then
        return 'Un jugador puede tener como máximo una acción negativa: su volantín cae una sola vez.';
    end if;

    if v_cupo = 1 then
        if v_total <> 1 then
            return 'En un individual se registra exactamente una causa.';
        elsif v_gano and v_positivas <> 1 then
            return 'Una victoria individual requiere una causa positiva (Cortó, Caída del rival o Reventón rival).';
        elsif not v_gano and v_positivas <> 0 then
            return 'Una derrota individual requiere una causa negativa (Lo cortaron, Caída propia o Reventón propio).';
        end if;
        return null;
    end if;

    if v_gano then
        if v_positivas < 1 then
            return 'Una victoria requiere al menos una acción positiva de algún integrante.';
        elsif v_positivas > v_cupo then
            return format('Como máximo %s acciones positivas: el rival tiene %s volantines.', v_cupo, v_cupo);
        elsif v_con_negativa >= v_integrantes then
            return 'Si todos los integrantes cayeron, el equipo no pudo ganar.';
        end if;
    else
        if v_con_negativa <> v_integrantes then
            return 'En una derrota, cada integrante debe tener su acción negativa.';
        elsif v_positivas >= v_cupo then
            return 'Si se eliminaron todos los volantines rivales, el equipo no pudo perder.';
        end if;
    end if;
    return null;
end;
$$;

-- Firma comparable de un conjunto de acciones (para respuestas idempotentes).
create function privado.firma_acciones(p_resultado uuid)
returns text
language sql stable set search_path = ''
as $$
    select coalesce(string_agg(a.participante_id::text || ':' || a.tipo_accion_codigo, ','
                               order by a.participante_id::text, a.tipo_accion_codigo), '')
      from public.acciones_resultado a
     where a.resultado_id = p_resultado;
$$;

create function privado.firma_entrada(p_enfrentamiento uuid, p_acciones jsonb)
returns text
language sql stable set search_path = ''
as $$
    select coalesce(string_agg(coalesce(privado.participante_de(p_enfrentamiento, x.jugador_id)::text, '?')
                               || ':' || x.tipo_accion, ','
                               order by coalesce(privado.participante_de(p_enfrentamiento, x.jugador_id)::text, '?'),
                                        x.tipo_accion), '')
      from jsonb_to_recordset(p_acciones) as x(jugador_id uuid, tipo_accion text);
$$;

-- Inserta las acciones de un resultado (con su puntaje) y valida las reglas.
create function privado.insertar_acciones(p_resultado uuid, p_enfrentamiento uuid, p_regla uuid, p_acciones jsonb)
returns void
language plpgsql set search_path = ''
as $$
declare
    r         record;
    v_part    uuid;
    v_problema text;
begin
    if p_acciones is null or jsonb_typeof(p_acciones) <> 'array' then
        perform privado.error('DATOS_INVALIDOS', 'Las acciones deben enviarse como un arreglo.');
    end if;

    for r in select * from jsonb_to_recordset(p_acciones) as x(jugador_id uuid, tipo_accion text) loop
        v_part := privado.participante_de(p_enfrentamiento, r.jugador_id);
        if v_part is null then
            perform privado.error('JUGADOR_NO_PARTICIPA', 'Un jugador indicado no participa en este enfrentamiento.');
        end if;
        if not exists (select 1 from public.tipos_accion t where t.codigo = r.tipo_accion and t.activo) then
            perform privado.error('TIPO_ACCION_INVALIDO', 'Una causa indicada no existe o no está activa.');
        end if;
        insert into public.acciones_resultado (resultado_id, enfrentamiento_id, participante_id, tipo_accion_codigo, puntos)
        values (p_resultado, p_enfrentamiento, v_part, r.tipo_accion, privado.valor_regla(p_regla, r.tipo_accion));
    end loop;

    v_problema := privado.problemas_acciones(p_resultado);
    if v_problema is not null then
        perform privado.error('ACCIONES_INVALIDAS', v_problema);
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. TRIGGERS
-- ---------------------------------------------------------------------

-- Acción por fila: ahora la polaridad se valida para el conjunto (reglas de
-- arriba). Aquí solo se impide agregar acciones a un resultado no vigente.
create or replace function privado.fn_acciones_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if exists (select 1 from public.resultados_enfrentamiento r where r.id = new.resultado_id and not r.vigente) then
        perform privado.error('RESULTADO_NO_VIGENTE', 'No se agregan acciones a un resultado anulado.');
    end if;
    return new;
end;
$$;

-- Coherencia estructural: DISPUTADO si y solo si hay exactamente un resultado vigente.
create or replace function privado.fn_coherencia_enfrentamiento()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    v_id               uuid := coalesce((to_jsonb(new) ->> 'enfrentamiento_id')::uuid, (to_jsonb(new) ->> 'id')::uuid);
    v_admite_resultado boolean;
    v_vigentes         integer;
begin
    select ee.admite_resultado into v_admite_resultado
      from public.enfrentamientos e
      join public.estados_enfrentamiento ee on ee.codigo = e.estado_codigo
     where e.id = v_id;
    if not found then
        return null;
    end if;

    select count(*) into v_vigentes
      from public.resultados_enfrentamiento r where r.enfrentamiento_id = v_id and r.vigente;

    if v_admite_resultado and v_vigentes <> 1 then
        perform privado.error('INCOHERENCIA_ENFRENTAMIENTO',
            'Un enfrentamiento disputado debe tener exactamente un resultado vigente.');
    elsif not v_admite_resultado and v_vigentes <> 0 then
        perform privado.error('INCOHERENCIA_ENFRENTAMIENTO',
            'Un enfrentamiento no disputado no puede tener resultado vigente.');
    end if;
    return null;
end;
$$;

-- Reglas de acciones de cada resultado NUEVO, verificadas al confirmar la
-- transacción (los resultados anteriores a esta migración no se revalidan).
create function privado.fn_validar_reglas_acciones()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    v_id       uuid := coalesce((to_jsonb(new) ->> 'resultado_id')::uuid, (to_jsonb(new) ->> 'id')::uuid);
    v_problema text;
begin
    if exists (select 1 from public.resultados_enfrentamiento r where r.id = v_id and r.vigente) then
        v_problema := privado.problemas_acciones(v_id);
        if v_problema is not null then
            perform privado.error('ACCIONES_INVALIDAS', v_problema);
        end if;
    end if;
    return null;
end;
$$;

create constraint trigger trg_resultados_reglas_acciones
    after insert on public.resultados_enfrentamiento
    deferrable initially deferred
    for each row execute function privado.fn_validar_reglas_acciones();

create constraint trigger trg_acciones_reglas
    after insert on public.acciones_resultado
    deferrable initially deferred
    for each row execute function privado.fn_validar_reglas_acciones();

-- ---------------------------------------------------------------------
-- 4. VERIFICACIÓN DE PARTIDO (reglas nuevas)
-- ---------------------------------------------------------------------

create or replace function privado.verificar_partido(p_partido uuid)
returns jsonb
language plpgsql stable set search_path = ''
as $$
declare
    v_partido  public.partidos;
    v_a        jsonb;
    v_local    integer;
    v_visit    integer;
    v_prob     text[] := '{}';
begin
    select * into v_partido from public.partidos where id = p_partido;
    if not found then
        return jsonb_build_array('El partido no existe.');
    end if;
    v_a := privado.analizar_secuencia(p_partido);

    select count(*) filter (where r.ganador_club_id = v_partido.club_local_id),
           count(*) filter (where r.ganador_club_id = v_partido.club_visitante_id)
      into v_local, v_visit
      from public.resultados_enfrentamiento r
      join public.enfrentamientos e on e.id = r.enfrentamiento_id
      join public.listas_juego l on l.id = e.lista_id
     where l.partido_id = p_partido and r.vigente and e.estado_codigo = 'DISPUTADO';

    if v_local <> v_partido.puntaje_local or v_visit <> v_partido.puntaje_visitante then
        v_prob := array_append(v_prob, 'El marcador guardado no coincide con los resultados vigentes.');
    end if;

    if v_partido.estado in ('FINALIZADO', 'EN_REVISION') then
        if v_a ->> 'cierre_enfrentamiento_id' is null then
            v_prob := array_append(v_prob, 'Partido cerrado sin punto de cierre.');
        end if;
        if jsonb_array_length(v_a -> 'invalidados') > 0 then
            v_prob := array_append(v_prob, 'Hay enfrentamientos disputados después del punto de cierre.');
        end if;
        if (v_a ->> 'ganador_club_id')::uuid is distinct from v_partido.ganador_club_id then
            v_prob := array_append(v_prob, 'El ganador registrado no coincide con el punto de cierre.');
        end if;
        if exists (select 1 from public.enfrentamientos e join public.listas_juego l on l.id = e.lista_id
                    where l.partido_id = p_partido and e.estado_codigo = 'PENDIENTE') then
            v_prob := array_append(v_prob, 'Quedan enfrentamientos PENDIENTE en un partido cerrado.');
        end if;
    elsif v_partido.estado in ('EN_CURSO', 'SUSPENDIDO') then
        if v_a ->> 'cierre_enfrentamiento_id' is not null then
            v_prob := array_append(v_prob, 'Un club alcanzó el objetivo pero el partido sigue abierto.');
        end if;
        if exists (select 1 from public.enfrentamientos e join public.listas_juego l on l.id = e.lista_id
                    where l.partido_id = p_partido and e.estado_codigo = 'NO_DISPUTADO_FIN_PARTIDO') then
            v_prob := array_append(v_prob, 'Hay enfrentamientos NO_DISPUTADO en un partido abierto.');
        end if;
    end if;

    if exists (
        select 1
          from public.enfrentamientos e
          join public.listas_juego l on l.id = e.lista_id
         where l.partido_id = p_partido
           and ((e.estado_codigo = 'DISPUTADO'
                 and (select count(*) from public.resultados_enfrentamiento r
                       where r.enfrentamiento_id = e.id and r.vigente) <> 1)
             or (e.estado_codigo <> 'DISPUTADO'
                 and exists (select 1 from public.resultados_enfrentamiento r
                              where r.enfrentamiento_id = e.id and r.vigente)))) then
        v_prob := array_append(v_prob, 'Hay enfrentamientos con resultado incoherente.');
    end if;

    if exists (
        select 1
          from public.resultados_enfrentamiento r
          join public.enfrentamientos e on e.id = r.enfrentamiento_id
          join public.listas_juego l on l.id = e.lista_id
         where l.partido_id = p_partido
           and r.vigente
           and e.estado_codigo = 'DISPUTADO'
           and privado.problemas_acciones(r.id) is not null) then
        v_prob := array_append(v_prob, 'Hay enfrentamientos con acciones incompletas o inválidas: complételos con Corregir.');
    end if;

    if exists (
        select 1
          from public.enfrentamientos e1
          join public.listas_juego l1 on l1.id = e1.lista_id
          join public.listas_juego l2 on l2.partido_id = l1.partido_id
          join public.enfrentamientos e2 on e2.lista_id = l2.id
         where l1.partido_id = p_partido
           and e1.estado_codigo = 'PENDIENTE'
           and e2.estado_codigo = 'DISPUTADO'
           and (l2.numero, e2.orden_juego) > (l1.numero, e1.orden_juego)) then
        v_prob := array_append(v_prob, 'Hay enfrentamientos disputados fuera del orden de juego.');
    end if;

    if exists (
        select 1
          from public.listas_juego l
          join public.enfrentamientos e on e.lista_id = l.id
          join public.modalidades m on m.codigo = e.modalidad_codigo
         where l.partido_id = p_partido
           and l.estado <> 'BORRADOR'
           and (select count(*) from public.participantes_enfrentamiento pe
                 where pe.enfrentamiento_id = e.id) <> m.jugadores_por_enfrentamiento) then
        v_prob := array_append(v_prob, 'Hay listas oficiales con composición incompleta.');
    end if;

    if exists (
        select 1
          from public.convocatorias c
          join public.listas_juego l on l.id = c.lista_id
         where l.partido_id = p_partido
           and ((l.estado = 'BORRADOR' and c.estado = 'VIGENTE')
             or (l.estado <> 'BORRADOR' and c.estado = 'PROPUESTA'))) then
        v_prob := array_append(v_prob, 'Hay convocatorias incoherentes con el estado de su lista.');
    end if;

    return to_jsonb(v_prob);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. RPC: REGISTRAR Y CORREGIR CON VARIAS ACCIONES
-- ---------------------------------------------------------------------

drop function public.registrar_resultado(uuid, text, uuid, text, integer);
drop function public.corregir_resultado(uuid, text, uuid, text, text, integer, boolean);
drop function privado.validar_polaridad(text, boolean);

-- p_resultado: 'GANADO' o 'PERDIDO' desde la perspectiva del club gestionado.
-- p_acciones:  [{"jugador_id": "...", "tipo_accion": "CORTO"}, ...]  (vacío si es por secretaría).
-- p_por_secretaria / p_motivo: resultado oficial sin acciones (DIRECTIVA o ADMINISTRADOR).
create function public.registrar_resultado(
    p_enfrentamiento_id uuid,
    p_resultado         text,
    p_acciones          jsonb,
    p_version           integer,
    p_por_secretaria    boolean default false,
    p_motivo            text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_enf        public.enfrentamientos;
    v_lista      public.listas_juego;
    v_partido    public.partidos;
    v_club       uuid;
    v_ganador    uuid;
    v_acciones   jsonb := coalesce(p_acciones, '[]'::jsonb);
    v_secretaria boolean := coalesce(p_por_secretaria, false);
    v_resultado  uuid;
    v_local      smallint;
    v_visitante  smallint;
    v_cierre     boolean;
begin
    select * into v_enf from public.enfrentamientos where id = p_enfrentamiento_id;
    if not found then
        perform privado.error('NO_ENCONTRADO', 'El enfrentamiento no existe.');
    end if;
    select * into v_lista from public.listas_juego where id = v_enf.lista_id;
    v_partido := privado.bloquear_partido(v_lista.partido_id);
    select * into v_enf from public.enfrentamientos where id = p_enfrentamiento_id;
    select * into v_lista from public.listas_juego where id = v_enf.lista_id;

    v_club := privado.club_gestionado(v_partido.id);
    perform privado.exigir_rol(v_club, array['CAPITAN', 'DIRECTIVA']);
    if v_secretaria then
        perform privado.exigir_rol(v_club, array['DIRECTIVA']);
        perform privado.exigir_motivo(p_motivo);
    end if;
    v_ganador := privado.ganador_desde_resultado(p_resultado, v_club, privado.club_rival(v_partido, v_club));

    -- Reenvío idéntico (doble toque, reintento por mala señal): respuesta idempotente.
    if v_enf.estado_codigo = 'DISPUTADO' then
        if exists (select 1
                     from public.resultados_enfrentamiento r
                    where r.enfrentamiento_id = p_enfrentamiento_id and r.vigente
                      and r.ganador_club_id = v_ganador
                      and r.por_secretaria = v_secretaria
                      and privado.firma_acciones(r.id) = privado.firma_entrada(p_enfrentamiento_id, v_acciones)) then
            return privado.estado_partido(v_partido.id)
                || jsonb_build_object('ya_registrado', true, 'cierre', false, 'enfrentamiento_version', v_enf.version);
        end if;
        perform privado.error('ENFRENTAMIENTO_YA_REGISTRADO',
            'Este enfrentamiento ya tiene otro resultado registrado. Actualice la pantalla.');
    end if;

    if v_partido.estado <> 'EN_CURSO' then
        perform privado.error('PARTIDO_NO_EN_CURSO', 'El partido no está EN_CURSO: no se registran resultados.');
    end if;
    if v_lista.estado not in ('CONFIRMADA', 'EN_JUEGO') then
        perform privado.error('LISTA_NO_CONFIRMADA', 'La lista debe estar confirmada para registrar resultados.');
    end if;
    if v_enf.estado_codigo <> 'PENDIENTE' then
        perform privado.error('ENFRENTAMIENTO_NO_PENDIENTE', 'El enfrentamiento no está pendiente.');
    end if;
    if p_version is distinct from v_enf.version then
        perform privado.error('CONFLICTO_VERSION', 'El enfrentamiento cambió desde que se cargó la pantalla. Actualice y reintente.');
    end if;
    if exists (select 1
                 from public.enfrentamientos e2
                 join public.listas_juego l2 on l2.id = e2.lista_id
                where l2.partido_id = v_partido.id
                  and e2.estado_codigo = 'PENDIENTE'
                  and (l2.numero, e2.orden_juego) < (v_lista.numero, v_enf.orden_juego)) then
        perform privado.error('ORDEN_DE_JUEGO', 'Debe registrar primero los enfrentamientos anteriores según el orden de la planilla.');
    end if;

    perform privado.fijar_contexto('REGISTRAR_RESULTADO', case when v_secretaria then p_motivo end);

    insert into public.resultados_enfrentamiento
        (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota, registrado_por,
         por_secretaria, motivo_secretaria)
    values
        (p_enfrentamiento_id, v_ganador,
         privado.valor_regla(v_partido.regla_version_id, 'VICTORIA'),
         privado.valor_regla(v_partido.regla_version_id, 'DERROTA'),
         auth.uid(),
         v_secretaria, case when v_secretaria then btrim(p_motivo) end)
    returning id into v_resultado;

    perform privado.insertar_acciones(v_resultado, p_enfrentamiento_id, v_partido.regla_version_id, v_acciones);

    update public.enfrentamientos
       set estado_codigo = 'DISPUTADO', version = version + 1
     where id = p_enfrentamiento_id;

    v_local     := v_partido.puntaje_local     + case when v_ganador = v_partido.club_local_id     then 1 else 0 end;
    v_visitante := v_partido.puntaje_visitante + case when v_ganador = v_partido.club_visitante_id then 1 else 0 end;
    v_cierre    := v_local >= v_partido.puntaje_objetivo or v_visitante >= v_partido.puntaje_objetivo;

    -- Marcador, estado y ganador en una sola sentencia (las restricciones CHECK lo exigen).
    update public.partidos
       set puntaje_local     = v_local,
           puntaje_visitante = v_visitante,
           estado            = case when v_cierre then 'FINALIZADO' else estado end,
           ganador_club_id   = case when v_cierre then v_ganador else null end,
           finalizado_at     = case when v_cierre then now() else finalizado_at end,
           version           = version + 1
     where id = v_partido.id;

    if v_cierre then
        update public.enfrentamientos e
           set estado_codigo = 'NO_DISPUTADO_FIN_PARTIDO', version = e.version + 1
          from public.listas_juego l
         where l.id = e.lista_id and l.partido_id = v_partido.id and e.estado_codigo = 'PENDIENTE';
    end if;

    perform privado.recalcular_listas(v_partido.id);
    perform privado.fijar_contexto(null, null);

    return privado.estado_partido(v_partido.id)
        || jsonb_build_object('ya_registrado', false, 'cierre', v_cierre, 'enfrentamiento_version', v_enf.version + 1);
end;
$$;

-- Corrección de un resultado (mismas reglas de permisos que en la 003):
--   EN_CURSO: DIRECTIVA o ADMINISTRADOR · EN_REVISION: ADMINISTRADOR · FINALIZADO: reabrir primero.
-- Si adelanta el cierre del partido (P-1) exige p_confirmar_impacto = true.
create function public.corregir_resultado(
    p_enfrentamiento_id  uuid,
    p_resultado          text,
    p_acciones           jsonb,
    p_motivo             text,
    p_version            integer,
    p_confirmar_impacto  boolean default false,
    p_por_secretaria     boolean default false)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_enf        public.enfrentamientos;
    v_lista      public.listas_juego;
    v_partido    public.partidos;
    v_club       uuid;
    v_ganador    uuid;
    v_acciones   jsonb := coalesce(p_acciones, '[]'::jsonb);
    v_secretaria boolean := coalesce(p_por_secretaria, false);
    v_anterior   public.resultados_enfrentamiento;
    v_nuevo      uuid;
    v_a          jsonb;
begin
    select * into v_enf from public.enfrentamientos where id = p_enfrentamiento_id;
    if not found then
        perform privado.error('NO_ENCONTRADO', 'El enfrentamiento no existe.');
    end if;
    select * into v_lista from public.listas_juego where id = v_enf.lista_id;
    v_partido := privado.bloquear_partido(v_lista.partido_id);
    select * into v_enf from public.enfrentamientos where id = p_enfrentamiento_id;
    v_club := privado.club_gestionado(v_partido.id);

    if v_partido.estado = 'EN_REVISION' then
        perform privado.exigir_admin();
    else
        perform privado.exigir_rol(v_club, array['DIRECTIVA']);
        if v_partido.estado = 'FINALIZADO' then
            perform privado.error('REABRIR_REQUERIDO',
                'El partido está FINALIZADO: un ADMINISTRADOR debe reabrirlo antes de corregir.');
        elsif v_partido.estado <> 'EN_CURSO' then
            perform privado.error('ESTADO_NO_PERMITE', 'El estado del partido no permite correcciones.');
        end if;
    end if;
    perform privado.exigir_motivo(p_motivo);

    if v_enf.estado_codigo <> 'DISPUTADO' then
        perform privado.error('ENFRENTAMIENTO_NO_DISPUTADO', 'Solo se corrigen enfrentamientos disputados.');
    end if;
    if p_version is distinct from v_enf.version then
        perform privado.error('CONFLICTO_VERSION', 'El enfrentamiento cambió desde que se cargó la pantalla. Actualice y reintente.');
    end if;

    v_ganador := privado.ganador_desde_resultado(p_resultado, v_club, privado.club_rival(v_partido, v_club));

    select * into v_anterior
      from public.resultados_enfrentamiento r
     where r.enfrentamiento_id = p_enfrentamiento_id and r.vigente;

    if v_anterior.ganador_club_id = v_ganador
       and v_anterior.por_secretaria = v_secretaria
       and privado.firma_acciones(v_anterior.id) = privado.firma_entrada(p_enfrentamiento_id, v_acciones) then
        perform privado.error('SIN_CAMBIOS', 'La corrección no cambia nada respecto del resultado vigente.');
    end if;

    v_a := privado.analizar_secuencia(v_partido.id, p_enfrentamiento_id, v_ganador);
    if jsonb_array_length(v_a -> 'invalidados') > 0 and not coalesce(p_confirmar_impacto, false) then
        perform privado.error('IMPACTO_REQUIERE_CONFIRMACION',
            format('La corrección adelanta el cierre del partido e invalida %s enfrentamiento(s) disputado(s). Revise el impacto y confirme.',
                   jsonb_array_length(v_a -> 'invalidados')),
            v_a::text);
    end if;

    perform privado.fijar_contexto('CORREGIR_RESULTADO', p_motivo);

    update public.resultados_enfrentamiento
       set vigente = false, anulado_at = now(), anulado_por = auth.uid(),
           causa_anulacion = 'CORREGIDO', motivo_anulacion = p_motivo
     where id = v_anterior.id;

    insert into public.resultados_enfrentamiento
        (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota, reemplaza_a_id, registrado_por,
         por_secretaria, motivo_secretaria)
    values
        (p_enfrentamiento_id, v_ganador,
         privado.valor_regla(v_partido.regla_version_id, 'VICTORIA'),
         privado.valor_regla(v_partido.regla_version_id, 'DERROTA'),
         v_anterior.id, auth.uid(),
         v_secretaria, case when v_secretaria then btrim(p_motivo) end)
    returning id into v_nuevo;

    perform privado.insertar_acciones(v_nuevo, p_enfrentamiento_id, v_partido.regla_version_id, v_acciones);

    update public.enfrentamientos set version = version + 1 where id = p_enfrentamiento_id;

    v_a := privado.aplicar_secuencia(v_partido.id, p_motivo);
    perform privado.fijar_contexto(null, null);

    return privado.estado_partido(v_partido.id)
        || jsonb_build_object('invalidados', v_a -> 'invalidados');
end;
$$;

-- ---------------------------------------------------------------------
-- 6. PRIVILEGIOS
-- ---------------------------------------------------------------------

revoke all on all functions in schema privado from public, anon;
revoke all on function public.registrar_resultado(uuid, text, jsonb, integer, boolean, text) from public, anon;
revoke all on function public.corregir_resultado(uuid, text, jsonb, text, integer, boolean, boolean) from public, anon;

grant execute on function
    public.registrar_resultado(uuid, text, jsonb, integer, boolean, text),
    public.corregir_resultado(uuid, text, jsonb, text, integer, boolean, boolean)
to authenticated;

-- ---------------------------------------------------------------------
-- 7. REGISTRO DE LA MIGRACIÓN
-- ---------------------------------------------------------------------

insert into public.migraciones_aplicadas (version, descripcion)
values ('004', 'Acciones por integrante (varias por enfrentamiento), reglas por jugador y equipo, resultado por secretaría');

commit;
