import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { CLASE_CAMPO, MensajeError } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import { listarJugadores, type EstadoJugador } from '../../datos/jugadores'
import { useCarga } from '../../hooks/useCarga'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'
import { EtiquetaEstado } from './EtiquetaEstado'

type FiltroEstado = EstadoJugador | 'TODOS'

/** Compara sin distinguir mayúsculas ni tildes. */
const plano = (t: string) => t.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()

export function ListaJugadores() {
  const { roles } = useSesion()
  const { estado, recargar } = useCarga(listarJugadores, [])
  const [busqueda, setBusqueda] = useState('')
  const [filtroEstado, setFiltroEstado] = useState<FiltroEstado>('ACTIVO')
  const [categoria, setCategoria] = useState('')

  const puedeCrear = tieneRol(roles, ['DIRECTIVA'])
  const jugadores = useMemo(() => (estado.tipo === 'listo' ? estado.datos : []), [estado])

  const categorias = useMemo(
    () => [...new Set(jugadores.map((j) => j.categoria).filter((c): c is string => !!c))].sort(),
    [jugadores],
  )

  const visibles = useMemo(() => {
    const texto = plano(busqueda.trim())
    return jugadores.filter(
      (j) =>
        (filtroEstado === 'TODOS' || j.estado === filtroEstado) &&
        (categoria === '' || j.categoria === categoria) &&
        (texto === '' || plano(`${j.nombre_completo} ${j.apodo ?? ''}`).includes(texto)),
    )
  }, [jugadores, busqueda, filtroEstado, categoria])

  const activos = jugadores.filter((j) => j.estado === 'ACTIVO').length

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Jugadores</h1>
          {estado.tipo === 'listo' && (
            <p className="text-sm text-slate-600">
              {activos} activos · {jugadores.length - activos} inactivos
            </p>
          )}
        </div>
        {puedeCrear && (
          <Link
            to="/jugadores/nuevo"
            className="flex min-h-12 items-center rounded-xl bg-slate-900 px-4 font-bold text-white active:bg-slate-700"
          >
            + Nuevo
          </Link>
        )}
      </div>

      <div className="space-y-3">
        <input
          type="search"
          placeholder="Buscar por nombre o apodo"
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
          className={CLASE_CAMPO}
          aria-label="Buscar jugador"
        />
        <div className="flex gap-2" role="group" aria-label="Filtrar por estado">
          {(['ACTIVO', 'INACTIVO', 'TODOS'] as const).map((f) => (
            <button
              key={f}
              type="button"
              onClick={() => setFiltroEstado(f)}
              aria-pressed={filtroEstado === f}
              className={`min-h-11 flex-1 rounded-full text-sm font-bold ${
                filtroEstado === f ? 'bg-slate-900 text-white' : 'bg-white text-slate-700 ring-1 ring-slate-300'
              }`}
            >
              {f === 'ACTIVO' ? 'Activos' : f === 'INACTIVO' ? 'Inactivos' : 'Todos'}
            </button>
          ))}
        </div>
        {categorias.length > 0 && (
          <select
            value={categoria}
            onChange={(e) => setCategoria(e.target.value)}
            className={CLASE_CAMPO}
            aria-label="Filtrar por categoría"
          >
            <option value="">Todas las categorías</option>
            {categorias.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        )}
      </div>

      {estado.tipo === 'cargando' && <Cargando texto="Cargando jugadores…" />}
      {estado.tipo === 'error' && (
        <div className="space-y-3">
          <MensajeError>{estado.mensaje}</MensajeError>
          <button type="button" onClick={recargar} className="min-h-11 font-semibold text-amber-700 underline">
            Reintentar
          </button>
        </div>
      )}

      {estado.tipo === 'listo' && visibles.length === 0 && (
        <p className="rounded-2xl bg-white p-5 text-center text-slate-600">
          {jugadores.length === 0
            ? puedeCrear
              ? 'Aún no hay jugadores. Use "+ Nuevo" para agregar el primero.'
              : 'Aún no hay jugadores registrados.'
            : 'Ningún jugador coincide con la búsqueda.'}
        </p>
      )}

      <ul className="space-y-2">
        {visibles.map((j) => (
          <li key={j.id}>
            <Link
              to={`/jugadores/${j.id}`}
              className="flex min-h-16 items-center justify-between gap-3 rounded-2xl bg-white px-4 py-3 shadow-sm active:bg-slate-50"
            >
              <div className="min-w-0">
                <p className="truncate font-bold">{j.nombre_completo}</p>
                <p className="truncate text-sm text-slate-600">
                  {[j.apodo && `"${j.apodo}"`, j.categoria].filter(Boolean).join(' · ') || ' '}
                </p>
              </div>
              <EtiquetaEstado estado={j.estado} />
            </Link>
          </li>
        ))}
      </ul>
    </div>
  )
}
