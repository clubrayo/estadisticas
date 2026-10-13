# Club Rayo — aplicación web

Frontend mobile-first del sistema de gestión y estadísticas de juego.
React + TypeScript + Tailwind CSS + Vite, conectado a Supabase.

## Puesta en marcha

1. Instalar dependencias (una sola vez):

   ```bash
   npm install
   ```

2. Crear `app/.env.local` a partir de `.env.example` con la URL del proyecto y la
   clave **publishable** (o la *anon* heredada) de Supabase. Nunca use la clave
   *secret* ni *service_role*.

3. Iniciar el servidor de desarrollo:

   ```bash
   npm run dev
   ```

   Para abrirla desde un celular en la misma red Wi‑Fi: `npm run dev -- --host` y
   abra en el teléfono la dirección "Network" que muestra la consola.

## Comandos

| Comando           | Uso                                             |
|-------------------|-------------------------------------------------|
| `npm run dev`     | Servidor de desarrollo con recarga automática.  |
| `npm run build`   | Verifica tipos (TypeScript) y genera `dist/`.   |
| `npm run lint`    | Revisión estática del código (Oxlint).          |
| `npm run preview` | Sirve localmente la versión compilada.          |

## Estructura

```
src/
  App.tsx              Rutas de la aplicación
  lib/                 Cliente Supabase, roles y traducción de errores
  sesion/              Sesión, perfil y roles del usuario; protección de rutas
  layouts/             Marco principal (encabezado + navegación inferior) y del partido
  paginas/             Pantallas
  componentes/         Piezas reutilizables (iconos, avisos, botones)
  hooks/               Estado de conexión
```

La autorización real la aplica la base de datos (RLS y funciones RPC). Los
controles de rol en la interfaz solo muestran u ocultan acciones.
