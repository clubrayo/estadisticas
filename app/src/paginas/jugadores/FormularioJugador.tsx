import { useState, type FormEvent } from 'react'
import { Link, useNavigate, useParams } from 'react-router'
import { AreaTexto, Campo, CLASE_CAMPO, Confirmacion, MensajeError } from '../../componentes/Formulario'
import { IconoAtras } from '../../componentes/Iconos'
import { BotonPrincipal, Cargando } from '../../componentes/Pantallas'
import { listarClubesAdministrables, type ClubResumen } from '../../datos/clubes'
import {
  actualizarJugador,
  crearJugador,
  claveNombre,
  datosDesdeJugador,
  listarJugadores,
  obtenerJugador,
  type DatosJugador,
  type Jugador,
} from '../../datos/jugadores'
import { useCarga } from '../../hooks/useCarga'
import { mensajeDeError } from '../../lib/errores'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'

/** Alta (sin :jugadorId) o edición (con :jugadorId) de un jugador. */
export function FormularioJugador() {
  const { jugadorId } = useParams()
  const esNuevo = !jugadorId
  const { roles } = useSesion()

  const { estado } = useCarga(async () => {
    const [jugador, clubes, existentes] = await Promise.all([
      jugadorId ? obtenerJugador(jugadorId) : Promise.resolve(null),
      listarClubesAdministrables(roles),
      listarJugadores(),
    ])
    return { jugador, clubes, existentes }
  }, [jugadorId, roles])

  if (estado.tipo === 'cargando') return <Cargando />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>

  const { jugador, clubes, existentes } = estado.datos

  if ((!esNuevo && !jugador) || !tieneRol(roles, ['DIRECTIVA'], jugador?.club_id) || clubes.length === 0) {
    return (
      <div className="space-y-3">
        <MensajeError>No tiene permiso para {esNuevo ? 'crear' : 'editar'} jugadores.</MensajeError>
        <Link to="/jugadores" className="font-semibold text-amber-700 underline">
          Volver a jugadores
        </Link>
      </div>
    )
  }

  return <Edicion key={jugador?.id ?? 'nuevo'} jugador={jugador} clubes={clubes} existentes={existentes} />
}

function Edicion({
  jugador,
  clubes,
  existentes,
}: {
  jugador: Jugador | null
  clubes: ClubResumen[]
  existentes: Jugador[]
}) {
  const esNuevo = !jugador
  const navegar = useNavigate()
  const volverA = jugador ? `/jugadores/${jugador.id}` : '/jugadores'
  const [datos, setDatos] = useState<DatosJugador>(() => datosDesdeJugador(jugador))
  const [clubId, setClubId] = useState(jugador?.club_id ?? clubes[0]?.id ?? '')
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [confirmarHomonimo, setConfirmarHomonimo] = useState(false)

  const categorias = [...new Set(existentes.map((j) => j.categoria).filter(Boolean))] as string[]
  const claveNueva = claveNombre(`${datos.primer_nombre} ${datos.apellidos}`)
  // Al editar solo se advierte si el nombre cambió; si no, se avisaría en cada edición.
  const nombreCambio = !jugador || claveNueva !== claveNombre(jugador.nombre_completo)
  const homonimo = nombreCambio
    ? existentes.find((j) => j.id !== jugador?.id && j.club_id === clubId && claveNombre(j.nombre_completo) === claveNueva)
    : undefined

  const cambiar = (campo: keyof DatosJugador) => (e: { target: { value: string } }) =>
    setDatos((d) => ({ ...d, [campo]: e.target.value }))

  function enviar(e: FormEvent) {
    e.preventDefault()
    if (guardando) return
    if (!datos.primer_nombre.trim() || !datos.apellidos.trim()) {
      setError('Primer nombre y apellidos son obligatorios.')
      return
    }
    if (homonimo) {
      setConfirmarHomonimo(true)
      return
    }
    void guardar()
  }

  async function guardar() {
    setConfirmarHomonimo(false)
    setGuardando(true)
    setError(null)
    try {
      const guardado = jugador ? await actualizarJugador(jugador.id, datos) : await crearJugador(clubId, datos)
      navegar(`/jugadores/${guardado.id}`, {
        replace: true,
        state: { aviso: jugador ? 'Cambios guardados.' : 'Jugador creado.' },
      })
    } catch (err) {
      setError(mensajeDeError(err))
      setGuardando(false)
    }
  }

  return (
    <div className="space-y-4">
      <Link to={volverA} className="inline-flex min-h-11 items-center gap-1 font-semibold text-slate-700">
        <IconoAtras className="size-5" />
        {jugador ? jugador.nombre_completo : 'Jugadores'}
      </Link>

      <h1 className="text-2xl font-bold">{esNuevo ? 'Nuevo jugador' : 'Editar jugador'}</h1>

      <form onSubmit={enviar} className="space-y-4" noValidate>
        {esNuevo && clubes.length > 1 && (
          <label className="block space-y-1">
            <span className="text-sm font-semibold text-slate-700">Club</span>
            <select value={clubId} onChange={(e) => setClubId(e.target.value)} className={CLASE_CAMPO}>
              {clubes.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nombre}
                </option>
              ))}
            </select>
          </label>
        )}

        <Campo etiqueta="Primer nombre" required autoComplete="off" value={datos.primer_nombre} onChange={cambiar('primer_nombre')} />
        <Campo etiqueta="Apellidos" required autoComplete="off" value={datos.apellidos} onChange={cambiar('apellidos')} />
        {homonimo && (
          <p className="rounded-xl bg-amber-50 px-4 py-3 text-sm font-semibold text-amber-800">
            Ya existe un jugador con ese nombre ({homonimo.estado === 'ACTIVO' ? 'activo' : 'inactivo'}). Verifique
            que no sea la misma persona antes de guardar.
          </p>
        )}
        <Campo etiqueta="Apodo" autoComplete="off" value={datos.apodo} onChange={cambiar('apodo')} />
        <Campo
          etiqueta="Categoría"
          autoComplete="off"
          list="categorias-existentes"
          value={datos.categoria}
          onChange={cambiar('categoria')}
          ayuda="Opcional."
        />
        <datalist id="categorias-existentes">
          {categorias.map((c) => (
            <option key={c} value={c} />
          ))}
        </datalist>
        <Campo
          etiqueta="Fecha de incorporación"
          type="date"
          value={datos.fecha_incorporacion}
          onChange={cambiar('fecha_incorporacion')}
        />
        <AreaTexto etiqueta="Observaciones" value={datos.observaciones} onChange={cambiar('observaciones')} />

        {error && <MensajeError>{error}</MensajeError>}

        <BotonPrincipal type="submit" disabled={guardando}>
          {guardando ? 'Guardando…' : esNuevo ? 'Crear jugador' : 'Guardar cambios'}
        </BotonPrincipal>
      </form>

      {confirmarHomonimo && homonimo && (
        <Confirmacion
          titulo="Nombre repetido"
          mensaje={
            <p>
              Ya existe <strong>{homonimo.nombre_completo}</strong>
              {homonimo.apodo ? ` ("${homonimo.apodo}")` : ''}, {homonimo.estado === 'ACTIVO' ? 'activo' : 'inactivo'}.
              ¿Es otra persona con el mismo nombre?
            </p>
          }
          textoConfirmar={esNuevo ? 'Sí, es otra persona: crear' : 'Sí, es otra persona: guardar'}
          onConfirmar={() => void guardar()}
          onCancelar={() => setConfirmarHomonimo(false)}
        />
      )}
    </div>
  )
}
