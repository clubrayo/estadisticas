-- =====================================================================
-- OPERACIÓN EJECUTADA — 2026-10-12 22:24 UTC (19:24 hora local)
-- Corrección manual de un jugador duplicado. YA FUE APLICADA: no volver a ejecutar.
--
-- Contexto: "Eric Rios" (id 1d548c22-…) se creó por error como duplicado de
-- "Mauricio Rios" (id 6edf0a5b-…) y recibió una asistencia JUSTIFICADO en el
-- partido 72ec0206-…. Se eliminaron ambos registros.
--
-- Cómo se hizo: en una sola transacción se desactivaron SOLO los triggers de
-- bloqueo de borrado de jugadores y asistencias, se borraron las dos filas con
-- verificaciones previas y se reactivaron los triggers antes del COMMIT.
-- La auditoría quedó registrada (2 filas DELETE, origen SISTEMA, con motivo).
-- Verificado después: los 16 triggers trg_bloquear_borrado siguen ACTIVOS.
--
-- Se archiva aquí para que la intervención sea trazable y reproducible
-- (sección 49 del Prompt Maestro).
-- =====================================================================

BEGIN;

LOCK TABLE public.jugadores, public.asistencias,
           public.convocatorias IN ACCESS EXCLUSIVE MODE;

DO $correccion$
DECLARE
    r record;
    v_filas integer;
BEGIN
    -- Confirmar el registro correcto y su asistencia.
    IF NOT EXISTS (
        SELECT 1
        FROM public.jugadores j
        JOIN public.asistencias a ON a.jugador_id = j.id
        WHERE j.id = '6edf0a5b-7618-49cb-9301-520e8a03a4e7'::uuid
          AND j.primer_nombre = 'Mauricio'
          AND j.apellidos = 'Rios'
          AND j.club_id =
              '20f63fab-e59f-425c-8a00-35f01b1ea573'::uuid
          AND a.id =
              'c389c2be-cb99-4b30-bdc2-d36b35f60828'::uuid
          AND a.partido_id =
              '72ec0206-833f-47f9-9b7f-ee60b3e2a311'::uuid
          AND a.estado = 'PRESENTE'
    ) THEN
        RAISE EXCEPTION 'La asistencia de Mauricio cambió. Revisar.';
    END IF;

    IF (
        SELECT count(*) FROM public.asistencias
        WHERE jugador_id =
            '1d548c22-bab4-494d-a08d-9a503631b0f2'::uuid
    ) <> 1 OR EXISTS (
        SELECT 1 FROM public.convocatorias
        WHERE jugador_id =
            '1d548c22-bab4-494d-a08d-9a503631b0f2'::uuid
    ) THEN
        RAISE EXCEPTION 'El historial de Eric cambió. Revisar.';
    END IF;

    PERFORM set_config(
        'app.motivo',
        'Corrección de duplicado: conservar Mauricio Rios y su asistencia PRESENTE; eliminar Eric Rios y su asistencia errónea.',
        true
    );

    -- Desactivar únicamente los triggers de bloqueo de borrado.
    -- La auditoría y las claves foráneas permanecen activas.
    FOR r IN
        SELECT t.tgname, t.tgenabled,
               t.tgrelid::regclass AS tabla
        FROM pg_trigger t
        JOIN pg_proc p ON p.oid = t.tgfoid
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE t.tgrelid IN (
            'public.jugadores'::regclass,
            'public.asistencias'::regclass
        )
          AND NOT t.tgisinternal
          AND n.nspname = 'privado'
          AND p.proname = 'fn_bloquear_borrado'
    LOOP
        IF r.tgenabled <> 'O' THEN
            RAISE EXCEPTION
                'Estado inesperado del trigger %. No se modifica.',
                r.tgname;
        END IF;

        EXECUTE format(
            'ALTER TABLE %s DISABLE TRIGGER %I',
            r.tabla, r.tgname
        );
    END LOOP;

    DELETE FROM public.asistencias
    WHERE id = '79bdbddf-7f82-4eae-a74f-d67d71e67359'::uuid
      AND jugador_id =
          '1d548c22-bab4-494d-a08d-9a503631b0f2'::uuid
      AND partido_id =
          '72ec0206-833f-47f9-9b7f-ee60b3e2a311'::uuid
      AND estado = 'JUSTIFICADO';

    GET DIAGNOSTICS v_filas = ROW_COUNT;
    IF v_filas <> 1 THEN
        RAISE EXCEPTION 'La asistencia de Eric cambió. Se revierte.';
    END IF;

    DELETE FROM public.jugadores
    WHERE id = '1d548c22-bab4-494d-a08d-9a503631b0f2'::uuid
      AND club_id =
          '20f63fab-e59f-425c-8a00-35f01b1ea573'::uuid
      AND primer_nombre = 'Eric'
      AND apellidos = 'Rios';

    GET DIAGNOSTICS v_filas = ROW_COUNT;
    IF v_filas <> 1 THEN
        RAISE EXCEPTION 'No se encontró a Eric. Se revierte.';
    END IF;

    -- Restablecer los bloqueos antes de confirmar.
    FOR r IN
        SELECT t.tgname, t.tgrelid::regclass AS tabla
        FROM pg_trigger t
        JOIN pg_proc p ON p.oid = t.tgfoid
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE t.tgrelid IN (
            'public.jugadores'::regclass,
            'public.asistencias'::regclass
        )
          AND NOT t.tgisinternal
          AND n.nspname = 'privado'
          AND p.proname = 'fn_bloquear_borrado'
    LOOP
        EXECUTE format(
            'ALTER TABLE %s ENABLE TRIGGER %I',
            r.tabla, r.tgname
        );
    END LOOP;
END;
$correccion$;

COMMIT;

SELECT j.primer_nombre, j.apellidos, j.estado,
       a.estado AS asistencia
FROM public.jugadores j
LEFT JOIN public.asistencias a
  ON a.jugador_id = j.id
 AND a.partido_id =
     '72ec0206-833f-47f9-9b7f-ee60b3e2a311'::uuid
WHERE j.id IN (
    '6edf0a5b-7618-49cb-9301-520e8a03a4e7'::uuid,
    '1d548c22-bab4-494d-a08d-9a503631b0f2'::uuid
);
