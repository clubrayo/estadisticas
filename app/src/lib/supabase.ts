import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const clave = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

/** Falso si falta .env.local: la app muestra una pantalla de configuración en vez de fallar. */
export const configuracionCompleta = Boolean(url && clave)

export const supabase = createClient(url ?? 'http://localhost', clave ?? 'sin-configurar', {
  auth: { persistSession: true, autoRefreshToken: true },
})
