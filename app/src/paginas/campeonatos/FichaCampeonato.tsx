import { Link, useLocation, useParams } from 'react-router'
import { EtiquetaCampeonato } from '../../componentes/Etiquetas'
import { MensajeError, MensajeExito } from '../../componentes/Formulario'
import { IconoAtras } from '../../componentes/Iconos'
import { Cargando } from '../../componentes/Pantallas'
import { TarjetaPartido } from '../../componentes/TarjetaPartido'
import { obtenerCampeonato } from '../../datos/campeonatos'
import { ladosDelPartido, listarPartidos } from '../../datos/partidos'
import { useCarga } from '../../hooks/useCarga'
import { formatoFecha } from '../../lib/formato'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'

export function FichaCampeonato() {
  const { campeonatoId = '' } = useParams()
  const { roles } = useSesion()
  const aviso = (useLocation().state as { aviso?: string } | null)?.aviso
  const { estado } = useCarga(
    async () => ({ campeonato: await obtenerCampeonato(campeonatoId), partidos: await listarPartidos(campeonatoId) }),
    [campeonatoId],
  )

  if (estado.tipo === 'cargando') return <Cargando />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>
  const { campeonato, partidos } = estado.datos
  if (!campeonato) return <MensajeError>El campeonato no existe.</MensajeError>

  const ganados = partidos.filter(
    (p) => p.estado === 'FINALIZADO' && p.ganador_club_id === ladosDelPartido(p).propio.id,
  ).length
  const finalizados = partidos.filter((p) => p.estado === 'FINALIZADO').length

  return (
    <div className="space-y-4">
      <Link to="/campeonatos" className="inline-flex min-h-11 items-center gap-1 font-semibold text-slate-700">
        <IconoAtras className="size-5" />
        Campeonatos
      </Link>

      <div className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">{campeonato.nombre}</h1>
          <p className="text-slate-600">Temporada {campeonato.temporada}</p>
        </div>
        <EtiquetaCampeonato estado={campeonato.estado} />
      </div>

      {aviso && <MensajeExito>{aviso}</MensajeExito>}

      <section className="grid grid-cols-3 gap-2 text-center">
        {[
          ['Meta', campeonato.puntaje_objetivo],
          ['Partidos', partidos.length],
          ['Ganados', `${ganados}/${finalizados}`],
        ].map(([etiqueta, valor]) => (
          <div key={etiqueta} className="rounded-2xl bg-white p-3 shadow-sm">
            <p className="text-2xl font-extrabold tabular-nums">{valor}</p>
            <p className="text-xs font-semibold uppercase text-slate-500">{etiqueta}</p>
          </div>
        ))}
      </section>

      <section className="space-y-1 rounded-2xl bg-white p-5 text-sm shadow-sm">
        <p>
          <span className="font-semibold">Inicio:</span> {formatoFecha(campeonato.fecha_inicio)}
        </p>
        <p>
          <span className="font-semibold">Término:</span>{' '}
          {campeonato.fecha_termino ? formatoFecha(campeonato.fecha_termino) : '—'}
        </p>
        {campeonato.observaciones && <p className="whitespace-pre-line text-slate-700">{campeonato.observaciones}</p>}
      </section>

      <div className="flex gap-2">
        {tieneRol(roles, ['DIRECTIVA']) && ['PROGRAMADO', 'EN_CURSO'].includes(campeonato.estado) && (
          <Link
            to={`/partidos/nuevo?campeonato=${campeonato.id}`}
            className="flex min-h-12 flex-1 items-center justify-center rounded-xl bg-slate-900 font-bold text-white active:bg-slate-700"
          >
            + Nuevo partido
          </Link>
        )}
        {tieneRol(roles, []) && (
          <Link
            to={`/campeonatos/${campeonato.id}/editar`}
            className="flex min-h-12 flex-1 items-center justify-center rounded-xl border-2 border-slate-300 font-bold text-slate-800 active:bg-slate-100"
          >
            Editar
          </Link>
        )}
      </div>

      <section className="space-y-2">
        <h2 className="font-bold">Partidos</h2>
        {partidos.length === 0 && <p className="text-slate-600">Este campeonato aún no tiene partidos.</p>}
        {partidos.map((p) => (
          <TarjetaPartido key={p.id} partido={p} mostrarCampeonato={false} />
        ))}
      </section>
    </div>
  )
}
