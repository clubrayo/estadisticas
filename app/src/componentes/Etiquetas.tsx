import { NOMBRE_ESTADO_CAMPEONATO, type EstadoCampeonato } from '../datos/campeonatos'
import type { EstadoPartido } from '../datos/partidos'

const ESTILO_BASE = 'shrink-0 rounded-full px-3 py-1 text-xs font-bold'

const PARTIDO: Record<EstadoPartido, [string, string]> = {
  PROGRAMADO: ['Programado', 'bg-sky-100 text-sky-800'],
  EN_CURSO: ['En curso', 'bg-green-600 text-white'],
  SUSPENDIDO: ['Suspendido', 'bg-amber-100 text-amber-800'],
  FINALIZADO: ['Finalizado', 'bg-slate-800 text-white'],
  EN_REVISION: ['En revisión', 'bg-purple-100 text-purple-800'],
  CANCELADO: ['Cancelado', 'bg-slate-200 text-slate-600 line-through'],
}

const COLOR_CAMPEONATO: Record<EstadoCampeonato, string> = {
  PROGRAMADO: 'bg-sky-100 text-sky-800',
  EN_CURSO: 'bg-green-100 text-green-800',
  FINALIZADO: 'bg-slate-800 text-white',
  CANCELADO: 'bg-slate-200 text-slate-600',
}

export function EtiquetaPartido({ estado }: { estado: EstadoPartido }) {
  const [texto, color] = PARTIDO[estado]
  return <span className={`${ESTILO_BASE} ${color}`}>{texto}</span>
}

export function EtiquetaCampeonato({ estado }: { estado: EstadoCampeonato }) {
  return <span className={`${ESTILO_BASE} ${COLOR_CAMPEONATO[estado]}`}>{NOMBRE_ESTADO_CAMPEONATO[estado]}</span>
}
