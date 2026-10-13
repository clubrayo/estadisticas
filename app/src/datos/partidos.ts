import { supabase } from '../lib/supabase'

export type EstadoPartido = 'PROGRAMADO' | 'EN_CURSO' | 'SUSPENDIDO' | 'FINALIZADO' | 'EN_REVISION' | 'CANCELADO'

export const ESTADOS_VIGENTES: EstadoPartido[] = ['PROGRAMADO', 'EN_CURSO', 'SUSPENDIDO', 'EN_REVISION']

interface ClubDelPartido {
  id: string
  nombre: string
  nombre_corto: string
  es_gestionado: boolean
}

export interface Partido {
  id: string
  campeonato_id: string
  fecha: string
  club_local_id: string
  club_visitante_id: string
  lugar: string | null
  estado: EstadoPartido
  puntaje_objetivo: number
  puntaje_local: number
  puntaje_visitante: number
  ganador_club_id: string | null
  observaciones: string | null
  /** Aumenta con cada cambio de estado o marcador: permite detectar novedades. */
  version: number
  campeonato: { nombre: string; temporada: string }
  local: ClubDelPartido
  visitante: ClubDelPartido
}

export interface NuevoPartido {
  campeonato_id: string
  fecha: string
  club_local_id: string
  club_visitante_id: string
  lugar: string
  observaciones: string
}

const COLUMNAS = `
  id, campeonato_id, fecha, club_local_id, club_visitante_id, lugar, estado,
  puntaje_objetivo, puntaje_local, puntaje_visitante, ganador_club_id, observaciones, version,
  campeonato:campeonatos(nombre, temporada),
  local:clubes!club_local_id(id, nombre, nombre_corto, es_gestionado),
  visitante:clubes!club_visitante_id(id, nombre, nombre_corto, es_gestionado)`

const opcional = (v: string) => (v.trim() === '' ? null : v.trim())

export async function listarPartidos(campeonatoId?: string): Promise<Partido[]> {
  let consulta = supabase.from('partidos').select(COLUMNAS).order('fecha', { ascending: false })
  if (campeonatoId) consulta = consulta.eq('campeonato_id', campeonatoId)
  const { data, error } = await consulta
  if (error) throw error
  return data as unknown as Partido[]
}

export async function obtenerPartido(id: string): Promise<Partido | null> {
  const { data, error } = await supabase.from('partidos').select(COLUMNAS).eq('id', id).maybeSingle()
  if (error) throw error
  return data as unknown as Partido | null
}

export async function crearPartido(d: NuevoPartido): Promise<{ id: string }> {
  const { data, error } = await supabase
    .from('partidos')
    .insert({ ...d, lugar: opcional(d.lugar), observaciones: opcional(d.observaciones) })
    .select('id')
    .single()
  if (error) throw error
  return data
}

/** Solo datos descriptivos: estado, marcador y ganador cambian únicamente por RPC. */
export async function actualizarPartido(id: string, fecha: string, lugar: string, observaciones: string) {
  const { error } = await supabase
    .from('partidos')
    .update({ fecha, lugar: opcional(lugar), observaciones: opcional(observaciones) })
    .eq('id', id)
    .select('id')
    .single()
  if (error) throw error
}

async function rpc(funcion: string, argumentos: Record<string, unknown>) {
  const { error } = await supabase.rpc(funcion, argumentos)
  if (error) throw error
}

export const iniciarPartido = (id: string) => rpc('iniciar_partido', { p_partido_id: id })
export const reanudarPartido = (id: string) => rpc('reanudar_partido', { p_partido_id: id })
export const suspenderPartido = (id: string, motivo: string) =>
  rpc('suspender_partido', { p_partido_id: id, p_motivo: motivo })
export const cancelarPartido = (id: string, motivo: string) =>
  rpc('cancelar_partido', { p_partido_id: id, p_motivo: motivo })

/** Solo ADMINISTRADOR: FINALIZADO → EN_REVISION para corregir resultados. */
export const reabrirPartido = (id: string, motivo: string) =>
  rpc('reabrir_partido', { p_partido_id: id, p_motivo: motivo })

/** Solo ADMINISTRADOR: EN_REVISION → FINALIZADO, si el partido no tiene inconsistencias. */
export const cerrarRevision = (id: string, motivo: string) =>
  rpc('cerrar_revision', { p_partido_id: id, p_motivo: motivo })

/** Problemas de consistencia del partido (vacío si está todo en orden). */
export async function verificarPartido(id: string): Promise<string[]> {
  const { data, error } = await supabase.rpc('verificar_partido', { p_partido_id: id })
  if (error) throw error
  return ((data as { problemas: string[] }).problemas ?? []) as string[]
}

/** Club gestionado del partido (el "propio") y su rival. */
export function ladosDelPartido(p: Partido) {
  const propioEsLocal = p.local.es_gestionado
  return {
    propio: propioEsLocal ? p.local : p.visitante,
    rival: propioEsLocal ? p.visitante : p.local,
    puntajePropio: propioEsLocal ? p.puntaje_local : p.puntaje_visitante,
    puntajeRival: propioEsLocal ? p.puntaje_visitante : p.puntaje_local,
    condicion: propioEsLocal ? 'Local' : 'Visitante',
  }
}
