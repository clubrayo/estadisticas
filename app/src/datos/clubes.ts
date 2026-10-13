import type { RolAsignado } from '../lib/roles'
import { supabase } from '../lib/supabase'

export interface ClubResumen {
  id: string
  nombre: string
  nombre_corto: string
}

export interface Rival extends ClubResumen {
  estado: 'ACTIVO' | 'INACTIVO'
}

/**
 * Clubes en los que el usuario puede administrar jugadores y partidos:
 * ADMINISTRADOR → todos los clubes gestionados; DIRECTIVA → los suyos.
 */
export async function listarClubesAdministrables(roles: RolAsignado[]): Promise<ClubResumen[]> {
  const esAdmin = roles.some((r) => r.rol === 'ADMINISTRADOR')
  const propios = roles.filter((r) => r.rol === 'DIRECTIVA' && r.clubId).map((r) => r.clubId as string)
  if (!esAdmin && propios.length === 0) return []

  let consulta = supabase.from('clubes').select('id, nombre, nombre_corto').eq('es_gestionado', true).order('nombre')
  if (!esAdmin) consulta = consulta.in('id', propios)
  const { data, error } = await consulta
  if (error) throw error
  return data as ClubResumen[]
}

/** Clubes rivales (no gestionados por el sistema). */
export async function listarRivales(): Promise<Rival[]> {
  const { data, error } = await supabase
    .from('clubes')
    .select('id, nombre, nombre_corto, estado')
    .eq('es_gestionado', false)
    .order('nombre')
  if (error) throw error
  return data as Rival[]
}

function normalizar(nombre: string, nombreCorto: string) {
  return {
    nombre: nombre.replace(/\s+/g, ' ').trim(),
    nombre_corto: nombreCorto.replace(/\s+/g, ' ').trim().toLocaleUpperCase('es'),
  }
}

export async function crearRival(nombre: string, nombreCorto: string): Promise<Rival> {
  const { data, error } = await supabase
    .from('clubes')
    .insert(normalizar(nombre, nombreCorto))
    .select('id, nombre, nombre_corto, estado')
    .single()
  if (error) throw error
  return data as Rival
}

export async function actualizarRival(
  id: string,
  nombre: string,
  nombreCorto: string,
  estado: Rival['estado'],
): Promise<Rival> {
  const { data, error } = await supabase
    .from('clubes')
    .update({ ...normalizar(nombre, nombreCorto), estado })
    .eq('id', id)
    .select('id, nombre, nombre_corto, estado')
    .single()
  if (error) throw error
  return data as Rival
}
