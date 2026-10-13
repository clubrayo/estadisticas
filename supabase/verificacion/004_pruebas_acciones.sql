-- =====================================================================
-- PRUEBAS 004 — ACCIONES POR INTEGRANTE Y RESULTADO POR SECRETARÍA
-- Simula un partido con la regla de la migración 004 actuando como cada rol
-- y DESHACE TODO al final (no queda ningún dato de prueba).
-- Resultado esperado: todas las filas con ok = true.
--
-- Columna "esperado":
--   P0001:CODIGO : rechazo de negocio con su código (p. ej. P0001:ACCIONES_INVALIDAS).
--   42501:...    : rechazo por permisos.
--   otro         : valor exacto que debe leerse (marcadores, puntajes).
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

-- Una acción para p_acciones.
create or replace function pg_temp.a(p_jugador uuid, p_tipo text)
returns jsonb
language sql
as $$
    select jsonb_build_object('jugador_id', p_jugador, 'tipo_accion', p_tipo);
$$;

-- Registra con la firma de la migración 004.
create or replace function pg_temp.reg4(p_uid uuid, p_lista uuid, p_orden int, p_resultado text, p_acciones jsonb,
                                        p_secretaria boolean default false, p_motivo text default null,
                                        p_version int default null)
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
        v_enf, p_resultado, p_acciones, coalesce(p_version, v_ver), p_secretaria, p_motivo));
end;
$$;

create or replace function pg_temp.corr4(p_uid uuid, p_lista uuid, p_orden int, p_resultado text, p_acciones jsonb,
                                         p_motivo text, p_secretaria boolean default false)
returns text
language plpgsql
as $$
declare
    v_enf uuid := pg_temp.enf(p_lista, p_orden);
    v_ver int;
begin
    select version into v_ver from public.enfrentamientos where id = v_enf;
    return pg_temp.como3(p_uid, format(
        'select public.corregir_resultado(%L, %L, %L::jsonb, %L, %s, false, %L)::text',
        v_enf, p_resultado, p_acciones, p_motivo, v_ver, p_secretaria));
end;
$$;

create or replace function pg_temp.ejecutar_pruebas_004()
returns table (n int, grupo text, prueba text, esperado text, obtenido text, ok boolean)
language plpgsql
as $$
declare
    r        jsonb := '[]'::jsonb;
    u_admin  uuid := gen_random_uuid();
    u_dir    uuid := gen_random_uuid();
    u_cap    uuid := gen_random_uuid();
    v_rayo   uuid;
    v_rival  uuid;
    v_camp   uuid;
    v_p      uuid;
    v_l      uuid;
    v_id     uuid;
    v_ver    int;
    j        uuid[] := '{}';
    v_asis   jsonb;
    a        jsonb;
begin
    begin
        -- ===================== DATOS FICTICIOS =====================
        select id into v_rayo from public.clubes where nombre_corto = 'RAYO';
        insert into auth.users (id, email) values
            (u_admin, 'zz4.admin@zzprueba.invalid'),
            (u_dir,   'zz4.directiva@zzprueba.invalid'),
            (u_cap,   'zz4.capitan@zzprueba.invalid');
        insert into public.usuario_roles (usuario_id, rol_codigo, club_id) values
            (u_admin, 'ADMINISTRADOR', null),
            (u_dir,   'DIRECTIVA',     v_rayo),
            (u_cap,   'CAPITAN',       v_rayo);
        insert into public.clubes (nombre, nombre_corto) values ('ZZPRUEBA4 RIVAL', 'ZZP4_RIV') returning id into v_rival;
        for i in 1 .. 17 loop
            insert into public.jugadores (club_id, primer_nombre, apellidos)
                 values (v_rayo, 'Zz', 'ZZPRUEBA4 ' || lpad(i::text, 2, '0')) returning id into v_id;
            j := j || v_id;
        end loop;
        insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo)
             values ('ZZPRUEBA CAMPEONATO 004', 'ZZ', current_date, 30) returning id into v_camp;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id)
             values (v_camp, current_date, v_rayo, v_rival) returning id into v_p;
        select jsonb_agg(jsonb_build_object('jugador_id', x, 'estado', 'PRESENTE')) into v_asis from unnest(j) x;
        perform pg_temp.como3(u_cap, format('select public.iniciar_partido(%L)::text', v_p));
        perform pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', v_p, v_asis));
        -- Lista: Ind1-5 = j1..j5 · D1 = j6,j7 · D2 = j8,j9 · D3 = j10,j11 · T1 = j12,j13,j14 · T2 = j15,j16,j17
        v_l := pg_temp.lista_confirmada(u_cap, v_p, j);

        -- ===================== INDIVIDUALES =====================
        r := r || pg_temp.fila3(1, 'Individual', 'Rechaza dos acciones en un individual', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_cap, v_l, 1, 'GANADO', jsonb_build_array(pg_temp.a(j[1], 'CORTO'), pg_temp.a(j[1], 'CORTO'))));
        r := r || pg_temp.fila3(2, 'Individual', 'Rechaza victoria sin acción', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_cap, v_l, 1, 'GANADO', '[]'::jsonb));
        r := r || pg_temp.fila3(3, 'Individual', 'Victoria con Cortó', 'EN_CURSO 1-0',
             pg_temp.m(pg_temp.reg4(u_cap, v_l, 1, 'GANADO', jsonb_build_array(pg_temp.a(j[1], 'CORTO')))));
        r := r || pg_temp.fila3(4, 'Individual', 'Rechaza derrota con causa positiva', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_cap, v_l, 2, 'PERDIDO', jsonb_build_array(pg_temp.a(j[2], 'CORTO'))));
        r := r || pg_temp.fila3(5, 'Individual', 'Derrota por caída propia (-1)', 'EN_CURSO 1-1|-0.50',
             pg_temp.m(pg_temp.reg4(u_cap, v_l, 2, 'PERDIDO', jsonb_build_array(pg_temp.a(j[2], 'CAIDA_PROPIA'))))
             || '|' || pg_temp.puntos(v_l, j[2]));

        -- ===================== POR SECRETARÍA =====================
        r := r || pg_temp.fila3(6, 'Secretaría', 'CAPITÁN no registra por secretaría', '42501:PERMISO_DENEGADO',
             pg_temp.reg4(u_cap, v_l, 3, 'GANADO', '[]'::jsonb, true, 'Rival descalificado'));
        r := r || pg_temp.fila3(7, 'Secretaría', 'Por secretaría exige motivo', 'P0001:MOTIVO_REQUERIDO',
             pg_temp.reg4(u_dir, v_l, 3, 'GANADO', '[]'::jsonb, true, null));
        r := r || pg_temp.fila3(8, 'Secretaría', 'Por secretaría no lleva acciones', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_dir, v_l, 3, 'GANADO', jsonb_build_array(pg_temp.a(j[3], 'CORTO')), true, 'Rival descalificado'));
        r := r || pg_temp.fila3(9, 'Secretaría', 'DIRECTIVA registra victoria por secretaría', 'EN_CURSO 2-1',
             pg_temp.m(pg_temp.reg4(u_dir, v_l, 3, 'GANADO', '[]'::jsonb, true, 'Rival descalificado')));
        r := r || pg_temp.fila3(10, 'Secretaría', 'Ganador por secretaría: 0.5 + 1, cuenta como EJ', '1.50|1',
             pg_temp.puntos(v_l, j[3]) || '|' || pg_temp.ej(v_l, j[3]));
        r := r || pg_temp.fila3(11, 'Secretaría', 'Queda marcado con su motivo', 'true|Rival descalificado',
             pg_temp.sistema3(format('select por_secretaria::text || ''|'' || motivo_secretaria from public.resultados_enfrentamiento where enfrentamiento_id = %L and vigente', pg_temp.enf(v_l, 3))));

        perform pg_temp.reg4(u_cap, v_l, 4, 'GANADO', jsonb_build_array(pg_temp.a(j[4], 'CORTO')));         -- 3-1
        perform pg_temp.reg4(u_cap, v_l, 5, 'PERDIDO', jsonb_build_array(pg_temp.a(j[5], 'LO_CORTARON')));  -- 3-2

        -- ===================== DUPLA 1 (j6, j7) =====================
        r := r || pg_temp.fila3(12, 'Dupla', 'Derrota con la negativa de un solo integrante', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_cap, v_l, 6, 'PERDIDO', jsonb_build_array(pg_temp.a(j[6], 'LO_CORTARON'))));
        r := r || pg_temp.fila3(13, 'Dupla', 'Un jugador con dos negativas', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_cap, v_l, 6, 'PERDIDO', jsonb_build_array(pg_temp.a(j[6], 'LO_CORTARON'), pg_temp.a(j[6], 'CAIDA_PROPIA'), pg_temp.a(j[7], 'LO_CORTARON'))));
        r := r || pg_temp.fila3(14, 'Dupla', 'Un jugador con tres acciones en dupla', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_cap, v_l, 6, 'GANADO', jsonb_build_array(pg_temp.a(j[6], 'CORTO'), pg_temp.a(j[6], 'CORTO'), pg_temp.a(j[6], 'CAIDA_RIVAL'))));
        r := r || pg_temp.fila3(15, 'Dupla', 'Victoria con ambos integrantes caídos', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_cap, v_l, 6, 'GANADO', jsonb_build_array(pg_temp.a(j[6], 'CORTO'), pg_temp.a(j[6], 'LO_CORTARON'), pg_temp.a(j[7], 'LO_CORTARON'))));
        select version into v_ver from public.enfrentamientos where id = pg_temp.enf(v_l, 6);
        a := jsonb_build_array(pg_temp.a(j[6], 'CORTO'), pg_temp.a(j[6], 'CORTO'), pg_temp.a(j[7], 'LO_CORTARON'));
        r := r || pg_temp.fila3(16, 'Dupla', 'Victoria: A corta a los dos rivales, a B lo cortan', 'EN_CURSO 4-2',
             pg_temp.m(pg_temp.reg4(u_cap, v_l, 6, 'GANADO', a)));
        r := r || pg_temp.fila3(17, 'Dupla', 'Puntaje: A 0.5+1+1+1 · B 0.5+1-0.5', '3.50|1.00',
             pg_temp.puntos(v_l, j[6]) || '|' || pg_temp.puntos(v_l, j[7]));
        r := r || pg_temp.fila3(18, 'Dupla', 'Reenvío con las acciones en otro orden: idempotente', 'true',
             pg_temp.como3(u_dir, format('select (public.registrar_resultado(%L, ''GANADO'', %L::jsonb, %s)) ->> ''ya_registrado''',
                 pg_temp.enf(v_l, 6), jsonb_build_array(pg_temp.a(j[7], 'LO_CORTARON'), pg_temp.a(j[6], 'CORTO'), pg_temp.a(j[6], 'CORTO')), v_ver)));

        -- ===================== DUPLA 2 (j8, j9) =====================
        r := r || pg_temp.fila3(19, 'Dupla', 'Derrota habiendo eliminado a ambos rivales', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_cap, v_l, 7, 'PERDIDO', jsonb_build_array(pg_temp.a(j[8], 'CORTO'), pg_temp.a(j[8], 'LO_CORTARON'), pg_temp.a(j[9], 'CORTO'), pg_temp.a(j[9], 'CAIDA_PROPIA'))));
        r := r || pg_temp.fila3(20, 'Dupla', 'Derrota: A corta y luego lo cortan; B revienta hilo', 'EN_CURSO 4-3',
             pg_temp.m(pg_temp.reg4(u_cap, v_l, 7, 'PERDIDO', jsonb_build_array(pg_temp.a(j[8], 'CORTO'), pg_temp.a(j[8], 'LO_CORTARON'), pg_temp.a(j[9], 'REVENTON_PROPIO')))));
        r := r || pg_temp.fila3(21, 'Dupla', 'Puntaje: A 0.5+0+1-0.5 · B 0.5+0-0.7', '1.00|-0.20',
             pg_temp.puntos(v_l, j[8]) || '|' || pg_temp.puntos(v_l, j[9]));

        perform pg_temp.reg4(u_cap, v_l, 8, 'GANADO', jsonb_build_array(pg_temp.a(j[10], 'CAIDA_RIVAL'), pg_temp.a(j[11], 'REVENTON_RIVAL')));  -- 5-3

        -- ===================== TRÍOS =====================
        r := r || pg_temp.fila3(22, 'Trío', 'Victoria con más positivas que volantines rivales', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_cap, v_l, 9, 'GANADO', jsonb_build_array(pg_temp.a(j[12], 'CORTO'), pg_temp.a(j[12], 'CORTO'), pg_temp.a(j[13], 'CORTO'), pg_temp.a(j[14], 'CORTO'))));
        perform pg_temp.reg4(u_cap, v_l, 9, 'GANADO', jsonb_build_array(pg_temp.a(j[12], 'CORTO'), pg_temp.a(j[12], 'CORTO'), pg_temp.a(j[12], 'CORTO')));  -- 6-3
        r := r || pg_temp.fila3(23, 'Trío', 'Victoria: A corta a los tres rivales', '4.50|1.50|1.50',
             pg_temp.puntos(v_l, j[12]) || '|' || pg_temp.puntos(v_l, j[13]) || '|' || pg_temp.puntos(v_l, j[14]));
        r := r || pg_temp.fila3(24, 'Trío', 'Derrota sin la negativa de un integrante', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.reg4(u_cap, v_l, 10, 'PERDIDO', jsonb_build_array(pg_temp.a(j[15], 'LO_CORTARON'), pg_temp.a(j[16], 'CAIDA_PROPIA'))));
        r := r || pg_temp.fila3(25, 'Trío', 'Derrota válida: cada integrante con su negativa', 'EN_CURSO 6-4|FINALIZADA',
             pg_temp.m(pg_temp.reg4(u_cap, v_l, 10, 'PERDIDO', jsonb_build_array(pg_temp.a(j[15], 'CORTO'), pg_temp.a(j[15], 'LO_CORTARON'), pg_temp.a(j[16], 'CAIDA_PROPIA'), pg_temp.a(j[17], 'LO_CORTARON'))))
             || '|' || pg_temp.sistema3(format('select estado from public.listas_juego where id = %L', v_l)));
        r := r || pg_temp.fila3(26, 'Trío', 'Puntaje: 0.5+1-0.5 · 0.5-1 · 0.5-0.5', '1.00|-0.50|0.00',
             pg_temp.puntos(v_l, j[15]) || '|' || pg_temp.puntos(v_l, j[16]) || '|' || pg_temp.puntos(v_l, j[17]));

        -- ===================== CORRECCIONES =====================
        r := r || pg_temp.fila3(27, 'Corrección', 'Corrección también exige las reglas', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.corr4(u_dir, v_l, 6, 'PERDIDO', jsonb_build_array(pg_temp.a(j[6], 'LO_CORTARON')), 'Error de registro'));
        r := r || pg_temp.fila3(28, 'Corrección', 'Dupla 1 corregida a derrota con ambos caídos', 'EN_CURSO 5-5',
             pg_temp.m(pg_temp.corr4(u_dir, v_l, 6, 'PERDIDO', jsonb_build_array(pg_temp.a(j[6], 'LO_CORTARON'), pg_temp.a(j[7], 'CAIDA_PROPIA')), 'Error de registro')));
        r := r || pg_temp.fila3(29, 'Corrección', 'Nuevo puntaje e historial conservado (versiones|acciones)', '0.00|-0.50|2|5',
             pg_temp.puntos(v_l, j[6]) || '|' || pg_temp.puntos(v_l, j[7]) || '|'
             || pg_temp.sistema3(format('select count(distinct r.id) || ''|'' || count(a.id) from public.resultados_enfrentamiento r left join public.acciones_resultado a on a.resultado_id = r.id where r.enfrentamiento_id = %L', pg_temp.enf(v_l, 6))));
        r := r || pg_temp.fila3(30, 'Corrección', 'Secretaría corregida a resultado con acción', 'EN_CURSO 5-5|false',
             pg_temp.m(pg_temp.corr4(u_dir, v_l, 3, 'GANADO', jsonb_build_array(pg_temp.a(j[3], 'CORTO')), 'Se jugó y cortó')) || '|'
             || pg_temp.sistema3(format('select por_secretaria::text from public.resultados_enfrentamiento where enfrentamiento_id = %L and vigente', pg_temp.enf(v_l, 3))));

        -- ===================== INTEGRIDAD =====================
        r := r || pg_temp.fila3(31, 'Integridad', 'Todas las verificaciones diferidas pasan', 'FILAS:0',
             pg_temp.sistema3('set constraints all immediate'));
        r := r || pg_temp.fila3(32, 'Integridad', 'verificar_partido sin problemas', '[]',
             pg_temp.como3(u_admin, format('select ((public.verificar_partido(%L)) -> ''problemas'')::text', v_p)));

        -- Simula un resultado con la regla anterior (acciones incompletas) escrito directo en la base.
        -- La prueba 31 dejó las verificaciones en modo inmediato: se vuelve al modo normal (diferido).
        perform pg_temp.sistema3('set constraints all deferred');
        perform pg_temp.sistema3(format(
            'insert into public.acciones_resultado (resultado_id, enfrentamiento_id, participante_id, tipo_accion_codigo, puntos)
             select r.id, r.enfrentamiento_id, pe.id, ''LO_CORTARON'', -0.5
               from public.resultados_enfrentamiento r
               join public.participantes_enfrentamiento pe on pe.enfrentamiento_id = r.enfrentamiento_id
              where r.enfrentamiento_id = %L and r.vigente', pg_temp.enf(v_l, 8)));
        r := r || pg_temp.fila3(33, 'Integridad', 'verificar_partido detecta acciones inválidas', 'true',
             pg_temp.como3(u_admin, format('select (((public.verificar_partido(%L)) -> ''problemas'')::text like ''%%acciones incompletas%%'')::text', v_p)));
        r := r || pg_temp.fila3(34, 'Integridad', 'La base rechaza esas acciones al confirmar la transacción', 'P0001:ACCIONES_INVALIDAS',
             pg_temp.sistema3('set constraints all immediate'));

        raise exception using errcode = 'P0001', message = 'ROLLBACK_PRUEBAS_004';
    exception
        when others then
            if sqlerrm <> 'ROLLBACK_PRUEBAS_004' then
                r := r || pg_temp.fila3(0, 'ERROR', 'ERROR INESPERADO: ' || sqlerrm, '-', sqlstate);
            end if;
    end;

    return query
        select (x ->> 'n')::int, x ->> 'g', x ->> 'p', x ->> 'e', x ->> 'o', (x ->> 'e') = (x ->> 'o')
          from jsonb_array_elements(r) as x
         order by 1;
end;
$$;

select * from pg_temp.ejecutar_pruebas_004();
