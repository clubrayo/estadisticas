import { useState } from 'react'
import { AreaTexto, BotonSecundario, MensajeError } from '../../componentes/Formulario'
import { BotonPrincipal } from '../../componentes/Pantallas'
import {
  corregirResultado,
  previsualizarCorreccion,
  type EnfrentamientoJuego,
  type Previsualizacion,
} from '../../datos/juego'
import { ladosDelPartido } from '../../datos/partidos'
import { mensajeDeError } from '../../lib/errores'
import { AsistenteResultado, type Eleccion } from './AsistenteResultado'
import { usePartido } from './contextoPartido'
import { accionesParaEnviar, etiquetaEnfrentamiento, textoEleccion, type Catalogos } from './juegoTextos'

/**
 * Corrección de un resultado registrado por error (DIRECTIVA o ADMINISTRADOR):
 * nuevo resultado + motivo → vista previa del impacto → aplicar.
 * Si la corrección adelanta el cierre del partido (P-1) exige confirmación explícita.
 */
export function Correccion({
  enfrentamiento,
  catalogos,
  onCerrar,
  onCorregido,
}: {
  enfrentamiento: EnfrentamientoJuego
  catalogos: Catalogos
  onCerrar: () => void
  onCorregido: (texto: string) => void
}) {
  const { partido } = usePartido()
  const { propio, rival } = ladosDelPartido(partido)
  const [eleccion, setEleccion] = useState<Eleccion | null>(null)
  const [motivo, setMotivo] = useState('')
  const [previa, setPrevia] = useState<Previsualizacion | null>(null)
  const [aceptaImpacto, setAceptaImpacto] = useState(false)
  const [ocupado, setOcupado] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const etiqueta = etiquetaEnfrentamiento(enfrentamiento, catalogos.modalidades)
  const propioEsLocal = partido.club_local_id === propio.id
  const marcador = (local: number, visitante: number) =>
    propioEsLocal ? `${propio.nombre_corto} ${local} – ${visitante} ${rival.nombre_corto}` : `${propio.nombre_corto} ${visitante} – ${local} ${rival.nombre_corto}`

  function cambiarEleccion(e: Eleccion | null) {
    setEleccion(e)
    setPrevia(null)
    setAceptaImpacto(false)
  }

  async function verImpacto() {
    if (!eleccion) return
    setOcupado(true)
    setError(null)
    try {
      setPrevia(await previsualizarCorreccion(enfrentamiento.id, eleccion.resultado))
    } catch (e) {
      setError(mensajeDeError(e))
    } finally {
      setOcupado(false)
    }
  }

  async function aplicar() {
    if (!eleccion || !previa) return
    setOcupado(true)
    setError(null)
    try {
      await corregirResultado(
        enfrentamiento.id,
        eleccion.resultado,
        accionesParaEnviar(eleccion),
        motivo.trim(),
        enfrentamiento.version,
        previa.requiere_confirmacion && aceptaImpacto,
        eleccion.porSecretaria,
      )
      onCorregido(`${etiqueta} · ${textoEleccion(eleccion, catalogos)}`)
    } catch (e) {
      setError(mensajeDeError(e))
      setOcupado(false)
    }
  }

  return (
    <div className="fixed inset-0 z-40 flex items-end justify-center bg-slate-900/50 sm:items-center" role="dialog" aria-modal="true" aria-label={`Corregir ${etiqueta}`}>
      <div className="max-h-[92dvh] w-full max-w-md space-y-4 overflow-y-auto rounded-t-2xl bg-white p-5 sm:rounded-2xl">
        <div>
          <p className="text-xs font-bold uppercase tracking-wide text-amber-700">Corregir resultado</p>
          <h2 className="text-xl font-extrabold">{etiqueta}</h2>
        </div>

        <AsistenteResultado
          participantes={enfrentamiento.participantes}
          nombres={catalogos.nombres}
          tipos={catalogos.tipos}
          permiteSecretaria
          deshabilitado={ocupado}
          onCompleto={cambiarEleccion}
        />

        <AreaTexto etiqueta="Motivo de la corrección (obligatorio)" value={motivo} onChange={(e) => setMotivo(e.target.value)} />

        {previa && (
          <div className="space-y-2 rounded-xl bg-slate-100 p-3 text-sm">
            <p>
              <span className="font-semibold">Ahora:</span> {marcador(previa.actual.puntaje_local, previa.actual.puntaje_visitante)}
            </p>
            <p>
              <span className="font-semibold">Quedará:</span>{' '}
              {marcador(previa.propuesto.puntaje_local, previa.propuesto.puntaje_visitante)}
              {previa.propuesto.estado === 'FINALIZADO' && ' · PARTIDO FINALIZADO'}
            </p>
            {previa.requiere_confirmacion && (
              <div className="space-y-2 rounded-xl bg-red-50 p-3 text-red-800">
                <p className="font-bold">Esta corrección adelanta el cierre del partido.</p>
                <p>
                  Pasan a <strong>No disputado</strong> (sus jugadores conservan el +0,5 de convocatoria, pero pierden el
                  resultado y la acción):
                </p>
                <ul className="list-disc pl-5">
                  {previa.invalidados.map((i) => (
                    <li key={i.enfrentamiento_id}>
                      Lista {i.lista} ·{' '}
                      {catalogos.modalidades.find((m) => m.codigo === i.modalidad)?.nombre ?? i.modalidad} {i.numero}
                    </li>
                  ))}
                </ul>
                <label className="flex min-h-11 items-center gap-3 font-semibold">
                  <input type="checkbox" checked={aceptaImpacto} onChange={(e) => setAceptaImpacto(e.target.checked)} className="size-5" />
                  Entiendo el impacto y quiero aplicarlo
                </label>
              </div>
            )}
          </div>
        )}

        {error && <MensajeError>{error}</MensajeError>}

        <div className="space-y-2">
          {!previa ? (
            <BotonPrincipal onClick={() => void verImpacto()} disabled={ocupado || !eleccion || !motivo.trim()}>
              {ocupado ? 'Calculando…' : 'Ver impacto'}
            </BotonPrincipal>
          ) : (
            <BotonPrincipal
              onClick={() => void aplicar()}
              disabled={ocupado || !motivo.trim() || (previa.requiere_confirmacion && !aceptaImpacto)}
            >
              {ocupado ? 'Aplicando…' : 'Aplicar corrección'}
            </BotonPrincipal>
          )}
          <BotonSecundario onClick={onCerrar} disabled={ocupado}>
            Cancelar
          </BotonSecundario>
        </div>
      </div>
    </div>
  )
}
