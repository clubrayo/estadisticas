import { Suspense } from 'react'
import { NavLink, Outlet } from 'react-router'
import { BannerConexion } from '../componentes/BannerConexion'
import {
  IconoCalendario,
  IconoCopa,
  IconoGrafico,
  IconoInicio,
  IconoJugadores,
  IconoSalir,
} from '../componentes/Iconos'
import { Logo } from '../componentes/Marca'
import { Cargando } from '../componentes/Pantallas'
import { NOMBRE_ROL } from '../lib/roles'
import { useSesion } from '../sesion/contexto'

const SECCIONES = [
  { ruta: '/', etiqueta: 'Inicio', Icono: IconoInicio },
  { ruta: '/campeonatos', etiqueta: 'Campeonatos', Icono: IconoCopa },
  { ruta: '/partidos', etiqueta: 'Partidos', Icono: IconoCalendario },
  { ruta: '/jugadores', etiqueta: 'Jugadores', Icono: IconoJugadores },
  { ruta: '/estadisticas', etiqueta: 'Estadísticas', Icono: IconoGrafico },
]

export function LayoutPrincipal() {
  const { perfil, roles, cerrarSesion } = useSesion()
  const rolPrincipal = roles[0]

  return (
    <div className="flex min-h-dvh flex-col">
      <header className="sticky top-0 z-20 bg-slate-900 text-white">
        <div className="mx-auto flex max-w-3xl items-center gap-3 px-4 py-3">
          <Logo className="size-9 shrink-0" />
          <div className="min-w-0 flex-1">
            <p className="text-base font-extrabold leading-tight tracking-wide">CLUB RAYO</p>
            <p className="truncate text-xs text-slate-300">
              {perfil?.nombre}
              {rolPrincipal && ` · ${NOMBRE_ROL[rolPrincipal.rol]}`}
            </p>
          </div>
          <button
            onClick={() => void cerrarSesion()}
            className="flex min-h-11 items-center gap-1 rounded-lg px-3 text-sm font-semibold text-slate-200 active:bg-slate-700"
          >
            <IconoSalir className="size-5" />
            Salir
          </button>
        </div>
        <BannerConexion />
      </header>

      <main className="mx-auto w-full max-w-3xl flex-1 px-4 pt-4 pb-28">
        <Suspense fallback={<Cargando />}>
          <Outlet />
        </Suspense>
      </main>

      <nav
        aria-label="Secciones"
        className="fixed inset-x-0 bottom-0 z-20 border-t border-slate-200 bg-white pb-[env(safe-area-inset-bottom)]"
      >
        <ul className="mx-auto grid max-w-3xl grid-cols-5">
          {SECCIONES.map(({ ruta, etiqueta, Icono }) => (
            <li key={ruta}>
              <NavLink
                to={ruta}
                end={ruta === '/'}
                className={({ isActive }) =>
                  `flex min-h-16 flex-col items-center justify-center gap-1 text-[11px] font-semibold ${
                    isActive ? 'text-amber-700' : 'text-slate-500'
                  }`
                }
              >
                {({ isActive }) => (
                  <>
                    <span className={`rounded-full px-4 py-1 ${isActive ? 'bg-amber-100' : ''}`}>
                      <Icono className="size-6" />
                    </span>
                    {etiqueta}
                  </>
                )}
              </NavLink>
            </li>
          ))}
        </ul>
      </nav>
    </div>
  )
}
