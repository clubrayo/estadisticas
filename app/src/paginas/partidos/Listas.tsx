import { useState } from 'react'
import { MensajeError } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import { listarAsistencia } from '../../datos/asistencia'
import { listarJugadores } from '../../datos/jugadores'
import { crearLista, listarListas, listarModalidades, NOMBRE_ESTADO_LISTA } from '../../datos/listas'
import { ladosDelPartido } from '../../datos/partidos'
import { useCarga } from '../../hooks/useCarga'
import { mensajeDeError } from '../../lib/errores'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'
import { usePartido } from './contextoPartido'
import { EditorLista, type JugadorDisponible } from './EditorLista'

/** Pestaña Listas del partido (secciones 7, 14 y 15). */
export function Listas() {
  const { partido } = usePartido()
  const { roles } = useSesion()
  const { propio } = ladosDelPartido(partido)
  const { estado, recargar } = useCarga(async () => {
    const [listas, modalidades, jugadores, asistencia] = await Promise.all([
      listarListas(partido.id),
      listarModalidades(),
      listarJugadores(),
      listarAsistencia(partido.id),
    ])
    return { listas, modalidades, jugadores, asistencia }
  }, [partido.id])
  const [seleccion, setSeleccion] = useState<string | null>(null)
  const [creando, setCreando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const puedeOperar = tieneRol(roles, ['CAPITAN', 'DIRECTIVA'], propio.id)

  if (estado.tipo === 'cargando') return <Cargando texto="Cargando listas…" />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>

  const { listas, modalidades, jugadores, asistencia } = estado.datos
  const lista = listas.find((l) => l.id === seleccion) ?? listas[listas.length - 1]
  const hayAbierta = listas.some((l) => l.estado !== 'FINALIZADA')
  const puedeCrear = puedeOperar && partido.estado === 'EN_CURSO' && !hayAbierta

  const presentes = new Set(asistencia.filter((a) => a.estado === 'PRESENTE').map((a) => a.jugador_id))
  const delClub = jugadores.filter((j) => j.club_id === propio.id)
  const disponibles: JugadorDisponible[] = delClub
    .filter((j) => presentes.has(j.id) && j.estado === 'ACTIVO')
    .map((j) => ({ id: j.id, nombre: j.nombre_completo, apodo: j.apodo }))
  const nombres = new Map(delClub.map((j) => [j.id, j.nombre_completo]))

  async function nueva() {
    setCreando(true)
    setError(null)
    try {
      const id = await crearLista(partido.id)
      setSeleccion(id)
      recargar()
    } catch (e) {
      setError(mensajeDeError(e))
    } finally {
      setCreando(false)
    }
  }

  return (
    <div className="space-y-4">
      {listas.length > 0 && (
        <nav aria-label="Listas del partido" className="-mx-4 overflow-x-auto px-4">
          <ul className="flex gap-2">
            {listas.map((l) => (
              <li key={l.id}>
                <button
                  type="button"
                  onClick={() => setSeleccion(l.id)}
                  aria-pressed={l.id === lista?.id}
                  className={`flex min-h-12 flex-col items-center justify-center rounded-xl px-4 leading-tight whitespace-nowrap ${
                    l.id === lista?.id ? 'bg-slate-900 text-white' : 'bg-white text-slate-700 ring-1 ring-slate-300'
                  }`}
                >
                  <span className="text-sm font-bold">Lista {l.numero}</span>
                  <span className="text-[11px] opacity-80">{NOMBRE_ESTADO_LISTA[l.estado]}</span>
                </button>
              </li>
            ))}
          </ul>
        </nav>
      )}

      {error && <MensajeError>{error}</MensajeError>}

      {puedeCrear && (
        <button
          type="button"
          onClick={() => void nueva()}
          disabled={creando}
          className="min-h-12 w-full rounded-xl bg-slate-900 font-bold text-white active:bg-slate-700 disabled:opacity-50"
        >
          {creando ? 'Creando…' : `+ Crear lista N° ${listas.length + 1}`}
        </button>
      )}

      {listas.length === 0 && !puedeCrear && (
        <p className="rounded-2xl bg-white p-5 text-center text-slate-600">
          {partido.estado === 'PROGRAMADO'
            ? 'Inicie el partido para crear la primera lista.'
            : partido.estado === 'EN_CURSO'
              ? 'Aún no hay listas.'
              : 'Este partido no tiene listas.'}
        </p>
      )}

      {lista && (
        <EditorLista
          key={`${lista.id}-${lista.estado}`}
          lista={lista}
          modalidades={modalidades}
          disponibles={disponibles}
          nombres={nombres}
          puedeOperar={puedeOperar}
          alCambiarEstado={recargar}
        />
      )}
    </div>
  )
}
