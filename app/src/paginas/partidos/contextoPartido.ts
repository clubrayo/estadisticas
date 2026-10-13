import { useOutletContext } from 'react-router'
import type { Partido } from '../../datos/partidos'

/** Datos del partido que el marco del partido comparte con sus pestañas. */
export interface ContextoPartido {
  partido: Partido
  recargar: () => void
}

export const usePartido = () => useOutletContext<ContextoPartido>()
