import { useMemo, useState, type ReactNode } from 'react'
import { CLASE_CAMPO, MensajeError } from '../../componentes/Formulario'
import { Cargando } from '../../componentes/Pantallas'
import { listarCampeonatos } from '../../datos/campeonatos'
import { listarHistorial, obtenerFicha, porcentaje, puntaje, type Participacion } from '../../datos/estadisticas'
import { listarTiposAccion } from '../../datos/juego'
import { listarModalidades } from '../../datos/listas'
import { useCarga } from '../../hooks/useCarga'
import { fechaCorta } from '../../lib/formato'

/** Estadísticas e historial del jugador (secciones 29, 30 y 34). */
export function EstadisticasJugador({ jugadorId }: { jugadorId: string }) {
  const [campeonatoId, setCampeonatoId] = useState('')
  const catalogos = useCarga(async () => {
    const [campeonatos, historial, tipos, modalidades] = await Promise.all([
      listarCampeonatos(),
      listarHistorial(jugadorId),
      listarTiposAccion(),
      listarModalidades(),
    ])
    return { campeonatos: campeonatos.filter((c) => c.estado !== 'CANCELADO'), historial, tipos, modalidades }
  }, [jugadorId])
  const ficha = useCarga(() => obtenerFicha(jugadorId, campeonatoId || null), [jugadorId, campeonatoId])

  if (catalogos.estado.tipo === 'cargando') return <Cargando texto="Calculando estadísticas…" />
  if (catalogos.estado.tipo === 'error') return <MensajeError>{catalogos.estado.mensaje}</MensajeError>
  const { campeonatos, historial, tipos, modalidades } = catalogos.estado.datos

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-xl font-bold">Estadísticas</h2>
        <select
          value={campeonatoId}
          onChange={(e) => setCampeonatoId(e.target.value)}
          className={`${CLASE_CAMPO} max-w-[60%]`}
          aria-label="Campeonato"
        >
          <option value="">Histórico</option>
          {campeonatos.map((c) => (
            <option key={c.id} value={c.id}>
              {c.nombre} {c.temporada}
            </option>
          ))}
        </select>
      </div>

      {ficha.estado.tipo === 'cargando' && <Cargando texto="Calculando…" />}
      {ficha.estado.tipo === 'error' && <MensajeError>{ficha.estado.mensaje}</MensajeError>}
      {ficha.estado.tipo === 'listo' && (
        <>
          <Bloque titulo="Puntaje">
            <p className="text-center text-5xl font-extrabold tabular-nums">{puntaje(ficha.estado.datos.puntos.total)}</p>
            <Tabla
              filas={[
                ['Convocatoria', puntaje(ficha.estado.datos.puntos.convocatoria)],
                ['Resultados', puntaje(ficha.estado.datos.puntos.resultado)],
                ['Acciones positivas', puntaje(ficha.estado.datos.puntos.positivas)],
                ['Penalizaciones', puntaje(ficha.estado.datos.puntos.penalizaciones)],
              ]}
            />
          </Bloque>

          <div className="grid grid-cols-2 gap-3">
            <Bloque titulo="Asistencia">
              <Grande valor={porcentaje(ficha.estado.datos.asistencia.porcentaje)} />
              <Tabla
                filas={[
                  ['Partidos', ficha.estado.datos.asistencia.partidos],
                  ['Presentes', ficha.estado.datos.asistencia.presentes],
                  ['Ausentes', ficha.estado.datos.asistencia.ausentes],
                  ['Justificados', ficha.estado.datos.asistencia.justificados],
                ]}
              />
            </Bloque>
            <Bloque titulo="Resultados">
              <Grande valor={porcentaje(ficha.estado.datos.participacion.porcentaje)} />
              <Tabla
                filas={[
                  ['Convocatorias', ficha.estado.datos.convocatorias.listas],
                  ['EJ', ficha.estado.datos.participacion.ej],
                  ['EG', ficha.estado.datos.participacion.eg],
                  ['EP', ficha.estado.datos.participacion.ep],
                ]}
              />
            </Bloque>
          </div>

          <Bloque titulo="Por modalidad">
            <table className="w-full text-sm tabular-nums">
              <thead>
                <tr className="text-left text-xs uppercase text-slate-500">
                  <th className="py-1 font-semibold">Modalidad</th>
                  <th className="py-1 text-right font-semibold">EJ</th>
                  <th className="py-1 text-right font-semibold">EG</th>
                  <th className="py-1 text-right font-semibold">EP</th>
                  <th className="py-1 text-right font-semibold">%</th>
                </tr>
              </thead>
              <tbody>
                {ficha.estado.datos.por_modalidad.map((m) => (
                  <tr key={m.modalidad} className="border-t border-slate-100">
                    <td className="py-2 font-semibold">{m.nombre}</td>
                    <td className="py-2 text-right">{m.ej}</td>
                    <td className="py-2 text-right">{m.eg}</td>
                    <td className="py-2 text-right">{m.ep}</td>
                    <td className="py-2 text-right font-bold">{porcentaje(m.porcentaje)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Bloque>

          <div className="grid grid-cols-2 gap-3">
            <Bloque titulo="Acciones positivas">
              <Tabla
                filas={[
                  ['Cortes', ficha.estado.datos.acciones.cortes],
                  ['Caídas del rival', ficha.estado.datos.acciones.caidas_rival],
                  ['Reventones rival', ficha.estado.datos.acciones.reventones_rival],
                ]}
              />
            </Bloque>
            <Bloque titulo="Acciones negativas">
              <Tabla
                filas={[
                  ['Veces cortado', ficha.estado.datos.acciones.veces_cortado],
                  ['Caídas propias', ficha.estado.datos.acciones.caidas_propias],
                  ['Reventones propios', ficha.estado.datos.acciones.reventones_propios],
                ]}
              />
            </Bloque>
          </div>
        </>
      )}

      <Historial
        historial={historial.filter((h) => !campeonatoId || h.campeonato_id === campeonatoId)}
        nombreAccion={(c) => tipos.find((t) => t.codigo === c)?.nombre ?? c}
        nombreModalidad={(c) => modalidades.find((m) => m.codigo === c)?.nombre ?? c}
        modalidades={modalidades.map((m) => ({ codigo: m.codigo, nombre: m.nombre }))}
      />
    </div>
  )
}

/** Historial del jugador con filtros de rival, modalidad y fecha (sección 34). */
function Historial({
  historial,
  nombreAccion,
  nombreModalidad,
  modalidades,
}: {
  historial: Participacion[]
  nombreAccion: (codigo: string) => string
  nombreModalidad: (codigo: string) => string
  modalidades: { codigo: string; nombre: string }[]
}) {
  const [rival, setRival] = useState('')
  const [modalidad, setModalidad] = useState('')
  const [desde, setDesde] = useState('')
  const [hasta, setHasta] = useState('')

  const rivales = useMemo(
    () => [...new Map(historial.map((h) => [h.rival_id, h.rival])).entries()].sort((a, b) => a[1].localeCompare(b[1])),
    [historial],
  )
  const visibles = historial.filter(
    (h) =>
      (!rival || h.rival_id === rival) &&
      (!modalidad || h.modalidad_codigo === modalidad) &&
      (!desde || h.fecha >= desde) &&
      (!hasta || h.fecha <= hasta),
  )

  return (
    <Bloque titulo={`Historial (${visibles.length})`}>
      <div className="grid grid-cols-2 gap-2">
        <select value={rival} onChange={(e) => setRival(e.target.value)} className={CLASE_CAMPO} aria-label="Rival">
          <option value="">Todos los rivales</option>
          {rivales.map(([id, nombre]) => (
            <option key={id} value={id}>
              {nombre}
            </option>
          ))}
        </select>
        <select value={modalidad} onChange={(e) => setModalidad(e.target.value)} className={CLASE_CAMPO} aria-label="Modalidad">
          <option value="">Todas las modalidades</option>
          {modalidades.map((m) => (
            <option key={m.codigo} value={m.codigo}>
              {m.nombre}
            </option>
          ))}
        </select>
        <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className={CLASE_CAMPO} aria-label="Desde" />
        <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className={CLASE_CAMPO} aria-label="Hasta" />
      </div>

      {visibles.length === 0 && <p className="py-3 text-center text-slate-500">Sin participaciones registradas.</p>}

      <ul className="divide-y divide-slate-100">
        {visibles.map((h) => {
          const total = Number(h.puntos_resultado) + Number(h.puntos_positivos) + Number(h.puntos_negativos)
          return (
            <li key={h.participante_id} className="flex items-start gap-3 py-3">
              <span
                className={`mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-lg text-sm font-extrabold ${
                  h.resultado === 'GANADO'
                    ? 'bg-green-600 text-white'
                    : h.resultado === 'PERDIDO'
                      ? 'bg-red-600 text-white'
                      : 'bg-slate-100 text-slate-400'
                }`}
              >
                {h.resultado === 'GANADO' ? 'G' : h.resultado === 'PERDIDO' ? 'P' : '—'}
              </span>
              <div className="min-w-0 flex-1 text-sm">
                <p className="font-bold">
                  {nombreModalidad(h.modalidad_codigo)} {h.enfrentamiento_numero} · Lista {h.lista_numero} · vs {h.rival}
                </p>
                <p className="text-xs text-slate-500">
                  {fechaCorta(h.fecha)} · {h.campeonato}
                </p>
                {h.companeros.length > 0 && <p className="text-xs text-slate-600">Con {h.companeros.join(' y ')}</p>}
                <p className="text-xs text-slate-600">
                  {!h.jugado
                    ? h.estado_codigo === 'PENDIENTE'
                      ? 'Pendiente'
                      : 'No disputado (fin del partido)'
                    : h.por_secretaria
                      ? 'Por secretaría'
                      : h.acciones.map(nombreAccion).join(', ') || 'Sin acción propia'}
                </p>
              </div>
              <span className="shrink-0 text-sm font-bold tabular-nums" title="Resultado + acciones (sin convocatoria)">
                {h.jugado ? puntaje(total) : ''}
              </span>
            </li>
          )
        })}
      </ul>
      <p className="text-xs text-slate-500">
        El puntaje de cada fila incluye resultado y acciones. La convocatoria (+0,5 por lista) se suma en el total.
      </p>
    </Bloque>
  )
}

function Bloque({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <section className="space-y-2 rounded-2xl bg-white p-4 shadow-sm">
      <h3 className="text-sm font-bold uppercase tracking-wide text-slate-500">{titulo}</h3>
      {children}
    </section>
  )
}

function Grande({ valor }: { valor: string }) {
  return <p className="text-3xl font-extrabold tabular-nums">{valor}</p>
}

function Tabla({ filas }: { filas: [string, string | number][] }) {
  return (
    <dl className="space-y-1 text-sm">
      {filas.map(([etiqueta, valor]) => (
        <div key={etiqueta} className="flex justify-between gap-2">
          <dt className="text-slate-600">{etiqueta}</dt>
          <dd className="font-bold tabular-nums">{valor}</dd>
        </div>
      ))}
    </dl>
  )
}
