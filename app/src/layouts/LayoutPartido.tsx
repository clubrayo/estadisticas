import { Suspense, useState } from 'react'
import { Link, NavLink, Outlet, useParams } from 'react-router'
import { EtiquetaPartido } from '../componentes/Etiquetas'
import { BotonSecundario, Confirmacion, DialogoMotivo, MensajeError, MensajeExito } from '../componentes/Formulario'
import { IconoAtras } from '../componentes/Iconos'
import { Cargando } from '../componentes/Pantallas'
import {
  cancelarPartido,
  cerrarRevision,
  iniciarPartido,
  ladosDelPartido,
  obtenerPartido,
  reabrirPartido,
  reanudarPartido,
  suspenderPartido,
  type Partido,
} from '../datos/partidos'
import { useCarga } from '../hooks/useCarga'
import { mensajeDeError } from '../lib/errores'
import { fechaCorta } from '../lib/formato'
import { tieneRol } from '../lib/roles'
import type { ContextoPartido } from '../paginas/partidos/contextoPartido'
import { useSesion } from '../sesion/contexto'

const PESTANAS = [
  { ruta: '', etiqueta: 'Marcador' },
  { ruta: 'asistencia', etiqueta: 'Asistencia' },
  { ruta: 'listas', etiqueta: 'Listas' },
  { ruta: 'juego', etiqueta: 'Juego' },
  { ruta: 'estadisticas', etiqueta: 'Estadísticas' },
]

type Accion = 'iniciar' | 'suspender' | 'reanudar' | 'cancelar' | 'reabrir' | 'cerrarRevision'

/** Marco de un partido: encabezado con marcador, acciones de estado y pestañas (sección 43). */
export function LayoutPartido() {
  const { partidoId = '' } = useParams()
  const { estado, recargar } = useCarga(() => obtenerPartido(partidoId), [partidoId])

  if (estado.tipo === 'cargando') return <Cargando texto="Cargando partido…" />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>
  if (!estado.datos) {
    return (
      <div className="space-y-3">
        <MensajeError>El partido no existe o no tiene permiso para verlo.</MensajeError>
        <Link to="/partidos" className="font-semibold text-amber-700 underline">
          Volver a partidos
        </Link>
      </div>
    )
  }

  const contexto: ContextoPartido = { partido: estado.datos, recargar }
  return (
    <div className="space-y-4">
      <Link to="/partidos" className="inline-flex min-h-11 items-center gap-1 font-semibold text-slate-700">
        <IconoAtras className="size-5" />
        Partidos
      </Link>

      <Encabezado partido={estado.datos} recargar={recargar} />

      <nav aria-label="Secciones del partido" className="-mx-4 overflow-x-auto px-4">
        <ul className="flex gap-2">
          {PESTANAS.map(({ ruta, etiqueta }) => (
            <li key={etiqueta}>
              <NavLink
                to={ruta}
                end
                className={({ isActive }) =>
                  `flex min-h-11 items-center rounded-full px-4 text-sm font-bold whitespace-nowrap ${
                    isActive ? 'bg-slate-900 text-white' : 'bg-white text-slate-700 ring-1 ring-slate-300'
                  }`
                }
              >
                {etiqueta}
              </NavLink>
            </li>
          ))}
        </ul>
      </nav>

      <Suspense fallback={<Cargando />}>
        <Outlet context={contexto} />
      </Suspense>
    </div>
  )
}

function Encabezado({ partido, recargar }: { partido: Partido; recargar: () => void }) {
  const { roles } = useSesion()
  const [accion, setAccion] = useState<Accion | null>(null)
  const [ocupado, setOcupado] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)

  const { propio, rival, puntajePropio, puntajeRival, condicion } = ladosDelPartido(partido)
  const operador = tieneRol(roles, ['CAPITAN', 'DIRECTIVA'], propio.id)
  const directiva = tieneRol(roles, ['DIRECTIVA'], propio.id)
  const esAdmin = tieneRol(roles, [])
  const abierto = ['PROGRAMADO', 'EN_CURSO', 'SUSPENDIDO'].includes(partido.estado)

  async function ejecutar(fn: () => Promise<void>, mensaje: string) {
    setOcupado(true)
    setError(null)
    try {
      await fn()
      setAviso(mensaje)
      setAccion(null)
      recargar()
    } catch (e) {
      setError(mensajeDeError(e))
    } finally {
      setOcupado(false)
    }
  }

  const cerrar = () => {
    setAccion(null)
    setError(null)
  }

  return (
    <section className="space-y-3">
      <div className="space-y-3 rounded-2xl bg-slate-900 p-4 text-white">
        <div className="flex items-center justify-between gap-2 text-sm text-slate-300">
          <span className="truncate">
            {partido.campeonato.nombre} · {fechaCorta(partido.fecha)}
          </span>
          <EtiquetaPartido estado={partido.estado} />
        </div>
        <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-2 text-center">
          <div className="min-w-0">
            <p className="truncate text-sm font-bold tracking-wide text-amber-400">{propio.nombre_corto}</p>
            <p className="text-5xl font-extrabold tabular-nums">{puntajePropio}</p>
          </div>
          <p className="text-xs font-semibold text-slate-400">META {partido.puntaje_objetivo}</p>
          <div className="min-w-0">
            <p className="truncate text-sm font-bold tracking-wide">{rival.nombre_corto}</p>
            <p className="text-5xl font-extrabold tabular-nums">{puntajeRival}</p>
          </div>
        </div>
        <p className="text-center text-xs text-slate-400">
          {condicion}
          {partido.lugar && ` · ${partido.lugar}`}
        </p>
      </div>

      {aviso && <MensajeExito>{aviso}</MensajeExito>}
      {error && !accion && <MensajeError>{error}</MensajeError>}

      {(operador || directiva) && (
        <div className="grid grid-cols-2 gap-2">
          {operador && partido.estado === 'PROGRAMADO' && (
            <button
              type="button"
              onClick={() => setAccion('iniciar')}
              className="col-span-2 min-h-12 rounded-xl bg-green-600 font-bold text-white active:bg-green-700"
            >
              Iniciar partido
            </button>
          )}
          {operador && partido.estado === 'EN_CURSO' && (
            <BotonSecundario onClick={() => setAccion('suspender')}>Suspender</BotonSecundario>
          )}
          {operador && partido.estado === 'SUSPENDIDO' && (
            <button
              type="button"
              onClick={() => setAccion('reanudar')}
              className="min-h-12 rounded-xl bg-green-600 font-bold text-white active:bg-green-700"
            >
              Reanudar
            </button>
          )}
          {directiva && abierto && (
            <BotonSecundario peligro onClick={() => setAccion('cancelar')}>
              Cancelar partido
            </BotonSecundario>
          )}
          {esAdmin && partido.estado === 'FINALIZADO' && (
            <BotonSecundario onClick={() => setAccion('reabrir')}>Reabrir (revisión)</BotonSecundario>
          )}
          {esAdmin && partido.estado === 'EN_REVISION' && (
            <button
              type="button"
              onClick={() => setAccion('cerrarRevision')}
              className="min-h-12 rounded-xl bg-purple-700 font-bold text-white active:bg-purple-800"
            >
              Cerrar revisión
            </button>
          )}
          {directiva && (
            <Link
              to="editar"
              className="flex min-h-12 items-center justify-center rounded-xl border-2 border-slate-300 font-bold text-slate-800 active:bg-slate-100"
            >
              Editar datos
            </Link>
          )}
          {esAdmin && (
            <Link
              to={`/auditoria?partido=${partido.id}`}
              className="flex min-h-12 items-center justify-center rounded-xl border-2 border-slate-300 font-bold text-slate-800 active:bg-slate-100"
            >
              Auditoría
            </Link>
          )}
        </div>
      )}

      {accion === 'iniciar' && (
        <Confirmacion
          titulo="Iniciar partido"
          mensaje={
            <p>
              El partido pasará a <strong>En curso</strong> y quedará fijado el reglamento de puntuación vigente. Desde
              ese momento se pueden crear las listas.
            </p>
          }
          textoConfirmar="Sí, iniciar"
          ocupado={ocupado}
          onConfirmar={() => void ejecutar(() => iniciarPartido(partido.id), 'Partido iniciado.')}
          onCancelar={cerrar}
        />
      )}
      {accion === 'reanudar' && (
        <Confirmacion
          titulo="Reanudar partido"
          mensaje={<p>El juego continuará desde el siguiente enfrentamiento pendiente.</p>}
          textoConfirmar="Sí, reanudar"
          ocupado={ocupado}
          onConfirmar={() => void ejecutar(() => reanudarPartido(partido.id), 'Partido reanudado.')}
          onCancelar={cerrar}
        />
      )}
      {accion === 'suspender' && (
        <DialogoMotivo
          titulo="Suspender partido"
          descripcion="No se podrán registrar resultados hasta reanudarlo. Lo jugado se conserva."
          textoConfirmar="Suspender"
          ocupado={ocupado}
          error={error}
          onConfirmar={(motivo) => void ejecutar(() => suspenderPartido(partido.id, motivo), 'Partido suspendido.')}
          onCancelar={cerrar}
        />
      )}
      {accion === 'reabrir' && (
        <DialogoMotivo
          titulo="Reabrir partido"
          descripcion="El partido pasará a En revisión: solo el administrador podrá corregir resultados en la pestaña Juego. Si una corrección deja a ambos clubes bajo la meta, el partido volverá a En curso."
          textoConfirmar="Reabrir partido"
          ocupado={ocupado}
          error={error}
          onConfirmar={(motivo) => void ejecutar(() => reabrirPartido(partido.id, motivo), 'Partido reabierto: en revisión.')}
          onCancelar={cerrar}
        />
      )}
      {accion === 'cerrarRevision' && (
        <DialogoMotivo
          titulo="Cerrar revisión"
          descripcion="Se verificará la consistencia del partido. Si hay problemas, se indicarán en la pestaña Marcador y el partido seguirá en revisión."
          textoConfirmar="Cerrar revisión"
          ocupado={ocupado}
          error={error}
          onConfirmar={(motivo) => void ejecutar(() => cerrarRevision(partido.id, motivo), 'Revisión cerrada: partido finalizado.')}
          onCancelar={cerrar}
        />
      )}
      {accion === 'cancelar' && (
        <DialogoMotivo
          titulo="Cancelar partido"
          descripcion="El partido quedará cancelado y no podrá reanudarse. Si ya tiene resultados, solo un administrador puede cancelarlo."
          textoConfirmar="Cancelar partido"
          peligro
          ocupado={ocupado}
          error={error}
          onConfirmar={(motivo) => void ejecutar(() => cancelarPartido(partido.id, motivo), 'Partido cancelado.')}
          onCancelar={cerrar}
        />
      )}
    </section>
  )
}
