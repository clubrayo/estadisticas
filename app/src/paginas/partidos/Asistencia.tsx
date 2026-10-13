import { useMemo, useState } from 'react'
import { CLASE_CAMPO, Confirmacion, MensajeError, MensajeExito } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import {
  listarAsistencia,
  listarConvocados,
  registrarAsistencia,
  type EstadoAsistencia,
} from '../../datos/asistencia'
import { listarJugadores, type Jugador } from '../../datos/jugadores'
import { ladosDelPartido } from '../../datos/partidos'
import { useCarga } from '../../hooks/useCarga'
import { mensajeDeError } from '../../lib/errores'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'
import { usePartido } from './contextoPartido'

const OPCIONES: { estado: EstadoAsistencia; letra: string; nombre: string; activo: string }[] = [
  { estado: 'PRESENTE', letra: 'P', nombre: 'Presente', activo: 'bg-green-600 text-white ring-green-600' },
  { estado: 'AUSENTE', letra: 'A', nombre: 'Ausente', activo: 'bg-red-600 text-white ring-red-600' },
  { estado: 'JUSTIFICADO', letra: 'J', nombre: 'Justificado', activo: 'bg-amber-500 text-white ring-amber-500' },
]

const ESTADOS_EDITABLES = ['PROGRAMADO', 'EN_CURSO', 'SUSPENDIDO']

/** Pestaña Asistencia del partido (sección 13). */
export function Asistencia() {
  const { partido } = usePartido()
  const { estado } = useCarga(async () => {
    const [jugadores, asistencia, convocados] = await Promise.all([
      listarJugadores(),
      listarAsistencia(partido.id),
      listarConvocados(partido.id),
    ])
    return { jugadores, asistencia, convocados }
  }, [partido.id])

  if (estado.tipo === 'cargando') return <Cargando texto="Cargando asistencia…" />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>

  return (
    <Registro
      key={partido.id}
      jugadores={estado.datos.jugadores}
      inicial={new Map(estado.datos.asistencia.map((a) => [a.jugador_id, a.estado]))}
      convocados={new Set(estado.datos.convocados)}
    />
  )
}

function Registro({
  jugadores,
  inicial,
  convocados,
}: {
  jugadores: Jugador[]
  inicial: Map<string, EstadoAsistencia>
  convocados: Set<string>
}) {
  const { partido } = usePartido()
  const { roles } = useSesion()
  const { propio } = ladosDelPartido(partido)
  const [estados, setEstados] = useState(inicial)
  const [guardando, setGuardando] = useState<Set<string>>(new Set())
  const [busqueda, setBusqueda] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const [confirmarTodos, setConfirmarTodos] = useState(false)

  const editable =
    ESTADOS_EDITABLES.includes(partido.estado) && tieneRol(roles, ['CAPITAN', 'DIRECTIVA'], propio.id)

  // Jugadores activos del club, más los que ya tienen asistencia aunque hoy estén inactivos.
  const considerados = useMemo(
    () => jugadores.filter((j) => j.club_id === propio.id && (j.estado === 'ACTIVO' || inicial.has(j.id))),
    [jugadores, propio.id, inicial],
  )
  const visibles = considerados.filter((j) =>
    `${j.nombre_completo} ${j.apodo ?? ''}`.toLowerCase().includes(busqueda.trim().toLowerCase()),
  )
  const sinMarcar = considerados.filter((j) => !estados.has(j.id))

  const resumen = useMemo(() => {
    const valores = [...estados.values()]
    const presentes = valores.filter((e) => e === 'PRESENTE').length
    return {
      total: valores.length,
      presentes,
      ausentes: valores.filter((e) => e === 'AUSENTE').length,
      justificados: valores.filter((e) => e === 'JUSTIFICADO').length,
      porcentaje: valores.length ? (presentes * 100) / valores.length : 0,
    }
  }, [estados])

  /** Guarda en el servidor y solo entonces actualiza la pantalla. */
  async function guardar(ids: string[], nuevo: EstadoAsistencia) {
    setGuardando((g) => new Set([...g, ...ids]))
    setError(null)
    setAviso(null)
    try {
      await registrarAsistencia(partido.id, ids.map((jugador_id) => ({ jugador_id, estado: nuevo })))
      setEstados((actual) => {
        const copia = new Map(actual)
        ids.forEach((id) => copia.set(id, nuevo))
        return copia
      })
      if (ids.length > 1) setAviso(`${ids.length} jugadores marcados como presentes.`)
    } catch (e) {
      setError(mensajeDeError(e))
    } finally {
      setGuardando((g) => new Set([...g].filter((id) => !ids.includes(id))))
    }
  }

  return (
    <div className="space-y-4">
      <section className="grid grid-cols-4 gap-2 text-center">
        {[
          ['Presentes', resumen.presentes, 'text-green-700'],
          ['Ausentes', resumen.ausentes, 'text-red-700'],
          ['Justif.', resumen.justificados, 'text-amber-700'],
          ['Asistencia', `${resumen.porcentaje.toLocaleString('es-CL', { maximumFractionDigits: 1 })}%`, 'text-slate-900'],
        ].map(([etiqueta, valor, color]) => (
          <div key={etiqueta} className="rounded-2xl bg-white px-1 py-3 shadow-sm">
            <p className={`text-2xl font-extrabold tabular-nums ${color}`}>{valor}</p>
            <p className="text-[11px] font-semibold uppercase text-slate-500">{etiqueta}</p>
          </div>
        ))}
      </section>
      <p className="text-sm text-slate-600">
        {resumen.total} registrados de {considerados.length} jugadores
        {sinMarcar.length > 0 && ` · ${sinMarcar.length} sin marcar`}
      </p>

      {!editable && (
        <p className="rounded-xl bg-slate-200 px-4 py-3 text-sm font-semibold text-slate-700">
          {ESTADOS_EDITABLES.includes(partido.estado)
            ? 'Solo lectura: su rol no permite registrar asistencia.'
            : 'Solo lectura: la asistencia ya no puede modificarse en este partido.'}
        </p>
      )}

      {editable && sinMarcar.length > 0 && (
        <button
          type="button"
          onClick={() => setConfirmarTodos(true)}
          disabled={guardando.size > 0}
          className="min-h-12 w-full rounded-xl bg-green-600 px-4 font-bold text-white active:bg-green-700 disabled:opacity-50"
        >
          Marcar {sinMarcar.length} sin marcar como presentes
        </button>
      )}

      {aviso && <MensajeExito>{aviso}</MensajeExito>}
      {error && <MensajeError>{error}</MensajeError>}

      {considerados.length > 8 && (
        <input
          type="search"
          placeholder="Buscar jugador"
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
          className={CLASE_CAMPO}
          aria-label="Buscar jugador"
        />
      )}

      {considerados.length === 0 && (
        <p className="rounded-2xl bg-white p-5 text-center text-slate-600">
          No hay jugadores activos en el club. Agréguelos en la sección Jugadores.
        </p>
      )}

      <ul className="space-y-2">
        {visibles.map((j) => {
          const actual = estados.get(j.id)
          const ocupado = guardando.has(j.id)
          const convocado = convocados.has(j.id)
          return (
            <li key={j.id} className="flex items-center gap-3 rounded-2xl bg-white px-3 py-2 shadow-sm">
              <div className="min-w-0 flex-1">
                <p className="truncate font-bold">{j.nombre_completo}</p>
                <p className="truncate text-xs text-slate-500">
                  {ocupado
                    ? 'Guardando…'
                    : actual
                      ? OPCIONES.find((o) => o.estado === actual)?.nombre
                      : 'Sin marcar'}
                  {convocado && ' · Convocado'}
                  {j.estado === 'INACTIVO' && ' · Inactivo'}
                </p>
              </div>
              <div className="flex shrink-0 gap-1.5" role="group" aria-label={`Asistencia de ${j.nombre_completo}`}>
                {OPCIONES.map((o) => {
                  const seleccionado = actual === o.estado
                  const bloqueado = !editable || ocupado || (convocado && o.estado !== 'PRESENTE')
                  return (
                    <button
                      key={o.estado}
                      type="button"
                      aria-label={o.nombre}
                      aria-pressed={seleccionado}
                      disabled={bloqueado}
                      onClick={() => !seleccionado && void guardar([j.id], o.estado)}
                      className={`size-12 rounded-xl text-lg font-extrabold ring-2 ${
                        seleccionado ? o.activo : 'bg-white text-slate-500 ring-slate-200'
                      } ${bloqueado && !seleccionado ? 'opacity-30' : ''} ${ocupado ? 'animate-pulse' : ''}`}
                    >
                      {o.letra}
                    </button>
                  )
                })}
              </div>
            </li>
          )
        })}
      </ul>

      <p className="text-center text-xs text-slate-500">P = Presente · A = Ausente · J = Justificado</p>

      {confirmarTodos && (
        <Confirmacion
          titulo="Marcar presentes"
          mensaje={<p>Se marcarán como presentes los {sinMarcar.length} jugadores que aún no tienen asistencia.</p>}
          textoConfirmar="Sí, marcar presentes"
          onConfirmar={() => {
            setConfirmarTodos(false)
            void guardar(
              sinMarcar.map((j) => j.id),
              'PRESENTE',
            )
          }}
          onCancelar={() => setConfirmarTodos(false)}
        />
      )}
    </div>
  )
}
