import { useState, type FormEvent } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router'
import { AreaTexto, Campo, MensajeError, Selector } from '../../componentes/Formulario'
import { IconoAtras } from '../../componentes/Iconos'
import { BotonPrincipal, Cargando } from '../../componentes/Pantallas'
import { listarCampeonatos, type Campeonato } from '../../datos/campeonatos'
import { listarClubesAdministrables, listarRivales, type ClubResumen, type Rival } from '../../datos/clubes'
import { crearPartido } from '../../datos/partidos'
import { useCarga } from '../../hooks/useCarga'
import { mensajeDeError } from '../../lib/errores'
import { hoyISO } from '../../lib/formato'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'
import { FormularioRival } from './FormularioRival'

/** Alta de un partido (DIRECTIVA o ADMINISTRADOR). */
export function FormularioPartido() {
  const { roles } = useSesion()
  const { estado } = useCarga(async () => {
    const [campeonatos, propios, rivales] = await Promise.all([
      listarCampeonatos(),
      listarClubesAdministrables(roles),
      listarRivales(),
    ])
    return {
      campeonatos: campeonatos.filter((c) => c.estado === 'PROGRAMADO' || c.estado === 'EN_CURSO'),
      propios,
      rivales: rivales.filter((r) => r.estado === 'ACTIVO'),
    }
  }, [roles])

  if (!tieneRol(roles, ['DIRECTIVA'])) return <MensajeError>No tiene permiso para crear partidos.</MensajeError>
  if (estado.tipo === 'cargando') return <Cargando />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>
  if (estado.datos.campeonatos.length === 0) {
    return (
      <div className="space-y-3">
        <MensajeError>No hay campeonatos programados o en curso. Un administrador debe crear uno primero.</MensajeError>
        <Link to="/campeonatos" className="font-semibold text-amber-700 underline">
          Ir a campeonatos
        </Link>
      </div>
    )
  }
  return <Edicion {...estado.datos} />
}

function Edicion({
  campeonatos,
  propios,
  rivales: rivalesIniciales,
}: {
  campeonatos: Campeonato[]
  propios: ClubResumen[]
  rivales: Rival[]
}) {
  const navegar = useNavigate()
  const [parametros] = useSearchParams()
  const sugerido = parametros.get('campeonato')
  const [rivales, setRivales] = useState(rivalesIniciales)
  const [campeonatoId, setCampeonatoId] = useState(
    campeonatos.some((c) => c.id === sugerido) ? (sugerido as string) : campeonatos[0].id,
  )
  const [propioId, setPropioId] = useState(propios[0]?.id ?? '')
  const [rivalId, setRivalId] = useState('')
  const [esLocal, setEsLocal] = useState(true)
  const [fecha, setFecha] = useState(hoyISO())
  const [lugar, setLugar] = useState('')
  const [observaciones, setObservaciones] = useState('')
  const [nuevoRival, setNuevoRival] = useState(false)
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const campeonato = campeonatos.find((c) => c.id === campeonatoId)

  async function guardar(e: FormEvent) {
    e.preventDefault()
    if (guardando) return
    if (!campeonatoId || !propioId || !rivalId || !fecha) {
      setError('Campeonato, rival y fecha son obligatorios.')
      return
    }
    setGuardando(true)
    setError(null)
    try {
      const { id } = await crearPartido({
        campeonato_id: campeonatoId,
        fecha,
        club_local_id: esLocal ? propioId : rivalId,
        club_visitante_id: esLocal ? rivalId : propioId,
        lugar,
        observaciones,
      })
      navegar(`/partidos/${id}`, { replace: true })
    } catch (err) {
      setError(mensajeDeError(err))
      setGuardando(false)
    }
  }

  return (
    <div className="space-y-4">
      <Link to="/partidos" className="inline-flex min-h-11 items-center gap-1 font-semibold text-slate-700">
        <IconoAtras className="size-5" />
        Partidos
      </Link>

      <h1 className="text-2xl font-bold">Nuevo partido</h1>

      <form onSubmit={guardar} className="space-y-4" noValidate>
        <Selector etiqueta="Campeonato" required value={campeonatoId} onChange={(e) => setCampeonatoId(e.target.value)}>
          {campeonatos.map((c) => (
            <option key={c.id} value={c.id}>
              {c.nombre} {c.temporada}
            </option>
          ))}
        </Selector>
        {campeonato && (
          <p className="-mt-2 text-sm text-slate-600">Meta del partido: {campeonato.puntaje_objetivo} puntos.</p>
        )}

        {propios.length > 1 && (
          <Selector etiqueta="Club" value={propioId} onChange={(e) => setPropioId(e.target.value)}>
            {propios.map((c) => (
              <option key={c.id} value={c.id}>
                {c.nombre}
              </option>
            ))}
          </Selector>
        )}

        <div className="space-y-2">
          <Selector etiqueta="Rival" required value={rivalId} onChange={(e) => setRivalId(e.target.value)}>
            <option value="">Seleccione un rival…</option>
            {rivales.map((r) => (
              <option key={r.id} value={r.id}>
                {r.nombre}
              </option>
            ))}
          </Selector>
          <button type="button" onClick={() => setNuevoRival(true)} className="min-h-11 font-semibold text-amber-700 underline">
            + Agregar un rival nuevo
          </button>
        </div>

        <div className="space-y-1">
          <span className="text-sm font-semibold text-slate-700">Condición</span>
          <div className="flex gap-2" role="group" aria-label="Condición">
            {[true, false].map((local) => (
              <button
                key={String(local)}
                type="button"
                onClick={() => setEsLocal(local)}
                aria-pressed={esLocal === local}
                className={`min-h-12 flex-1 rounded-xl font-bold ${
                  esLocal === local ? 'bg-slate-900 text-white' : 'bg-white text-slate-700 ring-1 ring-slate-300'
                }`}
              >
                {local ? 'Local' : 'Visitante'}
              </button>
            ))}
          </div>
        </div>

        <Campo etiqueta="Fecha" type="date" required value={fecha} onChange={(e) => setFecha(e.target.value)} />
        <Campo etiqueta="Lugar / terreno" value={lugar} onChange={(e) => setLugar(e.target.value)} />
        <AreaTexto etiqueta="Observaciones" value={observaciones} onChange={(e) => setObservaciones(e.target.value)} />

        {error && <MensajeError>{error}</MensajeError>}

        <BotonPrincipal type="submit" disabled={guardando}>
          {guardando ? 'Guardando…' : 'Crear partido'}
        </BotonPrincipal>
      </form>

      {nuevoRival && (
        <FormularioRival
          rival={null}
          onCancelar={() => setNuevoRival(false)}
          onGuardado={(r) => {
            setRivales((lista) => [...lista, r].sort((a, b) => a.nombre.localeCompare(b.nombre)))
            setRivalId(r.id)
            setNuevoRival(false)
          }}
        />
      )}
    </div>
  )
}
