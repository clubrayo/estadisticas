export type CodigoRol = 'ADMINISTRADOR' | 'DIRECTIVA' | 'CAPITAN' | 'CONSULTA'

export interface RolAsignado {
  rol: CodigoRol
  clubId: string | null
  club: string | null
}

export const NOMBRE_ROL: Record<CodigoRol, string> = {
  ADMINISTRADOR: 'Administrador',
  DIRECTIVA: 'Directiva',
  CAPITAN: 'Capitán',
  CONSULTA: 'Consulta',
}

/**
 * Espejo de privado.tiene_rol(): ADMINISTRADOR siempre puede; los demás roles
 * solo en su club. Sirve para mostrar u ocultar acciones: la autorización real
 * la aplica la base de datos (RLS y funciones RPC).
 */
export function tieneRol(roles: RolAsignado[], permitidos: CodigoRol[], clubId?: string): boolean {
  return roles.some(
    (r) =>
      r.rol === 'ADMINISTRADOR' ||
      (permitidos.includes(r.rol) && (clubId === undefined || r.clubId === clubId)),
  )
}
