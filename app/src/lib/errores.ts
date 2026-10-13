/**
 * Traduce errores de Supabase a mensajes para el usuario.
 * Las funciones RPC (migración 003) ya devuelven mensajes en español y un
 * código estable en `hint` (p. ej. ORDEN_DE_JUEGO); aquí se tratan los casos
 * que no vienen de esas funciones: red, autenticación y permisos.
 */
interface ErrorConCodigo {
  message?: string
  code?: string
  hint?: string
  status?: number
}

function comoError(error: unknown): ErrorConCodigo {
  return typeof error === 'object' && error !== null ? (error as ErrorConCodigo) : { message: String(error) }
}

/** Código de negocio de una RPC (HINT), útil para decidir la siguiente acción en pantalla. */
export function codigoDeError(error: unknown): string | null {
  return comoError(error).hint || null
}

export function esErrorDeRed(error: unknown): boolean {
  const mensaje = comoError(error).message ?? ''
  return /failed to fetch|networkerror|network request failed|load failed/i.test(mensaje)
}

/** Mensaje para cada restricción UNIQUE de la base (migración 001). */
const DUPLICADOS: Record<string, string> = {
  uq_clubes_nombre_corto: 'Ya existe un club con ese nombre corto.',
  uq_clubes_nombre: 'Ya existe un club con ese nombre. Búsquelo en la lista de rivales.',
  uq_campeonatos_nombre_temporada: 'Ya existe un campeonato con ese nombre y temporada.',
}

export function mensajeDeError(error: unknown): string {
  const e = comoError(error)

  if (esErrorDeRed(error)) {
    return 'Sin conexión con el servidor: la operación no se realizó. Reintente cuando vuelva la señal.'
  }
  if (e.message === 'Invalid login credentials') {
    return 'Correo o contraseña incorrectos.'
  }
  if (e.code === '42501') {
    return e.hint === 'PERMISO_DENEGADO' && e.message ? e.message : 'No tiene permiso para realizar esta operación.'
  }
  if (e.code === '23505') {
    const restriccion = Object.keys(DUPLICADOS).find((nombre) => e.message?.includes(nombre))
    return restriccion ? DUPLICADOS[restriccion] : 'Ya existe un registro con esos datos. Use otro nombre.'
  }
  if (e.code === 'PGRST116') {
    return 'No se encontró el registro o no tiene permiso para modificarlo.'
  }
  if (e.code === 'P0001' && e.message) {
    return e.message
  }
  return e.message || 'Ocurrió un error inesperado.'
}
