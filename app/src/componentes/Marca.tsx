/** Logo oficial del CLUB RAYO (public/logo.webp). */
export function Logo({ className = '' }: { className?: string }) {
  return <img src="/logo.webp" alt="Logo CLUB RAYO" className={`object-contain ${className}`} />
}

/** Créditos del desarrollador del sistema. */
export function Creditos({ className = '' }: { className?: string }) {
  return (
    <footer className={`space-y-1 text-center text-xs text-slate-500 ${className}`}>
      <p>
        Sistema desarrollado por <span className="font-semibold text-slate-700">DigitalPyme Limitada</span>
      </p>
      <p className="flex flex-wrap justify-center gap-x-3 gap-y-1">
        <a href="https://digitalpyme.cl" target="_blank" rel="noopener noreferrer" className="inline-flex min-h-8 items-center underline">
          digitalpyme.cl
        </a>
        <a href="tel:+56990894630" className="inline-flex min-h-8 items-center underline">
          +569 90894630
        </a>
        <a href="mailto:contacto@digitalpyme.cl" className="inline-flex min-h-8 items-center underline">
          contacto@digitalpyme.cl
        </a>
      </p>
    </footer>
  )
}
