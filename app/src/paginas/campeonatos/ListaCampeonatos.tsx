import { Link } from 'react-router'
import { EtiquetaCampeonato } from '../../componentes/Etiquetas'
import { MensajeError } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import { listarCampeonatos } from '../../datos/campeonatos'
import { useCarga } from '../../hooks/useCarga'
import { formatoFecha } from '../../lib/formato'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'

export function ListaCampeonatos() {
  const { roles } = useSesion()
  const { estado } = useCarga(listarCampeonatos, [])
  const esAdmin = tieneRol(roles, [])

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-2xl font-bold">Campeonatos</h1>
        {esAdmin && (
          <Link
            to="/campeonatos/nuevo"
            className="flex min-h-12 items-center rounded-xl bg-slate-900 px-4 font-bold text-white active:bg-slate-700"
          >
            + Nuevo
          </Link>
        )}
      </div>

      {estado.tipo === 'cargando' && <Cargando texto="Cargando campeonatos…" />}
      {estado.tipo === 'error' && <MensajeError>{estado.mensaje}</MensajeError>}
      {estado.tipo === 'listo' && estado.datos.length === 0 && (
        <p className="rounded-2xl bg-white p-5 text-center text-slate-600">
          {esAdmin ? 'Aún no hay campeonatos. Use "+ Nuevo" para crear el primero.' : 'Aún no hay campeonatos registrados.'}
        </p>
      )}

      {estado.tipo === 'listo' && (
        <ul className="space-y-2">
          {estado.datos.map((c) => (
            <li key={c.id}>
              <Link
                to={`/campeonatos/${c.id}`}
                className="block space-y-1 rounded-2xl bg-white px-4 py-3 shadow-sm active:bg-slate-50"
              >
                <div className="flex items-start justify-between gap-3">
                  <p className="font-bold">{c.nombre}</p>
                  <EtiquetaCampeonato estado={c.estado} />
                </div>
                <p className="text-sm text-slate-600">
                  Temporada {c.temporada} · Meta {c.puntaje_objetivo} puntos
                </p>
                <p className="text-xs text-slate-500">
                  Desde {formatoFecha(c.fecha_inicio)}
                  {c.fecha_termino && ` hasta ${formatoFecha(c.fecha_termino)}`}
                </p>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
