import type { AccionEntrada, EnfrentamientoJuego, EstadoJuego, TipoAccion } from '../../datos/juego'
import type { Modalidad } from '../../datos/listas'
import { problemaAcciones } from '../../lib/reglasAcciones'
import type { Eleccion } from './AsistenteResultado'

/** Catálogos que la pestaña Juego necesita para mostrar nombres. */
export interface Catalogos {
  tipos: TipoAccion[]
  modalidades: Modalidad[]
  nombres: Map<string, string>
}

/** "Dupla 2", "Trío 1", "Individual 4". */
export function etiquetaEnfrentamiento(e: EnfrentamientoJuego, modalidades: Modalidad[]) {
  return `${modalidades.find((m) => m.codigo === e.modalidad_codigo)?.nombre ?? e.modalidad_codigo} ${e.numero}`
}

/** Agrupa acciones por jugador: "Christian Campos: Cortó ×2 · Antonio Toro: Lo cortaron". */
export function textoAcciones(acciones: { jugadorId: string; tipoAccion: string }[], catalogos: Catalogos) {
  const porJugador = new Map<string, Map<string, number>>()
  for (const a of acciones) {
    const causas = porJugador.get(a.jugadorId) ?? new Map<string, number>()
    causas.set(a.tipoAccion, (causas.get(a.tipoAccion) ?? 0) + 1)
    porJugador.set(a.jugadorId, causas)
  }
  return [...porJugador]
    .map(([jugador, causas]) => {
      const detalle = [...causas]
        .map(([codigo, veces]) => `${catalogos.tipos.find((t) => t.codigo === codigo)?.nombre ?? codigo}${veces > 1 ? ` ×${veces}` : ''}`)
        .join(', ')
      return `${catalogos.nombres.get(jugador) ?? 'Jugador'}: ${detalle}`
    })
    .join(' · ')
}

/** "GANÓ · Christian Campos: Cortó ×2" o "GANÓ por secretaría". */
export function textoEleccion(eleccion: Eleccion, catalogos: Catalogos) {
  const resultado = eleccion.resultado === 'GANADO' ? 'GANÓ' : 'PERDIÓ'
  return eleccion.porSecretaria ? `${resultado} por secretaría` : `${resultado} · ${textoAcciones(eleccion.acciones, catalogos)}`
}

export function accionesParaEnviar(eleccion: Eleccion): AccionEntrada[] {
  return eleccion.acciones.map((a) => ({ jugador_id: a.jugadorId, tipo_accion: a.tipoAccion }))
}

/** Acciones registradas de un enfrentamiento, en formato de jugador. */
export function accionesRegistradas(e: EnfrentamientoJuego) {
  return (e.resultado?.acciones ?? []).flatMap((a) => {
    const p = e.participantes.find((x) => x.id === a.participante_id)
    return p ? [{ jugadorId: p.jugador_id, tipoAccion: a.tipo_accion_codigo }] : []
  })
}

/** Problema de un resultado ya registrado (p. ej. registrado con la regla anterior a la 004). */
export function problemaRegistrado(e: EnfrentamientoJuego, propioId: string, catalogos: Catalogos) {
  if (!e.resultado || e.resultado.por_secretaria) return null
  return problemaAcciones({
    cupo: e.participantes.length,
    gano: e.resultado.ganador_club_id === propioId,
    integrantes: e.participantes.map((p) => p.jugador_id),
    acciones: accionesRegistradas(e),
    polaridad: (codigo) => catalogos.tipos.find((t) => t.codigo === codigo)?.polaridad,
    nombre: (id) => catalogos.nombres.get(id) ?? 'Jugador',
  })
}

/** Siguiente enfrentamiento a registrar: el primer PENDIENTE de una lista confirmada o en juego. */
export function siguienteEnfrentamiento(juego: EstadoJuego, estadoPartido: string) {
  if (estadoPartido !== 'EN_CURSO') return undefined
  const estadoLista = new Map(juego.listas.map((l) => [l.id, l.estado]))
  return juego.enfrentamientos.find(
    (e) => e.estado_codigo === 'PENDIENTE' && ['CONFIRMADA', 'EN_JUEGO'].includes(estadoLista.get(e.lista_id) ?? ''),
  )
}
