import { useState } from 'react'
import { Link, useSearchParams } from 'react-router'
import { BotonSecundario, CLASE_CAMPO, MensajeError } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import {
  camposDelCambio,
  listarAuditoria,
  NOMBRE_ACCION,
  NOMBRE_TABLA,
  type FiltroAuditoria,
  type Operacion,
} from '../../datos/auditoria'
import { listarJugadores } from '../../datos/jugadores'
import { ladosDelPartido, listarPartidos } from '../../datos/partidos'
import { useCarga } from '../../hooks/useCarga'
import { mensajeDeError } from '../../lib/errores'
import { fechaCorta } from '../../lib/formato'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'

type Nombres = { partidos: Map<string, string>; jugadores: Map<string, string> }

/** Registro de auditoría (sección 40). Solo ADMINISTRADOR. */
export function Auditoria() {
  const { roles } = useSesion()
  const [parametros, setParametros] = useSearchParams()
  const [accion, setAccion] = useState('')
  const [desde, setDesde] = useState('')
  const partidoId = parametros.get('partido')

  const { estado } = useCarga(async () => {
    const [partidos, jugadores] = await Promise.all([listarPartidos(), listarJugadores()])
    return {
      partidos,
      nombres: {
        partidos: new Map(
          partidos.map((p) => {
            const { propio, rival } = ladosDelPartido(p)
            return [p.id, `${propio.nombre_corto} vs ${rival.nombre_corto} · ${fechaCorta(p.fecha)}`]
          }),
        ),
        jugadores: new Map(jugadores.map((j) => [j.id, j.nombre_completo])),
      } satisfies Nombres,
    }
  }, [])

  if (!tieneRol(roles, [])) return <MensajeError>La auditoría solo está disponible para administradores.</MensajeError>
  if (estado.tipo === 'cargando') return <Cargando />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>

  const filtro: FiltroAuditoria = { partidoId, accion, desde }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold">Auditoría</h1>

      <div className="grid gap-2 sm:grid-cols-3">
        <select
          value={partidoId ?? ''}
          onChange={(e) => setParametros(e.target.value ? { partido: e.target.value } : {})}
          className={CLASE_CAMPO}
          aria-label="Partido"
        >
          <option value="">Todos los partidos y datos</option>
          {estado.datos.partidos.map((p) => (
            <option key={p.id} value={p.id}>
              {estado.datos.nombres.partidos.get(p.id)}
            </option>
          ))}
        </select>
        <select value={accion} onChange={(e) => setAccion(e.target.value)} className={CLASE_CAMPO} aria-label="Acción">
          <option value="">Todas las acciones</option>
          {Object.entries(NOMBRE_ACCION).map(([codigo, nombre]) => (
            <option key={codigo} value={codigo}>
              {nombre}
            </option>
          ))}
        </select>
        <input
          type="date"
          value={desde}
          onChange={(e) => setDesde(e.target.value)}
          className={CLASE_CAMPO}
          aria-label="Desde"
        />
      </div>

      <Resultados key={JSON.stringify(filtro)} filtro={filtro} nombres={estado.datos.nombres} />
    </div>
  )
}

function Resultados({ filtro, nombres }: { filtro: FiltroAuditoria; nombres: Nombres }) {
  const { estado } = useCarga(() => listarAuditoria(filtro, null), [filtro])
  const [mas, setMas] = useState<{ operaciones: Operacion[]; siguiente: number | null } | null>(null)
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (estado.tipo === 'cargando') return <Cargando texto="Leyendo auditoría…" />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>

  const operaciones = [...estado.datos.operaciones, ...(mas?.operaciones ?? [])]
  const siguiente = mas ? mas.siguiente : estado.datos.siguiente

  async function cargarMas() {
    if (siguiente === null) return
    setCargando(true)
    setError(null)
    try {
      const pagina = await listarAuditoria(filtro, siguiente)
      setMas((m) => ({ operaciones: [...(m?.operaciones ?? []), ...pagina.operaciones], siguiente: pagina.siguiente }))
    } catch (e) {
      setError(mensajeDeError(e))
    } finally {
      setCargando(false)
    }
  }

  if (operaciones.length === 0) {
    return <p className="rounded-2xl bg-white p-5 text-center text-slate-600">No hay registros con estos filtros.</p>
  }

  return (
    <div className="space-y-2">
      <ol className="space-y-2">
        {operaciones.map((o) => (
          <TarjetaOperacion key={`${o.clave}-${o.cambios[0].id}`} o={o} nombres={nombres} />
        ))}
      </ol>
      {error && <MensajeError>{error}</MensajeError>}
      {siguiente !== null && (
        <BotonSecundario onClick={() => void cargarMas()} disabled={cargando}>
          {cargando ? 'Cargando…' : 'Cargar registros anteriores'}
        </BotonSecundario>
      )}
    </div>
  )
}

function TarjetaOperacion({ o, nombres }: { o: Operacion; nombres: Nombres }) {
  const momento = new Date(o.ocurrido_at).toLocaleString('es-CL', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
  const critica = ['REABRIR_PARTIDO', 'CORREGIR_RESULTADO', 'CANCELAR_PARTIDO', 'ACTIVAR_REGLAS'].includes(o.accion)

  return (
    <li className={`rounded-2xl bg-white p-4 shadow-sm ${critica ? 'border-l-4 border-amber-500' : ''}`}>
      <div className="flex items-start justify-between gap-2">
        <p className="font-bold">{NOMBRE_ACCION[o.accion] ?? o.accion}</p>
        <span className="shrink-0 text-xs text-slate-500 tabular-nums">{momento}</span>
      </div>
      <p className="text-sm text-slate-600">
        {o.origen === 'SISTEMA' ? 'Sistema / SQL Editor' : (o.usuario_email ?? 'Usuario desconocido')}
        {o.partido_id && (
          <>
            {' · '}
            <Link to={`/partidos/${o.partido_id}`} className="font-semibold text-slate-800 underline-offset-2 active:underline">
              {nombres.partidos.get(o.partido_id) ?? 'Partido'}
            </Link>
          </>
        )}
      </p>
      {o.motivo && <p className="mt-1 rounded-lg bg-amber-50 px-3 py-1 text-sm text-amber-900">Motivo: {o.motivo}</p>}

      <details className="mt-2">
        <summary className="min-h-11 cursor-pointer py-2 text-sm font-semibold text-slate-700">
          Ver {o.cambios.length} cambio(s) en la base de datos
        </summary>
        <ul className="space-y-2 text-sm">
          {[...o.cambios].reverse().map((c) => (
            <li key={c.id} className="rounded-lg bg-slate-50 p-2">
              <p className="font-semibold">
                {NOMBRE_TABLA[c.tabla] ?? c.tabla} ·{' '}
                {c.operacion === 'INSERT' ? 'creado' : c.operacion === 'UPDATE' ? 'modificado' : 'eliminado'}
              </p>
              {camposDelCambio(c).map(({ campo, antes, despues }) => (
                <p key={campo} className="break-words text-slate-700">
                  <span className="text-slate-500">{campo}:</span>{' '}
                  {c.operacion === 'UPDATE' && (
                    <>
                      <span className="text-red-700 line-through">{valor(antes, nombres)}</span> →{' '}
                    </>
                  )}
                  <span className={c.operacion === 'DELETE' ? 'text-red-700' : 'text-green-800'}>
                    {valor(c.operacion === 'DELETE' ? antes : despues, nombres)}
                  </span>
                </p>
              ))}
            </li>
          ))}
        </ul>
      </details>
    </li>
  )
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** Muestra un valor legible: nombres en vez de identificadores, Sí/No, fechas. */
function valor(v: unknown, nombres: Nombres): string {
  if (v === null || v === undefined) return '—'
  if (typeof v === 'boolean') return v ? 'Sí' : 'No'
  if (typeof v === 'string') {
    if (UUID.test(v)) return nombres.jugadores.get(v) ?? nombres.partidos.get(v) ?? `…${v.slice(-6)}`
    if (/^\d{4}-\d{2}-\d{2}T/.test(v)) return new Date(v).toLocaleString('es-CL')
    return v
  }
  return JSON.stringify(v)
}
