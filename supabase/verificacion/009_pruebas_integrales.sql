-- =====================================================================
-- PRUEBAS 009 — PRUEBAS INTEGRALES (FASE 15)
-- Juega un partido completo hasta 30-20 (con cambio de jugador, reapertura,
-- corrección y cambio de reglas) y comprueba que todas las capas coinciden:
-- marcador, dashboard del club, ranking, fichas, combinaciones, historial y
-- auditoría (secciones 35, 40, 51 y 52). DESHACE TODO al final.
-- Resultado esperado: 25 filas con ok = true.
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


create or replace function pg_temp.ejecutar_pruebas_009()
returns table (n int, grupo text, prueba text, esperado text, obtenido text, ok boolean)
language plpgsql
as $$
declare
    r          jsonb := '[]'::jsonb;
    u_admin    uuid := gen_random_uuid();
    u_dir      uuid := gen_random_uuid();
    u_cap      uuid := gen_random_uuid();
    u_con      uuid := gen_random_uuid();
    v_rayo     uuid;
    v_rival    uuid;
    v_camp     uuid;
    pa         uuid;
    l1         uuid;
    v_l        uuid;
    v_id       uuid;
    j          uuid[] := '{}';
    v_asis     jsonb;
    v_antes    text;
    v_suma     text;
begin
    begin
        -- ===================== DATOS FICTICIOS =====================
        select id into v_rayo from public.clubes where nombre_corto = 'RAYO';
        insert into public.clubes (nombre, nombre_corto) values ('ZZPRUEBA9 RIVAL', 'ZZP9_RIV') returning id into v_rival;
        insert into auth.users (id, email) values
            (u_admin, 'zz9.admin@zzprueba.invalid'), (u_dir, 'zz9.directiva@zzprueba.invalid'),
            (u_cap, 'zz9.capitan@zzprueba.invalid'), (u_con, 'zz9.consulta@zzprueba.invalid');
        insert into public.usuario_roles (usuario_id, rol_codigo, club_id) values
            (u_admin, 'ADMINISTRADOR', null), (u_dir, 'DIRECTIVA', v_rayo), (u_cap, 'CAPITAN', v_rayo),
            (u_con, 'CONSULTA', v_rayo);
        for i in 1 .. 19 loop
            insert into public.jugadores (club_id, primer_nombre, apellidos)
                 values (v_rayo, 'Zz', 'ZZPRUEBA9 ' || lpad(i::text, 2, '0')) returning id into v_id;
            j := j || v_id;
        end loop;
        insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo)
             values ('ZZPRUEBA9 CAMPEONATO', 'ZZ', current_date, 30) returning id into v_camp;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id)
             values (v_camp, current_date, v_rayo, v_rival) returning id into pa;

        -- 18 presentes y 1 ausente.
        select jsonb_agg(jsonb_build_object('jugador_id', x, 'estado', 'PRESENTE')) into v_asis from unnest(j[1:18]) x;
        v_asis := v_asis || jsonb_build_array(jsonb_build_object('jugador_id', j[19], 'estado', 'AUSENTE'));

        -- ===================== PARTIDO COMPLETO HASTA 30-20 =====================
        perform pg_temp.como3(u_cap, format('select public.iniciar_partido(%L)::text', pa));
        perform pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', pa, v_asis));

        -- Lista 1 con cambio de jugador antes de jugar: sale el 17, entra el 18.
        l1 := pg_temp.lista_confirmada(u_cap, pa, j[1:17]);
        perform pg_temp.como3(u_cap, format('select public.devolver_lista_a_edicion(%L, ''ZZ9 lesión del 17'')::text', l1));
        perform pg_temp.armar(u_cap, l1, j[1:16] || j[18], 'ZZ9 lesión del 17');
        perform pg_temp.como3(u_cap, format('select public.confirmar_lista(%L)::text', l1));
        perform pg_temp.jugar_patron(u_cap, l1, 'GGGGGGPPPP');
        for i in 2 .. 4 loop
            v_l := pg_temp.lista_confirmada(u_cap, pa, j[1:17]);
            perform pg_temp.jugar_patron(u_cap, v_l, 'GGGGGGPPPP');
        end loop;
        v_l := pg_temp.lista_confirmada(u_cap, pa, j[1:17]);
        r := r || pg_temp.fila3(1, 'Partido', 'Cierra exactamente 30-20 en el último enfrentamiento de la lista 5', '30-20@10',
             pg_temp.jugar_patron(u_cap, v_l, 'PPPPGGGGGG'));
        r := r || pg_temp.fila3(2, 'Partido', 'FINALIZADO con ganador RAYO y verificación sin problemas', 'FINALIZADO 30-20|true|[]',
             pg_temp.marcador(pa)
             || '|' || pg_temp.sistema3(format('select (ganador_club_id = %L)::text from public.partidos where id = %L', v_rayo, pa))
             || '|' || pg_temp.como3(u_admin, format('select ((public.verificar_partido(%L)) -> ''problemas'')::text', pa)));

        -- ===================== PRINCIPIO FUNDAMENTAL (SECCIÓN 52) =====================
        r := r || pg_temp.fila3(3, 'Principio', 'Puntaje del club = enfrentamientos ganados, separado del puntaje de jugadores', '30|30|true',
             pg_temp.sistema3(format('select puntaje_local::text from public.partidos where id = %L', pa))
             || '|' || pg_temp.como3(u_con, format('select count(distinct enfrentamiento_id)::text from public.v_est_participaciones where partido_id = %L and resultado = ''GANADO''', pa))
             || '|' || pg_temp.como3(u_con, format('select (sum(puntos_total) <> 30)::text from public.ranking_jugadores(%L)', v_camp)));

        -- ===================== COHERENCIA ENTRE PANTALLAS =====================
        r := r || pg_temp.fila3(4, 'Dashboard', 'Club: jugados|ganados|efectividad|listas|a favor|en contra', '1|1|100.0|5|30|20',
             pg_temp.como3(u_con, format('select concat_ws(''|'', x #>> ''{partidos,jugados}'', x #>> ''{partidos,ganados}'', x #>> ''{partidos,efectividad}'', x ->> ''listas_disputadas'', x #>> ''{puntos,a_favor}'', x #>> ''{puntos,en_contra}'') from public.estadisticas_club(%L, %L) x', v_rayo, v_camp)));
        r := r || pg_temp.fila3(5, 'Dashboard', 'Ganados por modalidad suman 30 de 50 jugados', '30|50',
             pg_temp.como3(u_con, format('select sum((m ->> ''eg'')::int) || ''|'' || sum((m ->> ''ej'')::int) from jsonb_array_elements(public.estadisticas_club(%L, %L) -> ''por_modalidad'') m', v_rayo, v_camp)));
        r := r || pg_temp.fila3(6, 'Ranking', 'Participaciones: EJ|EG|EP de todos los jugadores', '85|41|44',
             pg_temp.como3(u_con, format('select sum(ej) || ''|'' || sum(eg) || ''|'' || sum(ep) from public.ranking_jugadores(%L)', v_camp)));
        r := r || pg_temp.fila3(7, 'Ranking', 'Convocatorias: total|puntos|jugador 17|jugador 18 (reemplazo)', '85|42.50|4|1',
             pg_temp.como3(u_con, format('select sum(convocatorias) || ''|'' || sum(puntos_convocatoria) || ''|'' || max(convocatorias) filter (where jugador_id = %L) || ''|'' || max(convocatorias) filter (where jugador_id = %L) from public.ranking_jugadores(%L)', j[17], j[18], v_camp)));
        r := r || pg_temp.fila3(8, 'Ranking', 'Ranking = ficha individual para cada jugador (diferencias)', '0',
             pg_temp.como3(u_con, format('select count(*)::text from public.ranking_jugadores(%1$L) k where k.puntos_total <> (public.estadisticas_jugador(k.jugador_id, %1$L) #>> ''{puntos,total}'')::numeric or k.ej <> (public.estadisticas_jugador(k.jugador_id, %1$L) #>> ''{participacion,ej}'')::int', v_camp)));
        r := r || pg_temp.fila3(9, 'Ranking', 'Ausente: 1 partido, 0 asistencias, sin convocatorias', '1|0|0',
             pg_temp.como3(u_con, format('select partidos || ''|'' || asistencias || ''|'' || convocatorias from public.ranking_jugadores(%L) where jugador_id = %L', v_camp, j[19])));
        r := r || pg_temp.fila3(10, 'Combinaciones', 'EJ de duplas|EJ de tríos (3 y 2 por lista)', '15|10',
             pg_temp.como3(u_con, format('select (select sum(ej) from public.combinaciones(''DUPLA'', %1$L)) || ''|'' || (select sum(ej) from public.combinaciones(''TRIO'', %1$L))', v_camp)));

        -- ===================== HISTORIAL DEL PARTIDO (SECCIÓN 35) =====================
        r := r || pg_temp.fila3(11, 'Historial', 'Se conserva: asistencia|listas|convocatorias (incl. anulada)|enfrentamientos|resultados', '19|5|86|50|50',
             pg_temp.como3(u_con, format('select (select count(*) from public.asistencias where partido_id = %1$L) || ''|'' || (select count(*) from public.listas_juego where partido_id = %1$L) || ''|'' || (select count(*) from public.convocatorias c join public.listas_juego l on l.id = c.lista_id where l.partido_id = %1$L) || ''|'' || (select count(*) from public.enfrentamientos e join public.listas_juego l on l.id = e.lista_id where l.partido_id = %1$L) || ''|'' || (select count(*) from public.resultados_enfrentamiento x join public.enfrentamientos e on e.id = x.enfrentamiento_id join public.listas_juego l on l.id = e.lista_id where l.partido_id = %1$L)', pa)));

        -- ===================== REAPERTURA Y CORRECCIÓN =====================
        v_antes := pg_temp.como3(u_con, format('select puntos_total::text from public.ranking_jugadores(%L) where jugador_id = %L', v_camp, j[1]));
        r := r || pg_temp.fila3(12, 'Reapertura', 'ADMINISTRADOR reabre el partido', 'EN_REVISION 30-20',
             pg_temp.m(pg_temp.como3(u_admin, format('select public.reabrir_partido(%L, ''ZZ9 reclamo del rival'')::text', pa))));
        r := r || pg_temp.fila3(13, 'Corrección', 'Cambia la acción del Individual 1 (corte → caída rival): marcador igual', 'EN_REVISION 30-20',
             pg_temp.m(pg_temp.corregir(u_admin, l1, 1, true, 'ZZ9 era caída del rival', false, 1, 'CAIDA_RIVAL')));
        r := r || pg_temp.fila3(14, 'Corrección', 'Ranking refleja la corrección del jugador 1 (−0,50)', '-0.50',
             pg_temp.como3(u_con, format('select (puntos_total - %s)::text from public.ranking_jugadores(%L) where jugador_id = %L', v_antes, v_camp, j[1])));
        r := r || pg_temp.fila3(15, 'Reapertura', 'ADMINISTRADOR cierra la revisión', 'FINALIZADO 30-20',
             pg_temp.m(pg_temp.como3(u_admin, format('select public.cerrar_revision(%L, ''ZZ9 revisado'')::text', pa))));

        -- ===================== CAMBIO DE REGLAS =====================
        v_suma := pg_temp.como3(u_con, format('select sum(puntos_total)::text from public.ranking_jugadores(%L)', v_camp));
        perform pg_temp.como3(u_admin, 'insert into public.reglas_puntuacion_versiones (codigo, nombre) values (''ZZV9'', ''Prueba V9'')');
        perform pg_temp.como3(u_admin, 'insert into public.reglas_puntuacion_valores (regla_version_id, concepto_codigo, valor) select (select id from public.reglas_puntuacion_versiones where codigo = ''ZZV9''), v.concepto_codigo, case when v.concepto_codigo = ''CONVOCATORIA'' then 1 else v.valor end from public.reglas_puntuacion_valores v join public.reglas_puntuacion_versiones rv on rv.id = v.regla_version_id where rv.es_vigente');
        r := r || pg_temp.fila3(16, 'Reglas', 'Activar una nueva versión no cambia las estadísticas ya jugadas', 'true|' || v_suma,
             pg_temp.como3(u_admin, 'select (public.activar_regla_version((select id from public.reglas_puntuacion_versiones where codigo = ''ZZV9''))) ->> ''es_vigente''')
             || '|' || pg_temp.como3(u_con, format('select sum(puntos_total)::text from public.ranking_jugadores(%L)', v_camp)));

        -- ===================== AUDITORÍA (SECCIÓN 40) =====================
        r := r || pg_temp.fila3(17, 'Auditoría', 'Listas: creadas|devueltas a edición con motivo|confirmaciones', '5|1|true',
             pg_temp.sistema3(format('select (select count(*) from public.auditoria where partido_id = %1$L and accion = ''CREAR_LISTA'' and tabla = ''listas_juego'' and operacion = ''INSERT'') || ''|'' || (select count(*) from public.auditoria where partido_id = %1$L and accion = ''DEVOLVER_LISTA_A_EDICION'' and tabla = ''listas_juego'' and motivo = ''ZZ9 lesión del 17'') || ''|'' || ((select count(*) from public.auditoria where partido_id = %1$L and accion = ''CONFIRMAR_LISTA'') >= 6)', pa)));
        r := r || pg_temp.fila3(18, 'Auditoría', 'Cambio de jugador: convocatoria anulada con valor anterior, nuevo y motivo', '1',
             pg_temp.sistema3(format('select count(*)::text from public.auditoria where partido_id = %L and tabla = ''convocatorias'' and accion = ''GUARDAR_LISTA'' and valor_anterior ->> ''estado'' = ''PROPUESTA'' and valor_nuevo ->> ''estado'' = ''ANULADA_REEMPLAZO'' and valor_nuevo ->> ''jugador_id'' = %L and motivo = ''ZZ9 lesión del 17''', pa, j[17])));
        r := r || pg_temp.fila3(19, 'Auditoría', 'Resultados registrados: filas|con usuario capitán', '50|50',
             pg_temp.sistema3(format('select count(*) || ''|'' || count(*) filter (where usuario_id = %L and usuario_email = ''zz9.capitan@zzprueba.invalid'') from public.auditoria where partido_id = %L and accion = ''REGISTRAR_RESULTADO'' and tabla = ''resultados_enfrentamiento'' and operacion = ''INSERT''', u_cap, pa)));
        r := r || pg_temp.fila3(20, 'Auditoría', 'Corrección: versión anterior desactivada y nueva insertada, con motivo', '1|1',
             pg_temp.sistema3(format('select count(*) filter (where operacion = ''UPDATE'' and (valor_anterior ->> ''vigente'')::boolean and not (valor_nuevo ->> ''vigente'')::boolean) || ''|'' || count(*) filter (where operacion = ''INSERT'') from public.auditoria where partido_id = %L and accion = ''CORREGIR_RESULTADO'' and tabla = ''resultados_enfrentamiento'' and motivo = ''ZZ9 era caída del rival''', pa)));
        r := r || pg_temp.fila3(21, 'Auditoría', 'Reapertura y cierre de revisión con usuario y motivo', '1|1',
             pg_temp.sistema3(format('select count(*) filter (where accion = ''REABRIR_PARTIDO'' and motivo = ''ZZ9 reclamo del rival'') || ''|'' || count(*) filter (where accion = ''CERRAR_REVISION'' and motivo = ''ZZ9 revisado'') from public.auditoria where partido_id = %L and tabla = ''partidos'' and usuario_id = %L', pa, u_admin)));
        r := r || pg_temp.fila3(22, 'Auditoría', 'Cambio de reglas auditado (activación con valor anterior y nuevo)', 'true',
             pg_temp.sistema3(format('select (count(*) >= 1)::text from public.auditoria where accion = ''ACTIVAR_REGLAS'' and tabla = ''reglas_puntuacion_versiones'' and usuario_id = %L and valor_anterior is not null and valor_nuevo is not null', u_admin)));
        r := r || pg_temp.fila3(23, 'Auditoría', 'Operaciones del partido hechas por la app tienen usuario', '0',
             pg_temp.sistema3(format('select count(*)::text from public.auditoria where partido_id = %L and usuario_id is null and accion <> operacion', pa)));
        r := r || pg_temp.fila3(24, 'Auditoría', 'Solo ADMINISTRADOR lee la auditoría: directiva|admin', '0|true',
             pg_temp.como3(u_dir, format('select count(*)::text from public.auditoria where partido_id = %L', pa))
             || '|' || pg_temp.como3(u_admin, format('select (count(*) > 0)::text from public.auditoria where partido_id = %L', pa)));
        r := r || pg_temp.fila3(25, 'Auditoría', 'La auditoría no se puede modificar', 'P0001',
             pg_temp.sistema3(format('update public.auditoria set motivo = ''x'' where partido_id = %L', pa)));

        raise exception using errcode = 'P0001', message = 'ROLLBACK_PRUEBAS_009';
    exception
        when others then
            if sqlerrm <> 'ROLLBACK_PRUEBAS_009' then
                r := r || pg_temp.fila3(0, 'ERROR', 'ERROR INESPERADO: ' || sqlerrm, '-', sqlstate);
            end if;
    end;

    return query
        select (x ->> 'n')::int, x ->> 'g', x ->> 'p', x ->> 'e', x ->> 'o', (x ->> 'e') = (x ->> 'o')
          from jsonb_array_elements(r) as x
         order by 1;
end;
$$;

select * from pg_temp.ejecutar_pruebas_009();
