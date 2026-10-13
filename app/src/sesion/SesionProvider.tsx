import type { Session } from '@supabase/supabase-js'
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { mensajeDeError } from '../lib/errores'
import type { CodigoRol, RolAsignado } from '../lib/roles'
import { supabase } from '../lib/supabase'
import { ContextoSesion, type Perfil, type ValorSesion } from './contexto'

interface FilaRol {
  rol_codigo: CodigoRol
  club_id: string | null
  clubes: { nombre_corto: string } | { nombre_corto: string }[] | null
}

/** Perfil y roles cargados, asociados al usuario al que pertenecen. */
interface DatosUsuario {
  usuarioId: string
  perfil: Perfil | null
  roles: RolAsignado[]
  error: string | null
}

async function leerDatosUsuario(usuarioId: string): Promise<DatosUsuario> {
  const [p, r] = await Promise.all([
    supabase.from('perfiles').select('id, email, nombre_completo, estado').eq('id', usuarioId).maybeSingle(),
    supabase.from('usuario_roles').select('rol_codigo, club_id, clubes(nombre_corto)').eq('usuario_id', usuarioId),
  ])
  if (p.error || r.error) {
    return { usuarioId, perfil: null, roles: [], error: mensajeDeError(p.error ?? r.error) }
  }
  return {
    usuarioId,
    error: null,
    perfil: p.data && {
      id: p.data.id,
      email: p.data.email,
      nombre: p.data.nombre_completo,
      activo: p.data.estado === 'ACTIVO',
    },
    roles: ((r.data ?? []) as FilaRol[]).map((fila) => {
      const club = Array.isArray(fila.clubes) ? fila.clubes[0] : fila.clubes
      return { rol: fila.rol_codigo, clubId: fila.club_id, club: club?.nombre_corto ?? null }
    }),
  }
}

export function SesionProvider({ children }: { children: ReactNode }) {
  const [sesion, setSesion] = useState<Session | null>(null)
  const [sesionLeida, setSesionLeida] = useState(false)
  const [datos, setDatos] = useState<DatosUsuario | null>(null)

  // Sesión de Supabase Auth (persistida en el navegador y renovada automáticamente).
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSesion(data.session)
      setSesionLeida(true)
    })
    const { data } = supabase.auth.onAuthStateChange((_evento, nueva) => setSesion(nueva))
    return () => data.subscription.unsubscribe()
  }, [])

  const usuarioId = sesion?.user.id ?? null

  useEffect(() => {
    if (!usuarioId) return
    let vigente = true
    void leerDatosUsuario(usuarioId).then((d) => vigente && setDatos(d))
    return () => {
      vigente = false
    }
  }, [usuarioId])

  // Solo valen los datos del usuario actual; mientras no lleguen, se considera "cargando".
  const actuales = usuarioId && datos?.usuarioId === usuarioId ? datos : null

  const iniciarSesion = useCallback(async (email: string, clave: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password: clave })
    return error ? mensajeDeError(error) : null
  }, [])

  const cerrarSesion = useCallback(async () => {
    await supabase.auth.signOut()
  }, [])

  const reintentar = useCallback(async () => {
    if (!usuarioId) return
    setDatos(null)
    setDatos(await leerDatosUsuario(usuarioId))
  }, [usuarioId])

  const valor = useMemo<ValorSesion>(
    () => ({
      cargando: !sesionLeida || (usuarioId !== null && actuales === null),
      sesion,
      perfil: actuales?.perfil ?? null,
      roles: actuales?.roles ?? [],
      errorPerfil: actuales?.error ?? null,
      iniciarSesion,
      cerrarSesion,
      reintentar,
    }),
    [sesionLeida, usuarioId, actuales, sesion, iniciarSesion, cerrarSesion, reintentar],
  )

  return <ContextoSesion.Provider value={valor}>{children}</ContextoSesion.Provider>
}
