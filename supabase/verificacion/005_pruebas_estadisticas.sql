-- =====================================================================
-- PRUEBAS 005 — ESTADÍSTICAS INDIVIDUALES
-- Arma partidos con resultados conocidos, compara cada número de la ficha
-- del jugador y DESHACE TODO al final (no queda ningún dato de prueba).
-- Resultado esperado: todas las filas con ok = true.
--
-- Nota: el SQL Editor puede advertir "operaciones destructivas". Todo se
-- deshace al final. Elija "Correr sin RLS" / "Run without RLS" si aparece.
-- =====================================================================

-- ---------- Utilidades de prueba (las mismas de la suite 003) ----------

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

create or replace function pg_temp.a(p_jugador uuid, p_tipo text)
returns jsonb
language sql
as $$
    select jsonb_build_object('jugador_id', p_jugador, 'tipo_accion', p_tipo);
$$;

create or replace function pg_temp.reg5(p_uid uuid, p_lista uuid, p_orden int, p_resultado text, p_acciones jsonb,
                                        p_secretaria boolean default false, p_motivo text default null)
returns text
language plpgsql
as $$
declare
    v_enf uuid := pg_temp.enf(p_lista, p_orden);
    v_ver int;
begin
    select version into v_ver from public.enfrentamientos where id = v_enf;
    return pg_temp.como3(p_uid, format(
        'select public.registrar_resultado(%L, %L, %L::jsonb, %s, %L, %L)::text',
        v_enf, p_resultado, p_acciones, v_ver, p_secretaria, p_motivo));
end;
$$;

-- Lee un dato de la ficha como un usuario: ruta tipo '{puntos,total}'.
create or replace function pg_temp.ficha(p_uid uuid, p_jugador uuid, p_ruta text, p_campeonato uuid default null)
returns text
language sql
as $$
    select pg_temp.como3(p_uid, format('select public.estadisticas_jugador(%L, %L) #>> %L', p_jugador, p_campeonato, p_ruta));
$$;

create or replace function pg_temp.ejecutar_pruebas_005()
returns table (n int, grupo text, prueba text, esperado text, obtenido text, ok boolean)
language plpgsql
as $$
declare
    r          jsonb := '[]'::jsonb;
    u_admin    uuid := gen_random_uuid();
    u_dir      uuid := gen_random_uuid();
    u_cap      uuid := gen_random_uuid();
    u_con      uuid := gen_random_uuid();
    u_otro     uuid := gen_random_uuid();
    v_rayo     uuid;
    v_otro     uuid;
    v_rival    uuid;
    v_camp     uuid;
    v_camp_x   uuid;
    pa         uuid;
    pb         uuid;
    px         uuid;
    l1         uuid;
    l2         uuid;
    lb         uuid;
    v_id       uuid;
    j          uuid[] := '{}';
    v_asis     jsonb;
begin
    begin
        -- ===================== DATOS FICTICIOS =====================
        select id into v_rayo from public.clubes where nombre_corto = 'RAYO';
        insert into public.clubes (nombre, nombre_corto, es_gestionado) values ('ZZPRUEBA5 OTRO', 'ZZP5_OTRO', true) returning id into v_otro;
        insert into public.clubes (nombre, nombre_corto) values ('ZZPRUEBA5 RIVAL', 'ZZP5_RIV') returning id into v_rival;
        insert into auth.users (id, email) values
            (u_admin, 'zz5.admin@zzprueba.invalid'), (u_dir, 'zz5.directiva@zzprueba.invalid'),
            (u_cap, 'zz5.capitan@zzprueba.invalid'), (u_con, 'zz5.consulta@zzprueba.invalid'),
            (u_otro, 'zz5.otro@zzprueba.invalid');
        insert into public.usuario_roles (usuario_id, rol_codigo, club_id) values
            (u_admin, 'ADMINISTRADOR', null), (u_dir, 'DIRECTIVA', v_rayo), (u_cap, 'CAPITAN', v_rayo),
            (u_con, 'CONSULTA', v_rayo), (u_otro, 'DIRECTIVA', v_otro);
        for i in 1 .. 18 loop
            insert into public.jugadores (club_id, primer_nombre, apellidos)
                 values (v_rayo, 'Zz', 'ZZPRUEBA5 ' || lpad(i::text, 2, '0')) returning id into v_id;
            j := j || v_id;
        end loop;
        insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo)
             values ('ZZPRUEBA5 CAMPEONATO', 'ZZ', current_date, 30) returning id into v_camp;
        insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo)
             values ('ZZPRUEBA5 CAMPEONATO CANCELADO', 'ZZ', current_date, 30) returning id into v_camp_x;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (v_camp, current_date, v_rayo, v_rival) returning id into pa;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (v_camp, current_date, v_rayo, v_rival) returning id into pb;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (v_camp_x, current_date, v_rayo, v_rival) returning id into px;

        select jsonb_agg(jsonb_build_object('jugador_id', x, 'estado', 'PRESENTE')) into v_asis from unnest(j[1:17]) x;
        v_asis := v_asis || jsonb_build_array(jsonb_build_object('jugador_id', j[18], 'estado', 'AUSENTE'));

        -- Partido A: lista 1 completa (6-4) y lista 2 con un solo enfrentamiento jugado.
        perform pg_temp.como3(u_cap, format('select public.iniciar_partido(%L)::text', pa));
        perform pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pa, v_asis));
        l1 := pg_temp.lista_confirmada(u_cap, pa, j[1:17]);
        perform pg_temp.reg5(u_cap, l1, 1, 'GANADO',  jsonb_build_array(pg_temp.a(j[1], 'CORTO')));
        perform pg_temp.reg5(u_cap, l1, 2, 'PERDIDO', jsonb_build_array(pg_temp.a(j[2], 'CAIDA_PROPIA')));
        perform pg_temp.reg5(u_dir, l1, 3, 'GANADO',  '[]'::jsonb, true, 'Rival descalificado');
        perform pg_temp.reg5(u_cap, l1, 4, 'GANADO',  jsonb_build_array(pg_temp.a(j[4], 'CAIDA_RIVAL')));
        perform pg_temp.reg5(u_cap, l1, 5, 'PERDIDO', jsonb_build_array(pg_temp.a(j[5], 'REVENTON_PROPIO')));
        perform pg_temp.reg5(u_cap, l1, 6, 'GANADO',  jsonb_build_array(pg_temp.a(j[6], 'CORTO'), pg_temp.a(j[6], 'CORTO'), pg_temp.a(j[7], 'LO_CORTARON')));
        perform pg_temp.reg5(u_cap, l1, 7, 'PERDIDO', jsonb_build_array(pg_temp.a(j[8], 'CORTO'), pg_temp.a(j[8], 'LO_CORTARON'), pg_temp.a(j[9], 'CAIDA_PROPIA')));
        perform pg_temp.reg5(u_cap, l1, 8, 'GANADO',  jsonb_build_array(pg_temp.a(j[10], 'REVENTON_RIVAL')));
        perform pg_temp.reg5(u_cap, l1, 9, 'GANADO',  jsonb_build_array(pg_temp.a(j[12], 'CORTO')));
        perform pg_temp.reg5(u_cap, l1, 10, 'PERDIDO', jsonb_build_array(pg_temp.a(j[15], 'LO_CORTARON'), pg_temp.a(j[16], 'LO_CORTARON'), pg_temp.a(j[17], 'LO_CORTARON')));
        l2 := pg_temp.lista_confirmada(u_cap, pa, j[1:17]);
        perform pg_temp.reg5(u_cap, l2, 1, 'GANADO',  jsonb_build_array(pg_temp.a(j[1], 'CORTO')));

        -- Partido B: se juega un enfrentamiento y luego el ADMINISTRADOR lo cancela.
        perform pg_temp.como3(u_cap, format('select public.iniciar_partido(%L)::text', pb));
        perform pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pb, v_asis));
        lb := pg_temp.lista_confirmada(u_cap, pb, j[1:17]);
        perform pg_temp.reg5(u_cap, lb, 1, 'GANADO', jsonb_build_array(pg_temp.a(j[1], 'CORTO')));
        perform pg_temp.como3(u_admin, format('select public.cancelar_partido(%L, ''Prueba'')::text', pb));

        -- Partido X: solo asistencia, en un campeonato que luego se cancela.
        perform pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', px, v_asis));
        perform pg_temp.como3(u_admin, format('update public.campeonatos set estado = ''CANCELADO'' where id = %L', v_camp_x));

        -- ===================== FICHA: JUGADOR 1 =====================
        r := r || pg_temp.fila3(1, 'Asistencia', 'Excluye partido cancelado y campeonato cancelado', '1|1|100.0',
             pg_temp.ficha(u_con, j[1], '{asistencia,partidos}') || '|' || pg_temp.ficha(u_con, j[1], '{asistencia,presentes}')
             || '|' || pg_temp.ficha(u_con, j[1], '{asistencia,porcentaje}'));
        r := r || pg_temp.fila3(2, 'Convocatoria', 'Dos listas oficiales = 1.00 (excluye el cancelado)', '2|1.00',
             pg_temp.ficha(u_con, j[1], '{convocatorias,listas}') || '|' || pg_temp.ficha(u_con, j[1], '{convocatorias,puntos}'));
        r := r || pg_temp.fila3(3, 'Resultados', 'EJ|EG|EP|% del jugador 1', '2|2|0|100.0',
             pg_temp.ficha(u_con, j[1], '{participacion,ej}') || '|' || pg_temp.ficha(u_con, j[1], '{participacion,eg}') || '|'
             || pg_temp.ficha(u_con, j[1], '{participacion,ep}') || '|' || pg_temp.ficha(u_con, j[1], '{participacion,porcentaje}'));
        r := r || pg_temp.fila3(4, 'Puntos', 'conv|resultado|positivas|penal.|total', '1.00|2.00|2.00|0|5.00',
             pg_temp.ficha(u_con, j[1], '{puntos,convocatoria}') || '|' || pg_temp.ficha(u_con, j[1], '{puntos,resultado}') || '|'
             || pg_temp.ficha(u_con, j[1], '{puntos,positivas}') || '|' || pg_temp.ficha(u_con, j[1], '{puntos,penalizaciones}') || '|'
             || pg_temp.ficha(u_con, j[1], '{puntos,total}'));
        r := r || pg_temp.fila3(5, 'Modalidad', 'Individual: EJ|EG|%', '2|2|100.0',
             pg_temp.ficha(u_con, j[1], '{por_modalidad,0,ej}') || '|' || pg_temp.ficha(u_con, j[1], '{por_modalidad,0,eg}') || '|'
             || pg_temp.ficha(u_con, j[1], '{por_modalidad,0,porcentaje}'));
        r := r || pg_temp.fila3(6, 'Acciones', 'Cortes del jugador 1', '2', pg_temp.ficha(u_con, j[1], '{acciones,cortes}'));

        -- ===================== OTROS CASOS =====================
        r := r || pg_temp.fila3(7, 'Puntos', 'Caída propia: 1.00 + 0 - 1 = 0.00 (EP 1)', '0.00|1',
             pg_temp.ficha(u_con, j[2], '{puntos,total}') || '|' || pg_temp.ficha(u_con, j[2], '{participacion,ep}'));
        r := r || pg_temp.fila3(8, 'Secretaría', 'Victoria por secretaría: EG 1, sin acciones, total 2.00', '1|0|2.00',
             pg_temp.ficha(u_con, j[3], '{participacion,eg}') || '|' || pg_temp.ficha(u_con, j[3], '{acciones,cortes}') || '|'
             || pg_temp.ficha(u_con, j[3], '{puntos,total}'));
        r := r || pg_temp.fila3(9, 'Dupla', 'Cortó ×2: total 4.00 · dupla EJ 1 EG 1', '4.00|1|1',
             pg_temp.ficha(u_con, j[6], '{puntos,total}') || '|' || pg_temp.ficha(u_con, j[6], '{por_modalidad,1,ej}') || '|'
             || pg_temp.ficha(u_con, j[6], '{por_modalidad,1,eg}'));
        r := r || pg_temp.fila3(10, 'Dupla', 'Compañero cortado: 1.00 + 1 - 0.5 = 1.50 · veces cortado 1', '1.50|1',
             pg_temp.ficha(u_con, j[7], '{puntos,total}') || '|' || pg_temp.ficha(u_con, j[7], '{acciones,veces_cortado}'));
        r := r || pg_temp.fila3(11, 'Dupla', 'Corta y luego lo cortan en derrota: 1.00 + 1 - 0.5 = 1.50', '1.50|1|1',
             pg_temp.ficha(u_con, j[8], '{puntos,total}') || '|' || pg_temp.ficha(u_con, j[8], '{acciones,cortes}') || '|'
             || pg_temp.ficha(u_con, j[8], '{acciones,veces_cortado}'));
        r := r || pg_temp.fila3(12, 'Penalización', 'Reventón propio: penalización -0.70, total 0.30', '-0.70|0.30',
             pg_temp.ficha(u_con, j[5], '{puntos,penalizaciones}') || '|' || pg_temp.ficha(u_con, j[5], '{puntos,total}'));
        r := r || pg_temp.fila3(13, 'No disputado', 'Convocado en lista 2 sin jugar aún: no suma EJ', '1',
             pg_temp.ficha(u_con, j[6], '{participacion,ej}'));
        r := r || pg_temp.fila3(14, 'Asistencia', 'Ausente: 1 partido, 0 presentes, 0%', '1|0|1|0.0',
             pg_temp.ficha(u_con, j[18], '{asistencia,partidos}') || '|' || pg_temp.ficha(u_con, j[18], '{asistencia,presentes}') || '|'
             || pg_temp.ficha(u_con, j[18], '{asistencia,ausentes}') || '|' || pg_temp.ficha(u_con, j[18], '{asistencia,porcentaje}'));
        r := r || pg_temp.fila3(15, 'Filtro', 'Filtrado por campeonato da lo mismo que el histórico aquí', '5.00',
             pg_temp.ficha(u_con, j[1], '{puntos,total}', v_camp));
        r := r || pg_temp.fila3(16, 'Filtro', 'Filtrado por el campeonato cancelado: sin datos', '0|0',
             pg_temp.ficha(u_con, j[1], '{asistencia,partidos}', v_camp_x) || '|' || pg_temp.ficha(u_con, j[1], '{participacion,ej}', v_camp_x));

        -- ===================== HISTORIAL =====================
        r := r || pg_temp.fila3(17, 'Historial', 'Filas del jugador 6 (lista 1 jugada, lista 2 pendiente)', '2|1',
             pg_temp.como3(u_con, format('select count(*) || ''|'' || count(*) filter (where jugado) from public.v_est_participaciones where jugador_id = %L', j[6])));
        r := r || pg_temp.fila3(18, 'Historial', 'Compañero, rival y acciones de la Dupla 1', 'Zz ZZPRUEBA5 07|ZZP5_RIV|{CORTO,CORTO}',
             pg_temp.como3(u_con, format('select companeros[1] || ''|'' || rival || ''|'' || acciones::text from public.v_est_participaciones where jugador_id = %L and jugado', j[6])));

        -- ===================== PERMISOS (RLS) =====================
        r := r || pg_temp.fila3(19, 'Permisos', 'DIRECTIVA de otro club no ve estadísticas de RAYO', '0|0',
             pg_temp.ficha(u_otro, j[1], '{participacion,ej}') || '|'
             || pg_temp.como3(u_otro, format('select count(*)::text from public.v_est_participaciones where jugador_id = %L', j[1])));
        r := r || pg_temp.fila3(20, 'Permisos', 'anon no accede a las vistas', '42501',
             pg_temp.sistema3('set local role anon', 'select count(*) from public.v_est_participaciones'));

        raise exception using errcode = 'P0001', message = 'ROLLBACK_PRUEBAS_005';
    exception
        when others then
            if sqlerrm <> 'ROLLBACK_PRUEBAS_005' then
                r := r || pg_temp.fila3(0, 'ERROR', 'ERROR INESPERADO: ' || sqlerrm, '-', sqlstate);
            end if;
    end;

    return query
        select (x ->> 'n')::int, x ->> 'g', x ->> 'p', x ->> 'e', x ->> 'o', (x ->> 'e') = (x ->> 'o')
          from jsonb_array_elements(r) as x
         order by 1;
end;
$$;

select * from pg_temp.ejecutar_pruebas_005();
