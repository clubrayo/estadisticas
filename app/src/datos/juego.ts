import { supabase } from '../lib/supabase'
import type { Enfrentamiento, Lista } from './listas'

export type Resultado = 'GANADO' | 'PERDIDO'

export interface TipoAccion {
  codigo: string
  nombre: string
  polaridad: 'POSITIVA' | 'NEGATIVA'
  orden: number
}

export interface ParticipanteJuego {
  id: string
  posicion: number
  jugador_id: string
}

export interface AccionRegistrada {
  participante_id: string
  tipo_accion_codigo: string
}

export interface ResultadoVigente {
  ganador_club_id: string
  por_secretaria: boolean
  motivo_secretaria: string | null
  acciones: AccionRegistrada[]
}

/** Acción tal como la reciben registrar_resultado y corregir_resultado. */
export interface AccionEntrada {
  jugador_id: string
  tipo_accion: string
}

export interface EnfrentamientoJuego extends Enfrentamiento {
  lista_id: string
  participantes: ParticipanteJuego[]
  resultado: ResultadoVigente | null
}

export interface EstadoJuego {
  listas: Lista[]
  /** Todos los enfrentamientos del partido, en orden (lista, orden_juego). */
  enfrentamientos: EnfrentamientoJuego[]
}

/** Respuesta de registrar_resultado / corregir_resultado. */
export interface RespuestaJuego {
  estado: string
  puntaje_local: number
  puntaje_visitante: number
  ganador_club_id: string | null
  ya_registrado?: boolean
  cierre?: boolean
}

export interface Previsualizacion {
  actual: { puntaje_local: number; puntaje_visitante: number; estado: string }
  propuesto: { puntaje_local: number; puntaje_visitante: number; estado: string; ganador_club_id: string | null }
  requiere_confirmacion: boolean
  invalidados: { enfrentamiento_id: string; lista: number; modalidad: string; numero: number }[]
}

export async function listarTiposAccion(): Promise<TipoAccion[]> {
  const { data, error } = await supabase
    .from('tipos_accion')
    .select('codigo, nombre, polaridad, orden')
    .eq('activo', true)
    .order('orden')
  if (error) throw error
  return data as TipoAccion[]
}

type Fila = Enfrentamiento & {
  lista_id: string
  participantes: { id: string; posicion: number; convocatoria: { jugador_id: string } | { jugador_id: string }[] | null }[]
  resultados: {
    ganador_club_id: string
    vigente: boolean
    por_secretaria: boolean
    motivo_secretaria: string | null
    acciones: AccionRegistrada[]
  }[]
}

export async function cargarJuego(partidoId: string): Promise<EstadoJuego> {
  const { data: listas, error: e1 } = await supabase
    .from('listas_juego')
    .select('id, numero, estado')
    .eq('partido_id', partidoId)
    .order('numero')
  if (e1) throw e1
  if (!listas.length) return { listas: [], enfrentamientos: [] }

  const { data, error } = await supabase
    .from('enfrentamientos')
    .select(
      `id, lista_id, modalidad_codigo, numero, orden_juego, estado_codigo, version,
       participantes:participantes_enfrentamiento(id, posicion, convocatoria:convocatorias(jugador_id)),
       resultados:resultados_enfrentamiento(ganador_club_id, vigente, por_secretaria, motivo_secretaria, acciones:acciones_resultado(participante_id, tipo_accion_codigo))`,
    )
    .in(
      'lista_id',
      listas.map((l) => l.id),
    )
  if (error) throw error

  const numero = new Map(listas.map((l) => [l.id, l.numero as number]))
  const enfrentamientos = (data as unknown as Fila[])
    .map((f) => {
      const vigente = f.resultados.find((r) => r.vigente)
      return {
        id: f.id,
        lista_id: f.lista_id,
        modalidad_codigo: f.modalidad_codigo,
        numero: f.numero,
        orden_juego: f.orden_juego,
        estado_codigo: f.estado_codigo,
        version: f.version,
        participantes: f.participantes
          .flatMap((p) => {
            const conv = Array.isArray(p.convocatoria) ? p.convocatoria[0] : p.convocatoria
            return conv ? [{ id: p.id, posicion: p.posicion, jugador_id: conv.jugador_id }] : []
          })
          .sort((a, b) => a.posicion - b.posicion),
        resultado: vigente
          ? {
              ganador_club_id: vigente.ganador_club_id,
              por_secretaria: vigente.por_secretaria,
              motivo_secretaria: vigente.motivo_secretaria,
              acciones: vigente.acciones,
            }
          : null,
      }
    })
    .sort((a, b) => (numero.get(a.lista_id) ?? 0) - (numero.get(b.lista_id) ?? 0) || a.orden_juego - b.orden_juego)

  return { listas: listas as Lista[], enfrentamientos }
}

/** Registra un enfrentamiento con todas sus acciones (o por secretaría, sin acciones). */
export async function registrarResultado(
  enfrentamientoId: string,
  resultado: Resultado,
  acciones: AccionEntrada[],
  version: number,
  porSecretaria = false,
  motivo: string | null = null,
): Promise<RespuestaJuego> {
  const { data, error } = await supabase.rpc('registrar_resultado', {
    p_enfrentamiento_id: enfrentamientoId,
    p_resultado: resultado,
    p_acciones: acciones,
    p_version: version,
    p_por_secretaria: porSecretaria,
    p_motivo: motivo,
  })
  if (error) throw error
  return data as RespuestaJuego
}

export async function previsualizarCorreccion(enfrentamientoId: string, resultado: Resultado): Promise<Previsualizacion> {
  const { data, error } = await supabase.rpc('previsualizar_correccion', {
    p_enfrentamiento_id: enfrentamientoId,
    p_resultado: resultado,
  })
  if (error) throw error
  return data as Previsualizacion
}

export async function corregirResultado(
  enfrentamientoId: string,
  resultado: Resultado,
  acciones: AccionEntrada[],
  motivo: string,
  version: number,
  confirmarImpacto: boolean,
  porSecretaria = false,
): Promise<RespuestaJuego> {
  const { data, error } = await supabase.rpc('corregir_resultado', {
    p_enfrentamiento_id: enfrentamientoId,
    p_resultado: resultado,
    p_acciones: acciones,
    p_motivo: motivo,
    p_version: version,
    p_confirmar_impacto: confirmarImpacto,
    p_por_secretaria: porSecretaria,
  })
  if (error) throw error
  return data as RespuestaJuego
}
