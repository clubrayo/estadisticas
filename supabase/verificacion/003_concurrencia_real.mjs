// =====================================================================
// PRUEBA 003 — CONCURRENCIA REAL (dos conexiones simultáneas)
// Levanta un PostgreSQL local temporal, instala las migraciones 001-004 y
// hace competir a dos usuarios sobre el mismo partido. No usa Supabase.
//
// Ejecución (desde una carpeta temporal, fuera del proyecto):
//   1. Copie este archivo a una carpeta temporal.
//   2. En esa carpeta: npm init -y && npm i embedded-postgres pg
//   3. node 003_concurrencia_real.mjs <ruta-del-proyecto>/supabase
// Resultado esperado: 16 / 16 correctas.
// =====================================================================
import EmbeddedPostgres from 'embedded-postgres';
import pg from 'pg';
import fs from 'fs';
import path from 'path';
import os from 'os';
import { fileURLToPath } from 'url';

// Ruta a la carpeta supabase del proyecto (primer argumento).
const P = path.resolve(process.argv[2] ?? path.join(path.dirname(fileURLToPath(import.meta.url)), '..')) + '/';
const dir = path.join(os.tmpdir(), 'rayo-concurrencia-pg');
fs.rmSync(dir, { recursive: true, force: true });
const server = new EmbeddedPostgres({ databaseDir: dir, user: 'postgres', password: 'local', port: 54329, persistent: false });
await server.initialise();
await server.start();
const conf = { host: 'localhost', port: 54329, user: 'postgres', password: 'local', database: 'postgres' };
const admin = new pg.Client(conf);
await admin.connect();
console.log((await admin.query('select version()')).rows[0].version.split(',')[0]);

const U_CAP = '00000000-0000-0000-0000-0000000000c1';
const U_DIR = '00000000-0000-0000-0000-0000000000d1';

try {
  // Entorno mínimo equivalente a Supabase.
  await admin.query(`
    create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
    grant usage on schema public to anon, authenticated, service_role;
    alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
    alter default privileges for role postgres in schema public grant all on functions to anon, authenticated, service_role;
    alter default privileges for role postgres in schema public grant all on sequences to anon, authenticated, service_role;
    create schema auth; grant usage on schema auth to anon, authenticated, service_role;
    create table auth.users(id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb);
    create function auth.uid() returns uuid language sql stable as $f$
      select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $f$;
    grant execute on function auth.uid() to anon, authenticated;`);
  for (const m of ['001_esquema_inicial', '002_auth_roles_rls_auditoria', '003_reglas_de_juego_rpc', '004_acciones_por_integrante']) {
    await admin.query(fs.readFileSync(`${P}migrations/${m}.sql`, 'utf8'));
  }
  console.log('Migraciones 001-004 instaladas');

  // Datos: 5 partidos con objetivo 3, cada uno 2-0 con la lista 1 confirmada.
  const utilidades = fs.readFileSync(`${P}verificacion/003_pruebas_juego.sql`, 'utf8').split('-- ---------- Pruebas ----------')[0];
  await admin.query(utilidades);
  await admin.query('create table public.zz_ctx (k text primary key, v uuid)');
  await admin.query(`
  do $d$
  declare
    u_cap uuid := '${U_CAP}'; u_dir uuid := '${U_DIR}';
    v_rayo uuid; v_rival uuid; v_camp uuid; j uuid[] := '{}'; v_id uuid; p uuid; l uuid; v_asis jsonb;
  begin
    select id into v_rayo from public.clubes where nombre_corto = 'RAYO';
    insert into auth.users (id, email) values (u_cap, 'cap@local.invalid'), (u_dir, 'dir@local.invalid');
    insert into public.usuario_roles (usuario_id, rol_codigo, club_id) values (u_cap, 'CAPITAN', v_rayo), (u_dir, 'DIRECTIVA', v_rayo);
    insert into public.clubes (nombre, nombre_corto) values ('RIVAL', 'RIVAL') returning id into v_rival;
    for i in 1 .. 17 loop
      insert into public.jugadores (club_id, primer_nombre, apellidos) values (v_rayo, 'J', 'Jugador ' || i) returning id into v_id;
      j := j || v_id;
    end loop;
    select jsonb_agg(jsonb_build_object('jugador_id', x, 'estado', 'PRESENTE')) into v_asis from unnest(j) x;
    insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo)
         values ('C', 'T', current_date, 3) returning id into v_camp;
    for k in 1 .. 5 loop
      insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id)
           values (v_camp, current_date, v_rayo, v_rival) returning id into p;
      perform pg_temp.como3(u_cap, format('select public.iniciar_partido(%L)::text', p));
      perform pg_temp.como3(u_cap, format('select public.registrar_asistencia(%L, %L::jsonb)::text', p, v_asis));
      l := pg_temp.lista_confirmada(u_cap, p, j);
      if pg_temp.m(pg_temp.jugar(u_cap, l, 1, true)) <> 'EN_CURSO 1-0'
         or pg_temp.m(pg_temp.jugar(u_cap, l, 2, true)) <> 'EN_CURSO 2-0' then
        raise exception 'Preparación fallida';
      end if;
      insert into public.zz_ctx values ('p' || k, p), ('l' || k, l);
    end loop;
  end $d$;`);
  console.log('Datos de prueba: 5 partidos a 2-0 con objetivo 3\n');

  const ctx = Object.fromEntries((await admin.query('select k, v from public.zz_ctx')).rows.map(r => [r.k, r.v]));
  const enf = async (k, orden) => (await admin.query(
    'select e.id, e.version from public.enfrentamientos e where e.lista_id = $1 and e.orden_juego = $2',
    [ctx['l' + k], orden])).rows[0];
  const jugador = async (enfId) => (await admin.query(
    `select c.jugador_id from public.participantes_enfrentamiento pe
       join public.convocatorias c on c.id = pe.convocatoria_id
      where pe.enfrentamiento_id = $1 and pe.posicion = 1`, [enfId])).rows[0].jugador_id;

  // Conexión independiente como usuario autenticado, con su transacción abierta.
  const sesion = async (uid) => {
    const c = new pg.Client(conf);
    await c.connect();
    const pid = (await c.query('select pg_backend_pid() as pid')).rows[0].pid;
    await c.query('begin');
    await c.query(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify({ sub: uid, role: 'authenticated' })]);
    await c.query('set local role authenticated');
    return { c, pid };
  };
  const registrar = (s, e, jug, resultado, tipo) =>
    s.c.query('select public.registrar_resultado($1, $2, $3::jsonb, $4) as r',
      [e.id, resultado, JSON.stringify([{ jugador_id: jug, tipo_accion: tipo }]), e.version])
      .then(x => ({ ok: true, r: x.rows[0].r }), err => ({ ok: false, codigo: err.hint || err.code }));
  const esperandoBloqueo = async (pid) => {
    for (let i = 0; i < 50; i++) {
      const w = (await admin.query('select wait_event_type from pg_stat_activity where pid = $1', [pid])).rows[0];
      if (w && w.wait_event_type === 'Lock') return true;
      await new Promise(r => setTimeout(r, 100));
    }
    return false;
  };
  const estado = async (k) => (await admin.query(
    `select p.estado || ' ' || p.puntaje_local || '-' || p.puntaje_visitante as m,
            (select count(*) from public.resultados_enfrentamiento r
               join public.enfrentamientos e on e.id = r.enfrentamiento_id where e.lista_id = $2)::int as resultados,
            (select count(*) from public.enfrentamientos e
              where e.lista_id = $2 and e.estado_codigo = 'NO_DISPUTADO_FIN_PARTIDO')::int as no_disp
       from public.partidos p where p.id = $1`, [ctx['p' + k], ctx['l' + k]])).rows[0];

  const filas = [];
  const prueba = (n, nombre, esperado, obtenido) => filas.push({ n, nombre, esperado, obtenido, ok: esperado === obtenido });
  const marcador = (x) => x.ok ? `${x.r.estado} ${x.r.puntaje_local}-${x.r.puntaje_visitante}` : x.codigo;

  // C1: mismo enfrentamiento y mismo resultado, dos usuarios a la vez.
  {
    const e = await enf(1, 3), jug = await jugador(e.id);
    const a = await sesion(U_CAP), b = await sesion(U_DIR);
    const ra = await registrar(a, e, jug, 'GANADO', 'CORTO');
    const pb = registrar(b, e, jug, 'GANADO', 'CORTO');
    const bloqueado = await esperandoBloqueo(b.pid);
    await a.c.query('commit');
    const rb = await pb;
    await b.c.query('commit');
    const st = await estado(1);
    prueba('C1a', 'Mismo resultado simultáneo: B espera el bloqueo de A', 'true', String(bloqueado));
    prueba('C1b', 'A registra y cierra 3-0', 'FINALIZADO 3-0', marcador(ra));
    prueba('C1c', 'B recibe respuesta idempotente (ya_registrado)', 'true', rb.ok ? String(rb.r.ya_registrado) : rb.codigo);
    prueba('C1d', 'Un solo resultado nuevo; marcador 3-0', 'FINALIZADO 3-0|3', `${st.m}|${st.resultados}`);
    await a.c.end(); await b.c.end();
  }
  // C2: mismo enfrentamiento, resultados distintos.
  {
    const e = await enf(2, 3), jug = await jugador(e.id);
    const a = await sesion(U_CAP), b = await sesion(U_DIR);
    await registrar(a, e, jug, 'GANADO', 'CORTO');
    const pb = registrar(b, e, jug, 'PERDIDO', 'LO_CORTARON');
    const bloqueado = await esperandoBloqueo(b.pid);
    await a.c.query('commit');
    const rb = await pb;
    await b.c.query('rollback');
    const st = await estado(2);
    prueba('C2a', 'Resultados distintos simultáneos: B espera', 'true', String(bloqueado));
    prueba('C2b', 'B es rechazado sin duplicar', 'ENFRENTAMIENTO_YA_REGISTRADO', rb.ok ? 'ACEPTADO' : rb.codigo);
    prueba('C2c', 'Prevalece el resultado de A', 'FINALIZADO 3-0|3', `${st.m}|${st.resultados}`);
    await a.c.end(); await b.c.end();
  }
  // C3: carrera al objetivo: A registra el punto 3 y B el enfrentamiento siguiente.
  {
    const e3 = await enf(3, 3), e4 = await enf(3, 4);
    const j3 = await jugador(e3.id), j4 = await jugador(e4.id);
    const a = await sesion(U_CAP), b = await sesion(U_DIR);
    await registrar(a, e3, j3, 'GANADO', 'CORTO');
    const pb = registrar(b, e4, j4, 'GANADO', 'CORTO');
    const bloqueado = await esperandoBloqueo(b.pid);
    await a.c.query('commit');
    const rb = await pb;
    await b.c.query('rollback');
    const st = await estado(3);
    prueba('C3a', 'Carrera al objetivo: B espera a A', 'true', String(bloqueado));
    prueba('C3b', 'B no puede sumar tras el cierre', 'PARTIDO_NO_EN_CURSO', rb.ok ? 'ACEPTADO' : rb.codigo);
    prueba('C3c', 'Nunca supera el objetivo; 7 NO_DISPUTADO', 'FINALIZADO 3-0|7', `${st.m}|${st.no_disp}`);
    await a.c.end(); await b.c.end();
  }
  // C4: crear una lista nueva mientras otro usuario cierra el partido.
  {
    const e = await enf(4, 3), jug = await jugador(e.id);
    const a = await sesion(U_CAP), b = await sesion(U_DIR);
    await registrar(a, e, jug, 'GANADO', 'CORTO');
    const pb = b.c.query('select public.crear_lista($1) as r', [ctx.p4])
      .then(() => ({ ok: true }), err => ({ ok: false, codigo: err.hint || err.code }));
    const bloqueado = await esperandoBloqueo(b.pid);
    await a.c.query('commit');
    const rb = await pb;
    await b.c.query('rollback');
    const listas = (await admin.query('select count(*)::int n from public.listas_juego where partido_id = $1', [ctx.p4])).rows[0].n;
    prueba('C4a', 'Crear lista durante el cierre: B espera', 'true', String(bloqueado));
    prueba('C4b', 'B no crea lista tras el cierre', 'PARTIDO_NO_EN_CURSO|1', `${rb.ok ? 'ACEPTADO' : rb.codigo}|${listas}`);
    await a.c.end(); await b.c.end();
  }
  // C5: la transacción de A falla y se revierte; B registra normalmente.
  {
    const e = await enf(5, 3), jug = await jugador(e.id);
    const a = await sesion(U_CAP), b = await sesion(U_DIR);
    await registrar(a, e, jug, 'GANADO', 'CORTO');
    const pb = registrar(b, e, jug, 'PERDIDO', 'LO_CORTARON');
    const bloqueado = await esperandoBloqueo(b.pid);
    await a.c.query('rollback');
    const rb = await pb;
    await b.c.query('commit');
    const st = await estado(5);
    prueba('C5a', 'A se revierte: B espera y luego registra', 'true', String(bloqueado));
    prueba('C5b', 'B fue aceptado', 'EN_CURSO 2-1', marcador(rb));
    prueba('C5c', 'Queda solo el resultado de B (sin fantasmas)', 'EN_CURSO 2-1|3', `${st.m}|${st.resultados}`);
    await a.c.end(); await b.c.end();
  }
  const prob = (await admin.query(
    `select count(*) filter (where jsonb_array_length(privado.verificar_partido(v)) > 0)::int n
       from public.zz_ctx where k like 'p%'`)).rows[0].n;
  prueba('C6', 'verificar_partido sin problemas en los 5 partidos', '0', String(prob));

  for (const f of filas) console.log(`${f.ok ? 'OK' : 'XX'} ${f.n.padEnd(4)} ${f.nombre} | esp=${f.esperado} | obt=${f.obtenido}`);
  console.log(`\n${filas.filter(f => f.ok).length} / ${filas.length} correctas`);
} finally {
  await admin.end();
  await server.stop();
}
