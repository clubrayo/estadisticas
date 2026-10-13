import { NavLink } from 'react-router'
import { CLASE_CAMPO } from '../../componentes/Formulario'
import type { Campeonato } from '../../datos/campeonatos'

const VISTAS = [
  { ruta: '/estadisticas', etiqueta: 'Ranking' },
  { ruta: '/estadisticas/duplas', etiqueta: 'Duplas' },
  { ruta: '/estadisticas/trios', etiqueta: 'Tríos' },
]

/** Pestañas de la sección Estadísticas. */
export function NavEstadisticas() {
  return (
    <nav aria-label="Vistas de estadísticas" className="grid grid-cols-3 gap-1 rounded-xl bg-slate-200 p-1">
      {VISTAS.map((v) => (
        <NavLink
          key={v.ruta}
          to={v.ruta}
          end
          className={({ isActive }) =>
            `flex min-h-11 items-center justify-center rounded-lg font-bold ${
              isActive ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-600'
            }`
          }
        >
          {v.etiqueta}
        </NavLink>
      ))}
    </nav>
  )
}

/** Selector de alcance: un campeonato o el histórico (valor ''). */
export function SelectorAlcance({
  campeonatos,
  actual,
  valor,
  onCambio,
}: {
  campeonatos: Campeonato[]
  actual: Campeonato | null
  valor: string
  onCambio: (valor: string) => void
}) {
  return (
    <select value={valor} onChange={(e) => onCambio(e.target.value)} className={CLASE_CAMPO} aria-label="Campeonato">
      {campeonatos.map((c) => (
        <option key={c.id} value={c.id}>
          {c.id === actual?.id ? 'Actual: ' : ''}
          {c.nombre} {c.temporada}
        </option>
      ))}
      <option value="">Histórico (todos los campeonatos)</option>
    </select>
  )
}
