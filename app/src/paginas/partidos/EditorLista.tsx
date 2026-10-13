import { useEffect, useMemo, useState } from 'react'
import { BotonSecundario, CLASE_CAMPO, DialogoMotivo, MensajeError, MensajeExito } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import {
  confirmarLista,
  devolverListaAEdicion,
  guardarLista,
  NOMBRE_ESTADO_LISTA,
  obtenerDetalleLista,
  type DetalleLista,
  type Enfrentamiento,
  type Lista,
  type Modalidad,
  type PosicionAsignada,
} from '../../datos/listas'
import { useCarga } from '../../hooks/useCarga'
import { mensajeDeError } from '../../lib/errores'
import { usePartido } from './contextoPartido'

export interface JugadorDisponible {
  id: string
  nombre: string
  apodo: string | null
}

interface Props {
  lista: Lista
  modalidades: Modalidad[]
  /** Jugadores activos del club marcados PRESENTES en el partido. */
  disponibles: JugadorDisponible[]
  nombres: Map<string, string>
  puedeOperar: boolean
  alCambiarEstado: () => void
}

const LETRA_POSICION = ['A', 'B', 'C', 'D', 'E']
const ESTADO_ENFRENTAMIENTO: Record<string, [string, string]> = {
  PENDIENTE: ['Pendiente', 'bg-slate-100 text-slate-600'],
  DISPUTADO: ['Disputado', 'bg-green-100 text-green-800'],
  NO_DISPUTADO_FIN_PARTIDO: ['No disputado', 'bg-slate-200 text-slate-500'],
}

const clave = (enfrentamientoId: string, posicion: number) => `${enfrentamientoId}:${posicion}`

/** Carga el detalle de una lista y monta el editor con un borrador limpio en cada lectura. */
export function EditorLista(props: Props) {
  const { estado, recargar } = useCarga(() => obtenerDetalleLista(props.lista.id), [props.lista.id])
  if (estado.tipo === 'cargando') return <Cargando texto="Cargando lista…" />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>
  return <Editor key={estado.datos.leidoEn} {...props} detalle={estado.datos} recargarDetalle={recargar} />
}

function Editor({
  lista,
  modalidades,
  disponibles,
  nombres,
  puedeOperar,
  alCambiarEstado,
  detalle,
  recargarDetalle,
}: Props & { detalle: DetalleLista; recargarDetalle: () => void }) {
  const { partido } = usePartido()
  const inicial = useMemo(
    () => new Map(detalle.posiciones.map((p) => [clave(p.enfrentamiento_id, p.posicion), p.jugador_id])),
    [detalle],
  )
  const [borrador, setBorrador] = useState(inicial)
  const [hueco, setHueco] = useState<{ enfrentamiento: Enfrentamiento; posicion: number } | null>(null)
  const [pedirMotivo, setPedirMotivo] = useState<'guardar' | 'confirmar' | 'devolver' | null>(null)
  const [ocupado, setOcupado] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)

  const editable = puedeOperar && partido.estado === 'EN_CURSO' && lista.estado === 'BORRADOR'
  const devolvible = puedeOperar && partido.estado === 'EN_CURSO' && lista.estado === 'CONFIRMADA'

  const cupos = new Map(modalidades.map((m) => [m.codigo, m.jugadores_por_enfrentamiento]))
  const nombreModalidad = new Map(modalidades.map((m) => [m.codigo, m.nombre]))
  const requeridas = detalle.enfrentamientos.reduce((s, e) => s + (cupos.get(e.modalidad_codigo) ?? 0), 0)
  const etiqueta = (e: Enfrentamiento) => `${nombreModalidad.get(e.modalidad_codigo) ?? e.modalidad_codigo} ${e.numero}`

  // Dónde está asignado cada jugador en el borrador.
  const ubicacion = new Map<string, string>()
  for (const [k, jugador] of borrador) {
    const e = detalle.enfrentamientos.find((x) => x.id === k.split(':')[0])
    if (e) ubicacion.set(jugador, etiqueta(e))
  }

  const cambiosSinGuardar =
    borrador.size !== inicial.size || [...borrador].some(([k, v]) => inicial.get(k) !== v)

  // Aviso del navegador si se cierra la página con cambios sin guardar.
  useEffect(() => {
    if (!cambiosSinGuardar) return
    const avisar = (e: BeforeUnloadEvent) => e.preventDefault()
    window.addEventListener('beforeunload', avisar)
    return () => window.removeEventListener('beforeunload', avisar)
  }, [cambiosSinGuardar])

  // Jugadores que ya fueron oficiales en esta lista y se están retirando: exige motivo.
  const enBorrador = new Set(borrador.values())
  const retirados = detalle.convocatorias.filter(
    (c) => c.fue_confirmada && c.estado !== 'ANULADA_REEMPLAZO' && !enBorrador.has(c.jugador_id),
  )

  function asignar(jugadorId: string | null) {
    if (!hueco) return
    setBorrador((actual) => {
      const copia = new Map(actual)
      // Un jugador ocupa una sola posición por lista: si ya estaba en otra, se mueve.
      for (const [k, v] of copia) if (v === jugadorId) copia.delete(k)
      const k = clave(hueco.enfrentamiento.id, hueco.posicion)
      if (jugadorId) copia.set(k, jugadorId)
      else copia.delete(k)
      return copia
    })
    setHueco(null)
    setAviso(null)
  }

  function posiciones(): PosicionAsignada[] {
    return [...borrador].map(([k, jugador_id]) => {
      const [enfrentamiento_id, posicion] = k.split(':')
      return { enfrentamiento_id, posicion: Number(posicion), jugador_id }
    })
  }

  async function ejecutar(accion: 'guardar' | 'confirmar' | 'devolver', motivo?: string) {
    if ((accion !== 'devolver' && retirados.length > 0 && !motivo) || (accion === 'devolver' && !motivo)) {
      setPedirMotivo(accion)
      return
    }
    setOcupado(true)
    setError(null)
    setAviso(null)
    try {
      if (accion === 'devolver') {
        await devolverListaAEdicion(lista.id, motivo as string)
        alCambiarEstado()
        return
      }
      if (cambiosSinGuardar) await guardarLista(lista.id, posiciones(), motivo)
      if (accion === 'confirmar') {
        await confirmarLista(lista.id)
        alCambiarEstado()
        return
      }
      setAviso('Borrador guardado.')
      recargarDetalle()
    } catch (e) {
      setError(mensajeDeError(e))
    } finally {
      setOcupado(false)
      setPedirMotivo(null)
    }
  }

  return (
    <div className="space-y-4">
      <section className="space-y-2 rounded-2xl bg-white p-4 shadow-sm">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold">Lista N° {lista.numero}</h2>
          <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-bold text-slate-700">
            {NOMBRE_ESTADO_LISTA[lista.estado]}
          </span>
        </div>
        <div className="flex items-center gap-3">
          <div className="h-3 flex-1 overflow-hidden rounded-full bg-slate-200">
            <div
              className={`h-full rounded-full ${borrador.size === requeridas ? 'bg-green-600' : 'bg-amber-500'}`}
              style={{ width: `${requeridas ? (borrador.size * 100) / requeridas : 0}%` }}
            />
          </div>
          <p className="text-sm font-bold tabular-nums">
            {borrador.size} / {requeridas}
          </p>
        </div>
        <p className="text-xs text-slate-500">
          {editable
            ? `${disponibles.length} jugadores presentes disponibles.${cambiosSinGuardar ? ' Hay cambios sin guardar.' : ''}`
            : lista.estado === 'BORRADOR'
              ? 'Solo lectura.'
              : 'Composición oficial: ya no se puede modificar libremente.'}
        </p>
        {editable && disponibles.length < requeridas && (
          <p className="text-sm font-semibold text-amber-800">
            Hay solo {disponibles.length} presentes y se necesitan {requeridas}. Revise la asistencia.
          </p>
        )}
      </section>

      {aviso && <MensajeExito>{aviso}</MensajeExito>}
      {error && <MensajeError>{error}</MensajeError>}

      <ul className="space-y-2">
        {detalle.enfrentamientos.map((e) => {
          const [textoEstado, colorEstado] = ESTADO_ENFRENTAMIENTO[e.estado_codigo] ?? [e.estado_codigo, '']
          const cupo = cupos.get(e.modalidad_codigo) ?? 1
          return (
            <li key={e.id} className="space-y-2 rounded-2xl bg-white p-3 shadow-sm">
              <div className="flex items-center justify-between">
                <p className="font-bold">{etiqueta(e)}</p>
                {lista.estado !== 'BORRADOR' && (
                  <span className={`rounded-full px-2 py-0.5 text-[11px] font-bold ${colorEstado}`}>{textoEstado}</span>
                )}
              </div>
              {Array.from({ length: cupo }, (_, i) => i + 1).map((posicion) => {
                const jugador = borrador.get(clave(e.id, posicion))
                return (
                  <button
                    key={posicion}
                    type="button"
                    disabled={!editable || ocupado}
                    onClick={() => setHueco({ enfrentamiento: e, posicion })}
                    className={`flex min-h-12 w-full items-center gap-3 rounded-xl px-3 text-left ${
                      jugador ? 'bg-slate-100' : 'border-2 border-dashed border-slate-300 text-slate-500'
                    } ${editable ? 'active:bg-amber-50' : ''}`}
                  >
                    {cupo > 1 && <span className="w-4 text-xs font-bold text-slate-400">{LETRA_POSICION[posicion - 1]}</span>}
                    <span className={`truncate ${jugador ? 'font-semibold text-slate-900' : ''}`}>
                      {jugador ? (nombres.get(jugador) ?? 'Jugador') : editable ? 'Asignar jugador' : 'Sin asignar'}
                    </span>
                  </button>
                )
              })}
            </li>
          )
        })}
      </ul>

      {editable && (
        <div className="sticky bottom-20 z-10 grid grid-cols-2 gap-2 rounded-2xl bg-slate-100/95 p-2 shadow-lg backdrop-blur">
          <BotonSecundario onClick={() => void ejecutar('guardar')} disabled={ocupado || !cambiosSinGuardar}>
            {ocupado ? 'Guardando…' : 'Guardar'}
          </BotonSecundario>
          <button
            type="button"
            onClick={() => void ejecutar('confirmar')}
            disabled={ocupado || borrador.size !== requeridas}
            className="min-h-12 rounded-xl bg-green-600 font-bold text-white active:bg-green-700 disabled:bg-slate-300"
          >
            Confirmar {borrador.size}/{requeridas}
          </button>
        </div>
      )}

      {devolvible && (
        <BotonSecundario onClick={() => setPedirMotivo('devolver')} disabled={ocupado}>
          Devolver a edición (reemplazar jugador)
        </BotonSecundario>
      )}

      {hueco && (
        <SelectorJugador
          titulo={`${etiqueta(hueco.enfrentamiento)}${
            (cupos.get(hueco.enfrentamiento.modalidad_codigo) ?? 1) > 1 ? ` · Jugador ${LETRA_POSICION[hueco.posicion - 1]}` : ''
          }`}
          actual={borrador.get(clave(hueco.enfrentamiento.id, hueco.posicion)) ?? null}
          disponibles={disponibles}
          ubicacion={ubicacion}
          onElegir={asignar}
          onCerrar={() => setHueco(null)}
        />
      )}

      {pedirMotivo === 'devolver' && (
        <DialogoMotivo
          titulo="Devolver lista a edición"
          descripcion="Solo se permite antes de registrar el primer resultado de esta lista. Las convocatorias dejan de ser oficiales hasta volver a confirmar."
          textoConfirmar="Devolver a edición"
          ocupado={ocupado}
          error={error}
          onConfirmar={(motivo) => void ejecutar('devolver', motivo)}
          onCancelar={() => setPedirMotivo(null)}
        />
      )}
      {(pedirMotivo === 'guardar' || pedirMotivo === 'confirmar') && (
        <DialogoMotivo
          titulo="Reemplazo de jugadores"
          descripcion={
            <p>
              Se retira de la lista a <strong>{retirados.map((r) => nombres.get(r.jugador_id) ?? 'Jugador').join(', ')}</strong>,
              que ya estaba{retirados.length > 1 ? 'n' : ''} convocado{retirados.length > 1 ? 's' : ''}. No recibirá
              {retirados.length > 1 ? 'n' : ''} el punto de convocatoria de esta lista.
            </p>
          }
          textoConfirmar={pedirMotivo === 'confirmar' ? 'Reemplazar y confirmar' : 'Reemplazar y guardar'}
          ocupado={ocupado}
          error={error}
          onConfirmar={(motivo) => void ejecutar(pedirMotivo, motivo)}
          onCancelar={() => setPedirMotivo(null)}
        />
      )}
    </div>
  )
}

function SelectorJugador({
  titulo,
  actual,
  disponibles,
  ubicacion,
  onElegir,
  onCerrar,
}: {
  titulo: string
  actual: string | null
  disponibles: JugadorDisponible[]
  ubicacion: Map<string, string>
  onElegir: (jugadorId: string | null) => void
  onCerrar: () => void
}) {
  const [busqueda, setBusqueda] = useState('')
  const texto = busqueda.trim().toLowerCase()
  // Primero los libres, luego los ya asignados en otra posición.
  const ordenados = disponibles
    .filter((j) => `${j.nombre} ${j.apodo ?? ''}`.toLowerCase().includes(texto))
    .sort((a, b) => Number(ubicacion.has(a.id)) - Number(ubicacion.has(b.id)))

  return (
    <div className="fixed inset-0 z-40 flex items-end justify-center bg-slate-900/50 sm:items-center" role="dialog" aria-modal="true" aria-label={titulo}>
      <div className="flex max-h-[85dvh] w-full max-w-md flex-col rounded-t-2xl bg-white sm:rounded-2xl">
        <div className="space-y-3 border-b border-slate-200 p-4">
          <h2 className="text-lg font-bold">{titulo}</h2>
          <input
            type="search"
            placeholder="Buscar jugador presente"
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
            className={CLASE_CAMPO}
            aria-label="Buscar jugador"
          />
        </div>
        <ul className="flex-1 space-y-1 overflow-y-auto p-2">
          {ordenados.map((j) => {
            const enOtra = ubicacion.get(j.id)
            const esActual = j.id === actual
            return (
              <li key={j.id}>
                <button
                  type="button"
                  onClick={() => onElegir(j.id)}
                  className={`flex min-h-12 w-full items-center justify-between gap-3 rounded-xl px-3 text-left ${
                    esActual ? 'bg-amber-100' : 'active:bg-slate-100'
                  }`}
                >
                  <span className="min-w-0">
                    <span className="block truncate font-semibold">{j.nombre}</span>
                    {j.apodo && <span className="block truncate text-xs text-slate-500">"{j.apodo}"</span>}
                  </span>
                  {enOtra && !esActual && (
                    <span className="shrink-0 text-xs text-slate-500">En {enOtra} · mover</span>
                  )}
                </button>
              </li>
            )
          })}
          {ordenados.length === 0 && <li className="p-4 text-center text-slate-500">Ningún jugador presente coincide.</li>}
        </ul>
        <div className="grid grid-cols-2 gap-2 border-t border-slate-200 p-3">
          <BotonSecundario onClick={() => onElegir(null)} disabled={!actual} peligro>
            Quitar
          </BotonSecundario>
          <BotonSecundario onClick={onCerrar}>Cerrar</BotonSecundario>
        </div>
      </div>
    </div>
  )
}
