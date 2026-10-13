import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import './index.css'

// Si se publicó una versión nueva mientras la app estaba abierta, una pantalla
// puede no encontrar su archivo: se recarga la página para tomar la versión nueva.
window.addEventListener('vite:preloadError', () => window.location.reload())

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
