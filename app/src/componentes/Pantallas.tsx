import type { ButtonHTMLAttributes, ReactNode } from 'react'
import { Logo } from './Marca'

/** Pantalla completa centrada para estados de carga, error o configuración. */
export function PantallaCentrada({ titulo, children }: { titulo: string; children?: ReactNode }) {
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center gap-4 px-6 text-center">
      <Logo className="size-20" />
      <h1 className="text-xl font-bold">{titulo}</h1>
      {children}
    </main>
  )
}

export function Cargando({ texto = 'Cargando…' }: { texto?: string }) {
  return (
    <div className="flex items-center justify-center gap-3 py-10 text-slate-600" role="status">
      <span className="size-5 animate-spin rounded-full border-2 border-slate-300 border-t-amber-500" />
      <span>{texto}</span>
    </div>
  )
}

/** Sección todavía no implementada: indica en qué fase llega. */
export function Pendiente({ titulo, fase, descripcion }: { titulo: string; fase: string; descripcion: string }) {
  return (
    <section className="space-y-3">
      <h1 className="text-2xl font-bold">{titulo}</h1>
      <div className="rounded-2xl border-2 border-dashed border-slate-300 bg-white p-5">
        <p className="text-sm font-semibold uppercase tracking-wide text-amber-700">{fase}</p>
        <p className="mt-1 text-slate-700">{descripcion}</p>
      </div>
    </section>
  )
}

export function BotonPrincipal({
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      {...props}
      className="min-h-12 w-full rounded-xl bg-slate-900 px-5 text-base font-bold text-white active:bg-slate-700 disabled:opacity-50"
    >
      {children}
    </button>
  )
}
