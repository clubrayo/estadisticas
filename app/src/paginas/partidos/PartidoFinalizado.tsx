import { ladosDelPartido, type Partido } from '../../datos/partidos'

/** Aviso de cierre del partido (sección 28). */
export function PartidoFinalizado({ partido }: { partido: Partido }) {
  const { propio, rival, puntajePropio, puntajeRival } = ladosDelPartido(partido)
  const ganador = partido.ganador_club_id === propio.id ? propio : rival
  return (
    <section className="space-y-1 rounded-2xl bg-slate-900 p-5 text-center text-white">
      <p className="text-sm font-bold tracking-widest text-amber-400">
        {partido.estado === 'EN_REVISION' ? 'PARTIDO EN REVISIÓN' : 'PARTIDO FINALIZADO'}
      </p>
      <p className="text-3xl font-extrabold tabular-nums">
        {propio.nombre_corto} {puntajePropio} – {puntajeRival} {rival.nombre_corto}
      </p>
      <p className="text-sm text-slate-300">GANADOR</p>
      <p className="text-xl font-extrabold">{ganador.nombre}</p>
    </section>
  )
}
