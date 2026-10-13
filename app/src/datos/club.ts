import { supabase } from '../lib/supabase'
import type { ClubResumen } from './clubes'

/** Resultado de estadisticas_club (migración 008). */
export interface EstadisticasClub {
  jugadores_activos: number
  partidos: { jugados: number; ganados: number; perdidos: number; en_curso: number; efectividad: number | null }
  listas_disputadas: number
  puntos: { a_favor: number; en_contra: number }
  por_modalidad: { modalidad: string; nombre: string; ej: number; eg: number; ep: number; porcentaje: number | null }[]
  acciones: {
    cortes: number
    veces_cortado: number
    caidas_rival: number
    caidas_propias: number
    reventones_rival: number
    reventones_propios: number
  }
}

/** Clubes gestionados que el usuario puede ver (RLS). */
export async function listarClubesVisibles(): Promise<ClubResumen[]> {
  const { data, error } = await supabase
    .from('clubes')
    .select('id, nombre, nombre_corto')
    .eq('es_gestionado', true)
    .order('nombre')
  if (error) throw error
  return data as ClubResumen[]
}

/** Dashboard del club. campeonatoId nulo = histórico. */
export async function obtenerEstadisticasClub(clubId: string, campeonatoId: string | null): Promise<EstadisticasClub> {
  const { data, error } = await supabase.rpc('estadisticas_club', { p_club_id: clubId, p_campeonato_id: campeonatoId })
  if (error) throw error
  return data as EstadisticasClub
}
