import { useState, type ReactNode } from 'react'
import { Link } from 'react-router'
import { CLASE_CAMPO, MensajeError } from '../componentes/Formulario'
import { Creditos } from '../componentes/Marca'
import { Cargando } from '../componentes/Pantallas'
import { TarjetaPartido } from '../componentes/TarjetaPartido'
import { campeonatoActual, listarCampeonatos, type Campeonato } from '../datos/campeonatos'
import { listarClubesVisibles, obtenerEstadisticasClub, type EstadisticasClub } from '../datos/club'
import type { ClubResumen } from '../datos/clubes'
import { porcentaje } from '../datos/estadisticas'
import { listarPartidos } from '../datos/partidos'
import { useCarga } from '../hooks/useCarga'
import { NOMBRE_ROL } from '../lib/roles'
import { useSesion } from '../sesion/contexto'
import { SelectorAlcance } from './estadisticas/Comunes'

/** Inicio: partidos en curso y dashboard del club (sección 33). */
export function Inicio() {
  const { perfil, roles } = useSesion()
  const { estado } = useCarga(async () => {
    const [clubes, campeonatos, partidos] = await Promise.all([listarClubesVisibles(), listarCampeonatos(), listarPartidos()])
    return { clubes, campeonatos, partidos }
  }, [])

  const esAdmin = roles.some((r) => r.rol === 'ADMINISTRADOR')
  const propios = new Set(roles.map((r) => r.clubId).filter(Boolean))

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold">Hola, {perfil?.nombre}</h1>

      {estado.tipo === 'cargando' && <Cargando />}
      {estado.tipo === 'error' && <MensajeError>{estado.mensaje}</MensajeError>}
      {estado.tipo === 'listo' && (
        <>
          {estado.datos.partidos
            .filter((p) => ['EN_CURSO', 'SUSPENDIDO', 'EN_REVISION'].includes(p.estado))
            .map((p) => (
              <TarjetaPartido key={p.id} partido={p} />
            ))}
          <Dashboard
            clubes={estado.datos.clubes.filter((c) => esAdmin || propios.has(c.id))}
            campeonatos={estado.datos.campeonatos.filter((c) => c.estado !== 'CANCELADO')}
          />
        </>
      )}

      {esAdmin && (
        <Link
          to="/auditoria"
          className="flex min-h-12 items-center justify-center rounded-xl border-2 border-slate-300 bg-white font-bold text-slate-800 active:bg-slate-100"
        >
          Ver auditoría
        </Link>
      )}

      <section className="rounded-2xl bg-white p-4 text-sm shadow-sm">
        <h2 className="font-bold">Sus permisos</h2>
        <ul className="mt-1 text-slate-700">
          {roles.map((r) => (
            <li key={`${r.rol}-${r.clubId ?? 'global'}`}>
              <span className="font-semibold">{NOMBRE_ROL[r.rol]}</span>
              {r.club ? ` · ${r.club}` : ' · todos los clubes'}
            </li>
          ))}
        </ul>
      </section>

      <Creditos className="pt-2" />
    </div>
  )
}

function Dashboard({ clubes, campeonatos }: { clubes: ClubResumen[]; campeonatos: Campeonato[] }) {
  const actual = campeonatoActual(campeonatos)
  const [clubId, setClubId] = useState(clubes[0]?.id ?? '')
  const [alcance, setAlcance] = useState(actual?.id ?? '')
  const campeonatoId = alcance || null

  const { estado } = useCarga(
    async () => (clubId ? obtenerEstadisticasClub(clubId, campeonatoId) : null),
    [clubId, campeonatoId],
  )

  if (clubes.length === 0) return <p className="text-slate-600">Su usuario no tiene un club asignado.</p>

  return (
    <section className="space-y-3">
      <div className="grid gap-2 sm:grid-cols-2">
        {clubes.length > 1 && (
          <select value={clubId} onChange={(e) => setClubId(e.target.value)} className={CLASE_CAMPO} aria-label="Club">
            {clubes.map((c) => (
              <option key={c.id} value={c.id}>
                {c.nombre}
              </option>
            ))}
          </select>
        )}
        <SelectorAlcance campeonatos={campeonatos} actual={actual} valor={alcance} onCambio={setAlcance} />
      </div>

      {clubes.length === 1 && <h2 className="text-lg font-bold">{clubes[0].nombre}</h2>}
      {estado.tipo === 'cargando' && <Cargando texto="Calculando estadísticas del club…" />}
      {estado.tipo === 'error' && <MensajeError>{estado.mensaje}</MensajeError>}
      {estado.tipo === 'listo' && estado.datos && <Indicadores e={estado.datos} />}
    </section>
  )
}

function Indicadores({ e }: { e: EstadisticasClub }) {
  const p = e.partidos
  return (
    <>
      <div className="grid grid-cols-3 gap-2 text-center">
        <Cifra valor={p.jugados} etiqueta="Partidos jugados" />
        <Cifra valor={p.ganados} etiqueta="Ganados" color="text-green-700" />
        <Cifra valor={p.perdidos} etiqueta="Perdidos" color="text-red-700" />
        <Cifra valor={porcentaje(p.efectividad)} etiqueta="Efectividad" color="text-amber-700" />
        <Cifra valor={e.listas_disputadas} etiqueta="Listas disputadas" />
        <Cifra valor={e.jugadores_activos} etiqueta="Jugadores activos" />
      </div>

      <Tarjeta titulo="Puntos oficiales">
        <div className="flex items-baseline justify-center gap-3 tabular-nums">
          <span className="text-4xl font-extrabold text-green-700">{e.puntos.a_favor}</span>
          <span className="text-slate-400">a favor · en contra</span>
          <span className="text-4xl font-extrabold text-red-700">{e.puntos.en_contra}</span>
        </div>
        {p.en_curso > 0 && (
          <p className="mt-1 text-center text-xs text-slate-500">Incluye {p.en_curso} partido(s) en curso.</p>
        )}
      </Tarjeta>

      <Tarjeta titulo="Enfrentamientos ganados">
        <div className="grid grid-cols-3 gap-2 text-center">
          {e.por_modalidad.map((m) => (
            <div key={m.modalidad}>
              <p className="text-3xl font-extrabold tabular-nums">{m.eg}</p>
              <p className="text-xs font-semibold uppercase text-slate-500">{m.nombre}</p>
              <p className="text-xs text-slate-500 tabular-nums">
                de {m.ej} · {porcentaje(m.porcentaje)}
              </p>
            </div>
          ))}
        </div>
      </Tarjeta>

      <div className="grid grid-cols-2 gap-3">
        <Tarjeta titulo="A favor">
          <Fila texto="Cortes" valor={e.acciones.cortes} />
          <Fila texto="Caídas del rival" valor={e.acciones.caidas_rival} />
          <Fila texto="Reventones rival" valor={e.acciones.reventones_rival} />
        </Tarjeta>
        <Tarjeta titulo="En contra">
          <Fila texto="Veces cortado" valor={e.acciones.veces_cortado} />
          <Fila texto="Caídas propias" valor={e.acciones.caidas_propias} />
          <Fila texto="Reventones propios" valor={e.acciones.reventones_propios} />
        </Tarjeta>
      </div>

      <p className="text-xs text-slate-500">
        Partidos jugados = partidos terminados. Se excluyen partidos y campeonatos cancelados.
      </p>
    </>
  )
}

function Cifra({ valor, etiqueta, color = 'text-slate-900' }: { valor: ReactNode; etiqueta: string; color?: string }) {
  return (
    <div className="rounded-2xl bg-white p-3 shadow-sm">
      <p className={`text-2xl font-extrabold tabular-nums ${color}`}>{valor}</p>
      <p className="text-xs font-semibold uppercase leading-tight text-slate-500">{etiqueta}</p>
    </div>
  )
}

function Tarjeta({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <section className="rounded-2xl bg-white p-4 shadow-sm">
      <h3 className="mb-2 text-sm font-bold uppercase text-slate-500">{titulo}</h3>
      {children}
    </section>
  )
}

function Fila({ texto, valor }: { texto: string; valor: number }) {
  return (
    <p className="flex justify-between gap-2 text-sm">
      <span className="text-slate-700">{texto}</span>
      <span className="font-bold tabular-nums">{valor}</span>
    </p>
  )
}
