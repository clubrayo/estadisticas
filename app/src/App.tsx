import { lazy } from 'react'
import { BrowserRouter, Route, Routes } from 'react-router'
import { PantallaCentrada } from './componentes/Pantallas'
import { LayoutPrincipal } from './layouts/LayoutPrincipal'
import { configuracionCompleta } from './lib/supabase'
import { Ingresar } from './paginas/Ingresar'
import { NoEncontrada } from './paginas/Secciones'
import { RequiereSesion } from './sesion/RequiereSesion'
import { SesionProvider } from './sesion/SesionProvider'

// Cada pantalla se descarga solo cuando se abre (carga inicial más rápida en el celular).
const LayoutPartido = lazy(() => import('./layouts/LayoutPartido').then((m) => ({ default: m.LayoutPartido })))
const FichaCampeonato = lazy(() => import('./paginas/campeonatos/FichaCampeonato').then((m) => ({ default: m.FichaCampeonato })))
const FormularioCampeonato = lazy(() => import('./paginas/campeonatos/FormularioCampeonato').then((m) => ({ default: m.FormularioCampeonato })))
const ListaCampeonatos = lazy(() => import('./paginas/campeonatos/ListaCampeonatos').then((m) => ({ default: m.ListaCampeonatos })))
const Combinaciones = lazy(() => import('./paginas/estadisticas/Combinaciones').then((m) => ({ default: m.Combinaciones })))
const Ranking = lazy(() => import('./paginas/estadisticas/Ranking').then((m) => ({ default: m.Ranking })))
const Inicio = lazy(() => import('./paginas/Inicio').then((m) => ({ default: m.Inicio })))
const FichaJugador = lazy(() => import('./paginas/jugadores/FichaJugador').then((m) => ({ default: m.FichaJugador })))
const FormularioJugador = lazy(() => import('./paginas/jugadores/FormularioJugador').then((m) => ({ default: m.FormularioJugador })))
const ListaJugadores = lazy(() => import('./paginas/jugadores/ListaJugadores').then((m) => ({ default: m.ListaJugadores })))
const Asistencia = lazy(() => import('./paginas/partidos/Asistencia').then((m) => ({ default: m.Asistencia })))
const EditarPartido = lazy(() => import('./paginas/partidos/EditarPartido').then((m) => ({ default: m.EditarPartido })))
const EstadisticasPartido = lazy(() => import('./paginas/partidos/EstadisticasPartido').then((m) => ({ default: m.EstadisticasPartido })))
const FormularioPartido = lazy(() => import('./paginas/partidos/FormularioPartido').then((m) => ({ default: m.FormularioPartido })))
const Juego = lazy(() => import('./paginas/partidos/Juego').then((m) => ({ default: m.Juego })))
const ListaPartidos = lazy(() => import('./paginas/partidos/ListaPartidos').then((m) => ({ default: m.ListaPartidos })))
const Marcador = lazy(() => import('./paginas/partidos/Marcador').then((m) => ({ default: m.Marcador })))
const Listas = lazy(() => import('./paginas/partidos/Listas').then((m) => ({ default: m.Listas })))
const Rivales = lazy(() => import('./paginas/partidos/Rivales').then((m) => ({ default: m.Rivales })))
const Auditoria = lazy(() => import('./paginas/auditoria/Auditoria').then((m) => ({ default: m.Auditoria })))

export function App() {
  if (!configuracionCompleta) {
    return (
      <PantallaCentrada titulo="Falta configurar Supabase">
        <p className="max-w-sm text-slate-600">
          Cree el archivo <code className="font-mono">app/.env.local</code> a partir de{' '}
          <code className="font-mono">.env.example</code> y reinicie el servidor de desarrollo.
        </p>
      </PantallaCentrada>
    )
  }

  return (
    <SesionProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/ingresar" element={<Ingresar />} />
          <Route
            element={
              <RequiereSesion>
                <LayoutPrincipal />
              </RequiereSesion>
            }
          >
            <Route index element={<Inicio />} />
            <Route path="campeonatos" element={<ListaCampeonatos />} />
            <Route path="campeonatos/nuevo" element={<FormularioCampeonato />} />
            <Route path="campeonatos/:campeonatoId" element={<FichaCampeonato />} />
            <Route path="campeonatos/:campeonatoId/editar" element={<FormularioCampeonato />} />
            <Route path="partidos" element={<ListaPartidos />} />
            <Route path="partidos/nuevo" element={<FormularioPartido />} />
            <Route path="partidos/rivales" element={<Rivales />} />
            <Route path="partidos/:partidoId" element={<LayoutPartido />}>
              <Route index element={<Marcador />} />
              <Route path="asistencia" element={<Asistencia />} />
              <Route path="listas" element={<Listas />} />
              <Route path="juego" element={<Juego />} />
              <Route path="estadisticas" element={<EstadisticasPartido />} />
              <Route path="editar" element={<EditarPartido />} />
            </Route>
            <Route path="jugadores" element={<ListaJugadores />} />
            <Route path="jugadores/nuevo" element={<FormularioJugador />} />
            <Route path="jugadores/:jugadorId" element={<FichaJugador />} />
            <Route path="jugadores/:jugadorId/editar" element={<FormularioJugador />} />
            <Route path="estadisticas" element={<Ranking />} />
            <Route path="estadisticas/duplas" element={<Combinaciones key="DUPLA" modalidad="DUPLA" />} />
            <Route path="estadisticas/trios" element={<Combinaciones key="TRIO" modalidad="TRIO" />} />
            <Route path="auditoria" element={<Auditoria />} />
            <Route path="*" element={<NoEncontrada />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </SesionProvider>
  )
}
