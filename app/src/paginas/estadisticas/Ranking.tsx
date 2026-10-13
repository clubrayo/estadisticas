import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router'
import { CLASE_CAMPO, MensajeError } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import { campeonatoActual, listarCampeonatos, type Campeonato } from '../../datos/campeonatos'
import { porcentaje, puntaje } from '../../datos/estadisticas'
import { obtenerMinimoEJ, obtenerRanking, type FilaRanking } from '../../datos/ranking'
import { useCarga } from '../../hooks/useCarga'
import { NavEstadisticas, SelectorAlcance } from './Comunes'

type Clave = keyof Pick<
  FilaRanking,
  | 'puntos_total'
  | 'porcentaje'
  | 'eg'
  | 'ej'
  | 'ep'
  | 'asistencias'
  | 'convocatorias'
  | 'cortes'
  | 'veces_cortado'
  | 'caidas_propias'
  | 'reventones_propios'
  | 'puntos_convocatoria'
  | 'puntos_resultado'
  | 'puntos_acciones'
>

interface Columna {
  clave: Clave
  corto: string
  largo: string
  formato?: (f: FilaRanking) => string
}

const COLUMNAS: Columna[] = [
  { clave: 'asistencias', corto: 'Asist', largo: 'Asistencias' },
  { clave: 'convocatorias', corto: 'Conv', largo: 'Convocatorias' },
  { clave: 'ej', corto: 'EJ', largo: 'Enfrentamientos jugados' },
  { clave: 'eg', corto: 'EG', largo: 'Enfrentamientos ganados' },
  { clave: 'ep', corto: 'EP', largo: 'Enfrentamientos perdidos' },
  { clave: 'porcentaje', corto: '%', largo: '% de victorias', formato: (f) => porcentaje(f.porcentaje) },
  { clave: 'cortes', corto: 'Cort', largo: 'Cortes' },
  { clave: 'veces_cortado', corto: 'Cortado', largo: 'Veces cortado' },
  { clave: 'caidas_propias', corto: 'Caída', largo: 'Caídas propias' },
  { clave: 'reventones_propios', corto: 'Rev', largo: 'Reventones propios' },
  { clave: 'puntos_convocatoria', corto: 'P.Conv', largo: 'Puntaje convocatoria', formato: (f) => puntaje(f.puntos_convocatoria) },
  { clave: 'puntos_resultado', corto: 'P.Res', largo: 'Puntaje resultado', formato: (f) => puntaje(f.puntos_resultado) },
  { clave: 'puntos_acciones', corto: 'P.Acc', largo: 'Puntaje acciones', formato: (f) => puntaje(f.puntos_acciones) },
  { clave: 'puntos_total', corto: 'Total', largo: 'Puntaje total', formato: (f) => puntaje(f.puntos_total) },
]

/** Ranking general (sección 32). */
export function Ranking() {
  const campeonatos = useCarga(listarCampeonatos, [])
  if (campeonatos.estado.tipo === 'cargando') return <Cargando />
  if (campeonatos.estado.tipo === 'error') return <MensajeError>{campeonatos.estado.mensaje}</MensajeError>
  const vigentes = campeonatos.estado.datos.filter((c) => c.estado !== 'CANCELADO')
  return <Tablero campeonatos={vigentes} actual={campeonatoActual(vigentes)} />
}

function Tablero({ campeonatos, actual }: { campeonatos: Campeonato[]; actual: Campeonato | null }) {
  const navegar = useNavigate()
  const [alcance, setAlcance] = useState(actual?.id ?? '')
  const [orden, setOrden] = useState<Clave>('puntos_total')
  const [descendente, setDescendente] = useState(true)
  const campeonatoId = alcance || null

  const { estado } = useCarga(async () => {
    const [filas, minimo] = await Promise.all([obtenerRanking(campeonatoId), obtenerMinimoEJ(campeonatoId)])
    return { filas, minimo }
  }, [campeonatoId])

  const resultado = useMemo(() => {
    if (estado.tipo !== 'listo') return null
    const { filas, minimo } = estado.datos
    const porcentual = orden === 'porcentaje'
    // En rankings porcentuales solo clasifican quienes alcanzan el mínimo de EJ.
    const clasifican = filas.filter((f) => !porcentual || f.ej >= minimo)
    const fuera = porcentual ? filas.filter((f) => f.ej < minimo) : []
    const valor = (f: FilaRanking) => Number(f[orden] ?? -Infinity)
    const ordenadas = [...clasifican].sort(
      (a, b) =>
        (descendente ? valor(b) - valor(a) : valor(a) - valor(b)) || b.puntos_total - a.puntos_total || a.jugador.localeCompare(b.jugador),
    )
    // Posición con empates compartidos (1, 2, 2, 4…).
    const posiciones = ordenadas.map((f, i) =>
      i > 0 && valor(f) === valor(ordenadas[i - 1]) ? null : i + 1,
    )
    let ultima = 1
    const conPosicion = ordenadas.map((f, i) => {
      ultima = posiciones[i] ?? ultima
      return { fila: f, posicion: ultima as number | null }
    })
    return { filas: [...conPosicion, ...fuera.map((f) => ({ fila: f, posicion: null }))], minimo, porcentual, fuera: fuera.length }
  }, [estado, orden, descendente])

  return (
    <div className="space-y-4">
      <NavEstadisticas />
      <h1 className="text-2xl font-bold">Ranking</h1>

      <div className="grid gap-2 sm:grid-cols-2">
        <SelectorAlcance campeonatos={campeonatos} actual={actual} valor={alcance} onCambio={setAlcance} />
        <div className="flex gap-2">
          <select
            value={orden}
            onChange={(e) => {
              setOrden(e.target.value as Clave)
              setDescendente(true)
            }}
            className={CLASE_CAMPO}
            aria-label="Ordenar por"
          >
            {[...COLUMNAS].reverse().map((c) => (
              <option key={c.clave} value={c.clave}>
                Ordenar: {c.largo}
              </option>
            ))}
          </select>
          <button
            type="button"
            onClick={() => setDescendente((d) => !d)}
            className="min-h-12 shrink-0 rounded-xl bg-white px-4 font-bold ring-1 ring-slate-300"
            aria-label={descendente ? 'Mayor primero' : 'Menor primero'}
          >
            {descendente ? '↓' : '↑'}
          </button>
        </div>
      </div>

      {estado.tipo === 'cargando' && <Cargando texto="Calculando ranking…" />}
      {estado.tipo === 'error' && <MensajeError>{estado.mensaje}</MensajeError>}
      {resultado && resultado.filas.length === 0 && (
        <p className="rounded-2xl bg-white p-5 text-center text-slate-600">Aún no hay estadísticas en este alcance.</p>
      )}

      {resultado && resultado.porcentual && (
        <p className="rounded-xl bg-amber-50 px-4 py-2 text-sm font-semibold text-amber-800">
          Para el % de victorias clasifican quienes tienen al menos {resultado.minimo} EJ.
          {resultado.fuera > 0 && ` ${resultado.fuera} jugador(es) quedan al final sin posición.`}
        </p>
      )}

      {resultado && resultado.filas.length > 0 && (
        <div className="-mx-4 overflow-x-auto px-4">
          <table className="w-max min-w-full border-separate border-spacing-0 rounded-2xl bg-white text-sm tabular-nums shadow-sm">
            <thead>
              <tr className="text-xs uppercase text-slate-500">
                <th className="sticky left-0 z-10 rounded-tl-2xl bg-white px-2 py-2 text-left">#</th>
                <th className="sticky left-8 z-10 bg-white px-2 py-2 text-left">Jugador</th>
                {COLUMNAS.map((c) => (
                  <th
                    key={c.clave}
                    title={c.largo}
                    className={`px-2 py-2 text-right ${c.clave === orden ? 'text-amber-700' : ''}`}
                  >
                    <button type="button" onClick={() => (c.clave === orden ? setDescendente((d) => !d) : setOrden(c.clave))}>
                      {c.corto}
                      {c.clave === orden ? (descendente ? ' ↓' : ' ↑') : ''}
                    </button>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {resultado.filas.map(({ fila, posicion }) => (
                <tr
                  key={fila.jugador_id}
                  onClick={() => navegar(`/jugadores/${fila.jugador_id}`)}
                  className={`cursor-pointer active:bg-amber-50 ${posicion === null ? 'text-slate-400' : ''}`}
                >
                  <td className="sticky left-0 z-10 border-t border-slate-100 bg-white px-2 py-2 font-bold">{posicion ?? '—'}</td>
                  <td className="sticky left-8 z-10 max-w-36 truncate border-t border-slate-100 bg-white px-2 py-2 font-semibold">
                    {fila.jugador}
                    {fila.estado === 'INACTIVO' && <span className="ml-1 text-xs text-slate-400">(inactivo)</span>}
                  </td>
                  {COLUMNAS.map((c) => (
                    <td
                      key={c.clave}
                      className={`border-t border-slate-100 px-2 py-2 text-right ${
                        c.clave === orden ? 'bg-amber-50 font-bold' : c.clave === 'puntos_total' ? 'font-bold' : ''
                      }`}
                    >
                      {c.formato ? c.formato(fila) : fila[c.clave]}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <p className="text-xs text-slate-500">
        Deslice la tabla hacia los lados para ver todas las columnas. Toque un encabezado para ordenar o un jugador para abrir su
        ficha. Se excluyen partidos y campeonatos cancelados.
      </p>
    </div>
  )
}
