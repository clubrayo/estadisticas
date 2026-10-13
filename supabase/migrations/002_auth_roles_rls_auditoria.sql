-- =====================================================================
-- MIGRACIÓN 002 — AUTH, ROLES, RLS, AUDITORÍA Y PROTECCIONES
-- Sistema de Gestión y Estadísticas de Juego — CLUB RAYO
-- Fase 2.
--
-- Contenido:
--   - Esquema "privado" (no expuesto por la API) con funciones de apoyo.
--   - Tablas: perfiles, roles, usuario_roles, auditoria.
--   - Perfil automático al crear un usuario en Supabase Auth.
--   - Privilegios mínimos: anon sin acceso; authenticated solo lo necesario.
--   - Políticas RLS por rol y club.
--   - Auditoría automática de todas las tablas de negocio.
--   - Protecciones: historial no borrable, auditoría inmutable, reglas
--     usadas inmutables, siempre al menos un ADMINISTRADOR activo.
--
-- Escritura directa vía API permitida en esta fase (datos maestros):
--   clubes rivales, campeonatos, configuración, reglas (nuevas versiones),
--   jugadores, partidos (crear y datos descriptivos), perfiles, roles.
-- Escritura operativa SOLO mediante funciones RPC de Fase 3:
--   asistencias, listas, convocatorias, enfrentamientos, participantes,
--   resultados, acciones, estado/marcador/ganador del partido y activación
--   de versiones de reglas.
--
-- Ejecutar UNA sola vez, después de la migración 001.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. CONTROL DE MIGRACIONES
-- ---------------------------------------------------------------------

do $$
begin
    if not exists (select 1 from public.migraciones_aplicadas where version = '001') then
        raise exception 'Falta aplicar la migración 001. No se realizaron cambios.';
    end if;
    if exists (select 1 from public.migraciones_aplicadas where version = '002') then
        raise exception 'La migración 002 ya fue aplicada anteriormente. No se realizaron cambios.';
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. ESQUEMA PRIVADO (no expuesto por la API de Supabase)
-- ---------------------------------------------------------------------

create schema privado;
revoke all on schema privado from public;
grant usage on schema privado to authenticated;

-- ---------------------------------------------------------------------
-- 2. TABLAS DE SEGURIDAD Y AUDITORÍA
-- ---------------------------------------------------------------------

-- Un perfil por usuario de Supabase Auth (se crea automáticamente).
create table public.perfiles (
    id               uuid        primary key references auth.users (id) on delete cascade,
    email            text,
    nombre_completo  text        not null,
    estado           text        not null default 'ACTIVO',
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now(),
    constraint ck_perfiles_nombre check (btrim(nombre_completo) <> ''),
    constraint ck_perfiles_estado check (estado in ('ACTIVO', 'INACTIVO'))
);

create index ix_perfiles_email on public.perfiles (lower(email));

create table public.roles (
    codigo       text     primary key,
    nombre       text     not null,
    descripcion  text,
    orden        smallint not null,
    constraint uq_roles_orden unique (orden)
);

-- ADMINISTRADOR es global (club nulo); los demás roles se asignan por club.
create table public.usuario_roles (
    id          uuid        primary key default gen_random_uuid(),
    usuario_id  uuid        not null references public.perfiles (id) on delete cascade,
    rol_codigo  text        not null references public.roles (codigo),
    club_id     uuid        references public.clubes (id),
    created_at  timestamptz not null default now(),
    created_by  uuid        default auth.uid(),
    constraint uq_usuario_roles unique nulls not distinct (usuario_id, rol_codigo, club_id),
    constraint ck_usuario_roles_ambito check ((rol_codigo = 'ADMINISTRADOR') = (club_id is null))
);

create index ix_usuario_roles_club on public.usuario_roles (club_id);
create index ix_usuario_roles_rol on public.usuario_roles (rol_codigo);

-- Registro inmutable de cambios. Lo escriben solo los triggers.
--   origen  : APP (usuario autenticado) o SISTEMA (SQL Editor / procesos).
--   accion  : operación SQL o acción de negocio indicada por la RPC
--             mediante set_config('app.accion', ...) (Fase 3).
--   motivo  : indicado por la RPC mediante set_config('app.motivo', ...).
--   txid    : agrupa todos los cambios de una misma transacción.
create table public.auditoria (
    id              bigint      generated always as identity primary key,
    ocurrido_at     timestamptz not null default now(),
    usuario_id      uuid,
    usuario_email   text,
    origen          text        not null,
    accion          text        not null,
    operacion       text        not null,
    tabla           text        not null,
    registro_id     text,
    partido_id      uuid,
    valor_anterior  jsonb,
    valor_nuevo     jsonb,
    motivo          text,
    txid            bigint      not null default txid_current(),
    constraint ck_auditoria_origen check (origen in ('APP', 'SISTEMA')),
    constraint ck_auditoria_operacion check (operacion in ('INSERT', 'UPDATE', 'DELETE'))
);

create index ix_auditoria_tabla_registro on public.auditoria (tabla, registro_id);
create index ix_auditoria_partido on public.auditoria (partido_id);
create index ix_auditoria_usuario on public.auditoria (usuario_id);
create index ix_auditoria_ocurrido on public.auditoria (ocurrido_at desc);
create index ix_auditoria_txid on public.auditoria (txid);

create trigger trg_perfiles_updated_at before update on public.perfiles
    for each row execute function public.fn_set_updated_at();

-- ---------------------------------------------------------------------
-- 3. FUNCIONES DE APOYO (usadas por RLS y auditoría)
-- SECURITY DEFINER: consultan perfiles/roles sin depender de RLS.
-- ---------------------------------------------------------------------

create function privado.usuario_activo()
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.perfiles p
         where p.id = auth.uid() and p.estado = 'ACTIVO');
$$;

create function privado.es_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1
          from public.usuario_roles ur
          join public.perfiles p on p.id = ur.usuario_id
         where ur.usuario_id = auth.uid()
           and ur.rol_codigo = 'ADMINISTRADOR'
           and p.estado = 'ACTIVO');
$$;

-- ¿El usuario tiene alguno de los roles indicados en ese club? (ADMIN siempre sí)
create function privado.tiene_rol(p_club uuid, p_roles text[])
returns boolean
language sql stable security definer set search_path = ''
as $$
    select privado.es_admin()
        or exists (
            select 1
              from public.usuario_roles ur
              join public.perfiles p on p.id = ur.usuario_id
             where ur.usuario_id = auth.uid()
               and p.estado = 'ACTIVO'
               and ur.club_id = p_club
               and ur.rol_codigo = any (p_roles));
$$;

-- ¿El usuario tiene alguno de los roles indicados en cualquier club?
create function privado.tiene_rol_en_algun_club(p_roles text[])
returns boolean
language sql stable security definer set search_path = ''
as $$
    select privado.es_admin()
        or exists (
            select 1
              from public.usuario_roles ur
              join public.perfiles p on p.id = ur.usuario_id
             where ur.usuario_id = auth.uid()
               and p.estado = 'ACTIVO'
               and ur.rol_codigo = any (p_roles));
$$;

-- Lectura de datos de un club: cualquier rol del club (incluye CONSULTA).
create function privado.puede_ver_club(p_club uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select privado.tiene_rol(p_club, array['DIRECTIVA', 'CAPITAN', 'CONSULTA']);
$$;

create function privado.partido_de_lista(p_lista uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
    select l.partido_id from public.listas_juego l where l.id = p_lista;
$$;

create function privado.partido_de_enfrentamiento(p_enfrentamiento uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
    select l.partido_id
      from public.enfrentamientos e
      join public.listas_juego l on l.id = e.lista_id
     where e.id = p_enfrentamiento;
$$;

-- Lectura de un partido: usuarios de cualquiera de los dos clubes.
create function privado.puede_ver_partido(p_partido uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.partidos p
         where p.id = p_partido
           and (privado.puede_ver_club(p.club_local_id)
                or privado.puede_ver_club(p.club_visitante_id)));
$$;

create function privado.club_de_jugador(p_jugador uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
    select j.club_id from public.jugadores j where j.id = p_jugador;
$$;

create function privado.club_de_convocatoria(p_convocatoria uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
    select c.club_id from public.convocatorias c where c.id = p_convocatoria;
$$;

create function privado.club_de_participante(p_participante uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
    select c.club_id
      from public.participantes_enfrentamiento pe
      join public.convocatorias c on c.id = pe.convocatoria_id
     where pe.id = p_participante;
$$;

create function privado.hay_admin_activo()
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1
          from public.usuario_roles ur
          join public.perfiles p on p.id = ur.usuario_id
         where ur.rol_codigo = 'ADMINISTRADOR' and p.estado = 'ACTIVO');
$$;

-- ---------------------------------------------------------------------
-- 4. PERFIL AUTOMÁTICO AL CREAR UN USUARIO EN SUPABASE AUTH
-- ---------------------------------------------------------------------

create function privado.fn_crear_perfil()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    insert into public.perfiles (id, email, nombre_completo)
    values (new.id,
            new.email,
            coalesce(nullif(btrim(new.raw_user_meta_data ->> 'nombre_completo'), ''),
                     new.email,
                     'Usuario sin nombre'))
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger trg_auth_users_crear_perfil
    after insert on auth.users
    for each row execute function privado.fn_crear_perfil();

-- ---------------------------------------------------------------------
-- 5. PROTECCIONES
-- ---------------------------------------------------------------------

-- 5.1 Historial no borrable.
create function privado.fn_bloquear_borrado()
returns trigger
language plpgsql set search_path = ''
as $$
begin
    raise exception 'No se permite eliminar registros de "%": el historial es permanente. Use desactivación o anulación lógica.',
        tg_table_name;
end;
$$;

create function privado.fn_bloquear_truncate()
returns trigger
language plpgsql set search_path = ''
as $$
begin
    raise exception 'No se permite vaciar (TRUNCATE) la tabla "%".', tg_table_name;
end;
$$;

-- Convocatoria: solo se borra si nunca fue oficial (borrador de lista).
create function privado.fn_convocatorias_proteger_borrado()
returns trigger
language plpgsql set search_path = ''
as $$
begin
    if old.fue_confirmada then
        raise exception 'La convocatoria ya fue oficial: no se elimina, se anula por reemplazo.';
    end if;
    return old;
end;
$$;

-- Participante: solo se borra mientras la lista está en BORRADOR.
create function privado.fn_participantes_proteger_borrado()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if coalesce((select l.estado from public.listas_juego l where l.id = old.lista_id), '') <> 'BORRADOR' then
        raise exception 'Solo se pueden quitar participantes de una lista en BORRADOR.';
    end if;
    return old;
end;
$$;

-- 5.2 Auditoría inmutable.
create function privado.fn_auditoria_inmutable()
returns trigger
language plpgsql set search_path = ''
as $$
begin
    raise exception 'La auditoría es inmutable: no se permite % sobre sus registros.', tg_op;
end;
$$;

-- 5.3 Reglas de puntuación: una versión usada por algún partido no cambia.
create function privado.fn_reglas_valores_proteger()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if (tg_op in ('UPDATE', 'DELETE')
        and exists (select 1 from public.partidos p where p.regla_version_id = old.regla_version_id))
    or (tg_op in ('INSERT', 'UPDATE')
        and exists (select 1 from public.partidos p where p.regla_version_id = new.regla_version_id)) then
        raise exception 'La versión de reglas ya fue utilizada por partidos: sus valores no pueden modificarse. Cree una nueva versión.';
    end if;
    return coalesce(new, old);
end;
$$;

create function privado.fn_reglas_versiones_proteger()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if exists (select 1 from public.partidos p where p.regla_version_id = old.id)
       and (to_jsonb(new) - 'es_vigente') <> (to_jsonb(old) - 'es_vigente') then
        raise exception 'La versión de reglas "%" ya fue utilizada por partidos: solo puede cambiar su vigencia.', old.codigo;
    end if;
    return new;
end;
$$;

-- 5.4 Perfiles: solo un ADMINISTRADOR cambia el estado (los procesos de sistema también).
create function privado.fn_perfiles_proteger()
returns trigger
language plpgsql set search_path = ''
as $$
begin
    if new.estado is distinct from old.estado
       and auth.uid() is not null
       and not privado.es_admin() then
        raise exception 'Solo un ADMINISTRADOR puede activar o desactivar usuarios.';
    end if;
    return new;
end;
$$;

-- 5.5 Roles: los roles de club solo se asignan a clubes gestionados.
create function privado.fn_usuario_roles_validar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if new.club_id is not null
       and not exists (select 1 from public.clubes c where c.id = new.club_id and c.es_gestionado) then
        raise exception 'Solo se pueden asignar roles en clubes gestionados por el sistema.';
    end if;
    return new;
end;
$$;

-- 5.6 Siempre debe quedar al menos un ADMINISTRADOR activo.
create function privado.fn_verificar_admin_usuario_roles()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if exists (select 1 from filas_old where rol_codigo = 'ADMINISTRADOR')
       and not privado.hay_admin_activo() then
        raise exception 'Operación rechazada: debe existir al menos un ADMINISTRADOR activo.';
    end if;
    return null;
end;
$$;

create function privado.fn_verificar_admin_perfiles()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if exists (select 1
                 from filas_old o
                 join filas_new n on n.id = o.id
                 join public.usuario_roles ur on ur.usuario_id = o.id and ur.rol_codigo = 'ADMINISTRADOR'
                where o.estado = 'ACTIVO' and n.estado <> 'ACTIVO')
       and not privado.hay_admin_activo() then
        raise exception 'Operación rechazada: debe existir al menos un ADMINISTRADOR activo.';
    end if;
    return null;
end;
$$;

-- Instalación de protecciones.
do $$
declare
    t text;
begin
    -- Tablas cuyo historial no se borra nunca.
    foreach t in array array[
        'clubes', 'campeonatos', 'jugadores', 'partidos', 'asistencias', 'listas_juego',
        'enfrentamientos', 'resultados_enfrentamiento', 'acciones_resultado',
        'reglas_puntuacion_versiones', 'reglas_puntuacion_valores',
        'modalidades', 'estados_enfrentamiento', 'conceptos_puntuacion', 'tipos_accion', 'roles']
    loop
        execute format(
            'create trigger trg_bloquear_borrado before delete on public.%I
                 for each row execute function privado.fn_bloquear_borrado()', t);
    end loop;

    -- Ninguna tabla de negocio puede vaciarse con TRUNCATE.
    foreach t in array array[
        'clubes', 'campeonatos', 'configuracion', 'jugadores', 'partidos', 'asistencias',
        'listas_juego', 'convocatorias', 'enfrentamientos', 'participantes_enfrentamiento',
        'resultados_enfrentamiento', 'acciones_resultado',
        'reglas_puntuacion_versiones', 'reglas_puntuacion_valores',
        'modalidades', 'estados_enfrentamiento', 'conceptos_puntuacion', 'tipos_accion',
        'perfiles', 'roles', 'usuario_roles', 'auditoria']
    loop
        execute format(
            'create trigger trg_bloquear_truncate before truncate on public.%I
                 for each statement execute function privado.fn_bloquear_truncate()', t);
    end loop;
end $$;

create trigger trg_convocatorias_proteger_borrado before delete on public.convocatorias
    for each row execute function privado.fn_convocatorias_proteger_borrado();

create trigger trg_participantes_proteger_borrado before delete on public.participantes_enfrentamiento
    for each row execute function privado.fn_participantes_proteger_borrado();

create trigger trg_auditoria_inmutable before update or delete on public.auditoria
    for each row execute function privado.fn_auditoria_inmutable();

create trigger trg_reglas_valores_proteger before insert or update or delete on public.reglas_puntuacion_valores
    for each row execute function privado.fn_reglas_valores_proteger();

create trigger trg_reglas_versiones_proteger before update on public.reglas_puntuacion_versiones
    for each row execute function privado.fn_reglas_versiones_proteger();

create trigger trg_perfiles_proteger before update on public.perfiles
    for each row execute function privado.fn_perfiles_proteger();

create trigger trg_usuario_roles_validar before insert or update on public.usuario_roles
    for each row execute function privado.fn_usuario_roles_validar();

create trigger trg_usuario_roles_admin_restante_del after delete on public.usuario_roles
    referencing old table as filas_old
    for each statement execute function privado.fn_verificar_admin_usuario_roles();

create trigger trg_usuario_roles_admin_restante_upd after update on public.usuario_roles
    referencing old table as filas_old
    for each statement execute function privado.fn_verificar_admin_usuario_roles();

create trigger trg_perfiles_admin_restante after update on public.perfiles
    referencing old table as filas_old new table as filas_new
    for each statement execute function privado.fn_verificar_admin_perfiles();

-- ---------------------------------------------------------------------
-- 6. DATOS INICIALES
-- ---------------------------------------------------------------------

insert into public.roles (codigo, nombre, descripcion, orden) values
    ('ADMINISTRADOR', 'Administrador', 'Acceso completo y global.', 1),
    ('DIRECTIVA',     'Directiva',     'Jugadores, partidos, asistencia, listas, resultados y estadísticas de su club.', 2),
    ('CAPITAN',       'Capitán',       'Asistencia, listas, resultados y estadísticas de su club.', 3),
    ('CONSULTA',      'Consulta',      'Solo lectura de estadísticas de su club.', 4);

-- Perfiles para usuarios que ya existan en Supabase Auth.
insert into public.perfiles (id, email, nombre_completo)
select u.id,
       u.email,
       coalesce(nullif(btrim(u.raw_user_meta_data ->> 'nombre_completo'), ''), u.email, 'Usuario sin nombre')
  from auth.users u
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 7. AUDITORÍA AUTOMÁTICA
-- ---------------------------------------------------------------------

create function privado.fn_auditar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    v_old      jsonb;
    v_new      jsonb;
    v_row      jsonb;
    v_uid      uuid := auth.uid();
    v_email    text;
    v_partido  uuid;
begin
    if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old); end if;
    if tg_op in ('INSERT', 'UPDATE') then v_new := to_jsonb(new); end if;

    -- Un UPDATE que no cambia nada (salvo updated_at) no se audita.
    if tg_op = 'UPDATE' and (v_old - 'updated_at') = (v_new - 'updated_at') then
        return null;
    end if;

    v_row := coalesce(v_new, v_old);

    v_partido := case tg_table_name
        when 'partidos'                     then (v_row ->> 'id')::uuid
        when 'asistencias'                  then (v_row ->> 'partido_id')::uuid
        when 'listas_juego'                 then (v_row ->> 'partido_id')::uuid
        when 'convocatorias'                then privado.partido_de_lista((v_row ->> 'lista_id')::uuid)
        when 'enfrentamientos'              then privado.partido_de_lista((v_row ->> 'lista_id')::uuid)
        when 'participantes_enfrentamiento' then privado.partido_de_lista((v_row ->> 'lista_id')::uuid)
        when 'resultados_enfrentamiento'    then privado.partido_de_enfrentamiento((v_row ->> 'enfrentamiento_id')::uuid)
        when 'acciones_resultado'           then privado.partido_de_enfrentamiento((v_row ->> 'enfrentamiento_id')::uuid)
        else null
    end;

    if v_uid is not null then
        select u.email into v_email from auth.users u where u.id = v_uid;
    end if;

    insert into public.auditoria
        (usuario_id, usuario_email, origen, accion, operacion, tabla, registro_id,
         partido_id, valor_anterior, valor_nuevo, motivo)
    values
        (v_uid,
         v_email,
         case when v_uid is null then 'SISTEMA' else 'APP' end,
         coalesce(nullif(current_setting('app.accion', true), ''), tg_op),
         tg_op,
         tg_table_name,
         coalesce(v_row ->> 'id',
                  v_row ->> 'codigo',
                  (v_row ->> 'regla_version_id') || ':' || (v_row ->> 'concepto_codigo')),
         v_partido,
         v_old,
         v_new,
         nullif(current_setting('app.motivo', true), ''));

    return null;
end;
$$;

do $$
declare
    t text;
begin
    foreach t in array array[
        'clubes', 'campeonatos', 'configuracion', 'jugadores', 'partidos', 'asistencias',
        'listas_juego', 'convocatorias', 'enfrentamientos', 'participantes_enfrentamiento',
        'resultados_enfrentamiento', 'acciones_resultado',
        'reglas_puntuacion_versiones', 'reglas_puntuacion_valores',
        'modalidades', 'estados_enfrentamiento', 'conceptos_puntuacion', 'tipos_accion',
        'perfiles', 'roles', 'usuario_roles']
    loop
        execute format(
            'create trigger trg_auditoria after insert or update or delete on public.%I
                 for each row execute function privado.fn_auditar()', t);
    end loop;
end $$;

-- ---------------------------------------------------------------------
-- 8. PRIVILEGIOS
-- Se parte de cero: anon no accede a nada; authenticated recibe solo lo
-- necesario. RLS filtra después las filas visibles/modificables.
-- ---------------------------------------------------------------------

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- Objetos futuros creados por migraciones: sin privilegios por defecto.
alter default privileges for role postgres in schema public revoke all on tables    from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on functions from public, anon, authenticated;

revoke all on all functions in schema privado from public, anon, authenticated;
grant execute on function
    privado.usuario_activo(),
    privado.es_admin(),
    privado.tiene_rol(uuid, text[]),
    privado.tiene_rol_en_algun_club(text[]),
    privado.puede_ver_club(uuid),
    privado.puede_ver_partido(uuid),
    privado.partido_de_lista(uuid),
    privado.partido_de_enfrentamiento(uuid),
    privado.club_de_jugador(uuid),
    privado.club_de_convocatoria(uuid),
    privado.club_de_participante(uuid)
to authenticated;

-- Lectura (RLS decide qué filas).
grant select on
    public.modalidades, public.estados_enfrentamiento, public.conceptos_puntuacion, public.tipos_accion,
    public.reglas_puntuacion_versiones, public.reglas_puntuacion_valores,
    public.clubes, public.campeonatos, public.configuracion, public.jugadores, public.partidos,
    public.asistencias, public.listas_juego, public.convocatorias, public.enfrentamientos,
    public.participantes_enfrentamiento, public.resultados_enfrentamiento, public.acciones_resultado,
    public.perfiles, public.roles, public.usuario_roles, public.auditoria
to authenticated;

-- Escritura directa de datos maestros (columnas explícitas).
grant insert (nombre, nombre_corto, logo_url)                      on public.clubes to authenticated;
grant update (nombre, nombre_corto, logo_url, estado)              on public.clubes to authenticated;

grant insert (nombre, temporada, fecha_inicio, fecha_termino, estado, puntaje_objetivo, observaciones) on public.campeonatos to authenticated;
grant update (nombre, temporada, fecha_inicio, fecha_termino, estado, puntaje_objetivo, observaciones) on public.campeonatos to authenticated;

grant insert (clave, valor, descripcion, campeonato_id, club_id)   on public.configuracion to authenticated;
grant update (valor, descripcion)                                  on public.configuracion to authenticated;

grant insert (codigo, nombre, descripcion)                         on public.reglas_puntuacion_versiones to authenticated;
grant insert (regla_version_id, concepto_codigo, valor)            on public.reglas_puntuacion_valores to authenticated;

grant insert (club_id, primer_nombre, apellidos, apodo, estado, fecha_incorporacion, categoria, observaciones) on public.jugadores to authenticated;
grant update (club_id, primer_nombre, apellidos, apodo, estado, fecha_incorporacion, categoria, observaciones) on public.jugadores to authenticated;

-- Partidos: crear y editar datos descriptivos. Estado, marcador, ganador y
-- regla solo cambian mediante RPC (Fase 3).
grant insert (campeonato_id, fecha, club_local_id, club_visitante_id, lugar, observaciones) on public.partidos to authenticated;
grant update (fecha, lugar, observaciones)                         on public.partidos to authenticated;

grant update (nombre_completo, estado)                             on public.perfiles to authenticated;

grant insert (usuario_id, rol_codigo, club_id)                     on public.usuario_roles to authenticated;
grant delete                                                       on public.usuario_roles to authenticated;

-- ---------------------------------------------------------------------
-- 9. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------

alter table public.perfiles      enable row level security;
alter table public.roles         enable row level security;
alter table public.usuario_roles enable row level security;
alter table public.auditoria     enable row level security;

-- 9.1 Catálogos y datos generales: lectura para cualquier usuario activo.
do $$
declare
    t text;
begin
    foreach t in array array[
        'modalidades', 'estados_enfrentamiento', 'conceptos_puntuacion', 'tipos_accion',
        'reglas_puntuacion_versiones', 'reglas_puntuacion_valores', 'roles',
        'clubes', 'campeonatos', 'configuracion']
    loop
        execute format(
            'create policy pol_lectura_usuarios_activos on public.%I
                 for select to authenticated
                 using ((select privado.usuario_activo()))', t);
    end loop;
end $$;

-- 9.2 Reglas: nuevas versiones solo ADMINISTRADOR.
create policy pol_admin_inserta on public.reglas_puntuacion_versiones
    for insert to authenticated with check ((select privado.es_admin()));
create policy pol_admin_inserta on public.reglas_puntuacion_valores
    for insert to authenticated with check ((select privado.es_admin()));

-- 9.3 Clubes: ADMINISTRADOR todo; DIRECTIVA solo clubes rivales (no gestionados).
create policy pol_inserta_club on public.clubes
    for insert to authenticated
    with check ((select privado.es_admin())
                or ((select privado.tiene_rol_en_algun_club(array['DIRECTIVA'])) and not es_gestionado));
create policy pol_actualiza_club on public.clubes
    for update to authenticated
    using      ((select privado.es_admin())
                or ((select privado.tiene_rol_en_algun_club(array['DIRECTIVA'])) and not es_gestionado))
    with check ((select privado.es_admin())
                or ((select privado.tiene_rol_en_algun_club(array['DIRECTIVA'])) and not es_gestionado));

-- 9.4 Campeonatos y configuración: solo ADMINISTRADOR escribe.
create policy pol_admin_inserta on public.campeonatos
    for insert to authenticated with check ((select privado.es_admin()));
create policy pol_admin_actualiza on public.campeonatos
    for update to authenticated using ((select privado.es_admin())) with check ((select privado.es_admin()));
create policy pol_admin_inserta on public.configuracion
    for insert to authenticated with check ((select privado.es_admin()));
create policy pol_admin_actualiza on public.configuracion
    for update to authenticated using ((select privado.es_admin())) with check ((select privado.es_admin()));

-- 9.5 Jugadores: lectura por cualquier rol del club; escritura DIRECTIVA del club.
create policy pol_lectura_club on public.jugadores
    for select to authenticated using (privado.puede_ver_club(club_id));
create policy pol_directiva_inserta on public.jugadores
    for insert to authenticated with check (privado.tiene_rol(club_id, array['DIRECTIVA']));
create policy pol_directiva_actualiza on public.jugadores
    for update to authenticated
    using      (privado.tiene_rol(club_id, array['DIRECTIVA']))
    with check (privado.tiene_rol(club_id, array['DIRECTIVA']));

-- 9.6 Partidos: lectura por usuarios de ambos clubes; escritura DIRECTIVA de uno de ellos.
create policy pol_lectura_clubes_partido on public.partidos
    for select to authenticated
    using (privado.puede_ver_club(club_local_id) or privado.puede_ver_club(club_visitante_id));
create policy pol_directiva_inserta on public.partidos
    for insert to authenticated
    with check (privado.tiene_rol(club_local_id, array['DIRECTIVA'])
                or privado.tiene_rol(club_visitante_id, array['DIRECTIVA']));
create policy pol_directiva_actualiza on public.partidos
    for update to authenticated
    using      (privado.tiene_rol(club_local_id, array['DIRECTIVA'])
                or privado.tiene_rol(club_visitante_id, array['DIRECTIVA']))
    with check (privado.tiene_rol(club_local_id, array['DIRECTIVA'])
                or privado.tiene_rol(club_visitante_id, array['DIRECTIVA']));

-- 9.7 Datos operativos: solo lectura vía API (la escritura será por RPC en Fase 3).
create policy pol_lectura_club on public.asistencias
    for select to authenticated using (privado.puede_ver_club(privado.club_de_jugador(jugador_id)));
create policy pol_lectura_partido on public.listas_juego
    for select to authenticated using (privado.puede_ver_partido(partido_id));
create policy pol_lectura_club on public.convocatorias
    for select to authenticated using (privado.puede_ver_club(club_id));
create policy pol_lectura_partido on public.enfrentamientos
    for select to authenticated using (privado.puede_ver_partido(privado.partido_de_lista(lista_id)));
create policy pol_lectura_club on public.participantes_enfrentamiento
    for select to authenticated using (privado.puede_ver_club(privado.club_de_convocatoria(convocatoria_id)));
create policy pol_lectura_partido on public.resultados_enfrentamiento
    for select to authenticated using (privado.puede_ver_partido(privado.partido_de_enfrentamiento(enfrentamiento_id)));
create policy pol_lectura_club on public.acciones_resultado
    for select to authenticated using (privado.puede_ver_club(privado.club_de_participante(participante_id)));

-- 9.8 Perfiles: cada usuario ve y edita el suyo; ADMINISTRADOR todos.
create policy pol_propio_o_admin on public.perfiles
    for select to authenticated
    using (id = (select auth.uid()) or (select privado.es_admin()));
create policy pol_actualiza_propio_o_admin on public.perfiles
    for update to authenticated
    using      (id = (select auth.uid()) or (select privado.es_admin()))
    with check (id = (select auth.uid()) or (select privado.es_admin()));

-- 9.9 Roles de usuario: cada uno ve los suyos; solo ADMINISTRADOR asigna o quita.
create policy pol_propio_o_admin on public.usuario_roles
    for select to authenticated
    using (usuario_id = (select auth.uid()) or (select privado.es_admin()));
create policy pol_admin_inserta on public.usuario_roles
    for insert to authenticated with check ((select privado.es_admin()));
create policy pol_admin_elimina on public.usuario_roles
    for delete to authenticated using ((select privado.es_admin()));

-- 9.10 Auditoría: solo lectura para ADMINISTRADOR.
create policy pol_admin_lee on public.auditoria
    for select to authenticated using ((select privado.es_admin()));

-- ---------------------------------------------------------------------
-- 10. REGISTRO DE LA MIGRACIÓN
-- ---------------------------------------------------------------------

insert into public.migraciones_aplicadas (version, descripcion)
values ('002', 'Auth, perfiles, roles, privilegios, RLS, auditoría y protecciones de historial');

commit;
