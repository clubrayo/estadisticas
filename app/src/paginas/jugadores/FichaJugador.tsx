import { useState } from 'react'
import { Link, useLocation, useParams } from 'react-router'
import { IconoAtras } from '../../componentes/Iconos'
import { BotonSecundario, Confirmacion, MensajeError, MensajeExito } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import { cambiarEstadoJugador, obtenerJugador } from '../../datos/jugadores'
import { useCarga } from '../../hooks/useCarga'
import { mensajeDeError } from '../../lib/errores'
import { formatoFecha } from '../../lib/formato'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'
import { EstadisticasJugador } from './EstadisticasJugador'
import { EtiquetaEstado } from './EtiquetaEstado'

export function FichaJugador() {
  const { jugadorId = '' } = useParams()
  const { roles } = useSesion()
  const ubicacion = useLocation()
  const { estado, setEstado } = useCarga(() => obtenerJugador(jugadorId), [jugadorId])
  const [confirmando, setConfirmando] = useState(false)
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [aviso, setAviso] = useState<string | null>((ubicacion.state as { aviso?: string } | null)?.aviso ?? null)

  if (estado.tipo === 'cargando') return <Cargando />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>
  const jugador = estado.datos
  if (!jugador) {
    return (
      <div className="space-y-3">
        <MensajeError>El jugador no existe o no tiene permiso para verlo.</MensajeError>
        <Link to="/jugadores" className="font-semibold text-amber-700 underline">
          Volver a jugadores
        </Link>
      </div>
    )
  }

  const puedeEditar = tieneRol(roles, ['DIRECTIVA'], jugador.club_id)
  const activo = jugador.estado === 'ACTIVO'

  async function cambiarEstado() {
    if (!jugador) return
    setGuardando(true)
    setError(null)
    try {
      const actualizado = await cambiarEstadoJugador(jugador.id, activo ? 'INACTIVO' : 'ACTIVO')
      setEstado({ tipo: 'listo', datos: actualizado })
      setAviso(activo ? 'Jugador desactivado.' : 'Jugador reactivado.')
    } catch (e) {
      setError(mensajeDeError(e))
    } finally {
      setGuardando(false)
      setConfirmando(false)
    }
  }

  const datos: [string, string | null][] = [
    ['Primer nombre', jugador.primer_nombre],
    ['Apellidos', jugador.apellidos],
    ['Apodo', jugador.apodo],
    ['Categoría', jugador.categoria],
    ['Fecha de incorporación', jugador.fecha_incorporacion && formatoFecha(jugador.fecha_incorporacion)],
    ['Observaciones', jugador.observaciones],
  ]

  return (
    <div className="space-y-4">
      <Link to="/jugadores" className="inline-flex min-h-11 items-center gap-1 font-semibold text-slate-700">
        <IconoAtras className="size-5" />
        Jugadores
      </Link>

      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-bold">{jugador.nombre_completo}</h1>
          {jugador.apodo && <p className="text-slate-600">"{jugador.apodo}"</p>}
        </div>
        <EtiquetaEstado estado={jugador.estado} />
      </div>

      {aviso && <MensajeExito>{aviso}</MensajeExito>}
      {error && <MensajeError>{error}</MensajeError>}

      <section className="rounded-2xl bg-white p-5 shadow-sm">
        <h2 className="mb-3 font-bold">Datos</h2>
        <dl className="space-y-3">
          {datos.map(([etiqueta, valor]) => (
            <div key={etiqueta}>
              <dt className="text-xs font-semibold uppercase tracking-wide text-slate-500">{etiqueta}</dt>
              <dd className="whitespace-pre-line text-slate-900">{valor || '—'}</dd>
            </div>
          ))}
        </dl>
      </section>

      {puedeEditar && (
        <div className="space-y-2">
          <Link
            to={`/jugadores/${jugador.id}/editar`}
            className="flex min-h-12 w-full items-center justify-center rounded-xl bg-slate-900 font-bold text-white active:bg-slate-700"
          >
            Editar datos
          </Link>
          <BotonSecundario peligro={activo} onClick={() => setConfirmando(true)}>
            {activo ? 'Desactivar jugador' : 'Reactivar jugador'}
          </BotonSecundario>
        </div>
      )}

      <EstadisticasJugador jugadorId={jugador.id} />

      {confirmando && (
        <Confirmacion
          titulo={activo ? 'Desactivar jugador' : 'Reactivar jugador'}
          mensaje={
            activo ? (
              <p>
                <strong>{jugador.nombre_completo}</strong> dejará de aparecer en asistencia y listas. Su historial se
                conserva y puede reactivarse cuando quiera.
              </p>
            ) : (
              <p>
                <strong>{jugador.nombre_completo}</strong> volverá a estar disponible para asistencia y listas.
              </p>
            )
          }
          textoConfirmar={activo ? 'Sí, desactivar' : 'Sí, reactivar'}
          peligro={activo}
          ocupado={guardando}
          onConfirmar={() => void cambiarEstado()}
          onCancelar={() => setConfirmando(false)}
        />
      )}
    </div>
  )
}
