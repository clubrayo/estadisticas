import { useState, type FormEvent } from 'react'
import { Navigate, useLocation } from 'react-router'
import { BannerConexion } from '../componentes/BannerConexion'
import { Creditos, Logo } from '../componentes/Marca'
import { BotonPrincipal } from '../componentes/Pantallas'
import { useSesion } from '../sesion/contexto'

export function Ingresar() {
  const { sesion, iniciarSesion } = useSesion()
  const ubicacion = useLocation()
  const [email, setEmail] = useState('')
  const [clave, setClave] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (sesion) {
    const desde = (ubicacion.state as { desde?: string } | null)?.desde ?? '/'
    return <Navigate to={desde} replace />
  }

  async function enviar(e: FormEvent) {
    e.preventDefault()
    if (enviando) return
    setEnviando(true)
    setError(null)
    const mensaje = await iniciarSesion(email, clave)
    if (mensaje) setError(mensaje)
    setEnviando(false)
  }

  const campo =
    'min-h-12 w-full rounded-xl border border-slate-300 bg-white px-4 text-base outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-200'

  return (
    <div className="flex min-h-dvh flex-col">
      <BannerConexion />
      <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center px-6 py-10">
        <div className="mb-8 text-center">
          <Logo className="mx-auto mb-4 size-32" />
          <h1 className="text-2xl font-extrabold tracking-wide">CLUB RAYO</h1>
          <p className="text-slate-600">Gestión y estadísticas de juego</p>
        </div>

        <form onSubmit={enviar} className="space-y-4" noValidate>
          <label className="block space-y-1">
            <span className="text-sm font-semibold text-slate-700">Correo</span>
            <input
              type="email"
              autoComplete="email"
              inputMode="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className={campo}
            />
          </label>
          <label className="block space-y-1">
            <span className="text-sm font-semibold text-slate-700">Contraseña</span>
            <input
              type="password"
              autoComplete="current-password"
              required
              value={clave}
              onChange={(e) => setClave(e.target.value)}
              className={campo}
            />
          </label>

          {error && (
            <p role="alert" className="rounded-xl bg-red-50 px-4 py-3 text-sm font-semibold text-red-700">
              {error}
            </p>
          )}

          <BotonPrincipal type="submit" disabled={enviando || !email || !clave}>
            {enviando ? 'Ingresando…' : 'Ingresar'}
          </BotonPrincipal>
        </form>

        <p className="mt-6 text-center text-sm text-slate-500">
          Las cuentas las crea un administrador del club.
        </p>
      </main>
      <Creditos className="px-6 pb-[max(1rem,env(safe-area-inset-bottom))]" />
    </div>
  )
}
