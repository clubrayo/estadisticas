import { supabase } from '../lib/supabase'

/** Ficha estadística del jugador (función estadisticas_jugador, migración 005). */
export interface FichaEstadistica {
  asistencia: { partidos: number; presentes: number; ausentes: number; justificados: number; porcentaje: number | null }
  convocatorias: { listas: number; puntos: number }
  participacion: { ej: number; eg: number; ep: number; porcentaje: number | null }
  por_modalidad: { modalidad: string; nombre: string; ej: number; eg: number; ep: number; porcentaje: number | null }[]
  acciones: {
    cortes: number
    caidas_rival: number
    reventones_rival: number
    veces_cortado: number
    caidas_propias: number
    reventones_propios: number
  }
  puntos: { convocatoria: number; resultado: number; positivas: number; penalizaciones: number; total: number }
}

/** Una fila de v_est_participaciones: un jugador en un enfrentamiento de una lista oficial. */
export interface Participacion {
  participante_id: string
  jugador_id: string
  partido_id: string
  campeonato_id: string
  campeonato: string
  fecha: string
  rival_id: string
  rival: string
  lista_numero: number
  modalidad_codigo: string
  enfrentamiento_numero: number
  orden_juego: number
  estado_codigo: string
  jugado: boolean
  resultado: 'GANADO' | 'PERDIDO' | null
  por_secretaria: boolean
  puntos_resultado: number
  puntos_positivos: number
  puntos_negativos: number
  acciones: string[]
  companeros: string[]
}

export interface ConvocatoriaEstadistica {
  jugador_id: string
  lista_numero: number
  puntos: number
}

/** p_campeonato nulo = histórico completo. */
export async function obtenerFicha(jugadorId: string, campeonatoId: string | null): Promise<FichaEstadistica> {
  const { data, error } = await supabase.rpc('estadisticas_jugador', {
    p_jugador_id: jugadorId,
    p_campeonato_id: campeonatoId,
  })
  if (error) throw error
  return data as FichaEstadistica
}

const COLUMNAS_PARTICIPACION =
  'participante_id, jugador_id, partido_id, campeonato_id, campeonato, fecha, rival_id, rival, lista_numero, modalidad_codigo, enfrentamiento_numero, orden_juego, estado_codigo, jugado, resultado, por_secretaria, puntos_resultado, puntos_positivos, puntos_negativos, acciones, companeros'

/** Historial del jugador (sección 34), más reciente primero. */
export async function listarHistorial(jugadorId: string): Promise<Participacion[]> {
  const { data, error } = await supabase
    .from('v_est_participaciones')
    .select(COLUMNAS_PARTICIPACION)
    .eq('jugador_id', jugadorId)
    .order('fecha', { ascending: false })
    .order('lista_numero', { ascending: false })
    .order('orden_juego')
  if (error) throw error
  return data as Participacion[]
}

/** Participaciones y convocatorias de un partido (estadísticas del partido). */
export async function datosDelPartido(partidoId: string) {
  const [p, c] = await Promise.all([
    supabase.from('v_est_participaciones').select(COLUMNAS_PARTICIPACION).eq('partido_id', partidoId),
    supabase.from('v_est_convocatorias').select('jugador_id, lista_numero, puntos').eq('partido_id', partidoId),
  ])
  if (p.error) throw p.error
  if (c.error) throw c.error
  return { participaciones: p.data as Participacion[], convocatorias: c.data as ConvocatoriaEstadistica[] }
}

/** Puntaje con dos decimales y coma decimal: 2,50 · −0,70. */
export const puntaje = (n: number) =>
  Number(n).toLocaleString('es-CL', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

/** Porcentaje con un decimal, o "—" si no hay datos. */
export const porcentaje = (n: number | null) =>
  n === null ? '—' : `${Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 })}%`
