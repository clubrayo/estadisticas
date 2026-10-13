import { useState } from 'react'
import { Link } from 'react-router'
import { MensajeError, MensajeExito } from '../../componentes/Formulario'
import { IconoAtras } from '../../componentes/Iconos'
import { Cargando } from '../../componentes/Pantallas'
import { listarRivales, type Rival } from '../../datos/clubes'
import { useCarga } from '../../hooks/useCarga'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'
import { FormularioRival } from './FormularioRival'

export function Rivales() {
  const { roles } = useSesion()
  const { estado, recargar } = useCarga(listarRivales, [])
  const [editando, setEditando] = useState<Rival | 'nuevo' | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const puedeEditar = tieneRol(roles, ['DIRECTIVA'])

  return (
    <div className="space-y-4">
      <Link to="/partidos" className="inline-flex min-h-11 items-center gap-1 font-semibold text-slate-700">
        <IconoAtras className="size-5" />
        Partidos
      </Link>

      <div className="flex items-center justify-between gap-3">
        <h1 className="text-2xl font-bold">Clubes rivales</h1>
        {puedeEditar && (
          <button
            type="button"
            onClick={() => setEditando('nuevo')}
            className="min-h-12 rounded-xl bg-slate-900 px-4 font-bold text-white active:bg-slate-700"
          >
            + Nuevo
          </button>
        )}
      </div>

      {aviso && <MensajeExito>{aviso}</MensajeExito>}
      {estado.tipo === 'cargando' && <Cargando />}
      {estado.tipo === 'error' && <MensajeError>{estado.mensaje}</MensajeError>}
      {estado.tipo === 'listo' && estado.datos.length === 0 && (
        <p className="rounded-2xl bg-white p-5 text-center text-slate-600">Aún no hay clubes rivales.</p>
      )}

      {estado.tipo === 'listo' && (
        <ul className="space-y-2">
          {estado.datos.map((r) => (
            <li key={r.id}>
              <button
                type="button"
                disabled={!puedeEditar}
                onClick={() => setEditando(r)}
                className="flex min-h-16 w-full items-center justify-between gap-3 rounded-2xl bg-white px-4 py-3 text-left shadow-sm active:bg-slate-50"
              >
                <div className="min-w-0">
                  <p className="truncate font-bold">{r.nombre}</p>
                  <p className="text-sm text-slate-600">{r.nombre_corto}</p>
                </div>
                {r.estado === 'INACTIVO' && (
                  <span className="rounded-full bg-slate-200 px-3 py-1 text-xs font-bold text-slate-600">Inactivo</span>
                )}
              </button>
            </li>
          ))}
        </ul>
      )}

      {editando && (
        <FormularioRival
          rival={editando === 'nuevo' ? null : editando}
          onCancelar={() => setEditando(null)}
          onGuardado={(r) => {
            setAviso(editando === 'nuevo' ? `Club ${r.nombre} creado.` : 'Cambios guardados.')
            setEditando(null)
            recargar()
          }}
        />
      )}
    </div>
  )
}
