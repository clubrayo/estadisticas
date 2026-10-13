import { Link } from 'react-router'
import { ladosDelPartido, type Partido } from '../datos/partidos'
import { fechaCorta } from '../lib/formato'
import { EtiquetaPartido } from './Etiquetas'

/** Resumen de un partido en listados: fecha, rival, marcador y estado. */
export function TarjetaPartido({ partido, mostrarCampeonato = true }: { partido: Partido; mostrarCampeonato?: boolean }) {
  const { propio, rival, puntajePropio, puntajeRival, condicion } = ladosDelPartido(partido)
  const jugado = partido.estado !== 'PROGRAMADO'

  return (
    <Link
      to={`/partidos/${partido.id}`}
      className="block space-y-2 rounded-2xl bg-white px-4 py-3 shadow-sm active:bg-slate-50"
    >
      <div className="flex items-center justify-between gap-2 text-sm text-slate-600">
        <span className="truncate">
          {fechaCorta(partido.fecha)}
          {mostrarCampeonato && ` · ${partido.campeonato.nombre}`}
        </span>
        <EtiquetaPartido estado={partido.estado} />
      </div>
      <div className="flex items-center justify-between gap-3">
        <p className="min-w-0 truncate text-lg font-bold">
          {propio.nombre_corto} <span className="font-normal text-slate-500">vs</span> {rival.nombre_corto}
        </p>
        {jugado && (
          <p className="shrink-0 text-xl font-extrabold tabular-nums">
            {puntajePropio} – {puntajeRival}
          </p>
        )}
      </div>
      <p className="truncate text-xs text-slate-500">
        {condicion}
        {partido.lugar && ` · ${partido.lugar}`}
      </p>
    </Link>
  )
}
