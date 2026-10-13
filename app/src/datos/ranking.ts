import { supabase } from '../lib/supabase'

/** Fila de ranking_jugadores (migración 006). */
export interface FilaRanking {
  jugador_id: string
  jugador: string
  apodo: string | null
  estado: 'ACTIVO' | 'INACTIVO'
  asistencias: number
  partidos: number
  convocatorias: number
  ej: number
  eg: number
  ep: number
  porcentaje: number | null
  cortes: number
  caidas_rival: number
  reventones_rival: number
  veces_cortado: number
  caidas_propias: number
  reventones_propios: number
  puntos_convocatoria: number
  puntos_resultado: number
  puntos_positivos: number
  puntos_negativos: number
  puntos_acciones: number
  puntos_total: number
}

/** Valor por defecto si la configuración no define el mínimo. */
const MINIMO_EJ_POR_DEFECTO = 5

/** p_campeonato nulo = histórico. */
export async function obtenerRanking(campeonatoId: string | null): Promise<FilaRanking[]> {
  const { data, error } = await supabase.rpc('ranking_jugadores', { p_campeonato_id: campeonatoId })
  if (error) throw error
  return (data as FilaRanking[]).map((f) => ({
    ...f,
    porcentaje: f.porcentaje === null ? null : Number(f.porcentaje),
    puntos_convocatoria: Number(f.puntos_convocatoria),
    puntos_resultado: Number(f.puntos_resultado),
    puntos_positivos: Number(f.puntos_positivos),
    puntos_negativos: Number(f.puntos_negativos),
    puntos_acciones: Number(f.puntos_acciones),
    puntos_total: Number(f.puntos_total),
  }))
}

/**
 * Mínimo de enfrentamientos jugados para aparecer en rankings porcentuales
 * (sección 32). Prioridad: configuración del campeonato > global.
 */
export async function obtenerMinimoEJ(campeonatoId: string | null): Promise<number> {
  const { data, error } = await supabase
    .from('configuracion')
    .select('valor, campeonato_id, club_id')
    .eq('clave', 'minimo_ej_ranking_porcentual')
  if (error) throw error
  const filas = data as { valor: unknown; campeonato_id: string | null; club_id: string | null }[]
  const fila =
    (campeonatoId && filas.find((f) => f.campeonato_id === campeonatoId)) ||
    filas.find((f) => f.campeonato_id === null && f.club_id === null)
  const valor = Number(fila?.valor)
  return Number.isFinite(valor) && valor >= 0 ? valor : MINIMO_EJ_POR_DEFECTO
}
