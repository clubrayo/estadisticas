import { Link } from 'react-router'

export function NoEncontrada() {
  return (
    <section className="space-y-3">
      <h1 className="text-2xl font-bold">Página no encontrada</h1>
      <Link to="/" className="font-semibold text-amber-700 underline">
        Volver al inicio
      </Link>
    </section>
  )
}
