/** Fecha ISO (AAAA-MM-DD) en formato legible, sin desfases de zona horaria. */
export function formatoFecha(
  iso: string,
  opciones: Intl.DateTimeFormatOptions = { day: 'numeric', month: 'long', year: 'numeric' },
): string {
  return new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString('es-CL', opciones)
}

export const fechaCorta = (iso: string) =>
  formatoFecha(iso, { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' })

/** Fecha local de hoy en formato AAAA-MM-DD. */
export function hoyISO(): string {
  const d = new Date()
  const dos = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${dos(d.getMonth() + 1)}-${dos(d.getDate())}`
}

const PARTICULAS = new Set(['de', 'del', 'la', 'las', 'los', 'y', 'e', 'da', 'van', 'von'])

/**
 * Mayúscula inicial en cada palabra de un nombre ("victor cucumides" → "Victor Cucumides").
 * Respeta el resto de lo escrito (p. ej. "McDonald") y deja en minúscula las
 * partículas intermedias ("Ana de la Fuente").
 */
export function capitalizarNombre(texto: string): string {
  return texto
    .split(' ')
    .map((palabra, i) => {
      const minuscula = palabra.toLocaleLowerCase('es')
      if (i > 0 && PARTICULAS.has(minuscula)) return minuscula
      return palabra.replace(/(^|[-'])(\p{L})/gu, (_, sep: string, letra: string) => sep + letra.toLocaleUpperCase('es'))
    })
    .join(' ')
}
