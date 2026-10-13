# Pruebas de la base de datos — CLUB RAYO

Todas las suites se ejecutan en el **SQL Editor** de Supabase, pegando el archivo
completo y presionando **Run**. Cada suite crea datos ficticios (prefijo `ZZ`),
verifica y **deshace todo al final**: no deja datos en la base.
Resultado esperado: todas las filas con `ok = true`.

| Suite | Filas | Qué verifica |
|---|---|---|
| 001_verificacion_estructura | 21 | Tablas, restricciones y datos iniciales |
| 001_pruebas_restricciones | 53 | Reglas de integridad del esquema |
| 002_verificacion_estructura | 19 | Roles, RLS y auditoría instalados |
| 002_pruebas_seguridad | 79 | Permisos por rol y por club |
| 003_verificacion_estructura | 9 | Funciones de juego instaladas |
| 003_pruebas_juego | 100 | Partido, listas, resultados, cierre a 30, correcciones, reglas |
| 003_concurrencia_real.mjs | 16 | Dos conexiones simultáneas reales (se ejecuta con Node, no en Supabase) |
| 004_verificacion_estructura | 9 | Acciones por integrante instaladas |
| 004_pruebas_acciones | 34 | Varias acciones por enfrentamiento y resultado por secretaría |
| 005_verificacion_estructura | 6 | Vistas de estadísticas instaladas |
| 005_pruebas_estadisticas | 20 | Ficha estadística del jugador |
| 006_pruebas_ranking | 11 | Ranking general |
| 007_pruebas_combinaciones | 11 | Duplas y tríos |
| 008_pruebas_estadisticas_club | 13 | Dashboard del club |
| 009_pruebas_integrales | 25 | Partido completo cruzando todas las capas y la auditoría |

## Casos de prueba obligatorios (sección 51 del Prompt Maestro)

| Caso | Dónde se prueba |
|---|---|
| Partido que termina exactamente 30-20 | 003 n.º 85-87 · 009 n.º 1-2 |
| Partido que necesita Lista 6 | 003 n.º 55 |
| Partido que termina a mitad de Lista 6 | 003 n.º 56-58 |
| Jugador convocado que no alcanza a jugar | 003 n.º 59 · 005 |
| Dupla ganadora por corte de un integrante | 003 n.º 44 |
| Trío ganador por caída rival provocada por un integrante | 003 n.º 46 |
| Dupla perdedora porque cortaron a un integrante | 003 n.º 45 · 004 |
| Trío perdedor por caída propia | 003 n.º 47 · 004 |
| Cambio futuro de reglas sin modificar estadísticas históricas | 003 n.º 82-89 · 009 n.º 16 |
| Dos usuarios registrando simultáneamente el mismo enfrentamiento | 003 n.º 34-38 · 003_concurrencia_real.mjs (16/16) |

Otras secciones cubiertas por la suite 009: historial del partido (35),
auditoría (40) y separación entre puntaje del club y del jugador (52).
