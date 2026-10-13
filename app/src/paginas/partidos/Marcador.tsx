import { useEffect } from 'react'
import { Link } from 'react-router'
import { MensajeError } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import { cargarJuego, type EstadoJuego } from '../../datos/juego'
import { listarModalidades, NOMBRE_ESTADO_LISTA, type Modalidad } from '../../datos/listas'
import { ladosDelPartido, verificarPartido } from '../../datos/partidos'
import { useCarga } from '../../hooks/useCarga'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'
import { usePartido } from './contextoPartido'
import { siguienteEnfrentamiento } from './juegoTextos'
import { PartidoFinalizado } from './PartidoFinalizado'

/** Cada cuánto se actualiza solo el marcador mientras el partido está abierto. */
const SEGUNDOS_ACTUALIZACION = 10

/** Pestaña Marcador: estado en vivo, lista actual y marcador progresivo (secciones 27, 28 y 35). */
export function Marcador() {
  const { partido, recargar: recargarPartido } = usePartido()
  const { roles } = useSesion()
  const { propio } = ladosDelPartido(partido)
  const esAdmin = tieneRol(roles, [])
  const revisando = partido.estado === 'EN_REVISION'
  const { estado, recargar } = useCarga(async () => {
    const [juego, modalidades, problemas] = await Promise.all([
      cargarJuego(partido.id),
      listarModalidades(),
      revisando && esAdmin ? verificarPartido(partido.id) : Promise.resolve(null),
    ])
    return { juego, modalidades, problemas, leido: new Date() }
  }, [partido.id, partido.version, revisando, esAdmin])

  // Actualización automática mientras el partido está en juego (para quien solo mira el marcador).
  const enVivo = partido.estado === 'EN_CURSO' || partido.estado === 'SUSPENDIDO'
  useEffect(() => {
    if (!enVivo) return
    const temporizador = window.setInterval(() => {
      if (document.visibilityState === 'visible' && navigator.onLine) recargarPartido()
    }, SEGUNDOS_ACTUALIZACION * 1000)
    return () => window.clearInterval(temporizador)
  }, [enVivo, recargarPartido])

  if (estado.tipo === 'cargando') return <Cargando texto="Cargando marcador…" />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>

  const { juego, modalidades, problemas, leido } = estado.datos
  const puedeRegistrar = partido.estado === 'EN_CURSO' && tieneRol(roles, ['CAPITAN', 'DIRECTIVA'], propio.id)

  return (
    <div className="space-y-4">
      {(partido.estado === 'FINALIZADO' || revisando) && <PartidoFinalizado partido={partido} />}

      <ListaActual juego={juego} modalidades={modalidades} propioId={propio.id} puedeRegistrar={puedeRegistrar} />

      <Progresion juego={juego} propioId={propio.id} />

      {revisando && esAdmin && problemas && (
        <section
          className={`space-y-2 rounded-2xl p-4 ${problemas.length ? 'bg-amber-50 text-amber-900' : 'bg-green-50 text-green-900'}`}
        >
          <h2 className="font-bold">Verificación del partido</h2>
          {problemas.length === 0 ? (
            <p>Sin inconsistencias: puede cerrar la revisión.</p>
          ) : (
            <>
              <ul className="list-disc space-y-1 pl-5 text-sm">
                {problemas.map((p) => (
                  <li key={p}>{p}</li>
                ))}
              </ul>
              <p className="text-sm">Corrija en la pestaña Juego antes de cerrar la revisión.</p>
            </>
          )}
          <button type="button" onClick={recargar} className="min-h-11 text-sm font-bold underline">
            Volver a verificar
          </button>
        </section>
      )}

      <p className="text-center text-xs text-slate-500">
        Actualizado a las {leido.toLocaleTimeString('es-CL')}
        {enVivo && ` · se actualiza cada ${SEGUNDOS_ACTUALIZACION} s`}
      </p>
    </div>
  )
}

function ListaActual({
  juego,
  modalidades,
  propioId,
  puedeRegistrar,
}: {
  juego: EstadoJuego
  modalidades: Modalidad[]
  propioId: string
  puedeRegistrar: boolean
}) {
  const { partido } = usePartido()
  const { propio, rival } = ladosDelPartido(partido)
  const siguiente = siguienteEnfrentamiento(juego, partido.estado)
  const lista = siguiente ? juego.listas.find((l) => l.id === siguiente.lista_id) : juego.listas[juego.listas.length - 1]

  if (!lista) {
    return (
      <section className="rounded-2xl bg-white p-5 text-center text-slate-600 shadow-sm">
        {partido.estado === 'PROGRAMADO' ? 'El partido aún no comienza.' : 'Aún no hay listas en este partido.'}
      </section>
    )
  }

  const enfrentamientos = juego.enfrentamientos.filter((e) => e.lista_id === lista.id)
  const disputados = enfrentamientos.filter((e) => e.estado_codigo === 'DISPUTADO')
  const ganados = disputados.filter((e) => e.resultado?.ganador_club_id === propioId).length

  return (
    <section className="space-y-3 rounded-2xl bg-white p-4 shadow-sm">
      <div className="flex items-center justify-between">
        <p className="text-sm font-bold uppercase tracking-wide text-slate-500">
          {siguiente ? 'Lista actual' : 'Última lista'}: N° {lista.numero}
        </p>
        <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-bold text-slate-700">
          {NOMBRE_ESTADO_LISTA[lista.estado]}
        </span>
      </div>
      <p className="text-center text-3xl font-extrabold tabular-nums">
        {propio.nombre_corto} {ganados} – {disputados.length - ganados} {rival.nombre_corto}
      </p>
      <p className="text-center text-sm text-slate-600">
        {disputados.length} / {enfrentamientos.length} enfrentamientos disputados
      </p>
      <ul className="space-y-2">
        {modalidades.map((m) => {
          const delTipo = enfrentamientos.filter((e) => e.modalidad_codigo === m.codigo)
          const jugados = delTipo.filter((e) => e.estado_codigo === 'DISPUTADO').length
          return (
            <li key={m.codigo} className="flex items-center gap-3">
              <span className="w-24 text-sm font-semibold">{m.nombre}</span>
              <span className="h-2.5 flex-1 overflow-hidden rounded-full bg-slate-200">
                <span
                  className="block h-full rounded-full bg-slate-900"
                  style={{ width: `${delTipo.length ? (jugados * 100) / delTipo.length : 0}%` }}
                />
              </span>
              <span className="w-12 text-right text-sm font-bold tabular-nums">
                {jugados} / {delTipo.length}
              </span>
            </li>
          )
        })}
      </ul>
      {puedeRegistrar && siguiente && (
        <Link
          to="../juego"
          relative="path"
          className="flex min-h-14 items-center justify-center rounded-2xl bg-green-600 text-lg font-extrabold text-white active:bg-green-700"
        >
          CONTINUAR REGISTRO
        </Link>
      )}
      {puedeRegistrar && !siguiente && (
        <Link
          to="../listas"
          relative="path"
          className="flex min-h-14 items-center justify-center rounded-2xl bg-slate-900 text-lg font-extrabold text-white active:bg-slate-700"
        >
          {lista.estado === 'BORRADOR' ? `CONFIRMAR LISTA N° ${lista.numero}` : `CREAR LISTA N° ${lista.numero + 1}`}
        </Link>
      )}
    </section>
  )
}

/** Marcador progresivo: resultado de cada lista y acumulado (sección 35). */
function Progresion({ juego, propioId }: { juego: EstadoJuego; propioId: string }) {
  const { partido } = usePartido()
  const { propio, rival } = ladosDelPartido(partido)
  if (juego.listas.length === 0) return null

  const parciales = juego.listas.map((l) => {
    const disputados = juego.enfrentamientos.filter((e) => e.lista_id === l.id && e.estado_codigo === 'DISPUTADO')
    const ganados = disputados.filter((e) => e.resultado?.ganador_club_id === propioId).length
    return { lista: l, ganados, perdidos: disputados.length - ganados }
  })
  const filas = parciales.map((p, i) => ({
    ...p,
    acumuladoPropio: parciales.slice(0, i + 1).reduce((s, x) => s + x.ganados, 0),
    acumuladoRival: parciales.slice(0, i + 1).reduce((s, x) => s + x.perdidos, 0),
  }))

  return (
    <section className="rounded-2xl bg-white p-4 shadow-sm">
      <h2 className="mb-2 font-bold">Marcador por lista</h2>
      <table className="w-full text-sm tabular-nums">
        <thead>
          <tr className="text-left text-xs uppercase text-slate-500">
            <th className="py-1 font-semibold">Lista</th>
            <th className="py-1 text-center font-semibold">Resultado</th>
            <th className="py-1 text-right font-semibold">Acumulado</th>
          </tr>
        </thead>
        <tbody>
          {filas.map((f) => (
            <tr key={f.lista.id} className="border-t border-slate-100">
              <td className="py-2 font-semibold">N° {f.lista.numero}</td>
              <td className="py-2 text-center">
                {f.ganados} – {f.perdidos}
              </td>
              <td className="py-2 text-right font-bold">
                {f.acumuladoPropio} – {f.acumuladoRival}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="mt-2 text-xs text-slate-500">
        {propio.nombre_corto} – {rival.nombre_corto} · meta {partido.puntaje_objetivo}
      </p>
    </section>
  )
}
