import { capitalizarNombre } from '../lib/formato'
import { supabase } from '../lib/supabase'

export type EstadoJugador = 'ACTIVO' | 'INACTIVO'

export interface Jugador {
  id: string
  club_id: string
  primer_nombre: string
  apellidos: string
  nombre_completo: string
  apodo: string | null
  estado: EstadoJugador
  fecha_incorporacion: string | null
  categoria: string | null
  observaciones: string | null
  created_at: string
  updated_at: string
}

/** Campos que el usuario edita en el formulario. */
export interface DatosJugador {
  primer_nombre: string
  apellidos: string
  apodo: string
  fecha_incorporacion: string
  categoria: string
  observaciones: string
}

const COLUMNAS =
  'id, club_id, primer_nombre, apellidos, nombre_completo, apodo, estado, fecha_incorporacion, categoria, observaciones, created_at, updated_at'

/** Quita espacios sobrantes (al inicio, al final y repetidos). */
const limpiar = (v: string) => v.replace(/\s+/g, ' ').trim()

/** Clave para detectar homónimos: sin tildes, mayúsculas ni espacios sobrantes. */
export function claveNombre(nombre: string): string {
  return limpiar(nombre).normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
}

/** Limpia espacios y convierte los campos opcionales vacíos en null. */
function normalizar(d: DatosJugador) {
  const opcional = (v: string) => (limpiar(v) === '' ? null : limpiar(v))
  return {
    primer_nombre: capitalizarNombre(limpiar(d.primer_nombre)),
    apellidos: capitalizarNombre(limpiar(d.apellidos)),
    apodo: opcional(d.apodo),
    fecha_incorporacion: opcional(d.fecha_incorporacion),
    categoria: opcional(d.categoria),
    observaciones: d.observaciones.trim() === '' ? null : d.observaciones.trim(),
  }
}

export function datosDesdeJugador(j: Jugador | null): DatosJugador {
  return {
    primer_nombre: j?.primer_nombre ?? '',
    apellidos: j?.apellidos ?? '',
    apodo: j?.apodo ?? '',
    fecha_incorporacion: j?.fecha_incorporacion ?? '',
    categoria: j?.categoria ?? '',
    observaciones: j?.observaciones ?? '',
  }
}

/** Jugadores visibles para el usuario (RLS: los de sus clubes). */
export async function listarJugadores(): Promise<Jugador[]> {
  const { data, error } = await supabase
    .from('jugadores')
    .select(COLUMNAS)
    .order('apellidos')
    .order('primer_nombre')
  if (error) throw error
  return data as Jugador[]
}

export async function obtenerJugador(id: string): Promise<Jugador | null> {
  const { data, error } = await supabase.from('jugadores').select(COLUMNAS).eq('id', id).maybeSingle()
  if (error) throw error
  return data as Jugador | null
}

export async function crearJugador(clubId: string, datos: DatosJugador): Promise<Jugador> {
  const { data, error } = await supabase
    .from('jugadores')
    .insert({ club_id: clubId, ...normalizar(datos) })
    .select(COLUMNAS)
    .single()
  if (error) throw error
  return data as Jugador
}

export async function actualizarJugador(id: string, datos: DatosJugador): Promise<Jugador> {
  const { data, error } = await supabase
    .from('jugadores')
    .update(normalizar(datos))
    .eq('id', id)
    .select(COLUMNAS)
    .single()
  if (error) throw error
  return data as Jugador
}

/** Baja o alta lógica: los jugadores nunca se eliminan. */
export async function cambiarEstadoJugador(id: string, estado: EstadoJugador): Promise<Jugador> {
  const { data, error } = await supabase
    .from('jugadores')
    .update({ estado })
    .eq('id', id)
    .select(COLUMNAS)
    .single()
  if (error) throw error
  return data as Jugador
}
