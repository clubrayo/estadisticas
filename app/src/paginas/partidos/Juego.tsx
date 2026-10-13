import { useState } from 'react'
import { Link } from 'react-router'
import { AreaTexto, MensajeError, MensajeExito } from '../../componentes/Formulario'
import { BotonPrincipal, Cargando } from '../../componentes/Pantallas'
import {
  cargarJuego,
  listarTiposAccion,
  registrarResultado,
  type EnfrentamientoJuego,
  type EstadoJuego,
  type RespuestaJuego,
} from '../../datos/juego'
import { listarJugadores } from '../../datos/jugadores'
import { listarModalidades, NOMBRE_ESTADO_LISTA } from '../../datos/listas'
import { ladosDelPartido } from '../../datos/partidos'
import { useCarga } from '../../hooks/useCarga'
import { codigoDeError, mensajeDeError } from '../../lib/errores'
import { tieneRol } from '../../lib/roles'
import { useSesion } from '../../sesion/contexto'
import { AsistenteResultado, type Eleccion } from './AsistenteResultado'
import { usePartido } from './contextoPartido'
import { Correccion } from './Correccion'
import { PartidoFinalizado } from './PartidoFinalizado'
import {
  accionesParaEnviar,
  accionesRegistradas,
  etiquetaEnfrentamiento,
  problemaRegistrado,
  siguienteEnfrentamiento,
  textoAcciones,
  textoEleccion,
  type Catalogos,
} from './juegoTextos'

/** Errores tras los que conviene releer el estado del juego (otro usuario registró antes). */
const ERRORES_DE_DESFASE = ['CONFLICTO_VERSION', 'ENFRENTAMIENTO_YA_REGISTRADO', 'ENFRENTAMIENTO_NO_PENDIENTE', 'ORDEN_DE_JUEGO']

/** Pestaña Juego: registro de enfrentamientos (secciones 23 a 28). */
export function Juego() {
  const { partido } = usePartido()
  const { estado, recargar } = useCarga(async () => {
    const [juego, tipos, jugadores, modalidades] = await Promise.all([
      cargarJuego(partido.id),
      listarTiposAccion(),
      listarJugadores(),
      listarModalidades(),
    ])
    return { juego, catalogos: { tipos, modalidades, nombres: new Map(jugadores.map((j) => [j.id, j.nombre_completo])) } }
  }, [partido.id])

  if (estado.tipo === 'cargando') return <Cargando texto="Cargando juego…" />
  if (estado.tipo === 'error') return <MensajeError>{estado.mensaje}</MensajeError>
  return <Tablero juego={estado.datos.juego} catalogos={estado.datos.catalogos} recargarJuego={recargar} />
}

function Tablero({ juego, catalogos, recargarJuego }: { juego: EstadoJuego; catalogos: Catalogos; recargarJuego: () => void }) {
  const { partido, recargar: recargarPartido } = usePartido()
  const { roles } = useSesion()
  const { propio, rival } = ladosDelPartido(partido)
  const [aviso, setAviso] = useState<string | null>(null)
  const [verLista, setVerLista] = useState<string | null>(null)
  const [corrigiendo, setCorrigiendo] = useState<EnfrentamientoJuego | null>(null)

  const puedeOperar = tieneRol(roles, ['CAPITAN', 'DIRECTIVA'], propio.id)
  const esDirectiva = tieneRol(roles, ['DIRECTIVA'], propio.id)
  // EN_CURSO: DIRECTIVA o ADMINISTRADOR · EN_REVISION (partido reabierto): solo ADMINISTRADOR.
  const puedeCorregir =
    (partido.estado === 'EN_CURSO' && esDirectiva) || (partido.estado === 'EN_REVISION' && tieneRol(roles, []))

  const listaPorId = new Map(juego.listas.map((l) => [l.id, l]))
  const siguiente = siguienteEnfrentamiento(juego, partido.estado)
  const listaActual =
    juego.listas.find((l) => l.id === verLista) ??
    (siguiente ? listaPorId.get(siguiente.lista_id) : juego.listas[juego.listas.length - 1])

  function refrescar() {
    recargarJuego()
    recargarPartido()
  }

  function alRegistrar(r: RespuestaJuego, texto: string) {
    setVerLista(null)
    setAviso(r.ya_registrado ? `Ya estaba registrado: ${texto}.` : `Registrado: ${texto}.`)
    refrescar()
  }

  return (
    <div className="space-y-4">
      {aviso && <MensajeExito>{aviso}</MensajeExito>}

      {(partido.estado === 'FINALIZADO' || partido.estado === 'EN_REVISION') && <PartidoFinalizado partido={partido} />}

      {siguiente && puedeOperar && (
        <RegistroSiguiente
          key={`${siguiente.id}-${siguiente.version}`}
          enfrentamiento={siguiente}
          numeroLista={listaPorId.get(siguiente.lista_id)?.numero ?? 0}
          catalogos={catalogos}
          permiteSecretaria={esDirectiva}
          alRegistrar={alRegistrar}
          alDesfase={refrescar}
        />
      )}

      {!siguiente && partido.estado === 'EN_CURSO' && <SinPendientes juego={juego} />}
      {partido.estado === 'PROGRAMADO' && <Nota>Inicie el partido para registrar enfrentamientos.</Nota>}
      {partido.estado === 'SUSPENDIDO' && <Nota>Partido suspendido. Reanúdelo para continuar registrando.</Nota>}
      {partido.estado === 'CANCELADO' && <Nota>Partido cancelado.</Nota>}
      {siguiente && !puedeOperar && <Nota>Solo lectura: su rol no permite registrar resultados.</Nota>}

      {juego.listas.length > 1 && (
        <nav aria-label="Ver lista" className="-mx-4 overflow-x-auto px-4">
          <ul className="flex gap-2">
            {juego.listas.map((l) => (
              <li key={l.id}>
                <button
                  type="button"
                  onClick={() => setVerLista(l.id)}
                  aria-pressed={l.id === listaActual?.id}
                  className={`min-h-11 rounded-full px-4 text-sm font-bold whitespace-nowrap ${
                    l.id === listaActual?.id ? 'bg-slate-900 text-white' : 'bg-white text-slate-700 ring-1 ring-slate-300'
                  }`}
                >
                  Lista {l.numero}
                </button>
              </li>
            ))}
          </ul>
        </nav>
      )}

      {listaActual && (
        <ResumenLista
          numero={listaActual.numero}
          estadoLista={NOMBRE_ESTADO_LISTA[listaActual.estado]}
          enfrentamientos={juego.enfrentamientos.filter((e) => e.lista_id === listaActual.id)}
          siguienteId={siguiente?.id}
          catalogos={catalogos}
          propioId={propio.id}
          nombrePropio={propio.nombre_corto}
          nombreRival={rival.nombre_corto}
          puedeCorregir={puedeCorregir}
          onCorregir={setCorrigiendo}
        />
      )}

      {corrigiendo && (
        <Correccion
          enfrentamiento={corrigiendo}
          catalogos={catalogos}
          onCerrar={() => setCorrigiendo(null)}
          onCorregido={(texto) => {
            setCorrigiendo(null)
            setAviso(`Corregido: ${texto}.`)
            refrescar()
          }}
        />
      )}
    </div>
  )
}

function RegistroSiguiente({
  enfrentamiento,
  numeroLista,
  catalogos,
  permiteSecretaria,
  alRegistrar,
  alDesfase,
}: {
  enfrentamiento: EnfrentamientoJuego
  numeroLista: number
  catalogos: Catalogos
  permiteSecretaria: boolean
  alRegistrar: (r: RespuestaJuego, texto: string) => void
  alDesfase: () => void
}) {
  const [eleccion, setEleccion] = useState<Eleccion | null>(null)
  const [motivo, setMotivo] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const etiqueta = etiquetaEnfrentamiento(enfrentamiento, catalogos.modalidades)

  async function registrar() {
    if (!eleccion || enviando) return
    if (eleccion.porSecretaria && !motivo.trim()) {
      setError('Indique el motivo de la decisión por secretaría.')
      return
    }
    setEnviando(true)
    setError(null)
    try {
      const r = await registrarResultado(
        enfrentamiento.id,
        eleccion.resultado,
        accionesParaEnviar(eleccion),
        enfrentamiento.version,
        eleccion.porSecretaria,
        eleccion.porSecretaria ? motivo.trim() : null,
      )
      alRegistrar(r, `${etiqueta} · ${textoEleccion(eleccion, catalogos)}`)
    } catch (e) {
      setError(mensajeDeError(e))
      setEnviando(false)
      if (ERRORES_DE_DESFASE.includes(codigoDeError(e) ?? '')) alDesfase()
    }
  }

  return (
    <section className="space-y-4 rounded-2xl border-2 border-slate-900 bg-white p-4 shadow-sm">
      <div>
        <p className="text-xs font-bold uppercase tracking-wide text-amber-700">Siguiente · Lista {numeroLista}</p>
        <h2 className="text-2xl font-extrabold">{etiqueta}</h2>
        <p className="text-slate-700">
          {enfrentamiento.participantes.map((p) => catalogos.nombres.get(p.jugador_id) ?? 'Jugador').join(' · ')}
        </p>
      </div>

      <AsistenteResultado
        participantes={enfrentamiento.participantes}
        nombres={catalogos.nombres}
        tipos={catalogos.tipos}
        permiteSecretaria={permiteSecretaria}
        deshabilitado={enviando}
        onCompleto={setEleccion}
      />

      {eleccion && (
        <div className="space-y-3 rounded-xl bg-slate-100 p-3">
          <p className="font-bold">{textoEleccion(eleccion, catalogos)}</p>
          {eleccion.porSecretaria && (
            <AreaTexto etiqueta="Motivo de la decisión (obligatorio)" value={motivo} onChange={(e) => setMotivo(e.target.value)} />
          )}
          {error && <MensajeError>{error}</MensajeError>}
          <BotonPrincipal onClick={() => void registrar()} disabled={enviando}>
            {enviando ? 'Registrando…' : 'Registrar resultado'}
          </BotonPrincipal>
        </div>
      )}
    </section>
  )
}

function ResumenLista({
  numero,
  estadoLista,
  enfrentamientos,
  siguienteId,
  catalogos,
  propioId,
  nombrePropio,
  nombreRival,
  puedeCorregir,
  onCorregir,
}: {
  numero: number
  estadoLista: string
  enfrentamientos: EnfrentamientoJuego[]
  siguienteId?: string
  catalogos: Catalogos
  propioId: string
  nombrePropio: string
  nombreRival: string
  puedeCorregir: boolean
  onCorregir: (e: EnfrentamientoJuego) => void
}) {
  const disputados = enfrentamientos.filter((e) => e.estado_codigo === 'DISPUTADO')
  const ganados = disputados.filter((e) => e.resultado?.ganador_club_id === propioId).length
  const porModalidad = catalogos.modalidades.map((m) => {
    const delTipo = enfrentamientos.filter((e) => e.modalidad_codigo === m.codigo)
    return { nombre: m.nombre, jugados: delTipo.filter((e) => e.estado_codigo === 'DISPUTADO').length, total: delTipo.length }
  })

  return (
    <section className="space-y-3">
      <div className="rounded-2xl bg-white p-4 shadow-sm">
        <div className="flex items-center justify-between">
          <h2 className="font-bold">
            Lista N° {numero} <span className="font-normal text-slate-500">· {estadoLista}</span>
          </h2>
          <p className="text-lg font-extrabold tabular-nums">
            {nombrePropio} {ganados} – {disputados.length - ganados} {nombreRival}
          </p>
        </div>
        <p className="mt-1 text-sm text-slate-600">
          {disputados.length} / {enfrentamientos.length} enfrentamientos disputados ·{' '}
          {porModalidad.map((m) => `${m.nombre} ${m.jugados}/${m.total}`).join(' · ')}
        </p>
      </div>

      <ul className="space-y-2">
        {enfrentamientos.map((e) => {
          const r = e.resultado
          const gano = r?.ganador_club_id === propioId
          const incompleto = e.estado_codigo === 'DISPUTADO' ? problemaRegistrado(e, propioId, catalogos) : null
          return (
            <li
              key={e.id}
              className={`flex items-center gap-3 rounded-2xl bg-white px-3 py-2 shadow-sm ${
                e.id === siguienteId ? 'ring-2 ring-amber-500' : ''
              }`}
            >
              <span
                className={`flex size-10 shrink-0 items-center justify-center rounded-xl text-sm font-extrabold ${
                  e.estado_codigo === 'DISPUTADO'
                    ? gano
                      ? 'bg-green-600 text-white'
                      : 'bg-red-600 text-white'
                    : 'bg-slate-100 text-slate-400'
                }`}
              >
                {e.estado_codigo === 'DISPUTADO' ? (gano ? 'G' : 'P') : e.estado_codigo === 'PENDIENTE' ? '·' : '—'}
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate font-bold">{etiquetaEnfrentamiento(e, catalogos.modalidades)}</p>
                <p className="truncate text-xs text-slate-600">
                  {e.estado_codigo === 'DISPUTADO' && r
                    ? r.por_secretaria
                      ? `Por secretaría · ${r.motivo_secretaria ?? ''}`
                      : textoAcciones(accionesRegistradas(e), catalogos)
                    : e.estado_codigo === 'NO_DISPUTADO_FIN_PARTIDO'
                      ? 'No disputado (fin del partido)'
                      : e.participantes.map((p) => catalogos.nombres.get(p.jugador_id) ?? '').join(' · ')}
                </p>
                {incompleto && (
                  <p className="mt-1 rounded-md bg-amber-100 px-2 py-0.5 text-xs font-bold text-amber-800">
                    Acciones incompletas · {incompleto}
                  </p>
                )}
              </div>
              {puedeCorregir && e.estado_codigo === 'DISPUTADO' && (
                <button
                  type="button"
                  onClick={() => onCorregir(e)}
                  className="min-h-11 shrink-0 rounded-xl px-3 text-sm font-bold text-amber-700 ring-1 ring-amber-300 active:bg-amber-50"
                >
                  Corregir
                </button>
              )}
            </li>
          )
        })}
      </ul>
    </section>
  )
}

function SinPendientes({ juego }: { juego: EstadoJuego }) {
  const ultima = juego.listas[juego.listas.length - 1]
  let texto = 'Cree la primera lista en la pestaña Listas.'
  if (ultima?.estado === 'BORRADOR') texto = `Confirme la Lista N° ${ultima.numero} en la pestaña Listas para comenzar a registrar.`
  else if (ultima) texto = `Lista N° ${ultima.numero} finalizada. Cree la Lista N° ${ultima.numero + 1} en la pestaña Listas.`
  return (
    <div className="space-y-3 rounded-2xl bg-white p-5 text-center shadow-sm">
      <p className="text-slate-700">{texto}</p>
      <Link to="../listas" relative="path" className="inline-block font-bold text-amber-700 underline">
        Ir a Listas
      </Link>
    </div>
  )
}

function Nota({ children }: { children: string }) {
  return <p className="rounded-xl bg-slate-200 px-4 py-3 text-sm font-semibold text-slate-700">{children}</p>
}

