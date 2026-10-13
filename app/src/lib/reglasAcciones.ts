/**
 * Espejo de privado.problemas_acciones() (migración 004), para avisar en
 * pantalla qué falta antes de registrar. La validación real la hace la base.
 */
export interface AccionElegida {
  jugadorId: string
  tipoAccion: string
}

export function problemaAcciones({
  cupo,
  gano,
  integrantes,
  acciones,
  polaridad,
  nombre,
}: {
  /** 1 individual, 2 dupla, 3 trío. */
  cupo: number
  gano: boolean
  integrantes: string[]
  acciones: AccionElegida[]
  polaridad: (tipoAccion: string) => 'POSITIVA' | 'NEGATIVA' | undefined
  nombre: (jugadorId: string) => string
}): string | null {
  const porJugador = new Map<string, { total: number; negativas: number }>()
  let positivas = 0
  for (const a of acciones) {
    const p = polaridad(a.tipoAccion)
    if (p === 'POSITIVA') positivas++
    const actual = porJugador.get(a.jugadorId) ?? { total: 0, negativas: 0 }
    porJugador.set(a.jugadorId, {
      total: actual.total + 1,
      negativas: actual.negativas + (p === 'NEGATIVA' ? 1 : 0),
    })
  }

  for (const [id, c] of porJugador) {
    if (c.total > cupo) return `${nombre(id)} puede tener como máximo ${cupo} acciones.`
    if (c.negativas > 1) return `${nombre(id)} puede tener solo una acción negativa: su volantín cae una vez.`
  }

  if (cupo === 1) {
    if (acciones.length !== 1) return 'Elija la causa.'
    if (gano !== (positivas === 1)) return gano ? 'Una victoria requiere una causa positiva.' : 'Una derrota requiere una causa negativa.'
    return null
  }

  const conNegativa = integrantes.filter((id) => (porJugador.get(id)?.negativas ?? 0) > 0)
  if (gano) {
    if (positivas < 1) return 'Falta al menos una acción positiva (Cortó, Caída del rival o Reventón rival).'
    if (positivas > cupo) return `Como máximo ${cupo} acciones positivas: el rival tiene ${cupo} volantines.`
    if (conNegativa.length >= integrantes.length) return 'Si todos los integrantes cayeron, el equipo no pudo ganar.'
  } else {
    const faltan = integrantes.filter((id) => !conNegativa.includes(id))
    if (faltan.length > 0) return `Falta la acción negativa de ${faltan.map(nombre).join(' y ')}.`
    if (positivas >= cupo) return 'Si se eliminaron todos los volantines rivales, el equipo no pudo perder.'
  }
  return null
}
