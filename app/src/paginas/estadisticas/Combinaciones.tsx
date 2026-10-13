import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { CLASE_CAMPO, MensajeError } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import { campeonatoActual, listarCampeonatos, type Campeonato } from '../../datos/campeonatos'
import { obtenerCombinaciones, type Combinacion, type ModalidadCombinada } from '../../datos/combinaciones'
import { porcentaje, puntaje } from '../../datos/estadisticas'
import { obtenerMinimoEJ } from '../../datos/ranking'
import { useCarga } from '../../hooks/useCarga'
import { NavEstadisticas, SelectorAlcance } from './Comunes'

type Clave = 'porcentaje' | 'eg' | 'ej' | 'cortes' | 'puntos_acciones'

const ORDENES: { clave: Clave; texto: string }[] = [
  { clave: 'porcentaje', texto: '% de victorias' },
  { clave: 'eg', texto: 'Enfrentamientos ganados' },
  { clave: 'ej', texto: 'Enfrentamientos jugados' },
  { clave: 'cortes', texto: 'Cortes' },
  { clave: 'puntos_acciones', texto: 'Puntaje de acciones' },
]

const TITULO: Record<ModalidadCombinada, string> = { DUPLA: 'Mejores duplas', TRIO: 'Mejores tríos' }

/** Mejores combinaciones de jugadores: duplas y tríos (sección 31). */
export function Combinaciones({ modalidad }: { modalidad: ModalidadCombinada }) {
  const campeonatos = useCarga(listarCampeonatos, [])
  if (campeonatos.estado.tipo === 'cargando') return <Cargando />
  if (campeonatos.estado.tipo === 'error') return <MensajeError>{campeonatos.estado.mensaje}</MensajeError>
  const vigentes = campeonatos.estado.datos.filter((c) => c.estado !== 'CANCELADO')
  return <Tablero modalidad={modalidad} campeonatos={vigentes} actual={campeonatoActual(vigentes)} />
}

function Tablero({
  modalidad,
  campeonatos,
  actual,
}: {
  modalidad: ModalidadCombinada
  campeonatos: Campeonato[]
  actual: Campeonato | null
}) {
  const [alcance, setAlcance] = useState(actual?.id ?? '')
  const [orden, setOrden] = useState<Clave>('porcentaje')
  const [jugador, setJugador] = useState('')
  const campeonatoId = alcance || null

  const { estado } = useCarga(async () => {
    const [filas, minimo] = await Promise.all([obtenerCombinaciones(modalidad, campeonatoId), obtenerMinimoEJ(campeonatoId)])
    return { filas, minimo }
  }, [modalidad, campeonatoId])

  // Jugadores que aparecen en alguna combinación del alcance, para el filtro.
  const jugadores = useMemo(() => {
    if (estado.tipo !== 'listo') return []
    const mapa = new Map<string, string>()
    for (const c of estado.datos.filas) c.integrantes.forEach((id, i) => mapa.set(id, c.nombres[i]))
    return [...mapa].sort((a, b) => a[1].localeCompare(b[1]))
  }, [estado])

  const resultado = useMemo(() => {
    if (estado.tipo !== 'listo') return null
    const { minimo } = estado.datos
    const filas = estado.datos.filas.filter((c) => !jugador || c.integrantes.includes(jugador))
    const porcentual = orden === 'porcentaje'
    // Igual que en el ranking: para el % solo clasifican las que alcanzan el mínimo de EJ.
    const clasifican = filas.filter((c) => !porcentual || c.ej >= minimo)
    const fuera = porcentual ? filas.filter((c) => c.ej < minimo) : []
    const valor = (c: Combinacion) => c[orden] ?? -Infinity
    const ordenadas = [...clasifican].sort(
      (a, b) => valor(b) - valor(a) || b.eg - a.eg || b.ej - a.ej || a.nombres.join().localeCompare(b.nombres.join()),
    )
    let ultima = 0
    const conPosicion = ordenadas.map((c, i) => {
      if (i === 0 || valor(c) !== valor(ordenadas[i - 1])) ultima = i + 1
      return { combinacion: c, posicion: ultima as number | null }
    })
    return {
      filas: [...conPosicion, ...fuera.map((c) => ({ combinacion: c, posicion: null }))],
      minimo,
      porcentual,
      fuera: fuera.length,
    }
  }, [estado, orden, jugador])

  return (
    <div className="space-y-4">
      <NavEstadisticas />
      <h1 className="text-2xl font-bold">{TITULO[modalidad]}</h1>

      <div className="grid gap-2 sm:grid-cols-3">
        <SelectorAlcance
          campeonatos={campeonatos}
          actual={actual}
          valor={alcance}
          onCambio={(v) => {
            setAlcance(v)
            setJugador('')
          }}
        />
        <select
          value={orden}
          onChange={(e) => setOrden(e.target.value as Clave)}
          className={CLASE_CAMPO}
          aria-label="Ordenar por"
        >
          {ORDENES.map((o) => (
            <option key={o.clave} value={o.clave}>
              Ordenar: {o.texto}
            </option>
          ))}
        </select>
        <select value={jugador} onChange={(e) => setJugador(e.target.value)} className={CLASE_CAMPO} aria-label="Jugador">
          <option value="">Todos los jugadores</option>
          {jugadores.map(([id, nombre]) => (
            <option key={id} value={id}>
              Con {nombre}
            </option>
          ))}
        </select>
      </div>

      {estado.tipo === 'cargando' && <Cargando texto="Calculando combinaciones…" />}
      {estado.tipo === 'error' && <MensajeError>{estado.mensaje}</MensajeError>}
      {resultado && resultado.filas.length === 0 && (
        <p className="rounded-2xl bg-white p-5 text-center text-slate-600">
          Aún no hay {modalidad === 'DUPLA' ? 'duplas' : 'tríos'} con enfrentamientos jugados en este alcance.
        </p>
      )}

      {resultado && resultado.porcentual && resultado.filas.length > 0 && (
        <p className="rounded-xl bg-amber-50 px-4 py-2 text-sm font-semibold text-amber-800">
          Para el % de victorias clasifican las combinaciones con al menos {resultado.minimo} EJ.
          {resultado.fuera > 0 && ` ${resultado.fuera} quedan al final sin posición.`}
        </p>
      )}

      <ol className="space-y-2">
        {resultado?.filas.map(({ combinacion: c, posicion }) => (
          <li
            key={c.integrantes.join()}
            className={`flex items-center gap-3 rounded-2xl bg-white p-4 shadow-sm ${posicion === null ? 'opacity-60' : ''}`}
          >
            <span className="w-8 shrink-0 text-center text-xl font-extrabold tabular-nums text-slate-500">
              {posicion ?? '—'}
            </span>
            <div className="min-w-0 flex-1">
              <p className="space-x-1 font-semibold leading-snug">
                {c.integrantes.map((id, i) => (
                  <span key={id}>
                    {i > 0 && <span className="text-slate-400">+ </span>}
                    <Link to={`/jugadores/${id}`} className="underline-offset-2 active:underline">
                      {c.nombres[i]}
                    </Link>
                  </span>
                ))}
              </p>
              <p className="text-sm text-slate-600 tabular-nums">
                EJ {c.ej} · EG {c.eg} · EP {c.ep} · Cortes {c.cortes} · Acc. {puntaje(c.puntos_acciones)}
              </p>
            </div>
            <span
              className={`shrink-0 text-right text-2xl font-extrabold tabular-nums ${
                orden === 'porcentaje' ? 'text-amber-700' : 'text-slate-800'
              }`}
            >
              {orden === 'porcentaje' ? porcentaje(c.porcentaje) : orden === 'puntos_acciones' ? puntaje(c[orden]) : c[orden]}
            </span>
          </li>
        ))}
      </ol>

      <p className="text-xs text-slate-500">
        Una combinación es el mismo grupo de jugadores, sin importar en qué posición jugó cada uno. Solo se cuentan
        enfrentamientos jugados; se excluyen partidos y campeonatos cancelados. Toque un nombre para abrir su ficha.
      </p>
    </div>
  )
}
