import { useSyncExternalStore } from 'react'

function suscribir(aviso: () => void) {
  window.addEventListener('online', aviso)
  window.addEventListener('offline', aviso)
  return () => {
    window.removeEventListener('online', aviso)
    window.removeEventListener('offline', aviso)
  }
}

/**
 * Estado de red del dispositivo. "En línea" no garantiza llegar a Supabase:
 * por eso cada guardado se confirma solo con la respuesta del servidor.
 */
export function useConexion(): boolean {
  return useSyncExternalStore(suscribir, () => navigator.onLine, () => true)
}
