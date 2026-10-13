import { useState, type FormEvent } from 'react'
import { Link, useNavigate, useParams } from 'react-router'
import { AreaTexto, Campo, MensajeError, Selector } from '../../componentes/Formulario'
import { IconoAtras } from '../../componentes/Iconos'
import { BotonPrincipal, Cargando } from '../../componentes/Pantallas'
import {
  actualizarCampeonato,
  crearCampeonato,
  datosDesdeCampeonato,
  NOMBRE_ESTADO_CAMPEONATO,
  obtenerCampeonato,
  validarCampeonato,
  type Campeonato,
  type DatosCampeonato,
  type EstadoCampeonato,
} from '../../datos/campeonatos'
import { useCarga } from '../../hooks/useCarga'
import { mensajeDeError } from '../../lib/errores'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'

/** Alta o edición de un campeonato (solo ADMINISTRADOR). */
export function FormularioCampeonato() {
  const { campeonatoId } = useParams()
  const { roles } = useSesion()
  const { estado } = useCarga(
    () => (campeonatoId ? obtenerCampeonato(campeonatoId) : Promise.resolve(null)),
    [campeonatoId],
  )

  if (!tieneRol(roles, [])) {
    return <MensajeError>Solo un administrador puede crear o editar campeonatos.</MensajeError>
  }
  if (estado.tipo === 'cargando') return <Cargando />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>
  if (campeonatoId && !estado.datos) return <MensajeError>El campeonato no existe.</MensajeError>

  return <Edicion key={campeonatoId ?? 'nuevo'} campeonato={estado.datos} />
}

function Edicion({ campeonato }: { campeonato: Campeonato | null }) {
  const navegar = useNavigate()
  const [datos, setDatos] = useState<DatosCampeonato>(() => datosDesdeCampeonato(campeonato))
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const cambiar = (campo: keyof DatosCampeonato) => (e: { target: { value: string } }) =>
    setDatos((d) => ({ ...d, [campo]: e.target.value }))

  async function guardar(e: FormEvent) {
    e.preventDefault()
    if (guardando) return
    const problema = validarCampeonato(datos)
    if (problema) {
      setError(problema)
      return
    }
    setGuardando(true)
    setError(null)
    try {
      const guardado = campeonato ? await actualizarCampeonato(campeonato.id, datos) : await crearCampeonato(datos)
      navegar(`/campeonatos/${guardado.id}`, {
        replace: true,
        state: { aviso: campeonato ? 'Cambios guardados.' : 'Campeonato creado.' },
      })
    } catch (err) {
      setError(mensajeDeError(err))
      setGuardando(false)
    }
  }

  return (
    <div className="space-y-4">
      <Link
        to={campeonato ? `/campeonatos/${campeonato.id}` : '/campeonatos'}
        className="inline-flex min-h-11 items-center gap-1 font-semibold text-slate-700"
      >
        <IconoAtras className="size-5" />
        {campeonato ? campeonato.nombre : 'Campeonatos'}
      </Link>

      <h1 className="text-2xl font-bold">{campeonato ? 'Editar campeonato' : 'Nuevo campeonato'}</h1>

      <form onSubmit={guardar} className="space-y-4" noValidate>
        <Campo etiqueta="Nombre" required value={datos.nombre} onChange={cambiar('nombre')} placeholder="Ej.: Campeonato por Equipos" />
        <Campo etiqueta="Temporada" required value={datos.temporada} onChange={cambiar('temporada')} placeholder="Ej.: 2026-2027" />
        <div className="grid grid-cols-2 gap-3">
          <Campo etiqueta="Inicio" type="date" required value={datos.fecha_inicio} onChange={cambiar('fecha_inicio')} />
          <Campo etiqueta="Término" type="date" value={datos.fecha_termino} onChange={cambiar('fecha_termino')} />
        </div>
        <Campo
          etiqueta="Puntaje objetivo de los partidos"
          type="number"
          inputMode="numeric"
          min={1}
          required
          value={datos.puntaje_objetivo}
          onChange={cambiar('puntaje_objetivo')}
          ayuda={
            campeonato
              ? 'Cambiarlo solo afecta a los partidos que se creen después: los existentes conservan su meta.'
              : 'Primer club en alcanzar este puntaje gana el partido.'
          }
        />
        {campeonato && (
          <Selector etiqueta="Estado" value={datos.estado} onChange={cambiar('estado')}>
            {(Object.keys(NOMBRE_ESTADO_CAMPEONATO) as EstadoCampeonato[]).map((e) => (
              <option key={e} value={e}>
                {NOMBRE_ESTADO_CAMPEONATO[e]}
              </option>
            ))}
          </Selector>
        )}
        <AreaTexto etiqueta="Observaciones" value={datos.observaciones} onChange={cambiar('observaciones')} />

        {error && <MensajeError>{error}</MensajeError>}

        <BotonPrincipal type="submit" disabled={guardando}>
          {guardando ? 'Guardando…' : campeonato ? 'Guardar cambios' : 'Crear campeonato'}
        </BotonPrincipal>
      </form>
    </div>
  )
}
