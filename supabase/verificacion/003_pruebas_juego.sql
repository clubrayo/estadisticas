-- =====================================================================
-- PRUEBAS 003 — REGLAS DE JUEGO, RPC Y CASOS OBLIGATORIOS (SECCIÓN 51)
-- Actualizadas a la migración 004: derrotas de duplas/tríos con una acción
-- negativa por integrante y nuevas firmas de registrar/corregir.
-- Simula partidos completos actuando como cada rol y DESHACE TODO al final
-- (no queda ningún usuario, partido ni dato de prueba).
-- Resultado esperado: todas las filas con ok = true.
--
-- Columna "esperado":
--   P0001:CODIGO : rechazo de negocio con su código (p. ej. P0001:ORDEN_DE_JUEGO).
--   42501:...    : rechazo por permisos.
--   otro         : valor exacto que debe leerse (marcadores, puntajes, estados).
--
-- Nota: el SQL Editor puede advertir "operaciones destructivas". Todo se
-- deshace al final. Elija "Correr sin RLS" / "Run without RLS" si aparece.
-- =====================================================================

-- ---------- Utilidades de prueba ----------

create or replace function pg_temp.como3(p_uid uuid, p_sql text)
returns text
language plpgsql
as $$
declare
    v_txt  text;
    v_n    bigint;
    v_hint text;
begin
    begin
        perform set_config('request.jwt.claims',
                           json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
        execute 'set local role authenticated';
        if ltrim(lower(p_sql)) like 'select%' then
            execute p_sql into v_txt;
        else
            execute p_sql;
            get diagnostics v_n = row_count;
            v_txt := 'FILAS:' || v_n;
        end if;
        execute 'reset role';
        perform set_config('request.jwt.claims', '', true);
        return v_txt;
    exception when others then
        get stacked diagnostics v_hint = pg_exception_hint;
        return sqlstate || case when coalesce(v_hint, '') <> '' then ':' || v_hint else '' end;
    end;
end;
$$;

create or replace function pg_temp.sistema3(p_sql text, p_sql2 text default null)
returns text
language plpgsql
as $$
declare
    v_txt  text;
    v_n    bigint;
    v_hint text;
begin
    if ltrim(lower(p_sql)) like 'select%' then
        execute p_sql into v_txt;
    else
        execute p_sql;
        get diagnostics v_n = row_count;
        v_txt := 'FILAS:' || v_n;
    end if;
    if p_sql2 is not null then
        execute p_sql2;
    end if;
    return v_txt;
exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    return sqlstate || case when coalesce(v_hint, '') <> '' then ':' || v_hint else '' end;
end;
$$;

create or replace function pg_temp.fila3(p_n int, p_g text, p_p text, p_e text, p_o text)
returns jsonb
language sql
as $$
    select jsonb_build_array(jsonb_build_object('n', p_n, 'g', p_g, 'p', p_p, 'e', p_e, 'o', coalesce(p_o, '(nulo)')));
$$;

create or replace function pg_temp.enf(p_lista uuid, p_orden int)
returns uuid
language sql
as $$
    select id from public.enfrentamientos where lista_id = p_lista and orden_juego = p_orden;
$$;

-- Jugador que ocupa la posición p_pos del enfrentamiento p_orden.
create or replace function pg_temp.jugador_en(p_lista uuid, p_orden int, p_pos int)
returns uuid
language sql
as $$
    select c.jugador_id
      from public.participantes_enfrentamiento pe
      join public.convocatorias c on c.id = pe.convocatoria_id
     where pe.enfrentamiento_id = pg_temp.enf(p_lista, p_orden) and pe.posicion = p_pos;
$$;

-- Acciones del enfrentamiento según la regla de la migración 004:
--   victoria: una acción p_tipo (por defecto CORTO) del jugador en p_pos;
--   derrota:  cada integrante con una negativa (p_tipo para p_pos, LO_CORTARON para el resto).
create or replace function pg_temp.acciones(p_lista uuid, p_orden int, p_gano boolean,
                                            p_pos int default 1, p_tipo text default null)
returns jsonb
language sql
as $$
    select case when p_gano
        then jsonb_build_array(jsonb_build_object(
                 'jugador_id', pg_temp.jugador_en(p_lista, p_orden, p_pos),
                 'tipo_accion', coalesce(p_tipo, 'CORTO')))
        else (select jsonb_agg(jsonb_build_object(
                         'jugador_id', c.jugador_id,
                         'tipo_accion', case when pe.posicion = p_pos then coalesce(p_tipo, 'LO_CORTARON') else 'LO_CORTARON' end)
                       order by pe.posicion)
                from public.participantes_enfrentamiento pe
                join public.convocatorias c on c.id = pe.convocatoria_id
               where pe.enfrentamiento_id = pg_temp.enf(p_lista, p_orden))
    end;
$$;

-- Registra el resultado del enfrentamiento p_orden de la lista.
create or replace function pg_temp.jugar(p_uid uuid, p_lista uuid, p_orden int, p_gano boolean,
                                         p_pos int default 1, p_tipo text default null, p_version int default null)
returns text
language plpgsql
as $$
declare
    v_enf uuid := pg_temp.enf(p_lista, p_orden);
    v_ver int;
begin
    select version into v_ver from public.enfrentamientos where id = v_enf;
    return pg_temp.como3(p_uid, format(
        'select public.registrar_resultado(%L, %L, %L::jsonb, %s)::text',
        v_enf,
        case when p_gano then 'GANADO' else 'PERDIDO' end,
        pg_temp.acciones(p_lista, p_orden, p_gano, p_pos, p_tipo),
        coalesce(p_version, v_ver)));
end;
$$;

create or replace function pg_temp.corregir(p_uid uuid, p_lista uuid, p_orden int, p_gano boolean,
                                            p_motivo text, p_confirmar boolean default false,
                                            p_pos int default 1, p_tipo text default null)
returns text
language plpgsql
as $$
declare
    v_enf uuid := pg_temp.enf(p_lista, p_orden);
    v_ver int;
begin
    select version into v_ver from public.enfrentamientos where id = v_enf;
    return pg_temp.como3(p_uid, format(
        'select public.corregir_resultado(%L, %L, %L::jsonb, %L, %s, %L)::text',
        v_enf,
        case when p_gano then 'GANADO' else 'PERDIDO' end,
        pg_temp.acciones(p_lista, p_orden, p_gano, p_pos, p_tipo),
        p_motivo, v_ver, p_confirmar));
end;
$$;

-- Resume una respuesta RPC como "ESTADO local-visitante" (o devuelve el error).
create or replace function pg_temp.m(p_respuesta text)
returns text
language sql
as $$
    select case when left(p_respuesta, 1) = '{'
                then (p_respuesta::jsonb ->> 'estado') || ' ' || (p_respuesta::jsonb ->> 'puntaje_local')
                     || '-' || (p_respuesta::jsonb ->> 'puntaje_visitante')
                else p_respuesta end;
$$;

-- Juega una lista según un patrón de 10 letras (G = gana, P = pierde).
create or replace function pg_temp.jugar_patron(p_uid uuid, p_lista uuid, p_patron text)
returns text
language plpgsql
as $$
declare
    v text;
begin
    for i in 1 .. length(p_patron) loop
        v := pg_temp.jugar(p_uid, p_lista, i, substr(p_patron, i, 1) = 'G');
        if left(v, 1) <> '{' then
            return 'ERROR@' || i || ':' || v;
        end if;
        if (v::jsonb ->> 'estado') = 'FINALIZADO' then
            return (v::jsonb ->> 'puntaje_local') || '-' || (v::jsonb ->> 'puntaje_visitante') || '@' || i;
        end if;
    end loop;
    return (v::jsonb ->> 'puntaje_local') || '-' || (v::jsonb ->> 'puntaje_visitante');
end;
$$;

-- Asigna los jugadores del arreglo a las posiciones de la lista, en orden de planilla.
create or replace function pg_temp.armar(p_uid uuid, p_lista uuid, p_jug uuid[], p_motivo text default null)
returns text
language plpgsql
as $$
declare
    v_pos jsonb;
begin
    select jsonb_agg(jsonb_build_object('enfrentamiento_id', s.id, 'posicion', s.pos, 'jugador_id', p_jug[s.rn]))
      into v_pos
      from (select e.id, g.pos, row_number() over (order by e.orden_juego, g.pos) as rn
              from public.enfrentamientos e
              join public.modalidades m on m.codigo = e.modalidad_codigo
             cross join lateral generate_series(1, m.jugadores_por_enfrentamiento) as g(pos)
             where e.lista_id = p_lista) s
     where s.rn <= array_length(p_jug, 1);
    return pg_temp.como3(p_uid, format('select (public.guardar_lista(%L, %L::jsonb, %L)) ->> ''posiciones_asignadas''',
                                      p_lista, v_pos, p_motivo));
end;
$$;

create or replace function pg_temp.nueva_lista(p_uid uuid, p_partido uuid)
returns uuid
language plpgsql
as $$
declare
    v text := pg_temp.como3(p_uid, format('select (public.crear_lista(%L)) ->> ''lista_id''', p_partido));
begin
    if v !~ '^[0-9a-f-]{36}$' then
        raise exception 'No se pudo crear la lista: %', v;
    end if;
    return v::uuid;
end;
$$;

-- Crea, completa y confirma una lista.
create or replace function pg_temp.lista_confirmada(p_uid uuid, p_partido uuid, p_jug uuid[])
returns uuid
language plpgsql
as $$
declare
    v_lista uuid := pg_temp.nueva_lista(p_uid, p_partido);
    v       text;
begin
    v := pg_temp.armar(p_uid, v_lista, p_jug);
    v := pg_temp.como3(p_uid, format('select (public.confirmar_lista(%L)) ->> ''estado''', v_lista));
    if v <> 'CONFIRMADA' then
        raise exception 'No se pudo confirmar la lista: %', v;
    end if;
    return v_lista;
end;
$$;

-- Puntaje estadístico de un jugador en una lista: convocatoria + resultado + acción.
create or replace function pg_temp.puntos(p_lista uuid, p_jugador uuid)
returns text
language sql
as $$
    select (coalesce((select sum(c.puntos) from public.convocatorias c
                       where c.lista_id = p_lista and c.jugador_id = p_jugador and c.estado = 'VIGENTE'), 0)
          + coalesce((select sum(case when c.club_id = r.ganador_club_id then r.puntos_victoria else r.puntos_derrota end)
                        from public.participantes_enfrentamiento pe
                        join public.convocatorias c on c.id = pe.convocatoria_id
                        join public.enfrentamientos e on e.id = pe.enfrentamiento_id
                        join public.resultados_enfrentamiento r on r.enfrentamiento_id = e.id and r.vigente
                       where pe.lista_id = p_lista and c.jugador_id = p_jugador and e.estado_codigo = 'DISPUTADO'), 0)
          + coalesce((select sum(a.puntos)
                        from public.acciones_resultado a
                        join public.resultados_enfrentamiento r on r.id = a.resultado_id and r.vigente
                        join public.participantes_enfrentamiento pe on pe.id = a.participante_id
                        join public.convocatorias c on c.id = pe.convocatoria_id
                       where pe.lista_id = p_lista and c.jugador_id = p_jugador), 0))::text;
$$;

-- Enfrentamientos jugados (EJ) de un jugador en una lista.
create or replace function pg_temp.ej(p_lista uuid, p_jugador uuid)
returns text
language sql
as $$
    select count(*)::text
      from public.participantes_enfrentamiento pe
      join public.convocatorias c on c.id = pe.convocatoria_id
      join public.enfrentamientos e on e.id = pe.enfrentamiento_id
      join public.estados_enfrentamiento ee on ee.codigo = e.estado_codigo
     where pe.lista_id = p_lista and c.jugador_id = p_jugador and ee.cuenta_como_ej;
$$;

create or replace function pg_temp.marcador(p_partido uuid)
returns text
language sql
as $$
    select estado || ' ' || puntaje_local || '-' || puntaje_visitante from public.partidos where id = p_partido;
$$;

-- ---------- Pruebas ----------

create or replace function pg_temp.ejecutar_pruebas_003()
returns table (n int, grupo text, prueba text, esperado text, obtenido text, ok boolean)
language plpgsql
as $$
declare
    r        jsonb := '[]'::jsonb;
    u_admin  uuid := gen_random_uuid();
    u_dir    uuid := gen_random_uuid();
    u_cap    uuid := gen_random_uuid();
    u_con    uuid := gen_random_uuid();
    v_rayo   uuid;
    v_rival  uuid;
    v_rival2 uuid;
    v_camp   uuid;
    j        uuid[] := '{}';
    v_17     uuid[];
    v_asis   jsonb;
    pa       uuid;  -- partido A: necesita lista 6 y termina a mitad de ella
    pb       uuid;  -- partido B: termina exactamente 30-20 (con reglas V2)
    pc       uuid;  -- partido C: suspensión, concurrencia y cancelación
    pd       uuid;  -- partido D: cancelación sin resultados
    la       uuid[] := '{}';
    lb       uuid;
    lc       uuid;
    v_l      uuid;
    v_txt    text;
    v_ver    int;
    v_id     uuid;
begin
    begin
        -- ===================== DATOS FICTICIOS =====================
        select id into v_rayo from public.clubes where nombre_corto = 'RAYO';

        insert into auth.users (id, email) values
            (u_admin, 'zz3.admin@zzprueba.invalid'),
            (u_dir,   'zz3.directiva@zzprueba.invalid'),
            (u_cap,   'zz3.capitan@zzprueba.invalid'),
            (u_con,   'zz3.consulta@zzprueba.invalid');
        insert into public.usuario_roles (usuario_id, rol_codigo, club_id) values
            (u_admin, 'ADMINISTRADOR', null),
            (u_dir,   'DIRECTIVA',     v_rayo),
            (u_cap,   'CAPITAN',       v_rayo),
            (u_con,   'CONSULTA',      v_rayo);

        insert into public.clubes (nombre, nombre_corto) values ('ZZPRUEBA SHOOKER', 'ZZP_SHOOK') returning id into v_rival;
        insert into public.clubes (nombre, nombre_corto) values ('ZZPRUEBA OTRO RIVAL', 'ZZP_OTRO_R') returning id into v_rival2;

        for i in 1 .. 20 loop
            insert into public.jugadores (club_id, primer_nombre, apellidos)
                 values (v_rayo, 'Zz', 'ZZPRUEBA ' || lpad(i::text, 2, '0'))
              returning id into v_id;
            j := j || v_id;
        end loop;
        update public.jugadores set estado = 'INACTIVO' where id = j[20];
        v_17 := j[1:17];

        insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo)
             values ('ZZPRUEBA CAMPEONATO 003', 'ZZ', current_date, 30) returning id into v_camp;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (v_camp, current_date, v_rayo, v_rival) returning id into pa;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (v_camp, current_date, v_rayo, v_rival) returning id into pb;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (v_camp, current_date, v_rayo, v_rival) returning id into pc;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (v_camp, current_date, v_rayo, v_rival) returning id into pd;

        select jsonb_agg(jsonb_build_object('jugador_id', x, 'estado', 'PRESENTE')) into v_asis from unnest(j[1:18]) as x;
        v_asis := v_asis || jsonb_build_array(jsonb_build_object('jugador_id', j[19], 'estado', 'AUSENTE'));

        -- ===================== PARTIDO Y ASISTENCIA =====================
        r := r || pg_temp.fila3(1, 'Partido', 'No se crean listas en partido PROGRAMADO', 'P0001:PARTIDO_NO_EN_CURSO',
             pg_temp.como3(u_cap, format('select public.crear_lista(%L)::text', pa)));
        r := r || pg_temp.fila3(2, 'Partido', 'CONSULTA no inicia partidos', '42501:PERMISO_DENEGADO',
             pg_temp.como3(u_con, format('select public.iniciar_partido(%L)::text', pa)));
        r := r || pg_temp.fila3(3, 'Partido', 'CAPITÁN inicia el partido', 'EN_CURSO',
             pg_temp.como3(u_cap, format('select (public.iniciar_partido(%L)) ->> ''estado''', pa)));
        r := r || pg_temp.fila3(4, 'Partido', 'Al iniciar queda fijada la versión de reglas vigente', 'V1',
             pg_temp.sistema3(format('select v.codigo from public.partidos p join public.reglas_puntuacion_versiones v on v.id = p.regla_version_id where p.id = %L', pa)));
        r := r || pg_temp.fila3(5, 'Partido', 'No se inicia dos veces', 'P0001:ESTADO_NO_PERMITE',
             pg_temp.como3(u_cap, format('select public.iniciar_partido(%L)::text', pa)));

        r := r || pg_temp.fila3(6, 'Asistencia', 'Registro masivo: total|presentes|ausentes|justificados|%', '19|18|1|0|94.74',
             pg_temp.como3(u_cap, format('select x ->> ''total'' || ''|'' || (x ->> ''presentes'') || ''|'' || (x ->> ''ausentes'') || ''|'' || (x ->> ''justificados'') || ''|'' || (x ->> ''porcentaje_asistencia'') from (select public.registrar_asistencia(%L, %L::jsonb) as x) s', pa, v_asis)));
        r := r || pg_temp.fila3(7, 'Asistencia', 'Rechaza jugador INACTIVO', 'P0001:JUGADOR_INACTIVO',
             pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pa, jsonb_build_array(jsonb_build_object('jugador_id', j[20], 'estado', 'PRESENTE')))));
        r := r || pg_temp.fila3(8, 'Asistencia', 'Rechaza estado inválido', 'P0001:ESTADO_ASISTENCIA_INVALIDO',
             pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pa, jsonb_build_array(jsonb_build_object('jugador_id', j[1], 'estado', 'TARDE')))));
        r := r || pg_temp.fila3(9, 'Asistencia', 'CONSULTA no registra asistencia', '42501:PERMISO_DENEGADO',
             pg_temp.como3(u_con, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pa, v_asis)));

        -- ===================== LISTAS =====================
        v_l := pg_temp.nueva_lista(u_cap, pa);
        la := la || v_l;
        r := r || pg_temp.fila3(10, 'Listas', 'Lista generada en orden de planilla (5 ind, 3 duplas, 2 tríos)', 'I1,I2,I3,I4,I5,D1,D2,D3,T1,T2',
             pg_temp.sistema3(format('select string_agg(left(modalidad_codigo, 1) || numero, '','' order by orden_juego) from public.enfrentamientos where lista_id = %L', v_l)));
        r := r || pg_temp.fila3(11, 'Listas', 'No se crea otra lista con una abierta', 'P0001:LISTA_ABIERTA',
             pg_temp.como3(u_cap, format('select public.crear_lista(%L)::text', pa)));
        r := r || pg_temp.fila3(12, 'Listas', 'Rechaza jugador AUSENTE', 'P0001:JUGADOR_NO_HABILITADO',
             pg_temp.armar(u_cap, v_l, j[1:16] || j[19]));
        r := r || pg_temp.fila3(13, 'Listas', 'Rechaza jugador repetido en la lista', 'P0001:JUGADOR_REPETIDO',
             pg_temp.armar(u_cap, v_l, j[1:16] || j[1]));
        r := r || pg_temp.fila3(14, 'Listas', 'Rechaza posición fuera de la modalidad (2 en individual)', 'P0001:POSICION_INVALIDA',
             pg_temp.como3(u_cap, format('select public.guardar_lista(%L, %L::jsonb)::text', v_l,
                 jsonb_build_array(jsonb_build_object('enfrentamiento_id', pg_temp.enf(v_l, 1), 'posicion', 2, 'jugador_id', j[1])))));
        r := r || pg_temp.fila3(15, 'Listas', 'Guarda borrador parcial (16 de 17)', '16', pg_temp.armar(u_cap, v_l, j[1:16]));
        r := r || pg_temp.fila3(16, 'Listas', 'No confirma una lista incompleta', 'P0001:LISTA_INCOMPLETA',
             pg_temp.como3(u_cap, format('select public.confirmar_lista(%L)::text', v_l)));
        r := r || pg_temp.fila3(17, 'Listas', 'Guarda la lista completa', '17', pg_temp.armar(u_cap, v_l, v_17));
        r := r || pg_temp.fila3(18, 'Listas', 'Confirma la lista: 17 convocados', '17',
             pg_temp.como3(u_cap, format('select (public.confirmar_lista(%L)) ->> ''convocados''', v_l)));
        r := r || pg_temp.fila3(19, 'Listas', 'Cada convocado recibe +0.50 una sola vez', '17|0.50|0.50',
             pg_temp.sistema3(format('select count(*) || ''|'' || min(puntos) || ''|'' || max(puntos) from public.convocatorias where lista_id = %L and estado = ''VIGENTE''', v_l)));
        r := r || pg_temp.fila3(20, 'Listas', 'Convocado no puede quedar AUSENTE', 'P0001:JUGADOR_CONVOCADO',
             pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pa, jsonb_build_array(jsonb_build_object('jugador_id', j[1], 'estado', 'AUSENTE')))));
        r := r || pg_temp.fila3(21, 'Listas', 'Lista confirmada no se edita', 'P0001:LISTA_NO_EDITABLE', pg_temp.armar(u_cap, v_l, v_17));
        r := r || pg_temp.fila3(22, 'Reemplazo', 'Devolver a edición exige motivo', 'P0001:MOTIVO_REQUERIDO',
             pg_temp.como3(u_cap, format('select public.devolver_lista_a_edicion(%L, null)::text', v_l)));
        r := r || pg_temp.fila3(23, 'Reemplazo', 'Devuelve la lista a edición antes de jugar', 'BORRADOR',
             pg_temp.como3(u_cap, format('select (public.devolver_lista_a_edicion(%L, ''Lesión de jugador 17'')) ->> ''estado''', v_l)));
        r := r || pg_temp.fila3(24, 'Reemplazo', 'Retirar a un convocado exige motivo', 'P0001:MOTIVO_REQUERIDO',
             pg_temp.armar(u_cap, v_l, j[1:16] || j[18]));
        r := r || pg_temp.fila3(25, 'Reemplazo', 'Reemplaza jugador 17 por 18 con motivo', '17',
             pg_temp.armar(u_cap, v_l, j[1:16] || j[18], 'Lesión de jugador 17'));
        r := r || pg_temp.fila3(26, 'Reemplazo', 'Retirado queda ANULADA_REEMPLAZO con motivo', 'ANULADA_REEMPLAZO|Lesión de jugador 17',
             pg_temp.sistema3(format('select estado || ''|'' || motivo_anulacion from public.convocatorias where lista_id = %L and jugador_id = %L', v_l, j[17])));
        perform pg_temp.como3(u_cap, format('select public.confirmar_lista(%L)::text', v_l));
        r := r || pg_temp.fila3(27, 'Reemplazo', 'Retirado no suma convocatoria; ingresado sí', '0|0.50',
             pg_temp.puntos(v_l, j[17]) || '|' || pg_temp.puntos(v_l, j[18]));
        perform pg_temp.como3(u_cap, format('select public.devolver_lista_a_edicion(%L, ''Jugador 17 recuperado'')::text', v_l));
        perform pg_temp.armar(u_cap, v_l, v_17, 'Jugador 17 recuperado');
        perform pg_temp.como3(u_cap, format('select public.confirmar_lista(%L)::text', v_l));
        r := r || pg_temp.fila3(28, 'Reemplazo', 'Reincorporado reutiliza su única convocatoria', '1|VIGENTE|0.50',
             pg_temp.sistema3(format('select count(*) || ''|'' || min(estado) || ''|'' || min(puntos) from public.convocatorias where lista_id = %L and jugador_id = %L', v_l, j[17])));
        r := r || pg_temp.fila3(29, 'Reemplazo', 'Jugador 18 queda anulado y sin puntos', 'ANULADA_REEMPLAZO|0',
             pg_temp.sistema3(format('select estado from public.convocatorias where lista_id = %L and jugador_id = %L', v_l, j[18])) || '|' || pg_temp.puntos(v_l, j[18]));

        -- ===================== REGISTRO DE RESULTADOS (LISTA 1) =====================
        r := r || pg_temp.fila3(30, 'Resultados', 'Respeta el orden de la planilla', 'P0001:ORDEN_DE_JUEGO',
             pg_temp.jugar(u_cap, v_l, 2, true));
        r := r || pg_temp.fila3(31, 'Resultados', 'CONSULTA no registra resultados', '42501:PERMISO_DENEGADO',
             pg_temp.jugar(u_con, v_l, 1, true));
        r := r || pg_temp.fila3(32, 'Resultados', 'Victoria con causa negativa es rechazada', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.jugar(u_cap, v_l, 1, true, 1, 'LO_CORTARON'));
        r := r || pg_temp.fila3(33, 'Resultados', 'Acción de jugador que no participa es rechazada', 'P0001:JUGADOR_NO_PARTICIPA',
             pg_temp.como3(u_cap, format('select public.registrar_resultado(%L, ''GANADO'', %L::jsonb, 1)::text', pg_temp.enf(v_l, 1), jsonb_build_array(jsonb_build_object('jugador_id', j[2], 'tipo_accion', 'CORTO')))));
        r := r || pg_temp.fila3(34, 'Resultados', 'Versión desactualizada es rechazada', 'P0001:CONFLICTO_VERSION',
             pg_temp.jugar(u_cap, v_l, 1, true, 1, null, 99));
        select version into v_ver from public.enfrentamientos where id = pg_temp.enf(v_l, 1);
        r := r || pg_temp.fila3(35, 'Resultados', 'Individual 1 gana por corte: marcador 1-0', 'EN_CURSO 1-0',
             pg_temp.m(pg_temp.jugar(u_cap, v_l, 1, true, 1, 'CORTO')));
        r := r || pg_temp.fila3(36, 'Concurrencia', 'Segundo usuario reenvía lo mismo: idempotente', 'true',
             pg_temp.como3(u_dir, format('select (public.registrar_resultado(%L, ''GANADO'', %L::jsonb, %s)) ->> ''ya_registrado''', pg_temp.enf(v_l, 1), jsonb_build_array(jsonb_build_object('jugador_id', j[1], 'tipo_accion', 'CORTO')), v_ver)));
        r := r || pg_temp.fila3(37, 'Concurrencia', 'Segundo usuario con otro resultado: conflicto, sin duplicar', 'P0001:ENFRENTAMIENTO_YA_REGISTRADO',
             pg_temp.como3(u_dir, format('select public.registrar_resultado(%L, ''PERDIDO'', %L::jsonb, %s)::text', pg_temp.enf(v_l, 1), jsonb_build_array(jsonb_build_object('jugador_id', j[1], 'tipo_accion', 'LO_CORTARON')), v_ver)));
        r := r || pg_temp.fila3(38, 'Concurrencia', 'Sigue habiendo un solo resultado y un punto', '1|EN_CURSO 1-0',
             pg_temp.sistema3(format('select count(*)::text from public.resultados_enfrentamiento where enfrentamiento_id = %L', pg_temp.enf(v_l, 1))) || '|' || pg_temp.marcador(pa));
        r := r || pg_temp.fila3(39, 'Reemplazo', 'Lista con resultados no vuelve a edición', 'P0001:LISTA_INICIADA',
             pg_temp.como3(u_cap, format('select public.devolver_lista_a_edicion(%L, ''x'')::text', v_l)));

        perform pg_temp.jugar(u_cap, v_l, 2,  false, 1, 'CAIDA_PROPIA');
        perform pg_temp.jugar(u_cap, v_l, 3,  false, 1, 'REVENTON_PROPIO');
        perform pg_temp.jugar(u_cap, v_l, 4,  true,  1, 'CORTO');
        perform pg_temp.jugar(u_cap, v_l, 5,  false, 1, 'LO_CORTARON');
        perform pg_temp.jugar(u_cap, v_l, 6,  true,  1, 'CORTO');          -- Dupla 1: corta j6
        perform pg_temp.jugar(u_cap, v_l, 7,  false, 1, 'LO_CORTARON');    -- Dupla 2: cortaron a j8
        perform pg_temp.jugar(u_cap, v_l, 8,  true,  1, 'CAIDA_RIVAL');
        perform pg_temp.jugar(u_cap, v_l, 9,  true,  2, 'CAIDA_RIVAL');    -- Trío 1: caída rival por j13
        perform pg_temp.jugar(u_cap, v_l, 10, false, 2, 'CAIDA_PROPIA');   -- Trío 2: caída propia de j16

        r := r || pg_temp.fila3(40, 'Resultados', 'Lista 1 terminada 5-5 y FINALIZADA', 'EN_CURSO 5-5|FINALIZADA',
             pg_temp.marcador(pa) || '|' || pg_temp.sistema3(format('select estado from public.listas_juego where id = %L', v_l)));

        -- ===================== EJEMPLOS DE PUNTUACIÓN (SECCIÓN 22) =====================
        r := r || pg_temp.fila3(41, 'Puntaje', 'Ej. 1 individual gana y corta: 0.5+1+1', '2.50', pg_temp.puntos(v_l, j[1]));
        r := r || pg_temp.fila3(42, 'Puntaje', 'Ej. 5 caída propia: 0.5+0-1', '-0.50', pg_temp.puntos(v_l, j[2]));
        r := r || pg_temp.fila3(43, 'Puntaje', 'Ej. 6 reventón propio: 0.5+0-0.7', '-0.20', pg_temp.puntos(v_l, j[3]));
        r := r || pg_temp.fila3(44, 'Puntaje', 'Ej. 2 dupla ganadora por corte de un integrante', '2.50|1.50',
             pg_temp.puntos(v_l, j[6]) || '|' || pg_temp.puntos(v_l, j[7]));
        r := r || pg_temp.fila3(45, 'Puntaje', 'Dupla perdedora (regla 004): cada integrante con su negativa', '0.00|0.00',
             pg_temp.puntos(v_l, j[8]) || '|' || pg_temp.puntos(v_l, j[9]));
        r := r || pg_temp.fila3(46, 'Puntaje', 'Ej. 3 trío ganador por caída rival de un integrante', '1.50|2.00|1.50',
             pg_temp.puntos(v_l, j[12]) || '|' || pg_temp.puntos(v_l, j[13]) || '|' || pg_temp.puntos(v_l, j[14]));
        r := r || pg_temp.fila3(47, 'Puntaje', 'Trío perdedor (regla 004): caída propia + 2 cortados', '0.00|-0.50|0.00',
             pg_temp.puntos(v_l, j[15]) || '|' || pg_temp.puntos(v_l, j[16]) || '|' || pg_temp.puntos(v_l, j[17]));
        r := r || pg_temp.fila3(48, 'Puntaje', 'Punto oficial del club: dupla y trío valen 1 cada uno', '5',
             pg_temp.sistema3(format('select count(*)::text from public.resultados_enfrentamiento r join public.enfrentamientos e on e.id = r.enfrentamiento_id where e.lista_id = %L and r.vigente and r.ganador_club_id = %L', v_l, v_rayo)));

        -- ===================== LISTA 2 Y CORRECCIONES EN CURSO =====================
        v_l := pg_temp.lista_confirmada(u_cap, pa, v_17);
        la := la || v_l;
        perform pg_temp.jugar_patron(u_cap, v_l, 'GPGPGPGPGP');

        r := r || pg_temp.fila3(49, 'Corrección', 'CAPITÁN no corrige resultados', '42501:PERMISO_DENEGADO',
             pg_temp.corregir(u_cap, v_l, 2, true, 'Error de registro'));
        r := r || pg_temp.fila3(50, 'Corrección', 'Corrección exige motivo', 'P0001:MOTIVO_REQUERIDO',
             pg_temp.corregir(u_dir, v_l, 2, true, null));
        r := r || pg_temp.fila3(51, 'Corrección', 'DIRECTIVA corrige derrota a victoria: 11-9', 'EN_CURSO 11-9',
             pg_temp.m(pg_temp.corregir(u_dir, v_l, 2, true, 'Error de registro')));
        r := r || pg_temp.fila3(52, 'Corrección', 'Historial: 2 versiones, 1 vigente', '2|1',
             pg_temp.sistema3(format('select count(*) || ''|'' || count(*) filter (where vigente) from public.resultados_enfrentamiento where enfrentamiento_id = %L', pg_temp.enf(v_l, 2))));
        r := r || pg_temp.fila3(53, 'Corrección', 'Revierte la corrección: 10-10', 'EN_CURSO 10-10',
             pg_temp.m(pg_temp.corregir(u_dir, v_l, 2, false, 'Se revisó la planilla')));
        r := r || pg_temp.fila3(54, 'Corrección', 'Corrección sin cambios es rechazada', 'P0001:SIN_CAMBIOS',
             pg_temp.corregir(u_dir, v_l, 2, false, 'Nada'));

        -- ===================== LISTAS 3 A 6: CIERRE A MITAD DE LISTA 6 =====================
        for i in 3 .. 5 loop
            v_l := pg_temp.lista_confirmada(u_cap, pa, v_17);
            la := la || v_l;
            perform pg_temp.jugar_patron(u_cap, v_l, 'GPGPGPGPGP');
        end loop;
        r := r || pg_temp.fila3(55, 'Cierre a 30', 'Tras 5 listas el partido sigue: necesita lista 6', 'EN_CURSO 25-25', pg_temp.marcador(pa));

        v_l := pg_temp.lista_confirmada(u_cap, pa, v_17);
        la := la || v_l;
        r := r || pg_temp.fila3(56, 'Cierre a 30', 'Lista 6: RAYO llega a 30 en el Individual 5', '30-25@5',
             pg_temp.jugar_patron(u_cap, v_l, 'GGGGGGGGGG'));
        r := r || pg_temp.fila3(57, 'Cierre a 30', 'Partido FINALIZADO con ganador RAYO', 'FINALIZADO 30-25|true',
             pg_temp.marcador(pa) || '|' || pg_temp.sistema3(format('select (ganador_club_id = %L)::text from public.partidos where id = %L', v_rayo, pa)));
        r := r || pg_temp.fila3(58, 'Cierre a 30', 'Los 5 restantes quedan NO_DISPUTADO_FIN_PARTIDO', '5|FINALIZADA',
             pg_temp.sistema3(format('select count(*)::text from public.enfrentamientos where lista_id = %L and estado_codigo = ''NO_DISPUTADO_FIN_PARTIDO''', v_l))
             || '|' || pg_temp.sistema3(format('select estado from public.listas_juego where id = %L', v_l)));
        r := r || pg_temp.fila3(59, 'Cierre a 30', 'Convocado que no alcanza a jugar: +0.50 y 0 EJ', '0.50|0',
             pg_temp.puntos(v_l, j[6]) || '|' || pg_temp.ej(v_l, j[6]));
        r := r || pg_temp.fila3(60, 'Cierre a 30', 'No se registran resultados tras el cierre', 'P0001:PARTIDO_NO_EN_CURSO',
             pg_temp.jugar(u_cap, v_l, 6, true));
        r := r || pg_temp.fila3(61, 'Cierre a 30', 'No se crean listas tras el cierre', 'P0001:PARTIDO_NO_EN_CURSO',
             pg_temp.como3(u_cap, format('select public.crear_lista(%L)::text', pa)));
        r := r || pg_temp.fila3(62, 'Cierre a 30', 'Verificación de consistencia sin problemas', '[]',
             pg_temp.como3(u_cap, format('select ((public.verificar_partido(%L)) -> ''problemas'')::text', pa)));

        -- ===================== REAPERTURA Y CORRECCIÓN DE PARTIDO FINALIZADO =====================
        r := r || pg_temp.fila3(63, 'Reapertura', 'Partido finalizado: corregir exige reabrir', 'P0001:REABRIR_REQUERIDO',
             pg_temp.corregir(u_dir, v_l, 5, false, 'Error'));
        r := r || pg_temp.fila3(64, 'Reapertura', 'DIRECTIVA no reabre partidos', '42501:PERMISO_DENEGADO',
             pg_temp.como3(u_dir, format('select public.reabrir_partido(%L, ''x'')::text', pa)));
        r := r || pg_temp.fila3(65, 'Reapertura', 'Reabrir exige motivo', 'P0001:MOTIVO_REQUERIDO',
             pg_temp.como3(u_admin, format('select public.reabrir_partido(%L, null)::text', pa)));
        r := r || pg_temp.fila3(66, 'Reapertura', 'ADMINISTRADOR reabre: EN_REVISION', 'EN_REVISION 30-25',
             pg_temp.m(pg_temp.como3(u_admin, format('select public.reabrir_partido(%L, ''Reclamo del rival por Individual 5'')::text', pa))));
        r := r || pg_temp.fila3(67, 'Reapertura', 'En revisión solo corrige ADMINISTRADOR', '42501:PERMISO_DENEGADO',
             pg_temp.corregir(u_dir, v_l, 5, false, 'Error'));
        r := r || pg_temp.fila3(68, 'Reapertura', 'Corrección deja a RAYO en 29: vuelve EN_CURSO', 'EN_CURSO 29-26',
             pg_temp.m(pg_temp.corregir(u_admin, v_l, 5, false, 'Reclamo aceptado')));
        r := r || pg_temp.fila3(69, 'Reapertura', 'Pendientes restaurados y lista 6 EN_JUEGO', '5|EN_JUEGO',
             pg_temp.sistema3(format('select count(*)::text from public.enfrentamientos where lista_id = %L and estado_codigo = ''PENDIENTE''', v_l))
             || '|' || pg_temp.sistema3(format('select estado from public.listas_juego where id = %L', v_l)));
        r := r || pg_temp.fila3(70, 'Reapertura', 'Se continúa desde el punto correcto: Dupla 1 cierra 30-26', 'FINALIZADO 30-26',
             pg_temp.m(pg_temp.jugar(u_cap, v_l, 6, true, 1, 'CORTO')));
        r := r || pg_temp.fila3(71, 'Reapertura', 'Quedan 4 NO_DISPUTADO en lista 6', '4',
             pg_temp.sistema3(format('select count(*)::text from public.enfrentamientos where lista_id = %L and estado_codigo = ''NO_DISPUTADO_FIN_PARTIDO''', v_l)));

        -- ===================== P-1: CORRECCIÓN QUE ADELANTA EL CIERRE =====================
        perform pg_temp.como3(u_admin, format('select public.reabrir_partido(%L, ''Revisión de video del Individual 5'')::text', pa));
        r := r || pg_temp.fila3(72, 'P-1', 'Previsualiza: confirmación|invalidados|marcador|estado', 'true|1|30-25|EN_REVISION',
             pg_temp.como3(u_admin, format('select (x ->> ''requiere_confirmacion'') || ''|'' || jsonb_array_length(x -> ''invalidados'') || ''|'' || (x #>> ''{propuesto,puntaje_local}'') || ''-'' || (x #>> ''{propuesto,puntaje_visitante}'') || ''|'' || (x #>> ''{propuesto,estado}'') from (select public.previsualizar_correccion(%L, ''GANADO'') as x) s', pg_temp.enf(v_l, 5))));
        r := r || pg_temp.fila3(73, 'P-1', 'Sin confirmación explícita es rechazada', 'P0001:IMPACTO_REQUIERE_CONFIRMACION',
             pg_temp.corregir(u_admin, v_l, 5, true, 'Video confirma corte de RAYO'));
        r := r || pg_temp.fila3(74, 'P-1', 'Con confirmación: cierre en Individual 5, 30-25', 'EN_REVISION 30-25',
             pg_temp.m(pg_temp.corregir(u_admin, v_l, 5, true, 'Video confirma corte de RAYO', true)));
        r := r || pg_temp.fila3(75, 'P-1', 'Dupla 1 pasa a NO_DISPUTADO; su resultado queda invalidado (no borrado)', 'NO_DISPUTADO_FIN_PARTIDO|INVALIDADO_CIERRE_ANTICIPADO|1',
             pg_temp.sistema3(format('select e.estado_codigo || ''|'' || min(r.causa_anulacion) || ''|'' || count(r.id) from public.enfrentamientos e join public.resultados_enfrentamiento r on r.enfrentamiento_id = e.id where e.id = %L group by e.estado_codigo', pg_temp.enf(v_l, 6))));
        r := r || pg_temp.fila3(76, 'P-1', 'Jugador de la Dupla 1: conserva +0.50, pierde EJ, victoria y corte', '0.50|0',
             pg_temp.puntos(v_l, j[6]) || '|' || pg_temp.ej(v_l, j[6]));
        r := r || pg_temp.fila3(77, 'P-1', 'DIRECTIVA no cierra la revisión', '42501:PERMISO_DENEGADO',
             pg_temp.como3(u_dir, format('select public.cerrar_revision(%L)::text', pa)));
        r := r || pg_temp.fila3(78, 'P-1', 'ADMINISTRADOR cierra la revisión', 'FINALIZADO 30-25',
             pg_temp.m(pg_temp.como3(u_admin, format('select public.cerrar_revision(%L, ''Revisión terminada'')::text', pa))));
        r := r || pg_temp.fila3(79, 'P-1', 'Verificación de consistencia sin problemas', '[]',
             pg_temp.como3(u_admin, format('select ((public.verificar_partido(%L)) -> ''problemas'')::text', pa)));
        r := r || pg_temp.fila3(80, 'Auditoría', 'Reaperturas auditadas con motivo', '2',
             pg_temp.sistema3(format('select count(*)::text from public.auditoria where partido_id = %L and accion = ''REABRIR_PARTIDO'' and motivo is not null', pa)));
        r := r || pg_temp.fila3(81, 'Auditoría', 'Invalidación P-1 auditada', '1',
             pg_temp.sistema3(format('select count(*)::text from public.auditoria where partido_id = %L and accion = ''CORREGIR_RESULTADO'' and valor_nuevo ->> ''causa_anulacion'' = ''INVALIDADO_CIERRE_ANTICIPADO''', pa)));

        -- ===================== CAMBIO DE REGLAS SIN ALTERAR EL HISTORIAL =====================
        r := r || pg_temp.fila3(82, 'Reglas', 'ADMINISTRADOR crea versión V2 (convocatoria 0.75)', 'FILAS:1|FILAS:9',
             pg_temp.como3(u_admin, 'insert into public.reglas_puntuacion_versiones (codigo, nombre) values (''ZZV2'', ''Prueba V2'')')
             || '|' || pg_temp.como3(u_admin, 'insert into public.reglas_puntuacion_valores (regla_version_id, concepto_codigo, valor) select (select id from public.reglas_puntuacion_versiones where codigo = ''ZZV2''), v.concepto_codigo, case when v.concepto_codigo = ''CONVOCATORIA'' then 0.75 else v.valor end from public.reglas_puntuacion_valores v join public.reglas_puntuacion_versiones rv on rv.id = v.regla_version_id where rv.codigo = ''V1'''));
        r := r || pg_temp.fila3(83, 'Reglas', 'DIRECTIVA no activa versiones', '42501:PERMISO_DENEGADO',
             pg_temp.como3(u_dir, 'select public.activar_regla_version((select id from public.reglas_puntuacion_versiones where codigo = ''ZZV2''))::text'));
        r := r || pg_temp.fila3(84, 'Reglas', 'ADMINISTRADOR activa V2', 'true',
             pg_temp.como3(u_admin, 'select (public.activar_regla_version((select id from public.reglas_puntuacion_versiones where codigo = ''ZZV2''))) ->> ''es_vigente'''));

        -- Partido B con V2: termina exactamente 30-20 en el último enfrentamiento de la lista 5.
        perform pg_temp.como3(u_cap, format('select public.iniciar_partido(%L)::text', pb));
        perform pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pb, v_asis));
        for i in 1 .. 4 loop
            lb := pg_temp.lista_confirmada(u_cap, pb, v_17);
            perform pg_temp.jugar_patron(u_cap, lb, 'GGGGGGPPPP');
            if i = 1 then v_id := lb; end if;
        end loop;
        r := r || pg_temp.fila3(85, '30-20', 'Tras 4 listas: 24-16', 'EN_CURSO 24-16', pg_temp.marcador(pb));
        lb := pg_temp.lista_confirmada(u_cap, pb, v_17);
        r := r || pg_temp.fila3(86, '30-20', 'Lista 5 cierra exactamente 30-20 en el Trío 2', '30-20@10',
             pg_temp.jugar_patron(u_cap, lb, 'PPPPGGGGGG'));
        r := r || pg_temp.fila3(87, '30-20', 'Lista completa, sin NO_DISPUTADO', 'FINALIZADA|0',
             pg_temp.sistema3(format('select estado from public.listas_juego where id = %L', lb))
             || '|' || pg_temp.sistema3(format('select count(*)::text from public.enfrentamientos where lista_id = %L and estado_codigo = ''NO_DISPUTADO_FIN_PARTIDO''', lb)));
        r := r || pg_temp.fila3(88, 'Reglas', 'Partido nuevo usa V2 (convocatoria 0.75)', 'ZZV2|0.75',
             pg_temp.sistema3(format('select v.codigo from public.partidos p join public.reglas_puntuacion_versiones v on v.id = p.regla_version_id where p.id = %L', pb))
             || '|' || pg_temp.sistema3(format('select puntos::text from public.convocatorias where lista_id = %L and jugador_id = %L', v_id, j[1])));
        r := r || pg_temp.fila3(89, 'Reglas', 'Partido anterior conserva V1 y sus puntajes', 'V1|0.50|2.50',
             pg_temp.sistema3(format('select v.codigo from public.partidos p join public.reglas_puntuacion_versiones v on v.id = p.regla_version_id where p.id = %L', pa))
             || '|' || pg_temp.sistema3(format('select puntos::text from public.convocatorias where lista_id = %L and jugador_id = %L', la[1], j[1]))
             || '|' || pg_temp.puntos(la[1], j[1]));

        -- ===================== SUSPENSIÓN Y CANCELACIÓN =====================
        perform pg_temp.como3(u_cap, format('select public.iniciar_partido(%L)::text', pc));
        perform pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pc, v_asis));
        lc := pg_temp.lista_confirmada(u_cap, pc, v_17);
        perform pg_temp.jugar(u_cap, lc, 1, true);

        r := r || pg_temp.fila3(90, 'Suspensión', 'Suspender exige motivo', 'P0001:MOTIVO_REQUERIDO',
             pg_temp.como3(u_cap, format('select public.suspender_partido(%L, null)::text', pc)));
        r := r || pg_temp.fila3(91, 'Suspensión', 'CAPITÁN suspende el partido', 'SUSPENDIDO 1-0',
             pg_temp.m(pg_temp.como3(u_cap, format('select public.suspender_partido(%L, ''Lluvia'')::text', pc))));
        r := r || pg_temp.fila3(92, 'Suspensión', 'Suspendido: no se registran resultados', 'P0001:PARTIDO_NO_EN_CURSO',
             pg_temp.jugar(u_cap, lc, 2, true));
        r := r || pg_temp.fila3(93, 'Suspensión', 'Suspendido: la asistencia sí se puede editar', '1',
             pg_temp.como3(u_cap, format('select (public.registrar_asistencia(%L, %L::jsonb)) ->> ''justificados''', pc, jsonb_build_array(jsonb_build_object('jugador_id', j[18], 'estado', 'JUSTIFICADO')))));
        r := r || pg_temp.fila3(94, 'Suspensión', 'Al reanudar continúa desde el siguiente pendiente', 'EN_CURSO 1-0|EN_CURSO 2-0',
             pg_temp.m(pg_temp.como3(u_cap, format('select public.reanudar_partido(%L)::text', pc))) || '|' || pg_temp.m(pg_temp.jugar(u_cap, lc, 2, true)));
        r := r || pg_temp.fila3(95, 'Integridad', 'Resultado sin acción es rechazado al confirmar la transacción', 'P0001:INCOHERENCIA_ENFRENTAMIENTO',
             pg_temp.sistema3(format('insert into public.resultados_enfrentamiento (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota) values (%L, %L, 1, 0)', pg_temp.enf(lc, 3), v_rayo),
                             'set constraints all immediate'));
        r := r || pg_temp.fila3(96, 'Integridad', 'Partido sin club gestionado es rechazado', 'P0001:PARTIDO_SIN_CLUB_GESTIONADO',
             pg_temp.sistema3(format('insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (%L, current_date, %L, %L)', v_camp, v_rival, v_rival2)));
        r := r || pg_temp.fila3(97, 'Cancelación', 'Con resultados, DIRECTIVA no cancela', '42501:PERMISO_DENEGADO',
             pg_temp.como3(u_dir, format('select public.cancelar_partido(%L, ''Cancha inundada'')::text', pc)));
        r := r || pg_temp.fila3(98, 'Cancelación', 'Con resultados, ADMINISTRADOR cancela', 'CANCELADO 2-0',
             pg_temp.m(pg_temp.como3(u_admin, format('select public.cancelar_partido(%L, ''Cancha inundada'')::text', pc))));
        r := r || pg_temp.fila3(99, 'Cancelación', 'Sin resultados, DIRECTIVA cancela', 'CANCELADO 0-0',
             pg_temp.m(pg_temp.como3(u_dir, format('select public.cancelar_partido(%L, ''Rival no se presentó a coordinar'')::text', pd))));

        -- ===================== CONSISTENCIA FINAL =====================
        r := r || pg_temp.fila3(100, 'Integridad', 'Todas las verificaciones diferidas pasan', 'FILAS:0',
             pg_temp.sistema3('set constraints all immediate'));

        raise exception using errcode = 'P0001', message = 'ROLLBACK_PRUEBAS_003';
    exception
        when others then
            if sqlerrm <> 'ROLLBACK_PRUEBAS_003' then
                r := r || pg_temp.fila3(0, 'ERROR', 'ERROR INESPERADO: ' || sqlerrm, '-', sqlstate);
            end if;
    end;

    return query
        select (x ->> 'n')::int, x ->> 'g', x ->> 'p', x ->> 'e', x ->> 'o', (x ->> 'e') = (x ->> 'o')
          from jsonb_array_elements(r) as x
         order by 1;
end;
$$;

select * from pg_temp.ejecutar_pruebas_003();
