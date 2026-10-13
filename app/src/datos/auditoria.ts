import { supabase } from '../lib/supabase'

/** Fila de la tabla auditoria (migración 002). Solo ADMINISTRADOR puede leerla. */
export interface RegistroAuditoria {
  id: number
  ocurrido_at: string
  usuario_email: string | null
  origen: 'APP' | 'SISTEMA'
  accion: string
  operacion: 'INSERT' | 'UPDATE' | 'DELETE'
  tabla: string
  registro_id: string | null
  partido_id: string | null
  valor_anterior: Record<string, unknown> | null
  valor_nuevo: Record<string, unknown> | null
  motivo: string | null
  txid: number
}

/** Una operación = todas las filas que escribió una misma transacción (una acción del usuario). */
export interface Operacion {
  clave: string
  accion: string
  ocurrido_at: string
  usuario_email: string | null
  origen: 'APP' | 'SISTEMA'
  motivo: string | null
  partido_id: string | null
  cambios: RegistroAuditoria[]
}

export interface FiltroAuditoria {
  partidoId: string | null
  accion: string
  desde: string
}

/** Filas por consulta. La última transacción puede quedar incompleta: se descarta y se pide en la siguiente página. */
const POR_PAGINA = 400

export const NOMBRE_ACCION: Record<string, string> = {
  INICIAR_PARTIDO: 'Inicio de partido',
  SUSPENDER_PARTIDO: 'Suspensión de partido',
  REANUDAR_PARTIDO: 'Reanudación de partido',
  CANCELAR_PARTIDO: 'Cancelación de partido',
  REABRIR_PARTIDO: 'Reapertura de partido',
  CERRAR_REVISION: 'Cierre de revisión',
  REGISTRAR_ASISTENCIA: 'Registro de asistencia',
  CREAR_LISTA: 'Creación de lista',
  GUARDAR_LISTA: 'Modificación de lista / cambio de jugadores',
  CONFIRMAR_LISTA: 'Confirmación de lista',
  DEVOLVER_LISTA_A_EDICION: 'Lista devuelta a edición',
  REGISTRAR_RESULTADO: 'Registro de resultado',
  CORREGIR_RESULTADO: 'Corrección de resultado',
  ACTIVAR_REGLAS: 'Cambio de reglas de puntuación',
  INSERT: 'Creación directa',
  UPDATE: 'Edición directa',
  DELETE: 'Eliminación directa',
}

export const NOMBRE_TABLA: Record<string, string> = {
  partidos: 'Partido',
  asistencias: 'Asistencia',
  listas_juego: 'Lista',
  convocatorias: 'Convocatoria',
  enfrentamientos: 'Enfrentamiento',
  participantes_enfrentamiento: 'Posición en la lista',
  resultados_enfrentamiento: 'Resultado',
  acciones_resultado: 'Acción',
  jugadores: 'Jugador',
  campeonatos: 'Campeonato',
  clubes: 'Club',
  configuracion: 'Configuración',
  reglas_puntuacion_versiones: 'Versión de reglas',
  reglas_puntuacion_valores: 'Valor de regla',
  perfiles: 'Usuario',
  usuario_roles: 'Rol de usuario',
}

export async function listarAuditoria(
  filtro: FiltroAuditoria,
  antesDe: number | null,
): Promise<{ operaciones: Operacion[]; siguiente: number | null }> {
  let consulta = supabase
    .from('auditoria')
    .select(
      'id, ocurrido_at, usuario_email, origen, accion, operacion, tabla, registro_id, partido_id, valor_anterior, valor_nuevo, motivo, txid',
    )
    .order('id', { ascending: false })
    .limit(POR_PAGINA)
  if (filtro.partidoId) consulta = consulta.eq('partido_id', filtro.partidoId)
  if (filtro.accion) consulta = consulta.eq('accion', filtro.accion)
  if (filtro.desde) consulta = consulta.gte('ocurrido_at', new Date(`${filtro.desde}T00:00:00`).toISOString())
  if (antesDe !== null) consulta = consulta.lt('id', antesDe)
  const { data, error } = await consulta
  if (error) throw error
  const filas = data as RegistroAuditoria[]

  const operaciones: Operacion[] = []
  for (const f of filas) {
    const clave = `${f.txid}-${f.accion}`
    const ultima = operaciones.at(-1)
    if (ultima && ultima.clave === clave) {
      ultima.cambios.push(f)
      ultima.motivo ??= f.motivo
      ultima.partido_id ??= f.partido_id
    } else {
      operaciones.push({
        clave,
        accion: f.accion,
        ocurrido_at: f.ocurrido_at,
        usuario_email: f.usuario_email,
        origen: f.origen,
        motivo: f.motivo,
        partido_id: f.partido_id,
        cambios: [f],
      })
    }
  }

  // Página llena: la última operación puede continuar en la siguiente página.
  if (filas.length === POR_PAGINA && operaciones.length > 1) {
    const incompleta = operaciones.pop() as Operacion
    return { operaciones, siguiente: Math.max(...incompleta.cambios.map((c) => c.id)) + 1 }
  }
  return { operaciones, siguiente: filas.length === POR_PAGINA ? filas[filas.length - 1].id : null }
}

/** Campos que no aportan al leer un cambio. */
const IGNORAR = new Set(['id', 'created_at', 'updated_at', 'version'])

/** Campos que cambiaron (UPDATE) o que se escribieron (INSERT/DELETE), sin los técnicos. */
export function camposDelCambio(c: RegistroAuditoria): { campo: string; antes: unknown; despues: unknown }[] {
  const antes = c.valor_anterior ?? {}
  const despues = c.valor_nuevo ?? {}
  const campos = new Set([...Object.keys(antes), ...Object.keys(despues)])
  return [...campos]
    .filter((k) => !IGNORAR.has(k))
    .filter((k) => JSON.stringify(antes[k]) !== JSON.stringify(despues[k]))
    .filter((k) => c.operacion !== 'INSERT' || (despues[k] !== null && despues[k] !== false))
    .map((k) => ({ campo: k, antes: antes[k], despues: despues[k] }))
}
