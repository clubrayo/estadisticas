import {
  useState,
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
  type SelectHTMLAttributes,
  type TextareaHTMLAttributes,
} from 'react'

export const CLASE_CAMPO =
  'min-h-12 w-full rounded-xl border border-slate-300 bg-white px-4 text-base outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-200'

export function Campo({
  etiqueta,
  ayuda,
  ...props
}: InputHTMLAttributes<HTMLInputElement> & { etiqueta: string; ayuda?: string }) {
  return (
    <label className="block space-y-1">
      <span className="text-sm font-semibold text-slate-700">
        {etiqueta}
        {props.required && <span className="text-red-600"> *</span>}
      </span>
      <input {...props} className={CLASE_CAMPO} />
      {ayuda && <span className="block text-xs text-slate-500">{ayuda}</span>}
    </label>
  )
}

export function AreaTexto({
  etiqueta,
  ...props
}: TextareaHTMLAttributes<HTMLTextAreaElement> & { etiqueta: string }) {
  return (
    <label className="block space-y-1">
      <span className="text-sm font-semibold text-slate-700">{etiqueta}</span>
      <textarea {...props} rows={3} className={`${CLASE_CAMPO} py-3`} />
    </label>
  )
}

export function MensajeError({ children }: { children: ReactNode }) {
  return (
    <p role="alert" className="rounded-xl bg-red-50 px-4 py-3 text-sm font-semibold text-red-700">
      {children}
    </p>
  )
}

export function MensajeExito({ children }: { children: ReactNode }) {
  return (
    <p role="status" className="rounded-xl bg-green-50 px-4 py-3 text-sm font-semibold text-green-800">
      {children}
    </p>
  )
}

export function BotonSecundario({
  children,
  peligro,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { peligro?: boolean }) {
  return (
    <button
      type="button"
      {...props}
      className={`min-h-12 w-full rounded-xl border-2 px-5 text-base font-bold disabled:opacity-50 ${
        peligro
          ? 'border-red-600 text-red-700 active:bg-red-50'
          : 'border-slate-300 text-slate-800 active:bg-slate-100'
      }`}
    >
      {children}
    </button>
  )
}

export function Selector({
  etiqueta,
  children,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement> & { etiqueta: string }) {
  return (
    <label className="block space-y-1">
      <span className="text-sm font-semibold text-slate-700">
        {etiqueta}
        {props.required && <span className="text-red-600"> *</span>}
      </span>
      <select {...props} className={CLASE_CAMPO}>
        {children}
      </select>
    </label>
  )
}

/** Confirmación que exige escribir un motivo (queda en la auditoría). */
export function DialogoMotivo({
  titulo,
  descripcion,
  textoConfirmar,
  peligro,
  ocupado,
  error,
  onConfirmar,
  onCancelar,
}: {
  titulo: string
  descripcion: ReactNode
  textoConfirmar: string
  peligro?: boolean
  ocupado?: boolean
  error?: string | null
  onConfirmar: (motivo: string) => void
  onCancelar: () => void
}) {
  const [motivo, setMotivo] = useState('')
  return (
    <Confirmacion
      titulo={titulo}
      textoConfirmar={textoConfirmar}
      peligro={peligro}
      ocupado={ocupado}
      deshabilitado={motivo.trim() === ''}
      onConfirmar={() => onConfirmar(motivo.trim())}
      onCancelar={onCancelar}
      mensaje={
        <div className="space-y-3">
          <div>{descripcion}</div>
          <AreaTexto etiqueta="Motivo (obligatorio)" value={motivo} onChange={(e) => setMotivo(e.target.value)} />
          {error && <MensajeError>{error}</MensajeError>}
        </div>
      }
    />
  )
}

/** Confirmación explícita antes de una acción relevante (sección 42). */
export function Confirmacion({
  titulo,
  mensaje,
  textoConfirmar,
  peligro,
  ocupado,
  deshabilitado,
  onConfirmar,
  onCancelar,
}: {
  titulo: string
  mensaje: ReactNode
  textoConfirmar: string
  peligro?: boolean
  ocupado?: boolean
  deshabilitado?: boolean
  onConfirmar: () => void
  onCancelar: () => void
}) {
  return (
    <div className="fixed inset-0 z-40 flex items-end justify-center bg-slate-900/50 p-4 sm:items-center" role="dialog" aria-modal="true" aria-label={titulo}>
      <div className="w-full max-w-sm space-y-4 rounded-2xl bg-white p-5 shadow-xl">
        <h2 className="text-lg font-bold">{titulo}</h2>
        <div className="text-slate-700">{mensaje}</div>
        <div className="space-y-2">
          <button
            type="button"
            onClick={onConfirmar}
            disabled={ocupado || deshabilitado}
            className={`min-h-12 w-full rounded-xl px-5 text-base font-bold text-white disabled:opacity-50 ${
              peligro ? 'bg-red-600 active:bg-red-700' : 'bg-slate-900 active:bg-slate-700'
            }`}
          >
            {ocupado ? 'Guardando…' : textoConfirmar}
          </button>
          <BotonSecundario onClick={onCancelar} disabled={ocupado}>
            Cancelar
          </BotonSecundario>
        </div>
      </div>
    </div>
  )
}
