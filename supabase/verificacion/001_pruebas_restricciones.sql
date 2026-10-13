-- =====================================================================
-- PRUEBAS 001 — RESTRICCIONES DE INTEGRIDAD
-- Crea datos ficticios, intenta operaciones válidas e inválidas y DESHACE
-- TODO al final (no queda ningún dato de prueba en la base).
-- Resultado esperado: todas las filas con ok = true.
--
-- Columna "esperado":
--   ACEPTADO : la operación debe funcionar.
--   23514    : rechazada por CHECK o trigger de coherencia.
--   23505    : rechazada por UNIQUE.
--   23503    : rechazada por FOREIGN KEY.
--   otro     : valor exacto que debe leerse de la base.
--
-- NO CUBIERTO POR LA MIGRACIÓN 001 (se probará en Fase 3):
--   solo PRESENTES convocados; composición 1/2/3 por modalidad;
--   5/3/2 enfrentamientos por lista; polaridad de la acción; acción
--   obligatoria en todo DISPUTADO; orden estricto de juego; cierre
--   automático al objetivo; invalidación P-1; club gestionado en el partido.
-- =====================================================================

drop table if exists pg_temp.pruebas_001;
create temp table pruebas_001 (n int, grupo text, prueba text, esperado text, obtenido text, ok boolean);

-- Ejecuta una sentencia y devuelve 'ACEPTADO' o el SQLSTATE del error.
create or replace function pg_temp.intentar(p_sql text)
returns text
language plpgsql
as $$
begin
    execute p_sql;
    return 'ACEPTADO';
exception when others then
    return sqlstate;
end;
$$;

do $$
declare
    r          jsonb := '[]'::jsonb;   -- acumulador (las variables sobreviven al rollback)
    v_regla    uuid;
    v_club_a   uuid;   -- local (gestionado en la prueba)
    v_club_b   uuid;   -- visitante
    v_club_c   uuid;   -- club ajeno al partido
    v_camp     uuid;
    v_jug1     uuid;   -- club A
    v_jug2     uuid;   -- club A
    v_jug3     uuid;   -- club C
    v_partido  uuid;
    v_lista1   uuid;
    v_lista2   uuid;
    v_enf1     uuid;
    v_enf2     uuid;
    v_conv1    uuid;
    v_conv2    uuid;
    v_conv_l2  uuid;
    v_part1    uuid;
    v_part2    uuid;
    v_res1     uuid;
    v_res2     uuid;
    v_txt      text;
begin
    begin
        -- ================= DATOS FICTICIOS =================
        select id into v_regla from public.reglas_puntuacion_versiones where codigo = 'V1';

        -- Club A gestionado: desde la migración 003 todo partido debe incluir uno.
        insert into public.clubes (nombre, nombre_corto, es_gestionado) values ('PRUEBA CLUB A', 'PRUEBA_A', true) returning id into v_club_a;
        insert into public.clubes (nombre, nombre_corto) values ('PRUEBA CLUB B', 'PRUEBA_B') returning id into v_club_b;
        insert into public.clubes (nombre, nombre_corto) values ('PRUEBA CLUB C', 'PRUEBA_C') returning id into v_club_c;
        insert into public.campeonatos (nombre, temporada, fecha_inicio, puntaje_objetivo)
             values ('PRUEBA CAMPEONATO', 'PRUEBA', current_date, 30) returning id into v_camp;
        insert into public.jugadores (club_id, primer_nombre, apellidos) values (v_club_a, 'Prueba', 'Uno')  returning id into v_jug1;
        insert into public.jugadores (club_id, primer_nombre, apellidos) values (v_club_a, 'Prueba', 'Dos')  returning id into v_jug2;
        insert into public.jugadores (club_id, primer_nombre, apellidos) values (v_club_c, 'Prueba', 'Tres') returning id into v_jug3;

        -- ================= PARTIDO: SNAPSHOT Y ARRANQUE =================
        insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id, puntaje_objetivo)
             values (v_camp, current_date, v_club_a, v_club_b, 99)
          returning id, puntaje_objetivo::text into v_partido, v_txt;
        r := r || jsonb_build_array(jsonb_build_object('n',1,'g','Partido','p','Copia puntaje objetivo del campeonato (ignora 99)','e','30','o',v_txt));

        r := r || jsonb_build_array(jsonb_build_object('n',2,'g','Partido','p','Bloquea cambio de puntaje objetivo','e','23514','o',
            pg_temp.intentar(format('update public.partidos set puntaje_objetivo = 25 where id = %L', v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',3,'g','Partido','p','Rechaza local = visitante','e','23514','o',
            pg_temp.intentar(format('insert into public.partidos (campeonato_id, fecha, club_local_id, club_visitante_id) values (%L, current_date, %L, %L)',
                                    v_camp, v_club_a, v_club_a))));

        r := r || jsonb_build_array(jsonb_build_object('n',4,'g','Partido','p','Rechaza EN_CURSO sin regla fijada','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''EN_CURSO'', iniciado_at = now() where id = %L', v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',5,'g','Partido','p','Acepta EN_CURSO con regla fijada','e','ACEPTADO','o',
            pg_temp.intentar(format('update public.partidos set estado = ''EN_CURSO'', iniciado_at = now(), regla_version_id = %L where id = %L',
                                    v_regla, v_partido))));

        -- ================= PARTIDO: MARCADOR Y GANADOR =================
        r := r || jsonb_build_array(jsonb_build_object('n',6,'g','Partido','p','Rechaza puntaje > objetivo','e','23514','o',
            pg_temp.intentar(format('update public.partidos set puntaje_local = 31 where id = %L', v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',7,'g','Partido','p','Rechaza EN_CURSO con 30 puntos','e','23514','o',
            pg_temp.intentar(format('update public.partidos set puntaje_local = 30 where id = %L', v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',8,'g','Partido','p','Rechaza EN_CURSO con ganador','e','23514','o',
            pg_temp.intentar(format('update public.partidos set ganador_club_id = %L where id = %L', v_club_a, v_partido))));

        -- FINALIZADO
        r := r || jsonb_build_array(jsonb_build_object('n',9,'g','Cierre','p','FINALIZADO rechaza ganador NULL','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''FINALIZADO'', finalizado_at = now(), puntaje_local = 30, puntaje_visitante = 20 where id = %L', v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',10,'g','Cierre','p','FINALIZADO rechaza ganador ajeno al partido','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''FINALIZADO'', finalizado_at = now(), ganador_club_id = %L, puntaje_local = 30, puntaje_visitante = 20 where id = %L', v_club_c, v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',11,'g','Cierre','p','FINALIZADO rechaza ganador sin 30 puntos','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''FINALIZADO'', finalizado_at = now(), ganador_club_id = %L, puntaje_local = 30, puntaje_visitante = 20 where id = %L', v_club_b, v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',12,'g','Cierre','p','FINALIZADO rechaza ambos clubes con 30','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''FINALIZADO'', finalizado_at = now(), ganador_club_id = %L, puntaje_local = 30, puntaje_visitante = 30 where id = %L', v_club_a, v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',13,'g','Cierre','p','FINALIZADO rechaza falta de finalizado_at','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''FINALIZADO'', ganador_club_id = %L, puntaje_local = 30, puntaje_visitante = 20 where id = %L', v_club_a, v_partido))));

        -- EN_REVISION (mismas condiciones estructurales que FINALIZADO)
        r := r || jsonb_build_array(jsonb_build_object('n',14,'g','Cierre','p','EN_REVISION rechaza ganador NULL','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''EN_REVISION'', finalizado_at = now(), puntaje_local = 30, puntaje_visitante = 20 where id = %L', v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',15,'g','Cierre','p','EN_REVISION rechaza ganador ajeno al partido','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''EN_REVISION'', finalizado_at = now(), ganador_club_id = %L, puntaje_local = 30, puntaje_visitante = 20 where id = %L', v_club_c, v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',16,'g','Cierre','p','EN_REVISION rechaza ganador sin 30 puntos','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''EN_REVISION'', finalizado_at = now(), ganador_club_id = %L, puntaje_local = 30, puntaje_visitante = 20 where id = %L', v_club_b, v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',17,'g','Cierre','p','EN_REVISION rechaza ambos clubes con 30','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''EN_REVISION'', finalizado_at = now(), ganador_club_id = %L, puntaje_local = 30, puntaje_visitante = 30 where id = %L', v_club_a, v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',18,'g','Cierre','p','EN_REVISION rechaza falta de finalizado_at','e','23514','o',
            pg_temp.intentar(format('update public.partidos set estado = ''EN_REVISION'', ganador_club_id = %L, puntaje_local = 30, puntaje_visitante = 20 where id = %L', v_club_a, v_partido))));

        -- ================= ASISTENCIA =================
        insert into public.asistencias (partido_id, jugador_id, estado) values (v_partido, v_jug1, 'PRESENTE');

        r := r || jsonb_build_array(jsonb_build_object('n',19,'g','Asistencia','p','Rechaza asistencia duplicada','e','23505','o',
            pg_temp.intentar(format('insert into public.asistencias (partido_id, jugador_id, estado) values (%L, %L, ''AUSENTE'')', v_partido, v_jug1))));

        r := r || jsonb_build_array(jsonb_build_object('n',20,'g','Asistencia','p','Rechaza estado de asistencia inválido','e','23514','o',
            pg_temp.intentar(format('insert into public.asistencias (partido_id, jugador_id, estado) values (%L, %L, ''TARDE'')', v_partido, v_jug2))));

        -- ================= LISTAS Y ENFRENTAMIENTOS =================
        insert into public.listas_juego (partido_id, numero) values (v_partido, 1) returning id into v_lista1;
        insert into public.listas_juego (partido_id, numero) values (v_partido, 2) returning id into v_lista2;

        r := r || jsonb_build_array(jsonb_build_object('n',21,'g','Lista','p','Rechaza número de lista repetido','e','23505','o',
            pg_temp.intentar(format('insert into public.listas_juego (partido_id, numero) values (%L, 1)', v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',22,'g','Lista','p','Rechaza CONFIRMADA sin confirmada_at','e','23514','o',
            pg_temp.intentar(format('update public.listas_juego set estado = ''CONFIRMADA'' where id = %L', v_lista1))));

        insert into public.enfrentamientos (lista_id, modalidad_codigo, numero, orden_juego) values (v_lista1, 'INDIVIDUAL', 1, 1) returning id into v_enf1;
        insert into public.enfrentamientos (lista_id, modalidad_codigo, numero, orden_juego) values (v_lista1, 'INDIVIDUAL', 2, 2) returning id into v_enf2;

        r := r || jsonb_build_array(jsonb_build_object('n',23,'g','Enfrentamiento','p','Rechaza orden_juego repetido','e','23505','o',
            pg_temp.intentar(format('insert into public.enfrentamientos (lista_id, modalidad_codigo, numero, orden_juego) values (%L, ''DUPLA'', 1, 1)', v_lista1))));

        r := r || jsonb_build_array(jsonb_build_object('n',24,'g','Enfrentamiento','p','Rechaza estado inexistente','e','23503','o',
            pg_temp.intentar(format('update public.enfrentamientos set estado_codigo = ''EMPATE'' where id = %L', v_enf2))));

        -- ================= CONVOCATORIAS: CLUB =================
        insert into public.convocatorias (lista_id, jugador_id) values (v_lista1, v_jug1) returning id, club_id::text into v_conv1, v_txt;
        r := r || jsonb_build_array(jsonb_build_object('n',25,'g','Convocatoria','p','Completa club_id con el club del jugador','e',v_club_a::text,'o',v_txt));

        r := r || jsonb_build_array(jsonb_build_object('n',26,'g','Convocatoria','p','Rechaza club distinto al del jugador','e','23514','o',
            pg_temp.intentar(format('insert into public.convocatorias (lista_id, jugador_id, club_id) values (%L, %L, %L)', v_lista1, v_jug3, v_club_a))));

        r := r || jsonb_build_array(jsonb_build_object('n',27,'g','Convocatoria','p','Rechaza cambiar club_id posteriormente','e','23514','o',
            pg_temp.intentar(format('update public.convocatorias set club_id = %L where id = %L', v_club_b, v_conv1))));

        r := r || jsonb_build_array(jsonb_build_object('n',28,'g','Convocatoria','p','Rechaza cambiar jugador_id posteriormente','e','23514','o',
            pg_temp.intentar(format('update public.convocatorias set jugador_id = %L where id = %L', v_jug2, v_conv1))));

        -- ================= CONVOCATORIAS: UNICIDAD HISTÓRICA =================
        r := r || jsonb_build_array(jsonb_build_object('n',29,'g','Convocatoria','p','Rechaza segunda convocatoria activa en la lista','e','23505','o',
            pg_temp.intentar(format('insert into public.convocatorias (lista_id, jugador_id) values (%L, %L)', v_lista1, v_jug1))));

        r := r || jsonb_build_array(jsonb_build_object('n',30,'g','Convocatoria','p','Rechaza VIGENTE sin puntos','e','23514','o',
            pg_temp.intentar(format('update public.convocatorias set estado = ''VIGENTE'', fue_confirmada = true where id = %L', v_conv1))));

        r := r || jsonb_build_array(jsonb_build_object('n',31,'g','Convocatoria','p','Rechaza anulación sin motivo','e','23514','o',
            pg_temp.intentar(format('update public.convocatorias set estado = ''ANULADA_REEMPLAZO'', anulada_at = now() where id = %L', v_conv1))));

        r := r || jsonb_build_array(jsonb_build_object('n',32,'g','Convocatoria','p','Acepta anulación por reemplazo con motivo','e','ACEPTADO','o',
            pg_temp.intentar(format('update public.convocatorias set estado = ''ANULADA_REEMPLAZO'', anulada_at = now(), motivo_anulacion = ''Prueba reemplazo'' where id = %L', v_conv1))));

        r := r || jsonb_build_array(jsonb_build_object('n',33,'g','Convocatoria','p','Rechaza nueva convocatoria tras anulación (misma lista)','e','23505','o',
            pg_temp.intentar(format('insert into public.convocatorias (lista_id, jugador_id) values (%L, %L)', v_lista1, v_jug1))));

        r := r || jsonb_build_array(jsonb_build_object('n',34,'g','Convocatoria','p','Reincorporación reactiva el mismo registro','e','ACEPTADO','o',
            pg_temp.intentar(format('update public.convocatorias set estado = ''PROPUESTA'', anulada_at = null, motivo_anulacion = null where id = %L', v_conv1))));

        select count(*)::text || ':' || bool_and(id = v_conv1)::text into v_txt
          from public.convocatorias where lista_id = v_lista1 and jugador_id = v_jug1;
        r := r || jsonb_build_array(jsonb_build_object('n',35,'g','Convocatoria','p','Jugador+lista tiene un único registro (cantidad:mismo id)','e','1:true','o',v_txt));

        -- ================= DECIMALES EXACTOS =================
        update public.convocatorias set estado = 'VIGENTE', fue_confirmada = true, puntos = 0.50 where id = v_conv1;
        select puntos::text into v_txt from public.convocatorias where id = v_conv1;
        r := r || jsonb_build_array(jsonb_build_object('n',36,'g','Decimales','p','Convocatoria conserva 0.50','e','0.50','o',v_txt));

        -- ================= PARTICIPANTES =================
        insert into public.convocatorias (lista_id, jugador_id) values (v_lista2, v_jug2) returning id into v_conv_l2;

        r := r || jsonb_build_array(jsonb_build_object('n',37,'g','Participante','p','Rechaza convocatoria de otra lista','e','23503','o',
            pg_temp.intentar(format('insert into public.participantes_enfrentamiento (enfrentamiento_id, lista_id, convocatoria_id, posicion) values (%L, %L, %L, 1)',
                                    v_enf1, v_lista1, v_conv_l2))));

        insert into public.participantes_enfrentamiento (enfrentamiento_id, lista_id, convocatoria_id, posicion)
             values (v_enf1, v_lista1, v_conv1, 1) returning id into v_part1;
        insert into public.convocatorias (lista_id, jugador_id) values (v_lista1, v_jug2) returning id into v_conv2;

        r := r || jsonb_build_array(jsonb_build_object('n',38,'g','Participante','p','Rechaza posición repetida','e','23505','o',
            pg_temp.intentar(format('insert into public.participantes_enfrentamiento (enfrentamiento_id, lista_id, convocatoria_id, posicion) values (%L, %L, %L, 1)',
                                    v_enf1, v_lista1, v_conv2))));

        insert into public.participantes_enfrentamiento (enfrentamiento_id, lista_id, convocatoria_id, posicion)
             values (v_enf2, v_lista1, v_conv2, 1) returning id into v_part2;

        -- ================= RESULTADOS =================
        insert into public.resultados_enfrentamiento (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota)
             values (v_enf1, v_club_a, 1, 0) returning id into v_res1;

        r := r || jsonb_build_array(jsonb_build_object('n',39,'g','Resultado','p','Rechaza segundo resultado vigente','e','23505','o',
            pg_temp.intentar(format('insert into public.resultados_enfrentamiento (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota) values (%L, %L, 1, 0)',
                                    v_enf1, v_club_b))));

        r := r || jsonb_build_array(jsonb_build_object('n',40,'g','Resultado','p','Rechaza anulación sin causa ni motivo','e','23514','o',
            pg_temp.intentar(format('update public.resultados_enfrentamiento set vigente = false, anulado_at = now() where id = %L', v_res1))));

        r := r || jsonb_build_array(jsonb_build_object('n',41,'g','Resultado','p','Acepta anulación por corrección','e','ACEPTADO','o',
            pg_temp.intentar(format('update public.resultados_enfrentamiento set vigente = false, anulado_at = now(), causa_anulacion = ''CORREGIDO'', motivo_anulacion = ''Prueba'' where id = %L', v_res1))));

        insert into public.resultados_enfrentamiento (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota, reemplaza_a_id)
             values (v_enf1, v_club_b, 1, 0, v_res1) returning id into v_res1;
        select count(*)::text into v_txt from public.resultados_enfrentamiento where enfrentamiento_id = v_enf1;
        r := r || jsonb_build_array(jsonb_build_object('n',42,'g','Resultado','p','Corrección conserva historial (versiones)','e','2','o',v_txt));

        r := r || jsonb_build_array(jsonb_build_object('n',43,'g','Resultado','p','Rechaza reemplazo entre enfrentamientos','e','23503','o',
            pg_temp.intentar(format('insert into public.resultados_enfrentamiento (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota, reemplaza_a_id, vigente, anulado_at, causa_anulacion, motivo_anulacion) values (%L, %L, 1, 0, %L, false, now(), ''CORREGIDO'', ''Prueba'')',
                                    v_enf2, v_club_a, v_res1))));

        -- ================= ACCIONES =================
        r := r || jsonb_build_array(jsonb_build_object('n',44,'g','Acción','p','Rechaza jugador ajeno al enfrentamiento','e','23503','o',
            pg_temp.intentar(format('insert into public.acciones_resultado (resultado_id, enfrentamiento_id, participante_id, tipo_accion_codigo, puntos) values (%L, %L, %L, ''LO_CORTARON'', -0.50)',
                                    v_res1, v_enf1, v_part2))));

        insert into public.acciones_resultado (resultado_id, enfrentamiento_id, participante_id, tipo_accion_codigo, puntos)
             values (v_res1, v_enf1, v_part1, 'LO_CORTARON', -0.50);

        r := r || jsonb_build_array(jsonb_build_object('n',45,'g','Acción','p','Acepta varias acciones por resultado (desde 004; reglas al confirmar)','e','ACEPTADO','o',
            pg_temp.intentar(format('insert into public.acciones_resultado (resultado_id, enfrentamiento_id, participante_id, tipo_accion_codigo, puntos) values (%L, %L, %L, ''CAIDA_PROPIA'', -1)',
                                    v_res1, v_enf1, v_part1))));

        insert into public.resultados_enfrentamiento (enfrentamiento_id, ganador_club_id, puntos_victoria, puntos_derrota)
             values (v_enf2, v_club_b, 1, 0) returning id into v_res2;
        insert into public.acciones_resultado (resultado_id, enfrentamiento_id, participante_id, tipo_accion_codigo, puntos)
             values (v_res2, v_enf2, v_part2, 'REVENTON_PROPIO', -0.70);

        select puntos::text into v_txt from public.acciones_resultado where resultado_id = v_res1;
        r := r || jsonb_build_array(jsonb_build_object('n',46,'g','Decimales','p','Acción LO_CORTARON conserva -0.50','e','-0.50','o',v_txt));

        select puntos::text into v_txt from public.acciones_resultado where resultado_id = v_res2;
        r := r || jsonb_build_array(jsonb_build_object('n',47,'g','Decimales','p','Acción REVENTON_PROPIO conserva -0.70','e','-0.70','o',v_txt));

        -- Ejemplo 6 del Prompt Maestro: 0,5 + 0 + (-0,7) = -0,2 exacto.
        select (0.50::numeric(5,2) + r2.puntos_derrota + a.puntos)::text into v_txt
          from public.resultados_enfrentamiento r2
          join public.acciones_resultado a on a.resultado_id = r2.id
         where r2.id = v_res2;
        r := r || jsonb_build_array(jsonb_build_object('n',48,'g','Decimales','p','Suma exacta 0.50 + 0.00 - 0.70','e','-0.20','o',v_txt));

        select string_agg(rv.valor::text, '|' order by rv.concepto_codigo) into v_txt
          from public.reglas_puntuacion_valores rv
         where rv.regla_version_id = v_regla
           and rv.concepto_codigo in ('CONVOCATORIA', 'LO_CORTARON', 'REVENTON_PROPIO');
        r := r || jsonb_build_array(jsonb_build_object('n',49,'g','Decimales','p','Reglas V1: CONVOCATORIA|LO_CORTARON|REVENTON_PROPIO','e','0.50|-0.50|-0.70','o',v_txt));

        -- ================= REGLAS =================
        r := r || jsonb_build_array(jsonb_build_object('n',50,'g','Reglas','p','Rechaza dos versiones vigentes','e','23505','o',
            pg_temp.intentar('insert into public.reglas_puntuacion_versiones (codigo, nombre, es_vigente) values (''PRUEBA'', ''Prueba'', true)')));

        -- ================= CIERRES VÁLIDOS =================
        r := r || jsonb_build_array(jsonb_build_object('n',51,'g','Cierre','p','Acepta FINALIZADO 30-20 ganador local','e','ACEPTADO','o',
            pg_temp.intentar(format('update public.partidos set estado = ''FINALIZADO'', finalizado_at = now(), ganador_club_id = %L, puntaje_local = 30, puntaje_visitante = 20 where id = %L', v_club_a, v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',52,'g','Cierre','p','Acepta EN_REVISION con cierre coherente','e','ACEPTADO','o',
            pg_temp.intentar(format('update public.partidos set estado = ''EN_REVISION'' where id = %L', v_partido))));

        r := r || jsonb_build_array(jsonb_build_object('n',53,'g','Cierre','p','Acepta FINALIZADO 20-30 ganador visitante','e','ACEPTADO','o',
            pg_temp.intentar(format('update public.partidos set estado = ''FINALIZADO'', ganador_club_id = %L, puntaje_local = 20, puntaje_visitante = 30 where id = %L', v_club_b, v_partido))));

        -- Deshacer todos los datos de prueba.
        raise exception using errcode = 'P0001', message = 'ROLLBACK_PRUEBAS_001';
    exception
        when others then
            if sqlerrm <> 'ROLLBACK_PRUEBAS_001' then
                r := r || jsonb_build_array(jsonb_build_object('n',0,'g','ERROR','p','ERROR INESPERADO: ' || sqlerrm,'e','-','o',sqlstate));
            end if;
    end;

    insert into pruebas_001 (n, grupo, prueba, esperado, obtenido, ok)
    select (x->>'n')::int, x->>'g', x->>'p', x->>'e', x->>'o', (x->>'e') = (x->>'o')
      from jsonb_array_elements(r) as x;
end $$;

select n, grupo, prueba, esperado, obtenido, ok
  from pruebas_001
 order by n;
