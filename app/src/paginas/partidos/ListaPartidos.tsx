import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { CLASE_CAMPO, MensajeError } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import { TarjetaPartido } from '../../componentes/TarjetaPartido'
import { listarCampeonatos } from '../../datos/campeonatos'
import { ESTADOS_VIGENTES, listarPartidos } from '../../datos/partidos'
import { useCarga } from '../../hooks/useCarga'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'

type Filtro = 'VIGENTES' | 'TERMINADOS' | 'TODOS'

export function ListaPartidos() {
  const { roles } = useSesion()
  const { estado } = useCarga(async () => {
    const [partidos, campeonatos] = await Promise.all([listarPartidos(), listarCampeonatos()])
    return { partidos, campeonatos }
  }, [])
  const [filtro, setFiltro] = useState<Filtro>('VIGENTES')
  const [campeonatoId, setCampeonatoId] = useState('')

  const visibles = useMemo(() => {
    if (estado.tipo !== 'listo') return []
    return estado.datos.partidos.filter(
      (p) =>
        (campeonatoId === '' || p.campeonato_id === campeonatoId) &&
        (filtro === 'TODOS' || ESTADOS_VIGENTES.includes(p.estado) === (filtro === 'VIGENTES')),
    )
  }, [estado, filtro, campeonatoId])

  const puedeCrear = tieneRol(roles, ['DIRECTIVA'])

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-2xl font-bold">Partidos</h1>
        {puedeCrear && (
          <Link
            to="/partidos/nuevo"
            className="flex min-h-12 items-center rounded-xl bg-slate-900 px-4 font-bold text-white active:bg-slate-700"
          >
            + Nuevo
          </Link>
        )}
      </div>

      <div className="flex gap-2" role="group" aria-label="Filtrar por estado">
        {(
          [
            ['VIGENTES', 'Vigentes'],
            ['TERMINADOS', 'Terminados'],
            ['TODOS', 'Todos'],
          ] as const
        ).map(([valor, texto]) => (
          <button
            key={valor}
            type="button"
            onClick={() => setFiltro(valor)}
            aria-pressed={filtro === valor}
            className={`min-h-11 flex-1 rounded-full text-sm font-bold ${
              filtro === valor ? 'bg-slate-900 text-white' : 'bg-white text-slate-700 ring-1 ring-slate-300'
            }`}
          >
            {texto}
          </button>
        ))}
      </div>

      {estado.tipo === 'listo' && estado.datos.campeonatos.length > 1 && (
        <select
          value={campeonatoId}
          onChange={(e) => setCampeonatoId(e.target.value)}
          className={CLASE_CAMPO}
          aria-label="Filtrar por campeonato"
        >
          <option value="">Todos los campeonatos</option>
          {estado.datos.campeonatos.map((c) => (
            <option key={c.id} value={c.id}>
              {c.nombre} {c.temporada}
            </option>
          ))}
        </select>
      )}

      {estado.tipo === 'cargando' && <Cargando texto="Cargando partidos…" />}
      {estado.tipo === 'error' && <MensajeError>{estado.mensaje}</MensajeError>}
      {estado.tipo === 'listo' && visibles.length === 0 && (
        <p className="rounded-2xl bg-white p-5 text-center text-slate-600">
          {estado.datos.partidos.length === 0 ? 'Aún no hay partidos registrados.' : 'No hay partidos con este filtro.'}
        </p>
      )}

      <ul className="space-y-2">
        {visibles.map((p) => (
          <li key={p.id}>
            <TarjetaPartido partido={p} />
          </li>
        ))}
      </ul>

      {tieneRol(roles, ['DIRECTIVA']) && (
        <Link to="/partidos/rivales" className="block py-2 text-center font-semibold text-amber-700 underline">
          Administrar clubes rivales
        </Link>
      )}
    </div>
  )
}
