import type { ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router'
import { BotonPrincipal, Cargando, PantallaCentrada } from '../componentes/Pantallas'
import { useSesion } from './contexto'

/**
 * Deja pasar solo a usuarios con sesión, perfil ACTIVO y al menos un rol.
 * Es una protección de interfaz: la base de datos aplica la autorización real.
 */
export function RequiereSesion({ children }: { children: ReactNode }) {
  const { cargando, sesion, perfil, roles, errorPerfil, cerrarSesion, reintentar } = useSesion()
  const ubicacion = useLocation()

  if (cargando) {
    return <PantallaCentrada titulo="Club Rayo"><Cargando /></PantallaCentrada>
  }
  if (!sesion) {
    return <Navigate to="/ingresar" replace state={{ desde: ubicacion.pathname }} />
  }
  if (errorPerfil) {
    return (
      <PantallaCentrada titulo="No se pudo cargar su perfil">
        <p className="text-slate-600">{errorPerfil}</p>
        <div className="w-full max-w-xs space-y-3">
          <BotonPrincipal onClick={() => void reintentar()}>Reintentar</BotonPrincipal>
          <button className="min-h-12 w-full font-semibold text-slate-700" onClick={() => void cerrarSesion()}>
            Cerrar sesión
          </button>
        </div>
      </PantallaCentrada>
    )
  }
  if (!perfil?.activo || roles.length === 0) {
    return (
      <PantallaCentrada titulo={!perfil?.activo ? 'Usuario desactivado' : 'Sin rol asignado'}>
        <p className="max-w-sm text-slate-600">
          {!perfil?.activo
            ? 'Su usuario está desactivado. Contacte a un administrador del club.'
            : 'Su usuario aún no tiene permisos. Pida a un administrador que le asigne un rol.'}
        </p>
        <div className="w-full max-w-xs">
          <BotonPrincipal onClick={() => void cerrarSesion()}>Cerrar sesión</BotonPrincipal>
        </div>
      </PantallaCentrada>
    )
  }
  return <>{children}</>
}
