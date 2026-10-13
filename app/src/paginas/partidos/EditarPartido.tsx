import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router'
import { AreaTexto, BotonSecundario, Campo, MensajeError } from '../../componentes/Formulario'
import { BotonPrincipal } from '../../componentes/Pantallas'
import { actualizarPartido } from '../../datos/partidos'
import { mensajeDeError } from '../../lib/errores'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'
import { usePartido } from './contextoPartido'

/** Edición de datos descriptivos del partido (fecha, lugar, observaciones). */
export function EditarPartido() {
  const { partido, recargar } = usePartido()
  const { roles } = useSesion()
  const navegar = useNavigate()
  const [fecha, setFecha] = useState(partido.fecha)
  const [lugar, setLugar] = useState(partido.lugar ?? '')
  const [observaciones, setObservaciones] = useState(partido.observaciones ?? '')
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (!tieneRol(roles, ['DIRECTIVA'])) return <MensajeError>No tiene permiso para editar partidos.</MensajeError>

  async function guardar(e: FormEvent) {
    e.preventDefault()
    if (guardando || !fecha) return
    setGuardando(true)
    setError(null)
    try {
      await actualizarPartido(partido.id, fecha, lugar, observaciones)
      recargar()
      navegar(`/partidos/${partido.id}`, { replace: true })
    } catch (err) {
      setError(mensajeDeError(err))
      setGuardando(false)
    }
  }

  return (
    <form onSubmit={guardar} className="space-y-4 rounded-2xl bg-white p-5 shadow-sm" noValidate>
      <h2 className="text-lg font-bold">Editar datos del partido</h2>
      <Campo etiqueta="Fecha" type="date" required value={fecha} onChange={(e) => setFecha(e.target.value)} />
      <Campo etiqueta="Lugar / terreno" value={lugar} onChange={(e) => setLugar(e.target.value)} />
      <AreaTexto etiqueta="Observaciones" value={observaciones} onChange={(e) => setObservaciones(e.target.value)} />
      <p className="text-sm text-slate-600">
        El campeonato, los clubes y la meta no se modifican una vez creado el partido.
      </p>
      {error && <MensajeError>{error}</MensajeError>}
      <div className="space-y-2">
        <BotonPrincipal type="submit" disabled={guardando}>
          {guardando ? 'Guardando…' : 'Guardar cambios'}
        </BotonPrincipal>
        <BotonSecundario onClick={() => navegar(`/partidos/${partido.id}`)} disabled={guardando}>
          Cancelar
        </BotonSecundario>
      </div>
    </form>
  )
}
