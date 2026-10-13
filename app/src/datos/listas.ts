import { supabase } from '../lib/supabase'

export type EstadoLista = 'BORRADOR' | 'CONFIRMADA' | 'EN_JUEGO' | 'FINALIZADA'
export const NOMBRE_ESTADO_LISTA: Record<EstadoLista, string> = {
  BORRADOR: 'Borrador',
  CONFIRMADA: 'Confirmada',
  EN_JUEGO: 'En juego',
  FINALIZADA: 'Finalizada',
}

export type EstadoEnfrentamiento = 'PENDIENTE' | 'DISPUTADO' | 'NO_DISPUTADO_FIN_PARTIDO'

export interface Modalidad {
  codigo: string
  nombre: string
  jugadores_por_enfrentamiento: number
  orden: number
}

export interface Lista {
  id: string
  numero: number
  estado: EstadoLista
}

export interface Enfrentamiento {
  id: string
  modalidad_codigo: string
  numero: number
  orden_juego: number
  estado_codigo: EstadoEnfrentamiento
  version: number
}

export interface PosicionAsignada {
  enfrentamiento_id: string
  posicion: number
  jugador_id: string
}

export interface ConvocatoriaLista {
  jugador_id: string
  estado: 'PROPUESTA' | 'VIGENTE' | 'ANULADA_REEMPLAZO'
  fue_confirmada: boolean
}

export interface DetalleLista {
  enfrentamientos: Enfrentamiento[]
  posiciones: PosicionAsignada[]
  convocatorias: ConvocatoriaLista[]
  /** Momento de la lectura: permite reiniciar el borrador al recargar. */
  leidoEn: number
}

/** Composición de una lista (5 ind. / 3 duplas / 2 tríos) según la tabla modalidades. */
export async function listarModalidades(): Promise<Modalidad[]> {
  const { data, error } = await supabase
    .from('modalidades')
    .select('codigo, nombre, jugadores_por_enfrentamiento, orden')
    .eq('activo', true)
    .order('orden')
  if (error) throw error
  return data as Modalidad[]
}

export async function listarListas(partidoId: string): Promise<Lista[]> {
  const { data, error } = await supabase
    .from('listas_juego')
    .select('id, numero, estado')
    .eq('partido_id', partidoId)
    .order('numero')
  if (error) throw error
  return data as Lista[]
}

export async function obtenerDetalleLista(listaId: string): Promise<DetalleLista> {
  const [e, p, c] = await Promise.all([
    supabase
      .from('enfrentamientos')
      .select('id, modalidad_codigo, numero, orden_juego, estado_codigo, version')
      .eq('lista_id', listaId)
      .order('orden_juego'),
    supabase
      .from('participantes_enfrentamiento')
      .select('enfrentamiento_id, posicion, convocatoria:convocatorias(jugador_id)')
      .eq('lista_id', listaId),
    supabase.from('convocatorias').select('jugador_id, estado, fue_confirmada').eq('lista_id', listaId),
  ])
  const error = e.error ?? p.error ?? c.error
  if (error) throw error

  type FilaParticipante = {
    enfrentamiento_id: string
    posicion: number
    convocatoria: { jugador_id: string } | { jugador_id: string }[] | null
  }
  return {
    enfrentamientos: e.data as Enfrentamiento[],
    posiciones: (p.data as FilaParticipante[]).flatMap((f) => {
      const conv = Array.isArray(f.convocatoria) ? f.convocatoria[0] : f.convocatoria
      return conv ? [{ enfrentamiento_id: f.enfrentamiento_id, posicion: f.posicion, jugador_id: conv.jugador_id }] : []
    }),
    convocatorias: c.data as ConvocatoriaLista[],
    leidoEn: Date.now(),
  }
}

export async function crearLista(partidoId: string): Promise<string> {
  const { data, error } = await supabase.rpc('crear_lista', { p_partido_id: partidoId })
  if (error) throw error
  return (data as { lista_id: string }).lista_id
}

/** Reemplaza la composición completa del borrador (operación atómica en el servidor). */
export async function guardarLista(listaId: string, posiciones: PosicionAsignada[], motivo?: string) {
  const { error } = await supabase.rpc('guardar_lista', {
    p_lista_id: listaId,
    p_posiciones: posiciones,
    p_motivo: motivo ?? null,
  })
  if (error) throw error
}

export async function confirmarLista(listaId: string) {
  const { error } = await supabase.rpc('confirmar_lista', { p_lista_id: listaId })
  if (error) throw error
}

export async function devolverListaAEdicion(listaId: string, motivo: string) {
  const { error } = await supabase.rpc('devolver_lista_a_edicion', { p_lista_id: listaId, p_motivo: motivo })
  if (error) throw error
}
