import type { EstadoJugador } from '../../datos/jugadores'

export function EtiquetaEstado({ estado }: { estado: EstadoJugador }) {
  return (
    <span
      className={`shrink-0 rounded-full px-3 py-1 text-xs font-bold ${
        estado === 'ACTIVO' ? 'bg-green-100 text-green-800' : 'bg-slate-200 text-slate-600'
      }`}
    >
      {estado === 'ACTIVO' ? 'Activo' : 'Inactivo'}
    </span>
  )
}
