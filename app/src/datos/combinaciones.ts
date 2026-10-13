import { supabase } from '../lib/supabase'

export type ModalidadCombinada = 'DUPLA' | 'TRIO'

/** Fila de combinaciones() (migración 007). integrantes y nombres van en el mismo orden. */
export interface Combinacion {
  integrantes: string[]
  nombres: string[]
  ej: number
  eg: number
  ep: number
  porcentaje: number | null
  cortes: number
  puntos_acciones: number
}

/** Mejores duplas o tríos. campeonatoId nulo = histórico. */
export async function obtenerCombinaciones(
  modalidad: ModalidadCombinada,
  campeonatoId: string | null,
): Promise<Combinacion[]> {
  const { data, error } = await supabase.rpc('combinaciones', { p_modalidad: modalidad, p_campeonato_id: campeonatoId })
  if (error) throw error
  return (data as Combinacion[]).map((c) => ({
    ...c,
    porcentaje: c.porcentaje === null ? null : Number(c.porcentaje),
    puntos_acciones: Number(c.puntos_acciones),
  }))
}
