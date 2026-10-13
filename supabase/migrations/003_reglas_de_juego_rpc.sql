-- =====================================================================
-- MIGRACIÓN 003 — REGLAS DE JUEGO: VALIDACIONES Y FUNCIONES RPC
-- Sistema de Gestión y Estadísticas de Juego — CLUB RAYO
-- Fase 3.
--
-- Contenido:
--   1. Funciones internas (esquema privado).
--   2. Validaciones entre tablas (triggers), pendientes desde la 001:
--        - partido con al menos un club gestionado;
--        - listas solo en partidos EN_CURSO;
--        - convocatorias y posiciones solo editables con la lista en BORRADOR;
--        - convocado pertenece a uno de los clubes del partido;
--        - posición dentro del rango de la modalidad (1/2/3);
--        - resultado solo en partido EN_CURSO/EN_REVISION y con ganador del partido;
--        - polaridad de la acción según victoria/derrota;
--        - jugador convocado no puede pasar a AUSENTE/JUSTIFICADO;
--        - todo DISPUTADO tiene exactamente un resultado vigente con una acción
--          (verificación diferida al confirmar la transacción).
--   3. Funciones RPC transaccionales (única vía de escritura operativa):
--        iniciar_partido, suspender_partido, reanudar_partido, cancelar_partido,
--        registrar_asistencia,
--        crear_lista, guardar_lista, confirmar_lista, devolver_lista_a_edicion,
--        registrar_resultado (incluye cierre automático al objetivo),
--        previsualizar_correccion, corregir_resultado (incluye P-1),
--        reabrir_partido, cerrar_revision,
--        activar_regla_version, verificar_partido.
--
-- Limitación V1 documentada: las funciones operan partidos con UN club
-- gestionado (RAYO vs rival). Partidos entre dos clubes gestionados se
-- rechazan hasta una versión multi-club.
--
-- Errores de negocio: SQLSTATE P0001 con un código estable en HINT
-- (p. ej. ORDEN_DE_JUEGO). Permisos: SQLSTATE 42501, HINT PERMISO_DENEGADO.
--
-- Ejecutar UNA sola vez, después de la migración 002.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. CONTROL DE MIGRACIONES
-- ---------------------------------------------------------------------

do $$
begin
    if not exists (select 1 from public.migraciones_aplicadas where version = '002') then
        raise exception 'Falta aplicar la migración 002. No se realizaron cambios.';
    end if;
    if exists (select 1 from public.migraciones_aplicadas where version = '003') then
        raise exception 'La migración 003 ya fue aplicada anteriormente. No se realizaron cambios.';
    end if;
end $$;

-- Funciones futuras del esquema privado: sin EXECUTE para PUBLIC.
alter default privileges for role postgres in schema privado revoke execute on functions from public;

-- ---------------------------------------------------------------------
-- 1. FUNCIONES INTERNAS
-- ---------------------------------------------------------------------

create function privado.error(p_codigo text, p_mensaje text, p_detalle text default null)
returns void
language plpgsql set search_path = ''
as $$
begin
    raise exception using
        errcode = 'P0001',
        message = p_mensaje,
        hint    = p_codigo,
        detail  = coalesce(p_detalle, '');
end;
$$;

create function privado.exigir_rol(p_club uuid, p_roles text[])
returns void
language plpgsql set search_path = ''
as $$
begin
    if not privado.tiene_rol(p_club, p_roles) then
        raise exception using
            errcode = '42501',
            message = 'Permiso denegado para esta operación.',
            hint    = 'PERMISO_DENEGADO';
    end if;
end;
$$;

create function privado.exigir_admin()
returns void
language plpgsql set search_path = ''
as $$
begin
    if not privado.es_admin() then
        raise exception using
            errcode = '42501',
            message = 'Solo un ADMINISTRADOR puede realizar esta operación.',
            hint    = 'PERMISO_DENEGADO';
    end if;
end;
$$;

create function privado.exigir_motivo(p_motivo text)
returns void
language plpgsql set search_path = ''
as $$
begin
    if nullif(btrim(p_motivo), '') is null then
        perform privado.error('MOTIVO_REQUERIDO', 'Esta operación requiere indicar un motivo.');
    end if;
end;
$$;

-- Acción y motivo que la auditoría registrará en esta transacción.
create function privado.fijar_contexto(p_accion text, p_motivo text)
returns void
language plpgsql set search_path = ''
as $$
begin
    perform set_config('app.accion', coalesce(p_accion, ''), true);
    perform set_config('app.motivo', coalesce(p_motivo, ''), true);
end;
$$;

-- Configuración efectiva: campeonato > club > global.
create function privado.config(p_clave text, p_campeonato uuid, p_club uuid)
returns jsonb
language sql stable set search_path = ''
as $$
    select c.valor
      from public.configuracion c
     where c.clave = p_clave
       and (c.campeonato_id = p_campeonato
            or c.club_id = p_club
            or (c.campeonato_id is null and c.club_id is null))
     order by case when c.campeonato_id is not null then 1
                   when c.club_id is not null then 2
                   else 3 end
     limit 1;
$$;

create function privado.valor_regla(p_version uuid, p_concepto text)
returns numeric
language plpgsql stable set search_path = ''
as $$
declare
    v_valor numeric;
begin
    select r.valor into v_valor
      from public.reglas_puntuacion_valores r
     where r.regla_version_id = p_version and r.concepto_codigo = p_concepto;
    if v_valor is null then
        perform privado.error('REGLA_INCOMPLETA',
            format('La versión de reglas del partido no define el concepto %s.', p_concepto));
    end if;
    return v_valor;
end;
$$;

-- Club gestionado del partido (V1: exactamente uno).
create function privado.club_gestionado(p_partido uuid)
returns uuid
language plpgsql stable set search_path = ''
as $$
declare
    v_n    integer;
    v_club text;
begin
    select count(*), min(c.id::text) into v_n, v_club
      from public.partidos p
      join public.clubes c on c.id in (p.club_local_id, p.club_visitante_id)
     where p.id = p_partido and c.es_gestionado;

    if v_n = 0 then
        perform privado.error('PARTIDO_SIN_CLUB_GESTIONADO', 'El partido no incluye un club gestionado por el sistema.');
    elsif v_n > 1 then
        perform privado.error('PARTIDO_DOS_CLUBES_GESTIONADOS',
            'La versión actual no permite operar partidos entre dos clubes gestionados.');
    end if;
    return v_club::uuid;
end;
$$;

create function privado.club_rival(p_partido public.partidos, p_club uuid)
returns uuid
language sql immutable set search_path = ''
as $$
    select case when p_partido.club_local_id = p_club
                then p_partido.club_visitante_id
                else p_partido.club_local_id end;
$$;

-- Bloquea la fila del partido: serializa toda escritura sobre ese partido.
create function privado.bloquear_partido(p_partido uuid)
returns public.partidos
language plpgsql set search_path = ''
as $$
declare
    v_partido public.partidos;
begin
    select * into v_partido from public.partidos where id = p_partido for update;
    if not found then
        perform privado.error('NO_ENCONTRADO', 'El partido no existe.');
    end if;
    return v_partido;
end;
$$;

create function privado.estado_partido(p_partido uuid)
returns jsonb
language sql stable set search_path = ''
as $$
    select jsonb_build_object(
               'partido_id',        p.id,
               'estado',            p.estado,
               'puntaje_local',     p.puntaje_local,
               'puntaje_visitante', p.puntaje_visitante,
               'puntaje_objetivo',  p.puntaje_objetivo,
               'ganador_club_id',   p.ganador_club_id,
               'version',           p.version)
      from public.partidos p
     where p.id = p_partido;
$$;

create function privado.resumen_asistencia(p_partido uuid)
returns jsonb
language sql stable set search_path = ''
as $$
    select jsonb_build_object(
               'total',        count(*),
               'presentes',    count(*) filter (where a.estado = 'PRESENTE'),
               'ausentes',     count(*) filter (where a.estado = 'AUSENTE'),
               'justificados', count(*) filter (where a.estado = 'JUSTIFICADO'),
               'porcentaje_asistencia',
                   round(100.0 * count(*) filter (where a.estado = 'PRESENTE') / nullif(count(*), 0), 2))
      from public.asistencias a
     where a.partido_id = p_partido;
$$;

-- GANADO / PERDIDO desde la perspectiva del club gestionado.
create function privado.ganador_desde_resultado(p_resultado text, p_club uuid, p_rival uuid)
returns uuid
language plpgsql immutable set search_path = ''
as $$
begin
    if p_resultado = 'GANADO' then
        return p_club;
    elsif p_resultado = 'PERDIDO' then
        return p_rival;
    end if;
    perform privado.error('RESULTADO_INVALIDO', 'El resultado debe ser GANADO o PERDIDO.');
    return null;
end;
$$;

create function privado.participante_de(p_enfrentamiento uuid, p_jugador uuid)
returns uuid
language sql stable set search_path = ''
as $$
    select pe.id
      from public.participantes_enfrentamiento pe
      join public.convocatorias c on c.id = pe.convocatoria_id
     where pe.enfrentamiento_id = p_enfrentamiento and c.jugador_id = p_jugador
     limit 1;
$$;

create function privado.validar_polaridad(p_tipo_accion text, p_gano boolean)
returns void
language plpgsql stable set search_path = ''
as $$
declare
    v_polaridad text;
begin
    select t.polaridad into v_polaridad
      from public.tipos_accion t
     where t.codigo = p_tipo_accion and t.activo;
    if v_polaridad is null then
        perform privado.error('TIPO_ACCION_INVALIDO', 'La causa indicada no existe o no está activa.');
    end if;
    if (v_polaridad = 'POSITIVA') <> p_gano then
        perform privado.error('POLARIDAD_INCORRECTA',
            case when p_gano then 'Una victoria requiere una causa positiva (Cortó, Caída rival o Reventón rival).'
                 else 'Una derrota requiere una causa negativa (Lo cortaron, Caída propia o Reventón propio).' end);
    end if;
end;
$$;

-- Recorre los resultados vigentes en orden (lista, orden_juego) y determina
-- el marcador, el primer punto en que un club alcanza el objetivo (cierre) y
-- los enfrentamientos disputados DESPUÉS del cierre (invalidados, P-1).
-- p_override_*: simula un resultado distinto para un enfrentamiento (previsualización).
create function privado.analizar_secuencia(p_partido uuid, p_override_enf uuid default null, p_override_ganador uuid default null)
returns jsonb
language plpgsql stable set search_path = ''
as $$
declare
    v_partido     public.partidos;
    v_local       integer := 0;
    v_visitante   integer := 0;
    v_cierre      uuid;
    v_ganador     uuid;
    v_invalidados jsonb := '[]'::jsonb;
    v_g           uuid;
    rec           record;
begin
    select * into v_partido from public.partidos where id = p_partido;

    for rec in
        select e.id, r.ganador_club_id
          from public.enfrentamientos e
          join public.listas_juego l on l.id = e.lista_id
          join public.resultados_enfrentamiento r on r.enfrentamiento_id = e.id and r.vigente
         where l.partido_id = p_partido
           and e.estado_codigo = 'DISPUTADO'
         order by l.numero, e.orden_juego
    loop
        v_g := case when rec.id = p_override_enf then p_override_ganador else rec.ganador_club_id end;
        if v_cierre is null then
            if v_g = v_partido.club_local_id then
                v_local := v_local + 1;
            else
                v_visitante := v_visitante + 1;
            end if;
            if v_local >= v_partido.puntaje_objetivo or v_visitante >= v_partido.puntaje_objetivo then
                v_cierre  := rec.id;
                v_ganador := v_g;
            end if;
        else
            v_invalidados := v_invalidados || to_jsonb(rec.id);
        end if;
    end loop;

    return jsonb_build_object(
        'puntaje_local',            v_local,
        'puntaje_visitante',        v_visitante,
        'cierre_enfrentamiento_id', v_cierre,
        'ganador_club_id',          v_ganador,
        'invalidados',              v_invalidados);
end;
$$;

-- Estado de cada lista oficial según sus enfrentamientos.
create function privado.recalcular_listas(p_partido uuid)
returns void
language plpgsql set search_path = ''
as $$
begin
    update public.listas_juego l
       set estado = x.nuevo
      from (select l2.id,
                   case when not exists (select 1 from public.enfrentamientos e
                                          where e.lista_id = l2.id and e.estado_codigo = 'PENDIENTE')
                            then 'FINALIZADA'
                        when exists (select 1 from public.enfrentamientos e
                                       join public.resultados_enfrentamiento r on r.enfrentamiento_id = e.id
                                      where e.lista_id = l2.id)
                            then 'EN_JUEGO'
                        else 'CONFIRMADA' end as nuevo
              from public.listas_juego l2
             where l2.partido_id = p_partido and l2.estado <> 'BORRADOR') x
     where l.id = x.id and l.estado <> x.nuevo;
end;
$$;

-- Aplica a la base el resultado del análisis: marcador, cierre, invalidación
-- P-1 o reapertura del juego cuando nadie alcanza el objetivo.
create function privado.aplicar_secuencia(p_partido uuid, p_motivo text)
returns jsonb
language plpgsql set search_path = ''
as $$
declare
    v_a       jsonb := privado.analizar_secuencia(p_partido);
    v_cierre  uuid  := (v_a ->> 'cierre_enfrentamiento_id')::uuid;
begin
    if jsonb_array_length(v_a -> 'invalidados') > 0 then
        update public.resultados_enfrentamiento r
           set vigente = false, anulado_at = now(), anulado_por = auth.uid(),
               causa_anulacion = 'INVALIDADO_CIERRE_ANTICIPADO', motivo_anulacion = p_motivo
         where r.vigente
           and r.enfrentamiento_id in (select (x #>> '{}')::uuid from jsonb_array_elements(v_a -> 'invalidados') x);

        update public.enfrentamientos e
           set estado_codigo = 'NO_DISPUTADO_FIN_PARTIDO', version = e.version + 1
         where e.id in (select (x #>> '{}')::uuid from jsonb_array_elements(v_a -> 'invalidados') x);
    end if;

    if v_cierre is not null then
        update public.enfrentamientos e
           set estado_codigo = 'NO_DISPUTADO_FIN_PARTIDO', version = e.version + 1
          from public.listas_juego l
         where l.id = e.lista_id and l.partido_id = p_partido and e.estado_codigo = 'PENDIENTE';

        update public.partidos p
           set puntaje_local     = (v_a ->> 'puntaje_local')::smallint,
               puntaje_visitante = (v_a ->> 'puntaje_visitante')::smallint,
               ganador_club_id   = (v_a ->> 'ganador_club_id')::uuid,
               estado            = case when p.estado = 'EN_REVISION' then 'EN_REVISION' else 'FINALIZADO' end,
               finalizado_at     = coalesce(p.finalizado_at, now()),
               version           = p.version + 1
         where p.id = p_partido;
    else
        update public.enfrentamientos e
           set estado_codigo = 'PENDIENTE', version = e.version + 1
          from public.listas_juego l
         where l.id = e.lista_id and l.partido_id = p_partido and e.estado_codigo = 'NO_DISPUTADO_FIN_PARTIDO';

        update public.partidos p
           set puntaje_local     = (v_a ->> 'puntaje_local')::smallint,
               puntaje_visitante = (v_a ->> 'puntaje_visitante')::smallint,
               ganador_club_id   = null,
               estado            = 'EN_CURSO',
               finalizado_at     = null,
               version           = p.version + 1
         where p.id = p_partido;
    end if;

    perform privado.recalcular_listas(p_partido);
    return v_a;
end;
$$;

-- Reglas que siempre deben cumplirse (sección 6.5). Devuelve la lista de problemas.
create function privado.verificar_partido(p_partido uuid)
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
                 and ((select count(*) from public.resultados_enfrentamiento r
                        where r.enfrentamiento_id = e.id and r.vigente) <> 1
                      or (select count(*) from public.acciones_resultado a
                            join public.resultados_enfrentamiento r on r.id = a.resultado_id
                           where r.enfrentamiento_id = e.id and r.vigente) <> 1))
             or (e.estado_codigo <> 'DISPUTADO'
                 and exists (select 1 from public.resultados_enfrentamiento r
                              where r.enfrentamiento_id = e.id and r.vigente)))) then
        v_prob := array_append(v_prob, 'Hay enfrentamientos con resultado o acción incoherente.');
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
-- 2. VALIDACIONES ENTRE TABLAS (TRIGGERS)
-- ---------------------------------------------------------------------

create function privado.fn_partidos_validar_clubes()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if not exists (select 1 from public.clubes c
                    where c.id in (new.club_local_id, new.club_visitante_id) and c.es_gestionado) then
        perform privado.error('PARTIDO_SIN_CLUB_GESTIONADO',
            'El partido debe incluir al menos un club gestionado por el sistema.');
    end if;
    return new;
end;
$$;

create trigger trg_partidos_validar_clubes
    before insert or update of club_local_id, club_visitante_id on public.partidos
    for each row execute function privado.fn_partidos_validar_clubes();

create function privado.fn_listas_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if not exists (select 1 from public.partidos p where p.id = new.partido_id and p.estado = 'EN_CURSO') then
        perform privado.error('PARTIDO_NO_EN_CURSO', 'Solo se crean listas en un partido EN_CURSO.');
    end if;
    return new;
end;
$$;

create trigger trg_listas_validar
    before insert on public.listas_juego
    for each row execute function privado.fn_listas_validar();

-- Composición bloqueada: convocatorias solo cambian con la lista en BORRADOR.
create function privado.fn_convocatorias_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    v_estado_lista text;
    v_partido      public.partidos;
begin
    select l.estado into v_estado_lista from public.listas_juego l where l.id = new.lista_id;
    if v_estado_lista is null then
        return new;  -- lista inexistente: la rechaza la FK
    end if;
    if v_estado_lista <> 'BORRADOR' then
        perform privado.error('COMPOSICION_BLOQUEADA',
            'La lista no está en edición: sus convocatorias no pueden modificarse.');
    end if;
    if tg_op = 'INSERT' then
        select p.* into v_partido
          from public.partidos p join public.listas_juego l on l.partido_id = p.id
         where l.id = new.lista_id;
        if new.club_id not in (v_partido.club_local_id, v_partido.club_visitante_id) then
            perform privado.error('JUGADOR_NO_PERTENECE', 'El jugador no pertenece a ninguno de los clubes del partido.');
        end if;
    end if;
    return new;
end;
$$;

create trigger trg_convocatorias_validar
    before insert or update on public.convocatorias
    for each row execute function privado.fn_convocatorias_validar();

create function privado.fn_participantes_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    v_estado_lista text;
    v_max          smallint;
begin
    select l.estado into v_estado_lista from public.listas_juego l where l.id = new.lista_id;
    if v_estado_lista is not null and v_estado_lista <> 'BORRADOR' then
        perform privado.error('COMPOSICION_BLOQUEADA',
            'La lista no está en edición: sus posiciones no pueden modificarse.');
    end if;
    select m.jugadores_por_enfrentamiento into v_max
      from public.enfrentamientos e join public.modalidades m on m.codigo = e.modalidad_codigo
     where e.id = new.enfrentamiento_id;
    if v_max is not null and new.posicion > v_max then
        perform privado.error('POSICION_INVALIDA',
            format('La modalidad admite solo %s jugador(es) por enfrentamiento.', v_max));
    end if;
    return new;
end;
$$;

create trigger trg_participantes_validar
    before insert or update on public.participantes_enfrentamiento
    for each row execute function privado.fn_participantes_validar();

create function privado.fn_resultados_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    v_partido public.partidos;
begin
    select p.* into v_partido
      from public.partidos p
      join public.listas_juego l on l.partido_id = p.id
      join public.enfrentamientos e on e.lista_id = l.id
     where e.id = new.enfrentamiento_id;
    if not found then
        return new;  -- enfrentamiento inexistente: lo rechaza la FK
    end if;
    if v_partido.estado not in ('EN_CURSO', 'EN_REVISION') then
        perform privado.error('PARTIDO_NO_EN_CURSO', 'No se registran resultados en un partido que no está EN_CURSO o EN_REVISION.');
    end if;
    if new.ganador_club_id not in (v_partido.club_local_id, v_partido.club_visitante_id) then
        perform privado.error('GANADOR_INVALIDO', 'El ganador debe ser uno de los clubes del partido.');
    end if;
    return new;
end;
$$;

create trigger trg_resultados_validar
    before insert on public.resultados_enfrentamiento
    for each row execute function privado.fn_resultados_validar();

create function privado.fn_acciones_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    v_ganador   uuid;
    v_club      uuid;
    v_polaridad text;
begin
    select r.ganador_club_id into v_ganador from public.resultados_enfrentamiento r where r.id = new.resultado_id;
    select c.club_id into v_club
      from public.participantes_enfrentamiento pe join public.convocatorias c on c.id = pe.convocatoria_id
     where pe.id = new.participante_id;
    select t.polaridad into v_polaridad from public.tipos_accion t where t.codigo = new.tipo_accion_codigo;
    if v_ganador is null or v_club is null or v_polaridad is null then
        return new;  -- referencias inexistentes: las rechazan las FK
    end if;
    if (v_club = v_ganador) <> (v_polaridad = 'POSITIVA') then
        perform privado.error('POLARIDAD_INCORRECTA',
            'La causa no corresponde al resultado: victoria requiere causa positiva y derrota, negativa.');
    end if;
    return new;
end;
$$;

create trigger trg_acciones_validar
    before insert or update on public.acciones_resultado
    for each row execute function privado.fn_acciones_validar();

create function privado.fn_asistencias_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if old.estado = 'PRESENTE' and new.estado <> 'PRESENTE'
       and exists (select 1
                     from public.convocatorias c
                     join public.listas_juego l on l.id = c.lista_id
                    where l.partido_id = new.partido_id
                      and c.jugador_id = new.jugador_id
                      and c.estado <> 'ANULADA_REEMPLAZO'
                      and l.estado <> 'BORRADOR') then
        perform privado.error('JUGADOR_CONVOCADO',
            'El jugador ya fue convocado en una lista confirmada: no puede quedar AUSENTE o JUSTIFICADO.');
    end if;
    return new;
end;
$$;

create trigger trg_asistencias_validar
    before update on public.asistencias
    for each row execute function privado.fn_asistencias_validar();

-- Coherencia enfrentamiento/resultado/acción, verificada al confirmar la transacción.
create function privado.fn_coherencia_enfrentamiento()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    v_id               uuid := coalesce((to_jsonb(new) ->> 'enfrentamiento_id')::uuid, (to_jsonb(new) ->> 'id')::uuid);
    v_admite_resultado boolean;
    v_vigentes         integer;
    v_acciones         integer;
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
    select count(*) into v_acciones
      from public.acciones_resultado a
      join public.resultados_enfrentamiento r on r.id = a.resultado_id
     where r.enfrentamiento_id = v_id and r.vigente;

    if v_admite_resultado and (v_vigentes <> 1 or v_acciones <> 1) then
        perform privado.error('INCOHERENCIA_ENFRENTAMIENTO',
            'Un enfrentamiento disputado debe tener exactamente un resultado vigente con una acción.');
    elsif not v_admite_resultado and v_vigentes <> 0 then
        perform privado.error('INCOHERENCIA_ENFRENTAMIENTO',
            'Un enfrentamiento no disputado no puede tener resultado vigente.');
    end if;
    return null;
end;
$$;

create constraint trigger trg_enfrentamientos_coherencia
    after insert or update on public.enfrentamientos
    deferrable initially deferred
    for each row execute function privado.fn_coherencia_enfrentamiento();

create constraint trigger trg_resultados_coherencia
    after insert or update on public.resultados_enfrentamiento
    deferrable initially deferred
    for each row execute function privado.fn_coherencia_enfrentamiento();

-- ---------------------------------------------------------------------
-- 3. FUNCIONES RPC — CICLO DE VIDA DEL PARTIDO
-- ---------------------------------------------------------------------

create function public.iniciar_partido(p_partido_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_partido public.partidos := privado.bloquear_partido(p_partido_id);
    v_regla   uuid;
begin
    perform privado.exigir_rol(privado.club_gestionado(p_partido_id), array['CAPITAN', 'DIRECTIVA']);
    if v_partido.estado <> 'PROGRAMADO' then
        perform privado.error('ESTADO_NO_PERMITE', 'Solo se puede iniciar un partido PROGRAMADO.');
    end if;
    select v.id into v_regla from public.reglas_puntuacion_versiones v where v.es_vigente;
    if v_regla is null then
        perform privado.error('SIN_REGLA_VIGENTE', 'No hay una versión de reglas de puntuación vigente.');
    end if;

    perform privado.fijar_contexto('INICIAR_PARTIDO', null);
    update public.partidos
       set estado = 'EN_CURSO', iniciado_at = now(), regla_version_id = v_regla, version = version + 1
     where id = p_partido_id;
    perform privado.fijar_contexto(null, null);
    return privado.estado_partido(p_partido_id);
end;
$$;

create function public.suspender_partido(p_partido_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_partido public.partidos := privado.bloquear_partido(p_partido_id);
begin
    perform privado.exigir_rol(privado.club_gestionado(p_partido_id), array['CAPITAN', 'DIRECTIVA']);
    perform privado.exigir_motivo(p_motivo);
    if v_partido.estado <> 'EN_CURSO' then
        perform privado.error('ESTADO_NO_PERMITE', 'Solo se puede suspender un partido EN_CURSO.');
    end if;

    perform privado.fijar_contexto('SUSPENDER_PARTIDO', p_motivo);
    update public.partidos set estado = 'SUSPENDIDO', version = version + 1 where id = p_partido_id;
    perform privado.fijar_contexto(null, null);
    return privado.estado_partido(p_partido_id);
end;
$$;

create function public.reanudar_partido(p_partido_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_partido public.partidos := privado.bloquear_partido(p_partido_id);
begin
    perform privado.exigir_rol(privado.club_gestionado(p_partido_id), array['CAPITAN', 'DIRECTIVA']);
    if v_partido.estado <> 'SUSPENDIDO' then
        perform privado.error('ESTADO_NO_PERMITE', 'Solo se puede reanudar un partido SUSPENDIDO.');
    end if;

    perform privado.fijar_contexto('REANUDAR_PARTIDO', null);
    update public.partidos set estado = 'EN_CURSO', version = version + 1 where id = p_partido_id;
    perform privado.fijar_contexto(null, null);
    return privado.estado_partido(p_partido_id);
end;
$$;

-- Sin resultados: DIRECTIVA o ADMINISTRADOR. Con resultados: solo ADMINISTRADOR.
create function public.cancelar_partido(p_partido_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_partido public.partidos := privado.bloquear_partido(p_partido_id);
begin
    if exists (select 1
                 from public.resultados_enfrentamiento r
                 join public.enfrentamientos e on e.id = r.enfrentamiento_id
                 join public.listas_juego l on l.id = e.lista_id
                where l.partido_id = p_partido_id) then
        perform privado.exigir_admin();
    else
        perform privado.exigir_rol(privado.club_gestionado(p_partido_id), array['DIRECTIVA']);
    end if;
    perform privado.exigir_motivo(p_motivo);
    if v_partido.estado not in ('PROGRAMADO', 'EN_CURSO', 'SUSPENDIDO') then
        perform privado.error('ESTADO_NO_PERMITE', 'Solo se cancela un partido PROGRAMADO, EN_CURSO o SUSPENDIDO.');
    end if;

    perform privado.fijar_contexto('CANCELAR_PARTIDO', p_motivo);
    update public.partidos set estado = 'CANCELADO', version = version + 1 where id = p_partido_id;
    perform privado.fijar_contexto(null, null);
    return privado.estado_partido(p_partido_id);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. FUNCIONES RPC — ASISTENCIA
-- p_registros: [{"jugador_id": "...", "estado": "PRESENTE|AUSENTE|JUSTIFICADO"}, ...]
-- ---------------------------------------------------------------------

create function public.registrar_asistencia(p_partido_id uuid, p_registros jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_partido public.partidos := privado.bloquear_partido(p_partido_id);
    v_club    uuid := privado.club_gestionado(p_partido_id);
    r         record;
begin
    perform privado.exigir_rol(v_club, array['CAPITAN', 'DIRECTIVA']);
    if v_partido.estado not in ('PROGRAMADO', 'EN_CURSO', 'SUSPENDIDO') then
        perform privado.error('ESTADO_NO_PERMITE',
            'La asistencia se registra solo en partidos PROGRAMADO, EN_CURSO o SUSPENDIDO.');
    end if;
    if p_registros is null or jsonb_typeof(p_registros) <> 'array' or jsonb_array_length(p_registros) = 0 then
        perform privado.error('DATOS_INVALIDOS', 'Debe indicar al menos un registro de asistencia.');
    end if;

    perform privado.fijar_contexto('REGISTRAR_ASISTENCIA', null);
    for r in select * from jsonb_to_recordset(p_registros) as x(jugador_id uuid, estado text) loop
        if r.estado is null or r.estado not in ('PRESENTE', 'AUSENTE', 'JUSTIFICADO') then
            perform privado.error('ESTADO_ASISTENCIA_INVALIDO', 'El estado debe ser PRESENTE, AUSENTE o JUSTIFICADO.');
        end if;
        if not exists (select 1 from public.jugadores j where j.id = r.jugador_id and j.club_id = v_club) then
            perform privado.error('JUGADOR_NO_PERTENECE', 'El jugador no pertenece al club.');
        end if;
        if not exists (select 1 from public.asistencias a where a.partido_id = p_partido_id and a.jugador_id = r.jugador_id)
           and not exists (select 1 from public.jugadores j where j.id = r.jugador_id and j.estado = 'ACTIVO') then
            perform privado.error('JUGADOR_INACTIVO', 'Solo se registra asistencia de jugadores ACTIVOS.');
        end if;

        insert into public.asistencias (partido_id, jugador_id, estado)
        values (p_partido_id, r.jugador_id, r.estado)
        on conflict (partido_id, jugador_id)
        do update set estado = excluded.estado
            where public.asistencias.estado is distinct from excluded.estado;
    end loop;
    perform privado.fijar_contexto(null, null);
    return privado.resumen_asistencia(p_partido_id);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. FUNCIONES RPC — LISTAS DE JUEGO
-- ---------------------------------------------------------------------

-- Crea la siguiente lista con sus enfrentamientos (5 ind, 3 duplas, 2 tríos;
-- orden_juego 1..10 según la tabla modalidades).
create function public.crear_lista(p_partido_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_partido public.partidos := privado.bloquear_partido(p_partido_id);
    v_numero  smallint;
    v_lista   uuid;
begin
    perform privado.exigir_rol(privado.club_gestionado(p_partido_id), array['CAPITAN', 'DIRECTIVA']);
    if v_partido.estado <> 'EN_CURSO' then
        perform privado.error('PARTIDO_NO_EN_CURSO', 'Solo se crean listas en un partido EN_CURSO.');
    end if;
    if exists (select 1 from public.listas_juego l where l.partido_id = p_partido_id and l.estado <> 'FINALIZADA') then
        perform privado.error('LISTA_ABIERTA', 'Hay una lista sin finalizar en este partido.');
    end if;

    select coalesce(max(l.numero), 0) + 1 into v_numero from public.listas_juego l where l.partido_id = p_partido_id;

    perform privado.fijar_contexto('CREAR_LISTA', null);
    insert into public.listas_juego (partido_id, numero) values (p_partido_id, v_numero) returning id into v_lista;
    insert into public.enfrentamientos (lista_id, modalidad_codigo, numero, orden_juego)
    select v_lista, m.codigo, g.n, row_number() over (order by m.orden, g.n)
      from public.modalidades m
     cross join lateral generate_series(1, m.enfrentamientos_por_lista) as g(n)
     where m.activo;
    perform privado.fijar_contexto(null, null);

    return jsonb_build_object('lista_id', v_lista, 'numero', v_numero);
end;
$$;

-- Guarda la composición completa (o parcial) de una lista en BORRADOR.
-- p_posiciones: [{"enfrentamiento_id": "...", "posicion": 1, "jugador_id": "..."}, ...]
-- p_motivo: obligatorio si se retira a un jugador de una lista que ya fue confirmada.
create function public.guardar_lista(p_lista_id uuid, p_posiciones jsonb, p_motivo text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_lista    public.listas_juego;
    v_partido  public.partidos;
    v_club     uuid;
    v_repetir  boolean;
    r          record;
begin
    select * into v_lista from public.listas_juego where id = p_lista_id;
    if not found then
        perform privado.error('NO_ENCONTRADO', 'La lista no existe.');
    end if;
    v_partido := privado.bloquear_partido(v_lista.partido_id);
    select * into v_lista from public.listas_juego where id = p_lista_id;
    v_club := privado.club_gestionado(v_partido.id);

    perform privado.exigir_rol(v_club, array['CAPITAN', 'DIRECTIVA']);
    if v_partido.estado <> 'EN_CURSO' then
        perform privado.error('PARTIDO_NO_EN_CURSO', 'El partido no está EN_CURSO.');
    end if;
    if v_lista.estado <> 'BORRADOR' then
        perform privado.error('LISTA_NO_EDITABLE', 'La lista no está en edición.');
    end if;
    if p_posiciones is null or jsonb_typeof(p_posiciones) <> 'array' then
        perform privado.error('DATOS_INVALIDOS', 'Las posiciones deben enviarse como un arreglo.');
    end if;

    if exists (select 1
                 from jsonb_to_recordset(p_posiciones) as x(enfrentamiento_id uuid, posicion integer, jugador_id uuid)
                 left join public.enfrentamientos e on e.id = x.enfrentamiento_id and e.lista_id = p_lista_id
                 left join public.modalidades m on m.codigo = e.modalidad_codigo
                where e.id is null or x.jugador_id is null or x.posicion is null
                   or x.posicion < 1 or x.posicion > m.jugadores_por_enfrentamiento) then
        perform privado.error('POSICION_INVALIDA', 'Hay posiciones que no corresponden a esta lista o a su modalidad.');
    end if;

    if exists (select 1
                 from jsonb_to_recordset(p_posiciones) as x(enfrentamiento_id uuid, posicion integer)
                group by x.enfrentamiento_id, x.posicion
               having count(*) > 1) then
        perform privado.error('POSICION_DUPLICADA', 'Una misma posición fue asignada más de una vez.');
    end if;

    if exists (select 1
                 from jsonb_to_recordset(p_posiciones) as x(jugador_id uuid)
                 left join public.jugadores j
                        on j.id = x.jugador_id and j.club_id = v_club and j.estado = 'ACTIVO'
                 left join public.asistencias a
                        on a.partido_id = v_partido.id and a.jugador_id = x.jugador_id and a.estado = 'PRESENTE'
                where j.id is null or a.id is null) then
        perform privado.error('JUGADOR_NO_HABILITADO',
            'Solo pueden ser convocados jugadores ACTIVOS del club marcados como PRESENTES.');
    end if;

    v_repetir := coalesce((privado.config('permite_jugador_repetido_en_lista', v_partido.campeonato_id, v_club))::boolean, false);
    if not v_repetir and exists (select 1
                                   from jsonb_to_recordset(p_posiciones) as x(jugador_id uuid)
                                  group by x.jugador_id
                                 having count(*) > 1) then
        perform privado.error('JUGADOR_REPETIDO', 'Un jugador no puede ocupar más de una posición en la misma lista.');
    end if;

    perform privado.fijar_contexto('GUARDAR_LISTA', p_motivo);

    delete from public.participantes_enfrentamiento where lista_id = p_lista_id;

    -- Jugadores retirados de la lista.
    for r in
        select c.*
          from public.convocatorias c
         where c.lista_id = p_lista_id
           and c.estado <> 'ANULADA_REEMPLAZO'
           and c.jugador_id not in (select x.jugador_id from jsonb_to_recordset(p_posiciones) as x(jugador_id uuid))
    loop
        if r.fue_confirmada then
            perform privado.exigir_motivo(p_motivo);
            update public.convocatorias
               set estado = 'ANULADA_REEMPLAZO', puntos = null,
                   anulada_at = now(), anulada_por = auth.uid(), motivo_anulacion = p_motivo
             where id = r.id;
        else
            delete from public.convocatorias where id = r.id;
        end if;
    end loop;

    -- Jugadores reincorporados: se reactiva su convocatoria histórica.
    update public.convocatorias c
       set estado = 'PROPUESTA', anulada_at = null, anulada_por = null, motivo_anulacion = null
     where c.lista_id = p_lista_id
       and c.estado = 'ANULADA_REEMPLAZO'
       and c.jugador_id in (select x.jugador_id from jsonb_to_recordset(p_posiciones) as x(jugador_id uuid));

    -- Jugadores nuevos.
    insert into public.convocatorias (lista_id, jugador_id)
    select distinct p_lista_id, x.jugador_id
      from jsonb_to_recordset(p_posiciones) as x(jugador_id uuid)
     where not exists (select 1 from public.convocatorias c
                        where c.lista_id = p_lista_id and c.jugador_id = x.jugador_id);

    insert into public.participantes_enfrentamiento (enfrentamiento_id, lista_id, convocatoria_id, posicion)
    select x.enfrentamiento_id, p_lista_id, c.id, x.posicion
      from jsonb_to_recordset(p_posiciones) as x(enfrentamiento_id uuid, posicion integer, jugador_id uuid)
      join public.convocatorias c on c.lista_id = p_lista_id and c.jugador_id = x.jugador_id;

    perform privado.fijar_contexto(null, null);

    return jsonb_build_object(
        'lista_id', p_lista_id,
        'posiciones_asignadas', (select count(*) from public.participantes_enfrentamiento pe where pe.lista_id = p_lista_id),
        'posiciones_requeridas', (select sum(m.jugadores_por_enfrentamiento)
                                    from public.enfrentamientos e join public.modalidades m on m.codigo = e.modalidad_codigo
                                   where e.lista_id = p_lista_id));
end;
$$;

-- Confirma la lista: exige 17/17 y consolida +convocatoria a cada jugador (una vez por lista).
create function public.confirmar_lista(p_lista_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_lista      public.listas_juego;
    v_partido    public.partidos;
    v_club       uuid;
    v_repetir    boolean;
    v_asignadas  integer;
    v_requeridas integer;
    v_puntos     numeric;
begin
    select * into v_lista from public.listas_juego where id = p_lista_id;
    if not found then
        perform privado.error('NO_ENCONTRADO', 'La lista no existe.');
    end if;
    v_partido := privado.bloquear_partido(v_lista.partido_id);
    select * into v_lista from public.listas_juego where id = p_lista_id;
    v_club := privado.club_gestionado(v_partido.id);

    perform privado.exigir_rol(v_club, array['CAPITAN', 'DIRECTIVA']);
    if v_partido.estado <> 'EN_CURSO' then
        perform privado.error('PARTIDO_NO_EN_CURSO', 'El partido no está EN_CURSO.');
    end if;
    if v_lista.estado <> 'BORRADOR' then
        perform privado.error('LISTA_NO_EDITABLE', 'La lista no está en edición.');
    end if;

    if exists (select 1 from public.modalidades m
                where m.activo
                  and m.enfrentamientos_por_lista <> (select count(*) from public.enfrentamientos e
                                                       where e.lista_id = p_lista_id and e.modalidad_codigo = m.codigo)) then
        perform privado.error('ESTRUCTURA_LISTA_INVALIDA', 'La lista no tiene la cantidad correcta de enfrentamientos por modalidad.');
    end if;

    select count(*) into v_asignadas from public.participantes_enfrentamiento pe where pe.lista_id = p_lista_id;
    select sum(m.jugadores_por_enfrentamiento) into v_requeridas
      from public.enfrentamientos e join public.modalidades m on m.codigo = e.modalidad_codigo
     where e.lista_id = p_lista_id;

    if v_asignadas <> v_requeridas
       or exists (select 1
                    from public.enfrentamientos e
                    join public.modalidades m on m.codigo = e.modalidad_codigo
                   where e.lista_id = p_lista_id
                     and (select count(*) from public.participantes_enfrentamiento pe
                           where pe.enfrentamiento_id = e.id) <> m.jugadores_por_enfrentamiento) then
        perform privado.error('LISTA_INCOMPLETA', 'La lista está incompleta.',
            format('%s / %s posiciones asignadas', v_asignadas, v_requeridas));
    end if;

    if exists (select 1
                 from public.convocatorias c
                 left join public.jugadores j
                        on j.id = c.jugador_id and j.club_id = v_club and j.estado = 'ACTIVO'
                 left join public.asistencias a
                        on a.partido_id = v_partido.id and a.jugador_id = c.jugador_id and a.estado = 'PRESENTE'
                where c.lista_id = p_lista_id and c.estado = 'PROPUESTA'
                  and (j.id is null or a.id is null)) then
        perform privado.error('JUGADOR_NO_HABILITADO',
            'Solo pueden ser convocados jugadores ACTIVOS del club marcados como PRESENTES.');
    end if;

    v_repetir := coalesce((privado.config('permite_jugador_repetido_en_lista', v_partido.campeonato_id, v_club))::boolean, false);
    if not v_repetir and exists (select 1 from public.participantes_enfrentamiento pe
                                  where pe.lista_id = p_lista_id
                                  group by pe.convocatoria_id having count(*) > 1) then
        perform privado.error('JUGADOR_REPETIDO', 'Un jugador no puede ocupar más de una posición en la misma lista.');
    end if;

    v_puntos := privado.valor_regla(v_partido.regla_version_id, 'CONVOCATORIA');

    perform privado.fijar_contexto('CONFIRMAR_LISTA', null);
    update public.convocatorias
       set estado = 'VIGENTE', puntos = v_puntos, fue_confirmada = true
     where lista_id = p_lista_id and estado = 'PROPUESTA';
    update public.listas_juego
       set estado = 'CONFIRMADA', confirmada_at = now(), confirmada_por = auth.uid()
     where id = p_lista_id;
    perform privado.fijar_contexto(null, null);

    return jsonb_build_object(
        'lista_id',   p_lista_id,
        'estado',     'CONFIRMADA',
        'convocados', (select count(*) from public.convocatorias c where c.lista_id = p_lista_id and c.estado = 'VIGENTE'));
end;
$$;

-- Devolución excepcional a edición (solo antes del primer resultado de la lista).
create function public.devolver_lista_a_edicion(p_lista_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_lista   public.listas_juego;
    v_partido public.partidos;
begin
    select * into v_lista from public.listas_juego where id = p_lista_id;
    if not found then
        perform privado.error('NO_ENCONTRADO', 'La lista no existe.');
    end if;
    v_partido := privado.bloquear_partido(v_lista.partido_id);
    select * into v_lista from public.listas_juego where id = p_lista_id;

    perform privado.exigir_rol(privado.club_gestionado(v_partido.id), array['CAPITAN', 'DIRECTIVA']);
    perform privado.exigir_motivo(p_motivo);
    if v_partido.estado <> 'EN_CURSO' then
        perform privado.error('PARTIDO_NO_EN_CURSO', 'El partido no está EN_CURSO.');
    end if;
    if v_lista.estado <> 'CONFIRMADA'
       or exists (select 1 from public.resultados_enfrentamiento r
                    join public.enfrentamientos e on e.id = r.enfrentamiento_id
                   where e.lista_id = p_lista_id) then
        perform privado.error('LISTA_INICIADA',
            'Solo una lista confirmada y sin resultados registrados puede volver a edición.');
    end if;

    perform privado.fijar_contexto('DEVOLVER_LISTA_A_EDICION', p_motivo);
    update public.listas_juego
       set estado = 'BORRADOR', confirmada_at = null, confirmada_por = null
     where id = p_lista_id;
    update public.convocatorias
       set estado = 'PROPUESTA', puntos = null
     where lista_id = p_lista_id and estado = 'VIGENTE';
    perform privado.fijar_contexto(null, null);

    return jsonb_build_object('lista_id', p_lista_id, 'estado', 'BORRADOR');
end;
$$;

-- ---------------------------------------------------------------------
-- 6. FUNCIONES RPC — RESULTADOS
-- p_resultado: 'GANADO' o 'PERDIDO' desde la perspectiva del club gestionado.
-- p_version: versión del enfrentamiento que vio el usuario (control de concurrencia).
-- ---------------------------------------------------------------------

create function public.registrar_resultado(
    p_enfrentamiento_id uuid,
    p_resultado         text,
    p_jugador_id        uuid,
    p_tipo_accion       text,
    p_version           integer)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_enf        public.enfrentamientos;
    v_lista      public.listas_juego;
    v_partido    public.partidos;
    v_club       uuid;
    v_ganador    uuid;
    v_part       uuid;
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
    v_ganador := privado.ganador_desde_resultado(p_resultado, v_club, privado.club_rival(v_partido, v_club));
    v_part := privado.participante_de(p_enfrentamiento_id, p_jugador_id);

    -- Reenvío idéntico (doble toque, reintento por mala señal): respuesta idempotente.
    if v_enf.estado_codigo = 'DISPUTADO' then
        if exists (select 1
                     from public.resultados_enfrentamiento r
                     join public.acciones_resultado a on a.resultado_id = r.id
                    where r.enfrentamiento_id = p_enfrentamiento_id and r.vigente
                      and r.ganador_club_id = v_ganador
                      and a.participante_id = v_part
                      and a.tipo_accion_codigo = p_tipo_accion) then
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
    if v_part is null then
        perform privado.error('JUGADOR_NO_PARTICIPA', 'El jugador indicado no participa en este enfrentamiento.');
    end if;
    perform privado.validar_polaridad(p_tipo_accion, v_ganador = v_club);

    perform privado.fijar_contexto('REGISTRAR_RESULTADO', null);

    insert into public.resultados_enfrentamiento
        (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota, registrado_por)
    values
        (p_enfrentamiento_id, v_ganador,
         privado.valor_regla(v_partido.regla_version_id, 'VICTORIA'),
         privado.valor_regla(v_partido.regla_version_id, 'DERROTA'),
         auth.uid())
    returning id into v_resultado;

    insert into public.acciones_resultado (resultado_id, enfrentamiento_id, participante_id, tipo_accion_codigo, puntos)
    values (v_resultado, p_enfrentamiento_id, v_part, p_tipo_accion,
            privado.valor_regla(v_partido.regla_version_id, p_tipo_accion));

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

-- Muestra el impacto de una corrección sin aplicarla.
create function public.previsualizar_correccion(p_enfrentamiento_id uuid, p_resultado text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_enf      public.enfrentamientos;
    v_partido  public.partidos;
    v_club     uuid;
    v_ganador  uuid;
    v_a        jsonb;
begin
    select * into v_enf from public.enfrentamientos where id = p_enfrentamiento_id;
    if not found then
        perform privado.error('NO_ENCONTRADO', 'El enfrentamiento no existe.');
    end if;
    select p.* into v_partido
      from public.partidos p join public.listas_juego l on l.partido_id = p.id
     where l.id = v_enf.lista_id;
    v_club := privado.club_gestionado(v_partido.id);

    if v_partido.estado = 'EN_REVISION' then
        perform privado.exigir_admin();
    else
        perform privado.exigir_rol(v_club, array['DIRECTIVA']);
    end if;
    if v_enf.estado_codigo <> 'DISPUTADO' then
        perform privado.error('ENFRENTAMIENTO_NO_DISPUTADO', 'Solo se corrigen enfrentamientos disputados.');
    end if;

    v_ganador := privado.ganador_desde_resultado(p_resultado, v_club, privado.club_rival(v_partido, v_club));
    v_a := privado.analizar_secuencia(v_partido.id, p_enfrentamiento_id, v_ganador);

    return jsonb_build_object(
        'actual', privado.estado_partido(v_partido.id),
        'propuesto', jsonb_build_object(
            'puntaje_local',     v_a -> 'puntaje_local',
            'puntaje_visitante', v_a -> 'puntaje_visitante',
            'ganador_club_id',   v_a -> 'ganador_club_id',
            'estado', case when v_a ->> 'cierre_enfrentamiento_id' is null then 'EN_CURSO'
                           when v_partido.estado = 'EN_REVISION' then 'EN_REVISION'
                           else 'FINALIZADO' end),
        'requiere_confirmacion', jsonb_array_length(v_a -> 'invalidados') > 0,
        'invalidados', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'enfrentamiento_id', e.id, 'lista', l.numero,
                       'modalidad', e.modalidad_codigo, 'numero', e.numero)
                     order by l.numero, e.orden_juego)
              from public.enfrentamientos e
              join public.listas_juego l on l.id = e.lista_id
             where e.id in (select (x #>> '{}')::uuid from jsonb_array_elements(v_a -> 'invalidados') x)),
            '[]'::jsonb));
end;
$$;

-- Corrección de un resultado registrado por error.
--   EN_CURSO   : DIRECTIVA o ADMINISTRADOR.
--   EN_REVISION: solo ADMINISTRADOR (partido reabierto).
--   FINALIZADO : debe reabrirse primero.
-- Si la corrección adelanta el cierre (P-1), exige p_confirmar_impacto = true.
create function public.corregir_resultado(
    p_enfrentamiento_id  uuid,
    p_resultado          text,
    p_jugador_id         uuid,
    p_tipo_accion        text,
    p_motivo             text,
    p_version            integer,
    p_confirmar_impacto  boolean default false)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_enf        public.enfrentamientos;
    v_lista      public.listas_juego;
    v_partido    public.partidos;
    v_club       uuid;
    v_ganador    uuid;
    v_part       uuid;
    v_anterior   record;
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
    v_part := privado.participante_de(p_enfrentamiento_id, p_jugador_id);
    if v_part is null then
        perform privado.error('JUGADOR_NO_PARTICIPA', 'El jugador indicado no participa en este enfrentamiento.');
    end if;
    perform privado.validar_polaridad(p_tipo_accion, v_ganador = v_club);

    select r.id, r.ganador_club_id, a.participante_id, a.tipo_accion_codigo
      into v_anterior
      from public.resultados_enfrentamiento r
      join public.acciones_resultado a on a.resultado_id = r.id
     where r.enfrentamiento_id = p_enfrentamiento_id and r.vigente;

    if v_anterior.ganador_club_id = v_ganador
       and v_anterior.participante_id = v_part
       and v_anterior.tipo_accion_codigo = p_tipo_accion then
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
        (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota, reemplaza_a_id, registrado_por)
    values
        (p_enfrentamiento_id, v_ganador,
         privado.valor_regla(v_partido.regla_version_id, 'VICTORIA'),
         privado.valor_regla(v_partido.regla_version_id, 'DERROTA'),
         v_anterior.id, auth.uid())
    returning id into v_nuevo;

    insert into public.acciones_resultado (resultado_id, enfrentamiento_id, participante_id, tipo_accion_codigo, puntos)
    values (v_nuevo, p_enfrentamiento_id, v_part, p_tipo_accion,
            privado.valor_regla(v_partido.regla_version_id, p_tipo_accion));

    update public.enfrentamientos set version = version + 1 where id = p_enfrentamiento_id;

    v_a := privado.aplicar_secuencia(v_partido.id, p_motivo);
    perform privado.fijar_contexto(null, null);

    return privado.estado_partido(v_partido.id)
        || jsonb_build_object('invalidados', v_a -> 'invalidados');
end;
$$;

-- ---------------------------------------------------------------------
-- 7. FUNCIONES RPC — REAPERTURA Y REVISIÓN (solo ADMINISTRADOR)
-- ---------------------------------------------------------------------

create function public.reabrir_partido(p_partido_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_partido public.partidos;
begin
    perform privado.exigir_admin();
    perform privado.exigir_motivo(p_motivo);
    v_partido := privado.bloquear_partido(p_partido_id);
    if v_partido.estado <> 'FINALIZADO' then
        perform privado.error('ESTADO_NO_PERMITE', 'Solo se reabre un partido FINALIZADO.');
    end if;

    perform privado.fijar_contexto('REABRIR_PARTIDO', p_motivo);
    update public.partidos set estado = 'EN_REVISION', version = version + 1 where id = p_partido_id;
    perform privado.fijar_contexto(null, null);
    return privado.estado_partido(p_partido_id);
end;
$$;

create function public.cerrar_revision(p_partido_id uuid, p_motivo text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_partido   public.partidos;
    v_problemas jsonb;
begin
    perform privado.exigir_admin();
    v_partido := privado.bloquear_partido(p_partido_id);
    if v_partido.estado <> 'EN_REVISION' then
        perform privado.error('ESTADO_NO_PERMITE', 'El partido no está EN_REVISION.');
    end if;
    v_problemas := privado.verificar_partido(p_partido_id);
    if jsonb_array_length(v_problemas) > 0 then
        perform privado.error('INCONSISTENCIA', 'El partido presenta inconsistencias y no puede cerrarse.', v_problemas::text);
    end if;

    perform privado.fijar_contexto('CERRAR_REVISION', p_motivo);
    update public.partidos set estado = 'FINALIZADO', version = version + 1 where id = p_partido_id;
    perform privado.fijar_contexto(null, null);
    return privado.estado_partido(p_partido_id);
end;
$$;

-- ---------------------------------------------------------------------
-- 8. FUNCIONES RPC — REGLAS Y VERIFICACIÓN
-- ---------------------------------------------------------------------

-- Activa una versión de reglas para los partidos que se inicien desde ahora.
-- Los partidos ya iniciados conservan su versión (C-2).
create function public.activar_regla_version(p_version_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
    perform privado.exigir_admin();
    if not exists (select 1 from public.reglas_puntuacion_versiones v where v.id = p_version_id) then
        perform privado.error('NO_ENCONTRADO', 'La versión de reglas no existe.');
    end if;
    if exists (select 1 from public.conceptos_puntuacion c
                where not exists (select 1 from public.reglas_puntuacion_valores r
                                   where r.regla_version_id = p_version_id and r.concepto_codigo = c.codigo)) then
        perform privado.error('REGLA_INCOMPLETA', 'La versión no define un valor para todos los conceptos.');
    end if;
    if exists (select 1 from public.tipos_accion t
                 join public.reglas_puntuacion_valores r on r.concepto_codigo = t.codigo
                where r.regla_version_id = p_version_id
                  and ((t.polaridad = 'POSITIVA' and r.valor < 0) or (t.polaridad = 'NEGATIVA' and r.valor > 0))) then
        perform privado.error('REGLA_SIGNO_INVALIDO', 'Las acciones positivas no pueden restar ni las negativas sumar.');
    end if;

    perform privado.fijar_contexto('ACTIVAR_REGLAS', null);
    update public.reglas_puntuacion_versiones set es_vigente = false where es_vigente and id <> p_version_id;
    update public.reglas_puntuacion_versiones set es_vigente = true, vigente_desde = now() where id = p_version_id and not es_vigente;
    perform privado.fijar_contexto(null, null);

    return jsonb_build_object('regla_version_id', p_version_id, 'es_vigente', true);
end;
$$;

create function public.verificar_partido(p_partido_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
    if not privado.puede_ver_partido(p_partido_id) then
        raise exception using errcode = '42501', message = 'Permiso denegado para esta operación.', hint = 'PERMISO_DENEGADO';
    end if;
    return jsonb_build_object('partido_id', p_partido_id, 'problemas', privado.verificar_partido(p_partido_id));
end;
$$;

-- ---------------------------------------------------------------------
-- 9. PRIVILEGIOS
-- ---------------------------------------------------------------------

revoke all on all functions in schema privado from public, anon;
revoke all on all functions in schema public  from public, anon;

grant execute on function
    public.iniciar_partido(uuid),
    public.suspender_partido(uuid, text),
    public.reanudar_partido(uuid),
    public.cancelar_partido(uuid, text),
    public.registrar_asistencia(uuid, jsonb),
    public.crear_lista(uuid),
    public.guardar_lista(uuid, jsonb, text),
    public.confirmar_lista(uuid),
    public.devolver_lista_a_edicion(uuid, text),
    public.registrar_resultado(uuid, text, uuid, text, integer),
    public.previsualizar_correccion(uuid, text),
    public.corregir_resultado(uuid, text, uuid, text, text, integer, boolean),
    public.reabrir_partido(uuid, text),
    public.cerrar_revision(uuid, text),
    public.activar_regla_version(uuid),
    public.verificar_partido(uuid)
to authenticated;

-- ---------------------------------------------------------------------
-- 10. REGISTRO DE LA MIGRACIÓN
-- ---------------------------------------------------------------------

insert into public.migraciones_aplicadas (version, descripcion)
values ('003', 'Reglas de juego: validaciones entre tablas y funciones RPC (asistencia, listas, resultados, cierre a 30, correcciones, reapertura)');

commit;
