import { Link } from 'react-router'
import { MensajeError } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import { datosDelPartido, porcentaje, puntaje } from '../../datos/estadisticas'
import { listarJugadores } from '../../datos/jugadores'
import { listarModalidades } from '../../datos/listas'
import { useCarga } from '../../hooks/useCarga'
import { usePartido } from './contextoPartido'

interface FilaJugador {
  jugadorId: string
  convocatorias: number
  ej: number
  eg: number
  ep: number
  puntos: number
}

/** Pestaña Estadísticas del partido: rendimiento por jugador y por modalidad. */
export function EstadisticasPartido() {
  const { partido } = usePartido()
  const { estado } = useCarga(async () => {
    const [datos, jugadores, modalidades] = await Promise.all([
      datosDelPartido(partido.id),
      listarJugadores(),
      listarModalidades(),
    ])
    return { ...datos, nombres: new Map(jugadores.map((j) => [j.id, j.nombre_completo])), modalidades }
  }, [partido.id, partido.version])

  if (partido.estado === 'CANCELADO') {
    return <Nota>Partido cancelado: no se considera en las estadísticas.</Nota>
  }
  if (estado.tipo === 'cargando') return <Cargando texto="Calculando estadísticas…" />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>

  const { participaciones, convocatorias, nombres, modalidades } = estado.datos
  if (convocatorias.length === 0) return <Nota>Aún no hay listas confirmadas en este partido.</Nota>

  const filas = new Map<string, FilaJugador>()
  const fila = (id: string) => {
    const actual = filas.get(id) ?? { jugadorId: id, convocatorias: 0, ej: 0, eg: 0, ep: 0, puntos: 0 }
    filas.set(id, actual)
    return actual
  }
  for (const c of convocatorias) {
    const f = fila(c.jugador_id)
    f.convocatorias += 1
    f.puntos += Number(c.puntos)
  }
  for (const p of participaciones) {
    const f = fila(p.jugador_id)
    if (p.jugado) {
      f.ej += 1
      if (p.resultado === 'GANADO') f.eg += 1
      else f.ep += 1
    }
    f.puntos += Number(p.puntos_resultado) + Number(p.puntos_positivos) + Number(p.puntos_negativos)
  }
  const ordenadas = [...filas.values()].sort((a, b) => b.puntos - a.puntos || b.eg - a.eg)

  // Enfrentamientos únicos (una dupla tiene 2 participaciones pero es 1 enfrentamiento).
  const porEnfrentamiento = new Map(participaciones.filter((p) => p.jugado).map((p) => [`${p.lista_numero}-${p.orden_juego}`, p]))
  const resumenModalidad = modalidades.map((m) => {
    const jugados = [...porEnfrentamiento.values()].filter((p) => p.modalidad_codigo === m.codigo)
    const ganados = jugados.filter((p) => p.resultado === 'GANADO').length
    return { nombre: m.nombre, jugados: jugados.length, ganados, porcentaje: jugados.length ? (ganados * 100) / jugados.length : null }
  })

  return (
    <div className="space-y-4">
      <section className="grid grid-cols-3 gap-2 text-center">
        {resumenModalidad.map((m) => (
          <div key={m.nombre} className="rounded-2xl bg-white px-2 py-3 shadow-sm">
            <p className="text-xs font-bold uppercase text-slate-500">{m.nombre}</p>
            <p className="text-2xl font-extrabold tabular-nums">
              {m.ganados}/{m.jugados}
            </p>
            <p className="text-xs text-slate-600">{porcentaje(m.porcentaje === null ? null : Math.round(m.porcentaje * 10) / 10)}</p>
          </div>
        ))}
      </section>

      <section className="rounded-2xl bg-white p-4 shadow-sm">
        <h2 className="mb-2 font-bold">Jugadores</h2>
        <table className="w-full text-sm tabular-nums">
          <thead>
            <tr className="text-left text-xs uppercase text-slate-500">
              <th className="py-1 font-semibold">Jugador</th>
              <th className="py-1 text-right font-semibold" title="Listas convocado">Conv</th>
              <th className="py-1 text-right font-semibold">EJ</th>
              <th className="py-1 text-right font-semibold">EG</th>
              <th className="py-1 text-right font-semibold">EP</th>
              <th className="py-1 text-right font-semibold">Pts</th>
            </tr>
          </thead>
          <tbody>
            {ordenadas.map((f) => (
              <tr key={f.jugadorId} className="border-t border-slate-100">
                <td className="max-w-0 truncate py-2 pr-2">
                  <Link to={`/jugadores/${f.jugadorId}`} className="font-semibold underline-offset-2 active:underline">
                    {nombres.get(f.jugadorId) ?? 'Jugador'}
                  </Link>
                </td>
                <td className="py-2 text-right">{f.convocatorias}</td>
                <td className="py-2 text-right">{f.ej}</td>
                <td className="py-2 text-right">{f.eg}</td>
                <td className="py-2 text-right">{f.ep}</td>
                <td className="py-2 text-right font-bold">{puntaje(f.puntos)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="mt-2 text-xs text-slate-500">
          Pts = convocatoria + resultado + acciones de este partido. Toque un jugador para ver su ficha completa.
        </p>
      </section>
    </div>
  )
}

function Nota({ children }: { children: string }) {
  return <p className="rounded-xl bg-slate-200 px-4 py-3 text-sm font-semibold text-slate-700">{children}</p>
}
