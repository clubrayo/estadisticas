import { useState } from 'react'
import type { ParticipanteJuego, Resultado, TipoAccion } from '../../datos/juego'
import { problemaAcciones, type AccionElegida } from '../../lib/reglasAcciones'

export interface Eleccion {
  resultado: Resultado
  porSecretaria: boolean
  acciones: AccionElegida[]
}

interface Props {
  participantes: ParticipanteJuego[]
  nombres: Map<string, string>
  tipos: TipoAccion[]
  /** DIRECTIVA o ADMINISTRADOR: permite registrar el punto por secretaría. */
  permiteSecretaria: boolean
  deshabilitado?: boolean
  /** Recibe la elección cuando cumple las reglas, o null mientras falte algo. */
  onCompleto: (eleccion: Eleccion | null) => void
}

const BOTON_BASE = 'min-h-14 w-full rounded-2xl px-4 text-lg font-extrabold disabled:opacity-50'

/**
 * Registro en pasos (secciones 23 a 26, regla de la migración 004):
 *   1. GANÓ / PERDIÓ (o por secretaría, sin acciones).
 *   2. Individual: una causa. Dupla o trío: las acciones de cada integrante
 *      (varias por jugador; como máximo una negativa).
 */
export function AsistenteResultado({ participantes, nombres, tipos, permiteSecretaria, deshabilitado, onCompleto }: Props) {
  const [resultado, setResultado] = useState<Resultado | null>(null)
  const [porSecretaria, setPorSecretaria] = useState(false)
  const [acciones, setAcciones] = useState<AccionElegida[]>([])

  const cupo = participantes.length
  const individual = cupo === 1
  const nombre = (id: string) => nombres.get(id) ?? 'Jugador'
  const polaridad = (codigo: string) => tipos.find((t) => t.codigo === codigo)?.polaridad
  const problema =
    resultado && !porSecretaria
      ? problemaAcciones({
          cupo,
          gano: resultado === 'GANADO',
          integrantes: participantes.map((p) => p.jugador_id),
          acciones,
          polaridad,
          nombre,
        })
      : null

  function avisar(r: Resultado | null, secretaria: boolean, lista: AccionElegida[]) {
    if (!r) return onCompleto(null)
    if (secretaria) return onCompleto({ resultado: r, porSecretaria: true, acciones: [] })
    const falta = problemaAcciones({
      cupo,
      gano: r === 'GANADO',
      integrantes: participantes.map((p) => p.jugador_id),
      acciones: lista,
      polaridad,
      nombre,
    })
    onCompleto(falta ? null : { resultado: r, porSecretaria: false, acciones: lista })
  }

  function elegirResultado(r: Resultado) {
    setResultado(r)
    setAcciones([])
    avisar(r, porSecretaria, [])
  }

  function cambiarSecretaria(valor: boolean) {
    setPorSecretaria(valor)
    setAcciones([])
    avisar(resultado, valor, [])
  }

  function cambiarAcciones(lista: AccionElegida[]) {
    setAcciones(lista)
    avisar(resultado, porSecretaria, lista)
  }

  const positivas = tipos.filter((t) => t.polaridad === 'POSITIVA')
  const negativas = tipos.filter((t) => t.polaridad === 'NEGATIVA')

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3">
        {(['GANADO', 'PERDIDO'] as const).map((r) => {
          const elegido = resultado === r
          const color = r === 'GANADO' ? 'green' : 'red'
          return (
            <button
              key={r}
              type="button"
              disabled={deshabilitado}
              onClick={() => elegirResultado(r)}
              aria-pressed={elegido}
              className={`${BOTON_BASE} ${
                elegido
                  ? color === 'green'
                    ? 'bg-green-600 text-white'
                    : 'bg-red-600 text-white'
                  : color === 'green'
                    ? 'border-2 border-green-600 text-green-700 active:bg-green-50'
                    : 'border-2 border-red-600 text-red-700 active:bg-red-50'
              }`}
            >
              {r === 'GANADO' ? 'GANÓ' : 'PERDIÓ'}
            </button>
          )
        })}
      </div>

      {resultado && permiteSecretaria && (
        <label className="flex min-h-11 items-center gap-3 rounded-xl bg-slate-100 px-3 font-semibold">
          <input
            type="checkbox"
            checked={porSecretaria}
            disabled={deshabilitado}
            onChange={(e) => cambiarSecretaria(e.target.checked)}
            className="size-5"
          />
          Por secretaría (decisión oficial, sin acciones)
        </label>
      )}

      {resultado && !porSecretaria && individual && (
        <div className="space-y-2">
          <p className="text-sm font-bold uppercase tracking-wide text-slate-600">Causa</p>
          <div className="grid gap-2">
            {(resultado === 'GANADO' ? positivas : negativas).map((t) => {
              const elegido = acciones[0]?.tipoAccion === t.codigo
              return (
                <button
                  key={t.codigo}
                  type="button"
                  disabled={deshabilitado}
                  onClick={() => cambiarAcciones([{ jugadorId: participantes[0].jugador_id, tipoAccion: t.codigo }])}
                  aria-pressed={elegido}
                  className={`min-h-12 rounded-xl px-4 text-left font-bold ${
                    elegido
                      ? resultado === 'GANADO'
                        ? 'bg-green-600 text-white'
                        : 'bg-red-600 text-white'
                      : 'bg-white ring-2 ring-slate-300 active:bg-slate-100'
                  }`}
                >
                  {t.nombre}
                </button>
              )
            })}
          </div>
        </div>
      )}

      {resultado && !porSecretaria && !individual && (
        <div className="space-y-3">
          <p className="text-sm font-bold uppercase tracking-wide text-slate-600">Acciones de cada integrante</p>
          {participantes.map((p) => {
            const propias = acciones
              .map((a, indice) => ({ ...a, indice }))
              .filter((a) => a.jugadorId === p.jugador_id)
            const tieneNegativa = propias.some((a) => polaridad(a.tipoAccion) === 'NEGATIVA')
            const lleno = propias.length >= cupo
            return (
              <div key={p.id} className="space-y-2 rounded-xl bg-slate-50 p-3 ring-1 ring-slate-200">
                <p className="font-bold">{nombre(p.jugador_id)}</p>
                {propias.length > 0 && (
                  <div className="flex flex-wrap gap-2">
                    {propias.map((a) => (
                      <button
                        key={a.indice}
                        type="button"
                        disabled={deshabilitado}
                        onClick={() => cambiarAcciones(acciones.filter((_, i) => i !== a.indice))}
                        aria-label={`Quitar ${tipos.find((t) => t.codigo === a.tipoAccion)?.nombre}`}
                        className={`min-h-10 rounded-full px-3 text-sm font-bold text-white ${
                          polaridad(a.tipoAccion) === 'POSITIVA' ? 'bg-green-600' : 'bg-red-600'
                        }`}
                      >
                        {tipos.find((t) => t.codigo === a.tipoAccion)?.nombre} ✕
                      </button>
                    ))}
                  </div>
                )}
                <div className="grid grid-cols-2 gap-2">
                  {[...positivas, ...negativas].map((t) => {
                    const bloqueado = deshabilitado || lleno || (t.polaridad === 'NEGATIVA' && tieneNegativa)
                    return (
                      <button
                        key={t.codigo}
                        type="button"
                        disabled={bloqueado}
                        onClick={() => cambiarAcciones([...acciones, { jugadorId: p.jugador_id, tipoAccion: t.codigo }])}
                        className={`min-h-11 rounded-lg px-2 text-left text-sm font-semibold ring-1 disabled:opacity-30 ${
                          t.polaridad === 'POSITIVA'
                            ? 'bg-white text-green-800 ring-green-300 active:bg-green-50'
                            : 'bg-white text-red-800 ring-red-300 active:bg-red-50'
                        }`}
                      >
                        + {t.nombre}
                      </button>
                    )
                  })}
                </div>
              </div>
            )
          })}
          {problema && (
            <p className="rounded-xl bg-amber-50 px-3 py-2 text-sm font-semibold text-amber-800">{problema}</p>
          )}
        </div>
      )}
    </div>
  )
}
