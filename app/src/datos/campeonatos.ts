import { supabase } from '../lib/supabase'

export type EstadoCampeonato = 'PROGRAMADO' | 'EN_CURSO' | 'FINALIZADO' | 'CANCELADO'

export const NOMBRE_ESTADO_CAMPEONATO: Record<EstadoCampeonato, string> = {
  PROGRAMADO: 'Programado',
  EN_CURSO: 'En curso',
  FINALIZADO: 'Finalizado',
  CANCELADO: 'Cancelado',
}

/** Valor que se propone al crear un campeonato. El valor real es el guardado en cada campeonato. */
export const PUNTAJE_OBJETIVO_SUGERIDO = 30

export interface Campeonato {
  id: string
  nombre: string
  temporada: string
  fecha_inicio: string
  fecha_termino: string | null
  estado: EstadoCampeonato
  puntaje_objetivo: number
  observaciones: string | null
}

/** Campos del formulario (todo como texto, tal como se edita). */
export interface DatosCampeonato {
  nombre: string
  temporada: string
  fecha_inicio: string
  fecha_termino: string
  estado: EstadoCampeonato
  puntaje_objetivo: string
  observaciones: string
}

const COLUMNAS = 'id, nombre, temporada, fecha_inicio, fecha_termino, estado, puntaje_objetivo, observaciones'

export function datosDesdeCampeonato(c: Campeonato | null): DatosCampeonato {
  return {
    nombre: c?.nombre ?? '',
    temporada: c?.temporada ?? '',
    fecha_inicio: c?.fecha_inicio ?? '',
    fecha_termino: c?.fecha_termino ?? '',
    estado: c?.estado ?? 'PROGRAMADO',
    puntaje_objetivo: String(c?.puntaje_objetivo ?? PUNTAJE_OBJETIVO_SUGERIDO),
    observaciones: c?.observaciones ?? '',
  }
}

/** Devuelve un mensaje si los datos no son válidos, o null. */
export function validarCampeonato(d: DatosCampeonato): string | null {
  const faltantes = [
    !d.nombre.trim() && 'nombre',
    !d.temporada.trim() && 'temporada',
    !d.fecha_inicio && 'fecha de inicio',
  ].filter(Boolean)
  if (faltantes.length > 0) {
    return `Falta completar: ${faltantes.join(', ')}.`
  }
  const objetivo = Number(d.puntaje_objetivo)
  if (!Number.isInteger(objetivo) || objetivo <= 0) {
    return 'El puntaje objetivo debe ser un número entero mayor que cero.'
  }
  if (d.fecha_termino && d.fecha_termino < d.fecha_inicio) {
    return 'La fecha de término no puede ser anterior a la de inicio.'
  }
  return null
}

function normalizar(d: DatosCampeonato) {
  const opcional = (v: string) => (v.trim() === '' ? null : v.trim())
  return {
    nombre: d.nombre.replace(/\s+/g, ' ').trim(),
    temporada: d.temporada.trim(),
    fecha_inicio: d.fecha_inicio,
    fecha_termino: opcional(d.fecha_termino),
    estado: d.estado,
    puntaje_objetivo: Number(d.puntaje_objetivo),
    observaciones: opcional(d.observaciones),
  }
}

export async function listarCampeonatos(): Promise<Campeonato[]> {
  const { data, error } = await supabase.from('campeonatos').select(COLUMNAS).order('fecha_inicio', { ascending: false })
  if (error) throw error
  return data as Campeonato[]
}

export async function obtenerCampeonato(id: string): Promise<Campeonato | null> {
  const { data, error } = await supabase.from('campeonatos').select(COLUMNAS).eq('id', id).maybeSingle()
  if (error) throw error
  return data as Campeonato | null
}

export async function crearCampeonato(d: DatosCampeonato): Promise<Campeonato> {
  const { data, error } = await supabase.from('campeonatos').insert(normalizar(d)).select(COLUMNAS).single()
  if (error) throw error
  return data as Campeonato
}

export async function actualizarCampeonato(id: string, d: DatosCampeonato): Promise<Campeonato> {
  const { data, error } = await supabase.from('campeonatos').update(normalizar(d)).eq('id', id).select(COLUMNAS).single()
  if (error) throw error
  return data as Campeonato
}

/** Campeonato "actual": el más reciente en curso, o si no hay, el más reciente no cancelado. */
export function campeonatoActual(campeonatos: Campeonato[]): Campeonato | null {
  return campeonatos.find((c) => c.estado === 'EN_CURSO') ?? campeonatos.find((c) => c.estado !== 'CANCELADO') ?? null
}
