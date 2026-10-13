import { useConexion } from '../hooks/useConexion'
import { IconoSinSenal } from './Iconos'

/** Aviso permanente mientras el dispositivo no tenga red. */
export function BannerConexion() {
  const enLinea = useConexion()
  if (enLinea) return null

  return (
    <div role="alert" className="flex items-center gap-3 bg-red-600 px-4 py-3 text-white">
      <IconoSinSenal className="size-6 shrink-0" />
      <p className="text-sm font-semibold leading-snug">
        Sin conexión. Nada se guardará hasta que vuelva la señal.
      </p>
    </div>
  )
}
