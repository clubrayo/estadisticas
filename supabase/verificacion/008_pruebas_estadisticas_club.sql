-- =====================================================================
-- PRUEBAS 008 — ESTADÍSTICAS DEL CLUB (DASHBOARD)
-- Escenario de la suite 005 más un campeonato con meta 5 (un partido ganado
-- 5-0 de local y uno perdido 0-5 de visitante). Verifica los indicadores,
-- las exclusiones y los permisos, y DESHACE TODO al final.
-- Resultado esperado: 13 filas con ok = true.
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

-- Lee un dato del dashboard del club como un usuario: ruta tipo '{puntos,a_favor}'.
create or replace function pg_temp.club(p_uid uuid, p_club uuid, p_campeonato uuid, p_ruta text)
returns text
language sql
as $$
    select pg_temp.como3(p_uid, format('select public.estadisticas_club(%L, %L) #>> %L', p_club, p_campeonato, p_ruta));
$$;

create or replace function pg_temp.ejecutar_pruebas_008()
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
    v_camp5    uuid;
    pf         uuid;
    pg         uuid;
    lf         uuid;
    lg         uuid;
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

        -- Campeonato con meta 5: partido F ganado 5-0 y partido G perdido 0-5.
        insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo)
             values ('ZZPRUEBA5 CAMPEONATO META 5', 'ZZ', current_date, 5) returning id into v_camp5;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (v_camp5, current_date, v_rayo, v_rival) returning id into pf;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (v_camp5, current_date, v_rival, v_rayo) returning id into pg;
        perform pg_temp.como3(u_cap, format('select public.iniciar_partido(%L)::text', pf));
        perform pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pf, v_asis));
        lf := pg_temp.lista_confirmada(u_cap, pf, j[1:17]);
        for i in 1 .. 5 loop
            perform pg_temp.reg5(u_cap, lf, i, 'GANADO', jsonb_build_array(pg_temp.a(j[i], 'CORTO')));
        end loop;
        perform pg_temp.como3(u_cap, format('select public.iniciar_partido(%L)::text', pg));
        perform pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pg, v_asis));
        lg := pg_temp.lista_confirmada(u_cap, pg, j[1:17]);
        for i in 1 .. 5 loop
            perform pg_temp.reg5(u_cap, lg, i, 'PERDIDO', jsonb_build_array(pg_temp.a(j[i], 'LO_CORTARON')));
        end loop;

        -- ===================== CAMPEONATO EN CURSO (partido A) =====================
        r := r || pg_temp.fila3(1, 'Club', 'Jugadores activos = jugadores ACTIVO del club', 'true',
             pg_temp.como3(u_con, format('select (public.estadisticas_club(%L) ->> ''jugadores_activos'')::int = (select count(*) from public.jugadores where club_id = %L and estado = ''ACTIVO'')', v_rayo, v_rayo)));
        r := r || pg_temp.fila3(2, 'Club', 'Partidos: jugados|ganados|perdidos|en curso (B cancelado no cuenta)', '0|0|0|1',
             pg_temp.club(u_con, v_rayo, v_camp, '{partidos,jugados}') || '|' || pg_temp.club(u_con, v_rayo, v_camp, '{partidos,ganados}') || '|'
             || pg_temp.club(u_con, v_rayo, v_camp, '{partidos,perdidos}') || '|' || pg_temp.club(u_con, v_rayo, v_camp, '{partidos,en_curso}'));
        r := r || pg_temp.fila3(3, 'Club', 'Efectividad sin partidos terminados es nula', 'true',
             (pg_temp.club(u_con, v_rayo, v_camp, '{partidos,efectividad}') is null)::text);
        r := r || pg_temp.fila3(4, 'Club', 'Listas disputadas', '2',
             pg_temp.club(u_con, v_rayo, v_camp, '{listas_disputadas}'));
        r := r || pg_temp.fila3(5, 'Club', 'Puntos oficiales a favor|en contra', '7|4',
             pg_temp.club(u_con, v_rayo, v_camp, '{puntos,a_favor}') || '|' || pg_temp.club(u_con, v_rayo, v_camp, '{puntos,en_contra}'));
        r := r || pg_temp.fila3(6, 'Club', 'Individuales EJ|EG, duplas EJ|EG, tríos EJ|EG', '6|4|3|2|2|1',
             pg_temp.club(u_con, v_rayo, v_camp, '{por_modalidad,0,ej}') || '|' || pg_temp.club(u_con, v_rayo, v_camp, '{por_modalidad,0,eg}') || '|'
             || pg_temp.club(u_con, v_rayo, v_camp, '{por_modalidad,1,ej}') || '|' || pg_temp.club(u_con, v_rayo, v_camp, '{por_modalidad,1,eg}') || '|'
             || pg_temp.club(u_con, v_rayo, v_camp, '{por_modalidad,2,ej}') || '|' || pg_temp.club(u_con, v_rayo, v_camp, '{por_modalidad,2,eg}'));
        r := r || pg_temp.fila3(7, 'Club', 'Acciones: cortes|cortado|caída propia|caída rival|reventón propio|reventón rival', '6|5|2|1|1|1',
             pg_temp.club(u_con, v_rayo, v_camp, '{acciones,cortes}') || '|' || pg_temp.club(u_con, v_rayo, v_camp, '{acciones,veces_cortado}') || '|'
             || pg_temp.club(u_con, v_rayo, v_camp, '{acciones,caidas_propias}') || '|' || pg_temp.club(u_con, v_rayo, v_camp, '{acciones,caidas_rival}') || '|'
             || pg_temp.club(u_con, v_rayo, v_camp, '{acciones,reventones_propios}') || '|' || pg_temp.club(u_con, v_rayo, v_camp, '{acciones,reventones_rival}'));

        -- ===================== CAMPEONATO META 5 (F ganado, G perdido) =====================
        r := r || pg_temp.fila3(8, 'Club', 'Partidos terminados: jugados|ganados|perdidos|efectividad', '2|1|1|50.0',
             pg_temp.club(u_con, v_rayo, v_camp5, '{partidos,jugados}') || '|' || pg_temp.club(u_con, v_rayo, v_camp5, '{partidos,ganados}') || '|'
             || pg_temp.club(u_con, v_rayo, v_camp5, '{partidos,perdidos}') || '|' || pg_temp.club(u_con, v_rayo, v_camp5, '{partidos,efectividad}'));
        r := r || pg_temp.fila3(9, 'Club', 'Local y visitante: puntos a favor|en contra', '5|5',
             pg_temp.club(u_con, v_rayo, v_camp5, '{puntos,a_favor}') || '|' || pg_temp.club(u_con, v_rayo, v_camp5, '{puntos,en_contra}'));
        r := r || pg_temp.fila3(10, 'Club', 'No disputados por fin de partido no cuentan: individuales EJ|EG, duplas EJ', '10|5|0',
             pg_temp.club(u_con, v_rayo, v_camp5, '{por_modalidad,0,ej}') || '|' || pg_temp.club(u_con, v_rayo, v_camp5, '{por_modalidad,0,eg}') || '|'
             || pg_temp.club(u_con, v_rayo, v_camp5, '{por_modalidad,1,ej}'));

        -- ===================== FILTROS Y PERMISOS =====================
        r := r || pg_temp.fila3(11, 'Filtro', 'Campeonato cancelado: partidos|listas|puntos', '0|0|0',
             pg_temp.club(u_con, v_rayo, v_camp_x, '{partidos,en_curso}') || '|' || pg_temp.club(u_con, v_rayo, v_camp_x, '{listas_disputadas}') || '|'
             || pg_temp.club(u_con, v_rayo, v_camp_x, '{puntos,a_favor}'));
        r := r || pg_temp.fila3(12, 'Permisos', 'Usuario de otro club: jugadores|listas|puntos de RAYO', '0|0|0',
             pg_temp.club(u_otro, v_rayo, v_camp, '{jugadores_activos}') || '|' || pg_temp.club(u_otro, v_rayo, v_camp, '{listas_disputadas}') || '|'
             || pg_temp.club(u_otro, v_rayo, v_camp, '{puntos,a_favor}'));
        r := r || pg_temp.fila3(13, 'Permisos', 'anon no accede', '42501',
             pg_temp.sistema3('set local role anon', format('select public.estadisticas_club(%L)', v_rayo)));

        raise exception using errcode = 'P0001', message = 'ROLLBACK_PRUEBAS_008';
    exception
        when others then
            if sqlerrm <> 'ROLLBACK_PRUEBAS_008' then
                r := r || pg_temp.fila3(0, 'ERROR', 'ERROR INESPERADO: ' || sqlerrm, '-', sqlstate);
            end if;
    end;

    return query
        select (x ->> 'n')::int, x ->> 'g', x ->> 'p', x ->> 'e', x ->> 'o', (x ->> 'e') = (x ->> 'o')
          from jsonb_array_elements(r) as x
         order by 1;
end;
$$;

select * from pg_temp.ejecutar_pruebas_008();
