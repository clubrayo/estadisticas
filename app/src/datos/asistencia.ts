import { supabase } from '../lib/supabase'

export type EstadoAsistencia = 'PRESENTE' | 'AUSENTE' | 'JUSTIFICADO'

export interface RegistroAsistencia {
  jugador_id: string
  estado: EstadoAsistencia
}

/** Asistencia registrada del partido (una fila por jugador considerado). */
export async function listarAsistencia(partidoId: string): Promise<RegistroAsistencia[]> {
  const { data, error } = await supabase.from('asistencias').select('jugador_id, estado').eq('partido_id', partidoId)
  if (error) throw error
  return data as RegistroAsistencia[]
}

/**
 * Jugadores convocados en una lista ya confirmada del partido: no pueden
 * pasar a AUSENTE ni JUSTIFICADO (la base de datos también lo impide).
 */
export async function listarConvocados(partidoId: string): Promise<string[]> {
  const { data, error } = await supabase
    .from('convocatorias')
    .select('jugador_id, lista:listas_juego!inner(partido_id, estado)')
    .eq('lista.partido_id', partidoId)
    .neq('lista.estado', 'BORRADOR')
    .neq('estado', 'ANULADA_REEMPLAZO')
  if (error) throw error
  return [...new Set((data ?? []).map((c) => c.jugador_id as string))]
}

/** Registra uno o varios estados en una sola operación atómica (RPC). */
export async function registrarAsistencia(partidoId: string, registros: RegistroAsistencia[]) {
  const { error } = await supabase.rpc('registrar_asistencia', { p_partido_id: partidoId, p_registros: registros })
  if (error) throw error
}
