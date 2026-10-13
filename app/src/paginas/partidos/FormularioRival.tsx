import { useState, type FormEvent } from 'react'
import { BotonSecundario, Campo, MensajeError } from '../../componentes/Formulario'
import { BotonPrincipal } from '../../componentes/Pantallas'
import { actualizarRival, crearRival, type Rival } from '../../datos/clubes'
import { mensajeDeError } from '../../lib/errores'

/** Ventana para crear o editar un club rival. */
export function FormularioRival({
  rival,
  onGuardado,
  onCancelar,
}: {
  rival: Rival | null
  onGuardado: (rival: Rival) => void
  onCancelar: () => void
}) {
  const [nombre, setNombre] = useState(rival?.nombre ?? '')
  const [nombreCorto, setNombreCorto] = useState(rival?.nombre_corto ?? '')
  const [activo, setActivo] = useState(rival ? rival.estado === 'ACTIVO' : true)
  const [guardando, setGuardando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function guardar(e: FormEvent) {
    e.preventDefault()
    if (guardando) return
    if (!nombre.trim() || !nombreCorto.trim()) {
      setError('Nombre y nombre corto son obligatorios.')
      return
    }
    setGuardando(true)
    setError(null)
    try {
      onGuardado(
        rival
          ? await actualizarRival(rival.id, nombre, nombreCorto, activo ? 'ACTIVO' : 'INACTIVO')
          : await crearRival(nombre, nombreCorto),
      )
    } catch (err) {
      setError(mensajeDeError(err))
      setGuardando(false)
    }
  }

  return (
    <div className="fixed inset-0 z-40 flex items-end justify-center bg-slate-900/50 p-4 sm:items-center" role="dialog" aria-modal="true">
      <form onSubmit={guardar} className="w-full max-w-sm space-y-4 rounded-2xl bg-white p-5 shadow-xl" noValidate>
        <h2 className="text-lg font-bold">{rival ? 'Editar club rival' : 'Nuevo club rival'}</h2>
        <Campo etiqueta="Nombre" required value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Ej.: Club Shooker" />
        <Campo
          etiqueta="Nombre corto"
          required
          maxLength={12}
          value={nombreCorto}
          onChange={(e) => setNombreCorto(e.target.value)}
          placeholder="Ej.: SHOOKER"
          ayuda="Se muestra en el marcador."
        />
        {rival && (
          <label className="flex min-h-12 items-center gap-3 font-semibold">
            <input type="checkbox" checked={activo} onChange={(e) => setActivo(e.target.checked)} className="size-5" />
            Club activo
          </label>
        )}
        {error && <MensajeError>{error}</MensajeError>}
        <div className="space-y-2">
          <BotonPrincipal type="submit" disabled={guardando}>
            {guardando ? 'Guardando…' : 'Guardar'}
          </BotonPrincipal>
          <BotonSecundario onClick={onCancelar} disabled={guardando}>
            Cancelar
          </BotonSecundario>
        </div>
      </form>
    </div>
  )
}
