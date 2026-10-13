-- =====================================================================
-- PRUEBAS 002 — PERMISOS, RLS, AUDITORÍA Y PROTECCIONES
-- Crea usuarios y datos ficticios, actúa como cada rol y DESHACE TODO al
-- final (no queda ningún usuario ni dato de prueba).
-- Resultado esperado: todas las filas con ok = true.
--
-- Columna "esperado":
--   FILAS:n  : la operación funcionó y afectó n filas (FILAS:0 = RLS la filtró).
--   42501    : rechazada por falta de privilegio o por política RLS.
--   P0001    : rechazada por un trigger de protección.
--   23514    : rechazada por CHECK.
--   otro     : valor exacto que debe leerse.
--
-- Nota: el SQL Editor puede advertir "operaciones destructivas" porque el
-- texto contiene DELETE/TRUNCATE. Son intentos que DEBEN fallar y todo se
-- deshace al final. Elija "Correr sin RLS" / "Run without RLS" si aparece.
-- =====================================================================

-- Ejecuta p_sql como un usuario (p_uid) o como anon (p_uid nulo).
-- Devuelve el valor de un SELECT, 'FILAS:n' para escrituras o el SQLSTATE del error.
create or replace function pg_temp.como(p_uid uuid, p_sql text)
returns text
language plpgsql
as $$
declare
    v_txt text;
    v_n   bigint;
begin
    begin
        if p_uid is null then
            perform set_config('request.jwt.claims', '{"role":"anon"}', true);
            execute 'set local role anon';
        else
            perform set_config('request.jwt.claims',
                               json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
            execute 'set local role authenticated';
        end if;

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
        return sqlstate;  -- el rol y los claims se revierten automáticamente
    end;
end;
$$;

-- Ejecuta p_sql como sistema (SQL Editor). Mismo formato de respuesta.
create or replace function pg_temp.sistema(p_sql text)
returns text
language plpgsql
as $$
declare
    v_txt text;
    v_n   bigint;
begin
    if ltrim(lower(p_sql)) like 'select%' then
        execute p_sql into v_txt;
    else
        execute p_sql;
        get diagnostics v_n = row_count;
        v_txt := 'FILAS:' || v_n;
    end if;
    return v_txt;
exception when others then
    return sqlstate;
end;
$$;

create or replace function pg_temp.fila(p_n int, p_g text, p_p text, p_e text, p_o text)
returns jsonb
language sql
as $$
    select jsonb_build_array(jsonb_build_object('n', p_n, 'g', p_g, 'p', p_p, 'e', p_e, 'o', p_o));
$$;

create or replace function pg_temp.ejecutar_pruebas_002()
returns table (n int, grupo text, prueba text, esperado text, obtenido text, ok boolean)
language plpgsql
as $$
declare
    r            jsonb := '[]'::jsonb;
    u_admin      uuid := gen_random_uuid();
    u_dir        uuid := gen_random_uuid();
    u_cap        uuid := gen_random_uuid();
    u_con        uuid := gen_random_uuid();
    u_dir_otro   uuid := gen_random_uuid();
    u_sinrol     uuid := gen_random_uuid();
    u_inactivo   uuid := gen_random_uuid();
    v_regla      uuid;
    v_rayo       uuid;
    v_otro       uuid;
    v_rival      uuid;
    v_rival2     uuid;
    v_camp       uuid;
    j_r1         uuid;
    j_r2         uuid;
    j_o1         uuid;
    p1           uuid;
    p2           uuid;
    v_lista      uuid;
    v_enf        uuid;
    v_conv1      uuid;
    v_conv2      uuid;
    v_part       uuid;
    v_res        uuid;
    v_antes      bigint;
    v_despues    bigint;
    q_jug        text := 'select count(*)::text from public.jugadores where apellidos like ''ZZPRUEBA%''';
    q_par        text;
    q_cat        text := 'select count(*)::text from public.modalidades';
begin
    begin
        -- ===================== DATOS FICTICIOS =====================
        select id into v_regla from public.reglas_puntuacion_versiones where codigo = 'V1';
        select id into v_rayo  from public.clubes where nombre_corto = 'RAYO';

        insert into auth.users (id, email) values
            (u_admin,    'zz.admin@zzprueba.invalid'),
            (u_dir,      'zz.directiva@zzprueba.invalid'),
            (u_cap,      'zz.capitan@zzprueba.invalid'),
            (u_con,      'zz.consulta@zzprueba.invalid'),
            (u_dir_otro, 'zz.directiva.otro@zzprueba.invalid'),
            (u_sinrol,   'zz.sinrol@zzprueba.invalid'),
            (u_inactivo, 'zz.inactivo@zzprueba.invalid');

        insert into public.clubes (nombre, nombre_corto, es_gestionado) values ('ZZPRUEBA OTRO', 'ZZP_OTRO', true) returning id into v_otro;
        insert into public.clubes (nombre, nombre_corto) values ('ZZPRUEBA RIVAL', 'ZZP_RIVAL')   returning id into v_rival;
        insert into public.clubes (nombre, nombre_corto) values ('ZZPRUEBA RIVAL 2', 'ZZP_RIVAL2') returning id into v_rival2;

        insert into public.usuario_roles (usuario_id, rol_codigo, club_id) values
            (u_admin,    'ADMINISTRADOR', null),
            (u_dir,      'DIRECTIVA',     v_rayo),
            (u_cap,      'CAPITAN',       v_rayo),
            (u_con,      'CONSULTA',      v_rayo),
            (u_dir_otro, 'DIRECTIVA',     v_otro),
            (u_inactivo, 'DIRECTIVA',     v_rayo);
        update public.perfiles set estado = 'INACTIVO' where id = u_inactivo;

        insert into public.jugadores (club_id, primer_nombre, apellidos) values (v_rayo, 'Zz', 'ZZPRUEBA Uno')  returning id into j_r1;
        insert into public.jugadores (club_id, primer_nombre, apellidos) values (v_rayo, 'Zz', 'ZZPRUEBA Dos')  returning id into j_r2;
        insert into public.jugadores (club_id, primer_nombre, apellidos) values (v_otro, 'Zz', 'ZZPRUEBA Tres') returning id into j_o1;

        insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo)
             values ('ZZPRUEBA CAMPEONATO', 'ZZ', current_date, 30) returning id into v_camp;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id, lugar)
             values (v_camp, current_date, v_rayo, v_rival, 'Cancha A') returning id into p1;
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id, lugar)
             values (v_camp, current_date, v_otro, v_rival2, 'Cancha Z') returning id into p2;

        q_par := format('select count(*)::text from public.partidos where campeonato_id = %L', v_camp);

        -- ===================== PERFILES Y ROLES =====================
        r := r || pg_temp.fila(1, 'Perfiles', 'Perfil creado automáticamente para cada usuario nuevo', '7',
             pg_temp.sistema('select count(*)::text from public.perfiles where email like ''%@zzprueba.invalid'''));

        r := r || pg_temp.fila(2, 'Perfiles', 'Rechaza rol en club no gestionado (rival)', 'P0001',
             pg_temp.sistema(format('insert into public.usuario_roles (usuario_id, rol_codigo, club_id) values (%L, ''CONSULTA'', %L)', u_sinrol, v_rival)));

        r := r || pg_temp.fila(3, 'Perfiles', 'Rechaza ADMINISTRADOR asociado a un club', '23514',
             pg_temp.sistema(format('insert into public.usuario_roles (usuario_id, rol_codigo, club_id) values (%L, ''ADMINISTRADOR'', %L)', u_sinrol, v_rayo)));

        r := r || pg_temp.fila(4, 'Perfiles', 'Rechaza DIRECTIVA sin club', '23514',
             pg_temp.sistema(format('insert into public.usuario_roles (usuario_id, rol_codigo) values (%L, ''DIRECTIVA'')', u_sinrol)));

        -- ===================== ANÓNIMO =====================
        r := r || pg_temp.fila(5, 'Anónimo', 'anon no puede leer jugadores', '42501', pg_temp.como(null, q_jug));
        r := r || pg_temp.fila(6, 'Anónimo', 'anon no puede leer catálogos', '42501', pg_temp.como(null, q_cat));
        r := r || pg_temp.fila(7, 'Anónimo', 'anon no puede ejecutar funciones privadas', '42501',
             pg_temp.como(null, 'select privado.es_admin()::text'));

        -- ===================== LECTURA =====================
        r := r || pg_temp.fila(8,  'Lectura', 'Usuario activo sin rol lee catálogos', '3', pg_temp.como(u_sinrol, q_cat));
        r := r || pg_temp.fila(9,  'Lectura', 'Usuario INACTIVO no lee catálogos', '0', pg_temp.como(u_inactivo, q_cat));
        r := r || pg_temp.fila(10, 'Lectura', 'Usuario sin rol no ve jugadores', '0', pg_temp.como(u_sinrol, q_jug));
        r := r || pg_temp.fila(11, 'Lectura', 'CONSULTA RAYO ve solo jugadores de RAYO', '2', pg_temp.como(u_con, q_jug));
        r := r || pg_temp.fila(12, 'Lectura', 'DIRECTIVA de otro club ve solo los suyos', '1', pg_temp.como(u_dir_otro, q_jug));
        r := r || pg_temp.fila(13, 'Lectura', 'ADMINISTRADOR ve todos los jugadores', '3', pg_temp.como(u_admin, q_jug));
        r := r || pg_temp.fila(14, 'Lectura', 'DIRECTIVA INACTIVA no ve jugadores', '0', pg_temp.como(u_inactivo, q_jug));
        r := r || pg_temp.fila(15, 'Lectura', 'CONSULTA RAYO ve solo partidos de RAYO', '1', pg_temp.como(u_con, q_par));
        r := r || pg_temp.fila(16, 'Lectura', 'CAPITÁN RAYO ve solo partidos de RAYO', '1', pg_temp.como(u_cap, q_par));
        r := r || pg_temp.fila(17, 'Lectura', 'DIRECTIVA de otro club ve solo sus partidos', '1', pg_temp.como(u_dir_otro, q_par));
        r := r || pg_temp.fila(18, 'Lectura', 'ADMINISTRADOR ve todos los partidos', '2', pg_temp.como(u_admin, q_par));

        -- ===================== JUGADORES =====================
        r := r || pg_temp.fila(19, 'Jugadores', 'DIRECTIVA crea jugador de su club', 'FILAS:1',
             pg_temp.como(u_dir, format('insert into public.jugadores (club_id, primer_nombre, apellidos) values (%L, ''Zz'', ''ZZPRUEBA Nuevo'')', v_rayo)));
        r := r || pg_temp.fila(20, 'Jugadores', 'CAPITÁN no crea jugadores', '42501',
             pg_temp.como(u_cap, format('insert into public.jugadores (club_id, primer_nombre, apellidos) values (%L, ''Zz'', ''ZZPRUEBA X'')', v_rayo)));
        r := r || pg_temp.fila(21, 'Jugadores', 'CONSULTA no crea jugadores', '42501',
             pg_temp.como(u_con, format('insert into public.jugadores (club_id, primer_nombre, apellidos) values (%L, ''Zz'', ''ZZPRUEBA X'')', v_rayo)));
        r := r || pg_temp.fila(22, 'Jugadores', 'DIRECTIVA no crea jugadores en otro club', '42501',
             pg_temp.como(u_dir, format('insert into public.jugadores (club_id, primer_nombre, apellidos) values (%L, ''Zz'', ''ZZPRUEBA X'')', v_otro)));
        r := r || pg_temp.fila(23, 'Jugadores', 'DIRECTIVA no edita jugadores de otro club', 'FILAS:0',
             pg_temp.como(u_dir, format('update public.jugadores set apodo = ''X'' where id = %L', j_o1)));
        r := r || pg_temp.fila(24, 'Jugadores', 'DIRECTIVA no traslada jugador a otro club', '42501',
             pg_temp.como(u_dir, format('update public.jugadores set club_id = %L where id = %L', v_otro, j_r1)));
        r := r || pg_temp.fila(25, 'Jugadores', 'DIRECTIVA no elimina jugadores', '42501',
             pg_temp.como(u_dir, format('delete from public.jugadores where id = %L', j_r1)));
        r := r || pg_temp.fila(26, 'Jugadores', 'DIRECTIVA INACTIVA no crea jugadores', '42501',
             pg_temp.como(u_inactivo, format('insert into public.jugadores (club_id, primer_nombre, apellidos) values (%L, ''Zz'', ''ZZPRUEBA X'')', v_rayo)));

        -- ===================== PARTIDOS =====================
        r := r || pg_temp.fila(27, 'Partidos', 'DIRECTIVA crea partido de su club', 'FILAS:1',
             pg_temp.como(u_dir, format('insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (%L, current_date, %L, %L)', v_camp, v_rayo, v_rival)));
        r := r || pg_temp.fila(28, 'Partidos', 'CAPITÁN no crea partidos', '42501',
             pg_temp.como(u_cap, format('insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (%L, current_date, %L, %L)', v_camp, v_rayo, v_rival)));
        r := r || pg_temp.fila(29, 'Partidos', 'DIRECTIVA no crea partidos ajenos a su club', '42501',
             pg_temp.como(u_dir, format('insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (%L, current_date, %L, %L)', v_camp, v_otro, v_rival2)));
        r := r || pg_temp.fila(30, 'Partidos', 'DIRECTIVA no cambia estado del partido', '42501',
             pg_temp.como(u_dir, format('update public.partidos set estado = ''CANCELADO'' where id = %L', p1)));
        r := r || pg_temp.fila(31, 'Partidos', 'DIRECTIVA no cambia el marcador', '42501',
             pg_temp.como(u_dir, format('update public.partidos set puntaje_local = 1 where id = %L', p1)));
        r := r || pg_temp.fila(32, 'Partidos', 'DIRECTIVA no cambia la versión de reglas', '42501',
             pg_temp.como(u_dir, format('update public.partidos set regla_version_id = %L where id = %L', v_regla, p1)));
        r := r || pg_temp.fila(33, 'Partidos', 'DIRECTIVA edita lugar de su partido', 'FILAS:1',
             pg_temp.como(u_dir, format('update public.partidos set lugar = ''Cancha B'' where id = %L', p1)));
        r := r || pg_temp.fila(34, 'Partidos', 'DIRECTIVA de otro club no edita partido de RAYO', 'FILAS:0',
             pg_temp.como(u_dir_otro, format('update public.partidos set lugar = ''X'' where id = %L', p1)));
        r := r || pg_temp.fila(35, 'Partidos', 'CONSULTA no edita partidos', 'FILAS:0',
             pg_temp.como(u_con, format('update public.partidos set lugar = ''X'' where id = %L', p1)));

        -- ===================== DATOS OPERATIVOS (solo RPC Fase 3) =====================
        r := r || pg_temp.fila(36, 'Operativo', 'CAPITÁN no escribe asistencia directamente', '42501',
             pg_temp.como(u_cap, format('insert into public.asistencias (partido_id, jugador_id, estado) values (%L, %L, ''PRESENTE'')', p1, j_r1)));
        r := r || pg_temp.fila(37, 'Operativo', 'DIRECTIVA no crea listas directamente', '42501',
             pg_temp.como(u_dir, format('insert into public.listas_juego (partido_id, numero) values (%L, 1)', p1)));
        r := r || pg_temp.fila(38, 'Operativo', 'DIRECTIVA no crea convocatorias directamente', '42501',
             pg_temp.como(u_dir, format('insert into public.convocatorias (lista_id, jugador_id) values (%L, %L)', gen_random_uuid(), j_r1)));
        r := r || pg_temp.fila(39, 'Operativo', 'DIRECTIVA no registra resultados directamente', '42501',
             pg_temp.como(u_dir, format('insert into public.resultados_enfrentamiento (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota) values (%L, %L, 1, 0)', gen_random_uuid(), v_rayo)));
        r := r || pg_temp.fila(40, 'Operativo', 'Ni ADMINISTRADOR modifica enfrentamientos directamente', '42501',
             pg_temp.como(u_admin, 'update public.enfrentamientos set version = version + 1'));

        -- ===================== CLUBES =====================
        r := r || pg_temp.fila(41, 'Clubes', 'DIRECTIVA crea club rival', 'FILAS:1',
             pg_temp.como(u_dir, 'insert into public.clubes (nombre, nombre_corto) values (''ZZPRUEBA RIVAL 3'', ''ZZP_RIVAL3'')'));
        r := r || pg_temp.fila(42, 'Clubes', 'DIRECTIVA no marca un club como gestionado', '42501',
             pg_temp.como(u_dir, 'insert into public.clubes (nombre, nombre_corto, es_gestionado) values (''ZZPRUEBA RIVAL 4'', ''ZZP_RIVAL4'', true)'));
        r := r || pg_temp.fila(43, 'Clubes', 'DIRECTIVA no edita un club gestionado', 'FILAS:0',
             pg_temp.como(u_dir, format('update public.clubes set nombre = ''X'' where id = %L', v_rayo)));
        r := r || pg_temp.fila(44, 'Clubes', 'CAPITÁN no crea clubes', '42501',
             pg_temp.como(u_cap, 'insert into public.clubes (nombre, nombre_corto) values (''ZZPRUEBA RIVAL 5'', ''ZZP_RIVAL5'')'));

        -- ===================== CAMPEONATOS Y CONFIGURACIÓN =====================
        r := r || pg_temp.fila(45, 'Campeonatos', 'DIRECTIVA no crea campeonatos', '42501',
             pg_temp.como(u_dir, 'insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo) values (''ZZPRUEBA C2'', ''ZZ'', current_date, 30)'));
        r := r || pg_temp.fila(46, 'Campeonatos', 'ADMINISTRADOR crea campeonatos', 'FILAS:1',
             pg_temp.como(u_admin, 'insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo) values (''ZZPRUEBA C2'', ''ZZ'', current_date, 30)'));
        r := r || pg_temp.fila(47, 'Configuración', 'DIRECTIVA no modifica la configuración', 'FILAS:0',
             pg_temp.como(u_dir, 'update public.configuracion set valor = ''1''::jsonb where clave = ''minimo_ej_ranking_porcentual'''));
        r := r || pg_temp.fila(48, 'Configuración', 'ADMINISTRADOR modifica la configuración', 'FILAS:1',
             pg_temp.como(u_admin, 'update public.configuracion set descripcion = descripcion where clave = ''minimo_ej_ranking_porcentual'' and campeonato_id is null and club_id is null'));

        -- ===================== REGLAS DE PUNTUACIÓN =====================
        r := r || pg_temp.fila(49, 'Reglas', 'DIRECTIVA no crea versiones de reglas', '42501',
             pg_temp.como(u_dir, 'insert into public.reglas_puntuacion_versiones (codigo, nombre) values (''ZZ'', ''Prueba'')'));
        r := r || pg_temp.fila(50, 'Reglas', 'Activar versión no es directo (será RPC)', '42501',
             pg_temp.como(u_admin, format('update public.reglas_puntuacion_versiones set es_vigente = true where id = %L', v_regla)));

        update public.partidos set estado = 'EN_CURSO', iniciado_at = now(), regla_version_id = v_regla where id = p1;

        r := r || pg_temp.fila(51, 'Reglas', 'Versión usada: no se modifican sus valores', 'P0001',
             pg_temp.sistema(format('update public.reglas_puntuacion_valores set valor = 0.60 where regla_version_id = %L and concepto_codigo = ''CONVOCATORIA''', v_regla)));
        r := r || pg_temp.fila(52, 'Reglas', 'Versión usada: no se agregan valores', 'P0001',
             pg_temp.sistema(format('insert into public.reglas_puntuacion_valores (regla_version_id, concepto_codigo, valor) values (%L, ''CONVOCATORIA'', 1)', v_regla)));
        r := r || pg_temp.fila(53, 'Reglas', 'Versión usada: no cambia su nombre', 'P0001',
             pg_temp.sistema(format('update public.reglas_puntuacion_versiones set nombre = ''Otro'' where id = %L', v_regla)));
        r := r || pg_temp.fila(54, 'Reglas', 'Versión usada: sí puede cambiar su vigencia', 'FILAS:1',
             pg_temp.sistema(format('update public.reglas_puntuacion_versiones set es_vigente = false where id = %L', v_regla)));

        -- ===================== PERFILES Y ROLES (APP) =====================
        r := r || pg_temp.fila(55, 'Usuarios', 'DIRECTIVA ve solo sus propios roles', '1',
             pg_temp.como(u_dir, 'select count(*)::text from public.usuario_roles'));
        r := r || pg_temp.fila(56, 'Usuarios', 'DIRECTIVA no se asigna ADMINISTRADOR', '42501',
             pg_temp.como(u_dir, format('insert into public.usuario_roles (usuario_id, rol_codigo) values (%L, ''ADMINISTRADOR'')', u_dir)));
        r := r || pg_temp.fila(57, 'Usuarios', 'ADMINISTRADOR asigna rol CONSULTA', 'FILAS:1',
             pg_temp.como(u_admin, format('insert into public.usuario_roles (usuario_id, rol_codigo, club_id) values (%L, ''CONSULTA'', %L)', u_sinrol, v_rayo)));
        r := r || pg_temp.fila(58, 'Usuarios', 'Usuario no cambia su propio estado', 'P0001',
             pg_temp.como(u_dir, format('update public.perfiles set estado = ''INACTIVO'' where id = %L', u_dir)));
        r := r || pg_temp.fila(59, 'Usuarios', 'Usuario edita su propio nombre', 'FILAS:1',
             pg_temp.como(u_dir, format('update public.perfiles set nombre_completo = ''Zz Directiva'' where id = %L', u_dir)));
        r := r || pg_temp.fila(60, 'Usuarios', 'Usuario no edita perfiles ajenos', 'FILAS:0',
             pg_temp.como(u_dir, format('update public.perfiles set nombre_completo = ''X'' where id = %L', u_cap)));
        r := r || pg_temp.fila(61, 'Usuarios', 'Rechaza quitar todos los ADMINISTRADOR', 'P0001',
             pg_temp.sistema('delete from public.usuario_roles where rol_codigo = ''ADMINISTRADOR'''));
        r := r || pg_temp.fila(62, 'Usuarios', 'Rechaza desactivar a todos los ADMINISTRADOR', 'P0001',
             pg_temp.sistema('update public.perfiles set estado = ''INACTIVO'' where id in (select usuario_id from public.usuario_roles where rol_codigo = ''ADMINISTRADOR'')'));

        -- ===================== AUDITORÍA =====================
        r := r || pg_temp.fila(63, 'Auditoría', 'Alta de jugador auditada con usuario y origen', 'INSERT|APP|true',
             pg_temp.sistema(format('select operacion || ''|'' || origen || ''|'' || (usuario_id = %L)::text from public.auditoria where tabla = ''jugadores'' and valor_nuevo ->> ''apellidos'' = ''ZZPRUEBA Nuevo''', u_dir)));
        r := r || pg_temp.fila(64, 'Auditoría', 'Cambio guarda valor anterior, nuevo y partido', 'UPDATE|Cancha A|Cancha B|true',
             pg_temp.sistema(format('select operacion || ''|'' || (valor_anterior ->> ''lugar'') || ''|'' || (valor_nuevo ->> ''lugar'') || ''|'' || (partido_id = %L)::text from public.auditoria where tabla = ''partidos'' and registro_id = %L and valor_nuevo ->> ''lugar'' = ''Cancha B''', p1, p1)));

        perform set_config('app.motivo', 'Cambio de cancha por lluvia', true);
        perform pg_temp.como(u_dir, format('update public.partidos set lugar = ''Cancha C'' where id = %L', p1));
        perform set_config('app.motivo', '', true);
        r := r || pg_temp.fila(65, 'Auditoría', 'Registra el motivo indicado por la operación', 'Cambio de cancha por lluvia',
             pg_temp.sistema(format('select motivo from public.auditoria where tabla = ''partidos'' and registro_id = %L and valor_nuevo ->> ''lugar'' = ''Cancha C''', p1)));

        select count(*) into v_antes from public.auditoria where tabla = 'jugadores' and registro_id = j_r1::text;
        update public.jugadores set apodo = apodo where id = j_r1;
        select count(*) into v_despues from public.auditoria where tabla = 'jugadores' and registro_id = j_r1::text;
        r := r || pg_temp.fila(66, 'Auditoría', 'Un UPDATE sin cambios no genera auditoría', '0', (v_despues - v_antes)::text);

        r := r || pg_temp.fila(67, 'Auditoría', 'DIRECTIVA no lee la auditoría', '0',
             pg_temp.como(u_dir, 'select count(*)::text from public.auditoria'));
        r := r || pg_temp.fila(68, 'Auditoría', 'ADMINISTRADOR lee la auditoría', 'true',
             pg_temp.como(u_admin, 'select (count(*) > 0)::text from public.auditoria'));
        r := r || pg_temp.fila(69, 'Auditoría', 'Nadie modifica la auditoría', 'P0001',
             pg_temp.sistema('update public.auditoria set motivo = ''X'' where id = (select max(id) from public.auditoria)'));
        r := r || pg_temp.fila(70, 'Auditoría', 'Nadie elimina la auditoría', 'P0001',
             pg_temp.sistema('delete from public.auditoria where id = (select max(id) from public.auditoria)'));
        r := r || pg_temp.fila(71, 'Auditoría', 'Nadie vacía la auditoría (TRUNCATE)', 'P0001',
             pg_temp.sistema('truncate public.auditoria'));

        -- ===================== PROTECCIÓN DEL HISTORIAL =====================
        insert into public.listas_juego (partido_id, numero) values (p1, 1) returning id into v_lista;
        insert into public.enfrentamientos (lista_id, modalidad_codigo, numero, orden_juego) values (v_lista, 'INDIVIDUAL', 1, 1) returning id into v_enf;
        insert into public.convocatorias (lista_id, jugador_id) values (v_lista, j_r1) returning id into v_conv1;
        insert into public.convocatorias (lista_id, jugador_id) values (v_lista, j_r2) returning id into v_conv2;
        insert into public.participantes_enfrentamiento (enfrentamiento_id, lista_id, convocatoria_id, posicion)
             values (v_enf, v_lista, v_conv1, 1) returning id into v_part;
        update public.convocatorias set estado = 'VIGENTE', puntos = 0.50, fue_confirmada = true where id = v_conv1;
        update public.listas_juego set estado = 'CONFIRMADA', confirmada_at = now() where id = v_lista;
        insert into public.resultados_enfrentamiento (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota)
             values (v_enf, v_rayo, 1, 0) returning id into v_res;
        insert into public.asistencias (partido_id, jugador_id, estado) values (p1, j_r1, 'PRESENTE');

        r := r || pg_temp.fila(72, 'Historial', 'No se elimina un partido', 'P0001',
             pg_temp.sistema(format('delete from public.partidos where id = %L', p2)));
        r := r || pg_temp.fila(73, 'Historial', 'No se elimina un jugador', 'P0001',
             pg_temp.sistema(format('delete from public.jugadores where id = %L', j_o1)));
        r := r || pg_temp.fila(74, 'Historial', 'No se elimina una asistencia', 'P0001',
             pg_temp.sistema(format('delete from public.asistencias where partido_id = %L', p1)));
        r := r || pg_temp.fila(75, 'Historial', 'No se elimina un resultado', 'P0001',
             pg_temp.sistema(format('delete from public.resultados_enfrentamiento where id = %L', v_res)));
        r := r || pg_temp.fila(76, 'Historial', 'Convocatoria nunca confirmada sí se elimina', 'FILAS:1',
             pg_temp.sistema(format('delete from public.convocatorias where id = %L', v_conv2)));
        r := r || pg_temp.fila(77, 'Historial', 'Convocatoria confirmada no se elimina', 'P0001',
             pg_temp.sistema(format('delete from public.convocatorias where id = %L', v_conv1)));
        r := r || pg_temp.fila(78, 'Historial', 'Participante de lista confirmada no se elimina', 'P0001',
             pg_temp.sistema(format('delete from public.participantes_enfrentamiento where id = %L', v_part)));
        r := r || pg_temp.fila(79, 'Historial', 'No se vacía una tabla de historial (TRUNCATE)', 'P0001',
             pg_temp.sistema('truncate public.acciones_resultado'));

        -- Deshacer todos los datos de prueba.
        raise exception using errcode = 'P0001', message = 'ROLLBACK_PRUEBAS_002';
    exception
        when others then
            if sqlerrm <> 'ROLLBACK_PRUEBAS_002' then
                r := r || pg_temp.fila(0, 'ERROR', 'ERROR INESPERADO: ' || sqlerrm, '-', sqlstate);
            end if;
    end;

    return query
        select (x ->> 'n')::int, x ->> 'g', x ->> 'p', x ->> 'e', x ->> 'o', (x ->> 'e') = (x ->> 'o')
          from jsonb_array_elements(r) as x
         order by 1;
end;
$$;

select * from pg_temp.ejecutar_pruebas_002();
