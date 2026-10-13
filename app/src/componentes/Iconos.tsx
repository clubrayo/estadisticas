import type { SVGProps } from 'react'

type PropsIcono = SVGProps<SVGSVGElement>

function Icono({ children, ...props }: PropsIcono) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...props}
    >
      {children}
    </svg>
  )
}

export const IconoRayo = (p: PropsIcono) => (
  <Icono {...p} fill="currentColor" stroke="none">
    <path d="M13.5 2 4 14h6l-1 8 9.5-12H12z" />
  </Icono>
)

export const IconoInicio = (p: PropsIcono) => (
  <Icono {...p}>
    <path d="M3 11 12 4l9 7" />
    <path d="M5 10v10h14V10" />
  </Icono>
)

export const IconoCopa = (p: PropsIcono) => (
  <Icono {...p}>
    <path d="M8 4h8v5a4 4 0 0 1-8 0z" />
    <path d="M8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4" />
    <path d="M12 13v4M8 20h8" />
  </Icono>
)

export const IconoCalendario = (p: PropsIcono) => (
  <Icono {...p}>
    <rect x="4" y="5" width="16" height="15" rx="2" />
    <path d="M4 10h16M9 3v4M15 3v4" />
  </Icono>
)

export const IconoJugadores = (p: PropsIcono) => (
  <Icono {...p}>
    <circle cx="9" cy="8" r="3" />
    <path d="M3 20a6 6 0 0 1 12 0" />
    <circle cx="17" cy="9" r="2.5" />
    <path d="M16 14a5 5 0 0 1 5 6" />
  </Icono>
)

export const IconoGrafico = (p: PropsIcono) => (
  <Icono {...p}>
    <path d="M4 20V4M4 20h16" />
    <path d="M8 16v-4M12 16V8M16 16v-6" />
  </Icono>
)

export const IconoSalir = (p: PropsIcono) => (
  <Icono {...p}>
    <path d="M15 4h4v16h-4" />
    <path d="M10 8l-4 4 4 4M6 12h10" />
  </Icono>
)

export const IconoAtras = (p: PropsIcono) => (
  <Icono {...p}>
    <path d="M15 5l-7 7 7 7" />
  </Icono>
)

export const IconoSinSenal = (p: PropsIcono) => (
  <Icono {...p}>
    <path d="M3 3l18 18" />
    <path d="M8.5 16.5a5 5 0 0 1 7 0M5 13a10 10 0 0 1 5-2.7M14 10.3A10 10 0 0 1 19 13" />
    <path d="M12 20h.01" />
  </Icono>
)
