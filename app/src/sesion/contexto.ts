import type { Session } from '@supabase/supabase-js'
import { createContext, useContext } from 'react'
import type { RolAsignado } from '../lib/roles'

export interface Perfil {
  id: string
  email: string | null
  nombre: string
  activo: boolean
}

export interface ValorSesion {
  cargando: boolean
  sesion: Session | null
  perfil: Perfil | null
  roles: RolAsignado[]
  errorPerfil: string | null
  /** Devuelve un mensaje de error, o null si ingresó correctamente. */
  iniciarSesion: (email: string, clave: string) => Promise<string | null>
  cerrarSesion: () => Promise<void>
  reintentar: () => Promise<void>
}

export const ContextoSesion = createContext<ValorSesion | null>(null)

export function useSesion(): ValorSesion {
  const valor = useContext(ContextoSesion)
  if (!valor) {
    throw new Error('useSesion debe usarse dentro de <SesionProvider>')
  }
  return valor
}
