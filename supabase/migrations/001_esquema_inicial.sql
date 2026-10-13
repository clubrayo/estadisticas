-- =====================================================================
-- MIGRACIÓN 001 — ESQUEMA INICIAL
-- Sistema de Gestión y Estadísticas de Juego — CLUB RAYO
-- Fase 1: tablas, relaciones, restricciones, índices y catálogos V1.
--
-- Fuera de alcance (fases posteriores):
--   Fase 2: perfiles, roles, políticas RLS, auditoría y triggers de protección
--           (no borrar historial, reglas usadas inmutables).
--   Fase 3: funciones RPC y validaciones entre tablas. Esta migración NO
--           garantiza todavía:
--             - solo jugadores PRESENTES pueden ser convocados;
--             - composición exacta 1/2/3 jugadores por modalidad;
--             - 5 individuales, 3 duplas y 2 tríos por lista (17 posiciones);
--             - no repetición de jugador en la lista según configuración;
--             - polaridad de la acción según victoria/derrota de RAYO;
--             - todo DISPUTADO tiene exactamente una acción;
--             - ganador del resultado es uno de los clubes del partido;
--             - orden estricto de juego;
--             - cierre automático al llegar al objetivo;
--             - invalidación P-1 (corrección que adelanta el cierre);
--             - uno de los clubes del partido es gestionado;
--             - convocado pertenece a uno de los clubes del partido.
--
-- Ejecutar UNA sola vez. Si ya fue aplicada, el script se detiene sin
-- modificar nada.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. CONTROL DE MIGRACIONES
-- ---------------------------------------------------------------------

create table if not exists public.migraciones_aplicadas (
    version      text        primary key,
    descripcion  text        not null,
    aplicada_at  timestamptz not null default now()
);

do $$
begin
    if exists (select 1 from public.migraciones_aplicadas where version = '001') then
        raise exception 'La migración 001 ya fue aplicada anteriormente. No se realizaron cambios.';
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. FUNCIONES GENÉRICAS
-- ---------------------------------------------------------------------

-- Mantiene updated_at en cada UPDATE.
create or replace function public.fn_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. CATÁLOGOS
-- ---------------------------------------------------------------------

-- Composición de una lista: cuántos enfrentamientos y jugadores por modalidad.
create table public.modalidades (
    codigo                        text     primary key,
    nombre                        text     not null,
    jugadores_por_enfrentamiento  smallint not null,
    enfrentamientos_por_lista     smallint not null,
    orden                         smallint not null,
    activo                        boolean  not null default true,
    constraint uq_modalidades_orden unique (orden),
    constraint ck_modalidades_jugadores check (jugadores_por_enfrentamiento between 1 and 10),
    constraint ck_modalidades_enfrentamientos check (enfrentamientos_por_lista between 1 and 20)
);

-- Estados posibles de un enfrentamiento. Extensible (W.O., anulado, etc.).
create table public.estados_enfrentamiento (
    codigo            text    primary key,
    nombre            text    not null,
    cuenta_como_ej    boolean not null,  -- suma Enfrentamiento Jugado (EJ)
    admite_resultado  boolean not null,  -- debe tener un resultado vigente
    orden             smallint not null,
    constraint uq_estados_enfrentamiento_orden unique (orden)
);

-- Conceptos que reciben puntaje estadístico (convocatoria, resultado, acciones).
create table public.conceptos_puntuacion (
    codigo     text primary key,
    nombre     text not null,
    categoria  text not null,
    orden      smallint not null,
    constraint uq_conceptos_puntuacion_orden unique (orden),
    constraint ck_conceptos_puntuacion_categoria
        check (categoria in ('CONVOCATORIA', 'RESULTADO', 'ACCION'))
);

-- Causas/acciones determinantes de un enfrentamiento. Extensible.
-- Cada tipo de acción es también un concepto de puntuación.
create table public.tipos_accion (
    codigo       text     primary key references public.conceptos_puntuacion (codigo),
    nombre       text     not null,
    polaridad    text     not null,
    descripcion  text,
    orden        smallint not null,
    activo       boolean  not null default true,
    constraint uq_tipos_accion_orden unique (orden),
    constraint ck_tipos_accion_polaridad check (polaridad in ('POSITIVA', 'NEGATIVA'))
);

-- Versiones del reglamento de puntuación. Solo una vigente a la vez.
create table public.reglas_puntuacion_versiones (
    id             uuid        primary key default gen_random_uuid(),
    codigo         text        not null,
    nombre         text        not null,
    descripcion    text,
    es_vigente     boolean     not null default false,
    vigente_desde  timestamptz not null default now(),
    created_at     timestamptz not null default now(),
    constraint uq_reglas_puntuacion_versiones_codigo unique (codigo)
);

create unique index uq_reglas_puntuacion_una_vigente
    on public.reglas_puntuacion_versiones ((true))
    where es_vigente;

-- Valor de cada concepto dentro de una versión.
create table public.reglas_puntuacion_valores (
    regla_version_id  uuid         not null references public.reglas_puntuacion_versiones (id),
    concepto_codigo   text         not null references public.conceptos_puntuacion (codigo),
    valor             numeric(5,2) not null,
    primary key (regla_version_id, concepto_codigo)
);

create index ix_reglas_puntuacion_valores_concepto
    on public.reglas_puntuacion_valores (concepto_codigo);

-- ---------------------------------------------------------------------
-- 3. CLUBES, CAMPEONATOS Y CONFIGURACIÓN
-- ---------------------------------------------------------------------

create table public.clubes (
    id             uuid        primary key default gen_random_uuid(),
    nombre         text        not null,
    nombre_corto   text        not null,
    logo_url       text,
    es_gestionado  boolean     not null default false,  -- club con nómina y usuarios propios
    estado         text        not null default 'ACTIVO',
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),
    constraint ck_clubes_nombre check (btrim(nombre) <> ''),
    constraint ck_clubes_nombre_corto check (btrim(nombre_corto) <> ''),
    constraint ck_clubes_estado check (estado in ('ACTIVO', 'INACTIVO'))
);

create unique index uq_clubes_nombre on public.clubes (lower(nombre));
create unique index uq_clubes_nombre_corto on public.clubes (lower(nombre_corto));

create table public.campeonatos (
    id                uuid        primary key default gen_random_uuid(),
    nombre            text        not null,
    temporada         text        not null,
    fecha_inicio      date        not null,
    fecha_termino     date,
    estado            text        not null default 'PROGRAMADO',
    puntaje_objetivo  smallint    not null,
    observaciones     text,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    constraint ck_campeonatos_nombre check (btrim(nombre) <> ''),
    constraint ck_campeonatos_estado
        check (estado in ('PROGRAMADO', 'EN_CURSO', 'FINALIZADO', 'CANCELADO')),
    constraint ck_campeonatos_puntaje_objetivo check (puntaje_objetivo > 0),
    constraint ck_campeonatos_fechas check (fecha_termino is null or fecha_termino >= fecha_inicio)
);

create unique index uq_campeonatos_nombre_temporada
    on public.campeonatos (lower(nombre), lower(temporada));

-- Parámetros configurables. Ámbito: global (ambos nulos), campeonato o club.
create table public.configuracion (
    id             uuid        primary key default gen_random_uuid(),
    clave          text        not null,
    valor          jsonb       not null,
    descripcion    text,
    campeonato_id  uuid        references public.campeonatos (id),
    club_id        uuid        references public.clubes (id),
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),
    constraint ck_configuracion_ambito check (campeonato_id is null or club_id is null),
    constraint uq_configuracion_clave_ambito unique nulls not distinct (clave, campeonato_id, club_id)
);

create index ix_configuracion_campeonato on public.configuracion (campeonato_id);
create index ix_configuracion_club on public.configuracion (club_id);

-- ---------------------------------------------------------------------
-- 4. JUGADORES
-- ---------------------------------------------------------------------

create table public.jugadores (
    id                   uuid        primary key default gen_random_uuid(),
    club_id              uuid        not null references public.clubes (id),
    primer_nombre        text        not null,
    apellidos            text        not null,
    nombre_completo      text        generated always as (btrim(primer_nombre) || ' ' || btrim(apellidos)) stored,
    apodo                text,
    estado               text        not null default 'ACTIVO',
    fecha_incorporacion  date,
    categoria            text,
    observaciones        text,
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now(),
    constraint ck_jugadores_primer_nombre check (btrim(primer_nombre) <> ''),
    constraint ck_jugadores_apellidos check (btrim(apellidos) <> ''),
    constraint ck_jugadores_estado check (estado in ('ACTIVO', 'INACTIVO'))
);

create index ix_jugadores_club_estado on public.jugadores (club_id, estado);
create index ix_jugadores_nombre_completo on public.jugadores (lower(nombre_completo));

-- ---------------------------------------------------------------------
-- 5. PARTIDOS
-- ---------------------------------------------------------------------

create table public.partidos (
    id                 uuid        primary key default gen_random_uuid(),
    campeonato_id      uuid        not null references public.campeonatos (id),
    fecha              date        not null,
    club_local_id      uuid        not null references public.clubes (id),
    club_visitante_id  uuid        not null references public.clubes (id),
    lugar              text,
    estado             text        not null default 'PROGRAMADO',
    puntaje_objetivo   smallint    not null,  -- copia del campeonato (trigger)
    regla_version_id   uuid        references public.reglas_puntuacion_versiones (id),  -- se fija al pasar a EN_CURSO
    puntaje_local      smallint    not null default 0,
    puntaje_visitante  smallint    not null default 0,
    ganador_club_id    uuid        references public.clubes (id),
    version            integer     not null default 1,  -- control de concurrencia optimista
    iniciado_at        timestamptz,
    finalizado_at      timestamptz,
    observaciones      text,
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now(),
    constraint ck_partidos_clubes_distintos check (club_local_id <> club_visitante_id),
    constraint ck_partidos_estado check (estado in
        ('PROGRAMADO', 'EN_CURSO', 'SUSPENDIDO', 'FINALIZADO', 'EN_REVISION', 'CANCELADO')),
    constraint ck_partidos_puntaje_objetivo check (puntaje_objetivo > 0),
    constraint ck_partidos_puntajes_rango check (
        puntaje_local between 0 and puntaje_objetivo
        and puntaje_visitante between 0 and puntaje_objetivo),
    constraint ck_partidos_ganador_participa check (
        ganador_club_id is null or ganador_club_id in (club_local_id, club_visitante_id)),
    -- FINALIZADO / EN_REVISION: hay ganador, tiene exactamente el objetivo y el rival menos.
    constraint ck_partidos_cierre check (
        estado not in ('FINALIZADO', 'EN_REVISION')
        or (ganador_club_id is not null
            and ((ganador_club_id = club_local_id
                  and puntaje_local = puntaje_objetivo and puntaje_visitante < puntaje_objetivo)
              or (ganador_club_id = club_visitante_id
                  and puntaje_visitante = puntaje_objetivo and puntaje_local < puntaje_objetivo)))),
    -- Cualquier otro estado: sin ganador.
    constraint ck_partidos_sin_ganador check (
        estado in ('FINALIZADO', 'EN_REVISION') or ganador_club_id is null),
    -- PROGRAMADO / EN_CURSO / SUSPENDIDO: nadie ha alcanzado el objetivo.
    constraint ck_partidos_en_juego_bajo_objetivo check (
        estado not in ('PROGRAMADO', 'EN_CURSO', 'SUSPENDIDO')
        or (puntaje_local < puntaje_objetivo and puntaje_visitante < puntaje_objetivo)),
    -- Una vez iniciado, la versión de reglas queda fijada (C-2).
    constraint ck_partidos_regla_fijada check (
        estado in ('PROGRAMADO', 'CANCELADO') or regla_version_id is not null),
    constraint ck_partidos_iniciado check (
        estado in ('PROGRAMADO', 'CANCELADO') or iniciado_at is not null),
    constraint ck_partidos_finalizado_at check (
        estado not in ('FINALIZADO', 'EN_REVISION') or finalizado_at is not null),
    constraint ck_partidos_version check (version > 0)
);

create index ix_partidos_campeonato_fecha on public.partidos (campeonato_id, fecha);
create index ix_partidos_club_local on public.partidos (club_local_id);
create index ix_partidos_club_visitante on public.partidos (club_visitante_id);
create index ix_partidos_ganador on public.partidos (ganador_club_id);
create index ix_partidos_estado on public.partidos (estado);
create index ix_partidos_regla_version on public.partidos (regla_version_id);

-- El puntaje objetivo se copia del campeonato al crear el partido y no se modifica.
create or replace function public.fn_partidos_fijar_puntaje_objetivo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if tg_op = 'INSERT' then
        select c.puntaje_objetivo
          into new.puntaje_objetivo
          from public.campeonatos c
         where c.id = new.campeonato_id;
    elsif new.puntaje_objetivo is distinct from old.puntaje_objetivo then
        raise exception 'El puntaje objetivo del partido es una copia del campeonato y no puede modificarse.'
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

create trigger trg_partidos_fijar_puntaje_objetivo
    before insert or update of puntaje_objetivo on public.partidos
    for each row execute function public.fn_partidos_fijar_puntaje_objetivo();

-- ---------------------------------------------------------------------
-- 6. ASISTENCIA
-- ---------------------------------------------------------------------

create table public.asistencias (
    id             uuid        primary key default gen_random_uuid(),
    partido_id     uuid        not null references public.partidos (id),
    jugador_id     uuid        not null references public.jugadores (id),
    estado         text        not null,
    observaciones  text,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),
    constraint uq_asistencias_partido_jugador unique (partido_id, jugador_id),
    constraint ck_asistencias_estado check (estado in ('PRESENTE', 'AUSENTE', 'JUSTIFICADO'))
);

create index ix_asistencias_jugador on public.asistencias (jugador_id);

-- ---------------------------------------------------------------------
-- 7. LISTAS DE JUEGO Y CONVOCATORIAS
-- ---------------------------------------------------------------------

create table public.listas_juego (
    id             uuid        primary key default gen_random_uuid(),
    partido_id     uuid        not null references public.partidos (id),
    numero         smallint    not null,
    estado         text        not null default 'BORRADOR',
    confirmada_at  timestamptz,
    confirmada_por uuid        references auth.users (id),
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),
    constraint uq_listas_juego_partido_numero unique (partido_id, numero),
    constraint ck_listas_juego_numero check (numero > 0),
    constraint ck_listas_juego_estado
        check (estado in ('BORRADOR', 'CONFIRMADA', 'EN_JUEGO', 'FINALIZADA')),
    constraint ck_listas_juego_confirmacion
        check ((estado = 'BORRADOR') = (confirmada_at is null))
);

create index ix_listas_juego_estado on public.listas_juego (partido_id, estado);

-- UNA ÚNICA convocatoria histórica por jugador y lista (nunca por posición).
-- Si un jugador reemplazado vuelve a la misma lista, se reactiva el mismo
-- registro (ANULADA_REEMPLAZO -> PROPUESTA); nunca se crea uno nuevo.
--   PROPUESTA          : lista en edición, sin puntaje.
--   VIGENTE            : lista confirmada, puntaje de convocatoria consolidado.
--   ANULADA_REEMPLAZO  : jugador retirado antes de iniciar la lista. No suma.
create table public.convocatorias (
    id                 uuid         primary key default gen_random_uuid(),
    lista_id           uuid         not null references public.listas_juego (id),
    jugador_id         uuid         not null references public.jugadores (id),
    club_id            uuid         not null references public.clubes (id),  -- snapshot del club del jugador (trigger)
    estado             text         not null default 'PROPUESTA',
    puntos             numeric(5,2),                                           -- copia del valor CONVOCATORIA
    fue_confirmada     boolean      not null default false,                    -- si alguna vez fue oficial, no se borra
    anulada_at         timestamptz,
    anulada_por        uuid         references auth.users (id),
    motivo_anulacion   text,
    created_at         timestamptz  not null default now(),
    updated_at         timestamptz  not null default now(),
    constraint uq_convocatorias_id_lista unique (id, lista_id),
    constraint uq_convocatorias_lista_jugador unique (lista_id, jugador_id),
    constraint ck_convocatorias_estado
        check (estado in ('PROPUESTA', 'VIGENTE', 'ANULADA_REEMPLAZO')),
    constraint ck_convocatorias_vigente_puntos
        check (estado <> 'VIGENTE' or (puntos is not null and fue_confirmada)),
    constraint ck_convocatorias_propuesta_sin_puntos
        check (estado <> 'PROPUESTA' or puntos is null),
    constraint ck_convocatorias_anulacion
        check ((estado = 'ANULADA_REEMPLAZO') = (anulada_at is not null)),
    constraint ck_convocatorias_motivo_anulacion
        check (estado <> 'ANULADA_REEMPLAZO' or nullif(btrim(motivo_anulacion), '') is not null)
);

create index ix_convocatorias_jugador on public.convocatorias (jugador_id);
create index ix_convocatorias_club on public.convocatorias (club_id);

-- club_id es un snapshot del club del jugador al crear la convocatoria:
--   INSERT: si viene nulo se completa; si no coincide con el club del jugador, error.
--   UPDATE: lista_id, jugador_id y club_id son inmutables.
create or replace function public.fn_convocatorias_coherencia_jugador()
returns trigger
language plpgsql
set search_path = public
as $$
declare
    v_club_jugador uuid;
begin
    if tg_op = 'INSERT' then
        select j.club_id into v_club_jugador
          from public.jugadores j
         where j.id = new.jugador_id;

        if v_club_jugador is null then
            return new;  -- jugador inexistente: lo rechaza la FK
        end if;

        if new.club_id is null then
            new.club_id := v_club_jugador;
        elsif new.club_id <> v_club_jugador then
            raise exception 'La convocatoria indica un club distinto al club del jugador.'
                using errcode = 'check_violation';
        end if;
    elsif new.lista_id   is distinct from old.lista_id
       or new.jugador_id is distinct from old.jugador_id
       or new.club_id    is distinct from old.club_id then
        raise exception 'Lista, jugador y club de una convocatoria no pueden modificarse.'
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

create trigger trg_convocatorias_coherencia_jugador
    before insert or update of lista_id, jugador_id, club_id on public.convocatorias
    for each row execute function public.fn_convocatorias_coherencia_jugador();

-- ---------------------------------------------------------------------
-- 8. ENFRENTAMIENTOS Y PARTICIPANTES
-- ---------------------------------------------------------------------

create table public.enfrentamientos (
    id                uuid        primary key default gen_random_uuid(),
    lista_id          uuid        not null references public.listas_juego (id),
    modalidad_codigo  text        not null references public.modalidades (codigo),
    numero            smallint    not null,  -- Individual 1..5, Dupla 1..3, Trío 1..2
    orden_juego       smallint    not null,  -- 1..10 según planilla
    estado_codigo     text        not null default 'PENDIENTE' references public.estados_enfrentamiento (codigo),
    version           integer     not null default 1,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    constraint uq_enfrentamientos_id_lista unique (id, lista_id),
    constraint uq_enfrentamientos_lista_orden unique (lista_id, orden_juego),
    constraint uq_enfrentamientos_lista_modalidad_numero unique (lista_id, modalidad_codigo, numero),
    constraint ck_enfrentamientos_numero check (numero > 0),
    constraint ck_enfrentamientos_orden check (orden_juego > 0),
    constraint ck_enfrentamientos_version check (version > 0)
);

create index ix_enfrentamientos_estado on public.enfrentamientos (estado_codigo);
create index ix_enfrentamientos_modalidad on public.enfrentamientos (modalidad_codigo);

-- Jugador que ocupa una posición (A=1, B=2, C=3) en un enfrentamiento.
-- Las FK compuestas garantizan que la convocatoria pertenece a la misma lista.
create table public.participantes_enfrentamiento (
    id                uuid        primary key default gen_random_uuid(),
    enfrentamiento_id uuid        not null,
    lista_id          uuid        not null,
    convocatoria_id   uuid        not null,
    posicion          smallint    not null,
    created_at        timestamptz not null default now(),
    constraint fk_participantes_enfrentamiento
        foreign key (enfrentamiento_id, lista_id)
        references public.enfrentamientos (id, lista_id),
    constraint fk_participantes_convocatoria
        foreign key (convocatoria_id, lista_id)
        references public.convocatorias (id, lista_id),
    constraint uq_participantes_id_enfrentamiento unique (id, enfrentamiento_id),
    constraint uq_participantes_enfrentamiento_posicion unique (enfrentamiento_id, posicion),
    constraint uq_participantes_enfrentamiento_convocatoria unique (enfrentamiento_id, convocatoria_id),
    constraint ck_participantes_posicion check (posicion between 1 and 10)
);

create index ix_participantes_lista on public.participantes_enfrentamiento (lista_id);
create index ix_participantes_convocatoria on public.participantes_enfrentamiento (convocatoria_id);

-- ---------------------------------------------------------------------
-- 9. RESULTADOS (VERSIONADOS) Y ACCIONES
-- ---------------------------------------------------------------------

-- Cada corrección crea un nuevo resultado y deja el anterior como no vigente.
--   causa_anulacion = CORREGIDO                     : reemplazado por una corrección.
--   causa_anulacion = INVALIDADO_CIERRE_ANTICIPADO  : el enfrentamiento quedó después
--                     de un nuevo punto de cierre (P-1) y pasó a NO_DISPUTADO.
create table public.resultados_enfrentamiento (
    id                uuid         primary key default gen_random_uuid(),
    enfrentamiento_id uuid         not null references public.enfrentamientos (id),
    ganador_club_id   uuid         not null references public.clubes (id),
    vigente           boolean      not null default true,
    puntos_victoria   numeric(5,2) not null,  -- copia del valor VICTORIA de la regla del partido
    puntos_derrota    numeric(5,2) not null,  -- copia del valor DERROTA de la regla del partido
    reemplaza_a_id    uuid,
    registrado_por    uuid         references auth.users (id),
    registrado_at     timestamptz  not null default now(),
    anulado_at        timestamptz,
    anulado_por       uuid         references auth.users (id),
    causa_anulacion   text,
    motivo_anulacion  text,
    constraint uq_resultados_id_enfrentamiento unique (id, enfrentamiento_id),
    constraint uq_resultados_reemplaza_a unique (reemplaza_a_id),
    constraint fk_resultados_reemplaza_a
        foreign key (reemplaza_a_id, enfrentamiento_id)
        references public.resultados_enfrentamiento (id, enfrentamiento_id),
    constraint ck_resultados_no_autorreemplazo check (reemplaza_a_id is null or reemplaza_a_id <> id),
    constraint ck_resultados_causa_anulacion
        check (causa_anulacion is null
               or causa_anulacion in ('CORREGIDO', 'INVALIDADO_CIERRE_ANTICIPADO')),
    constraint ck_resultados_vigencia check (
        (vigente and anulado_at is null and causa_anulacion is null and motivo_anulacion is null)
        or (not vigente and anulado_at is not null and causa_anulacion is not null
            and nullif(btrim(motivo_anulacion), '') is not null))
);

-- Garantía central: como máximo UN resultado vigente por enfrentamiento.
create unique index uq_resultados_un_vigente
    on public.resultados_enfrentamiento (enfrentamiento_id)
    where vigente;

create index ix_resultados_enfrentamiento on public.resultados_enfrentamiento (enfrentamiento_id);
create index ix_resultados_ganador on public.resultados_enfrentamiento (ganador_club_id);

-- Acción determinante. V1: exactamente una por resultado.
-- Las FK compuestas garantizan que el participante pertenece al mismo enfrentamiento.
create table public.acciones_resultado (
    id                  uuid         primary key default gen_random_uuid(),
    resultado_id        uuid         not null,
    enfrentamiento_id   uuid         not null,
    participante_id     uuid         not null,
    tipo_accion_codigo  text         not null references public.tipos_accion (codigo),
    puntos              numeric(5,2) not null,  -- copia del valor de la acción en la regla del partido
    created_at          timestamptz  not null default now(),
    constraint fk_acciones_resultado
        foreign key (resultado_id, enfrentamiento_id)
        references public.resultados_enfrentamiento (id, enfrentamiento_id),
    constraint fk_acciones_participante
        foreign key (participante_id, enfrentamiento_id)
        references public.participantes_enfrentamiento (id, enfrentamiento_id),
    constraint uq_acciones_resultado_v1 unique (resultado_id)
);

create index ix_acciones_participante on public.acciones_resultado (participante_id);
create index ix_acciones_tipo on public.acciones_resultado (tipo_accion_codigo);
create index ix_acciones_enfrentamiento on public.acciones_resultado (enfrentamiento_id);

-- ---------------------------------------------------------------------
-- 10. TRIGGERS updated_at
-- ---------------------------------------------------------------------

create trigger trg_clubes_updated_at          before update on public.clubes          for each row execute function public.fn_set_updated_at();
create trigger trg_campeonatos_updated_at     before update on public.campeonatos     for each row execute function public.fn_set_updated_at();
create trigger trg_configuracion_updated_at   before update on public.configuracion   for each row execute function public.fn_set_updated_at();
create trigger trg_jugadores_updated_at       before update on public.jugadores       for each row execute function public.fn_set_updated_at();
create trigger trg_partidos_updated_at        before update on public.partidos        for each row execute function public.fn_set_updated_at();
create trigger trg_asistencias_updated_at     before update on public.asistencias     for each row execute function public.fn_set_updated_at();
create trigger trg_listas_juego_updated_at    before update on public.listas_juego    for each row execute function public.fn_set_updated_at();
create trigger trg_convocatorias_updated_at   before update on public.convocatorias   for each row execute function public.fn_set_updated_at();
create trigger trg_enfrentamientos_updated_at before update on public.enfrentamientos for each row execute function public.fn_set_updated_at();

-- ---------------------------------------------------------------------
-- 11. BLOQUEO PREVENTIVO DE ACCESO VÍA API
-- RLS activado SIN políticas: la API pública (anon/authenticated) no puede
-- leer ni escribir hasta que la Fase 2 defina las políticas. El SQL Editor
-- de Supabase (rol postgres) no se ve afectado.
-- ---------------------------------------------------------------------

alter table public.migraciones_aplicadas        enable row level security;
alter table public.modalidades                  enable row level security;
alter table public.estados_enfrentamiento       enable row level security;
alter table public.conceptos_puntuacion         enable row level security;
alter table public.tipos_accion                 enable row level security;
alter table public.reglas_puntuacion_versiones  enable row level security;
alter table public.reglas_puntuacion_valores    enable row level security;
alter table public.clubes                       enable row level security;
alter table public.campeonatos                  enable row level security;
alter table public.configuracion                enable row level security;
alter table public.jugadores                    enable row level security;
alter table public.partidos                     enable row level security;
alter table public.asistencias                  enable row level security;
alter table public.listas_juego                 enable row level security;
alter table public.convocatorias                enable row level security;
alter table public.enfrentamientos              enable row level security;
alter table public.participantes_enfrentamiento enable row level security;
alter table public.resultados_enfrentamiento    enable row level security;
alter table public.acciones_resultado           enable row level security;

-- ---------------------------------------------------------------------
-- 12. DATOS INICIALES
-- ---------------------------------------------------------------------

insert into public.modalidades (codigo, nombre, jugadores_por_enfrentamiento, enfrentamientos_por_lista, orden) values
    ('INDIVIDUAL', 'Individual', 1, 5, 1),
    ('DUPLA',      'Dupla',      2, 3, 2),
    ('TRIO',       'Trío',       3, 2, 3);

insert into public.estados_enfrentamiento (codigo, nombre, cuenta_como_ej, admite_resultado, orden) values
    ('PENDIENTE',                'Pendiente',                         false, false, 1),
    ('DISPUTADO',                'Disputado',                         true,  true,  2),
    ('NO_DISPUTADO_FIN_PARTIDO', 'No disputado (fin del partido)',    false, false, 3);

insert into public.conceptos_puntuacion (codigo, nombre, categoria, orden) values
    ('CONVOCATORIA',    'Convocatoria',           'CONVOCATORIA', 1),
    ('VICTORIA',        'Victoria',               'RESULTADO',    2),
    ('DERROTA',         'Derrota',                'RESULTADO',    3),
    ('CORTO',           'Cortó',                  'ACCION',       4),
    ('CAIDA_RIVAL',     'Caída del rival',        'ACCION',       5),
    ('REVENTON_RIVAL',  'Reventón de hilo rival', 'ACCION',       6),
    ('LO_CORTARON',     'Lo cortaron',            'ACCION',       7),
    ('CAIDA_PROPIA',    'Caída propia',           'ACCION',       8),
    ('REVENTON_PROPIO', 'Reventón de hilo propio','ACCION',       9);

insert into public.tipos_accion (codigo, nombre, polaridad, orden) values
    ('CORTO',           'Cortó',                   'POSITIVA', 1),
    ('CAIDA_RIVAL',     'Caída del rival',         'POSITIVA', 2),
    ('REVENTON_RIVAL',  'Reventón de hilo rival',  'POSITIVA', 3),
    ('LO_CORTARON',     'Lo cortaron',             'NEGATIVA', 4),
    ('CAIDA_PROPIA',    'Caída propia',            'NEGATIVA', 5),
    ('REVENTON_PROPIO', 'Reventón de hilo propio', 'NEGATIVA', 6);

insert into public.reglas_puntuacion_versiones (codigo, nombre, descripcion, es_vigente) values
    ('V1', 'Reglamento de puntuación V1', 'Valores iniciales definidos en el Prompt Maestro v1.0', true);

insert into public.reglas_puntuacion_valores (regla_version_id, concepto_codigo, valor)
select v.id, x.concepto, x.valor
  from public.reglas_puntuacion_versiones v
 cross join (values
        ('CONVOCATORIA',     0.50),
        ('VICTORIA',         1.00),
        ('DERROTA',          0.00),
        ('CORTO',            1.00),
        ('CAIDA_RIVAL',      0.50),
        ('REVENTON_RIVAL',   0.50),
        ('LO_CORTARON',     -0.50),
        ('CAIDA_PROPIA',    -1.00),
        ('REVENTON_PROPIO', -0.70)
     ) as x (concepto, valor)
 where v.codigo = 'V1';

insert into public.configuracion (clave, valor, descripcion) values
    ('permite_jugador_repetido_en_lista', 'false'::jsonb,
     'Si un jugador puede ocupar más de una posición en la misma lista. V1: no.'),
    ('minimo_ej_ranking_porcentual', '5'::jsonb,
     'Enfrentamientos jugados (EJ) mínimos para aparecer en rankings porcentuales.');

insert into public.clubes (nombre, nombre_corto, es_gestionado) values
    ('CLUB RAYO', 'RAYO', true);

-- ---------------------------------------------------------------------
-- 13. REGISTRO DE LA MIGRACIÓN
-- ---------------------------------------------------------------------

insert into public.migraciones_aplicadas (version, descripcion)
values ('001', 'Esquema inicial: catálogos, clubes, campeonatos, jugadores, partidos, asistencia, listas, convocatorias, enfrentamientos, resultados y acciones');

commit;
