import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { mensajeDeError } from '../lib/errores'

export type EstadoCarga<T> =
  | { tipo: 'cargando' }
  | { tipo: 'error'; mensaje: string }
  | { tipo: 'listo'; datos: T }

/**
 * Ejecuta una consulta al montar y cada vez que cambian sus dependencias
 * (comparadas por valor) y expone su estado. `recargar` vuelve a consultar.
 */
export function useCarga<T>(consulta: () => Promise<T>, dependencias: readonly unknown[]) {
  const [estado, setEstado] = useState<EstadoCarga<T>>({ tipo: 'cargando' })
  const [version, setVersion] = useState(0)

  // Siempre se ejecuta la versión más reciente de la consulta.
  const consultaActual = useRef(consulta)
  useLayoutEffect(() => {
    consultaActual.current = consulta
  })

  const clave = JSON.stringify(dependencias)

  useEffect(() => {
    let vigente = true
    consultaActual.current().then(
      (datos) => vigente && setEstado({ tipo: 'listo', datos }),
      (error) => vigente && setEstado({ tipo: 'error', mensaje: mensajeDeError(error) }),
    )
    return () => {
      vigente = false
    }
  }, [clave, version])

  const recargar = useCallback(() => setVersion((v) => v + 1), [])
  return { estado, recargar, setEstado }
}
