# #67 — Centro de emergencias 911

**Dominio:** Seguridad y ciudad · despacho de unidades por prioridad y cercanía (tiempo de viaje real).

Aplicación Erlang/OTP que recibe llamadas, filtra las improcedentes, detecta duplicadas,
asigna prioridad y despacha la unidad adecuada con **menor tiempo de viaje**, reasigna
cuando surge algo más grave o cuando una unidad falla, y guarda una **línea de tiempo
auditable** (encadenada con SHA-256) de cada incidente. Incluye panel web en tiempo real
(cowboy + WebSocket), métricas `/metrics`, simulador de escenarios y pruebas de caos.

## Equipo

| Rol | Integrante |
|---|---|
| Backend (OTP) | Diego Antonio Barboza Carballo |
| Frontend (Stitch + cowboy) | Diego Antonio Barboza Carballo |
| Ops/QA | Diego Antonio Barboza Carballo |

## Arranque

```bash
rebar3 compile
rebar3 eunit          # 12 pruebas
rebar3 shell          # panel en http://localhost:8080
```

Instalación completa en una VM (Ubuntu/Debian) como servicio systemd:

```bash
bash deploy/instalar.sh
```

## Pendiente

- [x] Diseñar pantallas en Stitch (`design/PROMPT_STITCH.md`)
- [x] Modelar el dominio: qué es un proceso, qué es un supervisor
- [x] Endpoints `/api/...` y WebSocket con cowboy
- [x] Métricas `/metrics` y diagnóstico con recon
- [x] Release + systemd (`deploy/`)
- [x] Prueba de caos (matar procesos y verificar recuperación)

## Diseño OTP

```
p67_centro_de_emergencias_911_sup        rest_for_one
├── p67_bitacora                          gen_server + DETS (lo que nunca se pierde)
├── p67_nucleo_sup                        rest_for_one
│   ├── p67_unidades_sup                  one_for_one
│   │   └── p67_unidad  × 40              gen_server por unidad (máquina de estados)
│   └── p67_despachador                   gen_server: prioridad, cola, asignación
└── p67_simulador                         escenarios y caos
cowboy (ranch) ── p67_http_api (REST, /metrics) · p67_ws (WebSocket 1 s)
```

| Decisión | Por qué (caso difícil que resuelve) |
|---|---|
| Un proceso por unidad, `one_for_one` | Si una unidad falla, las otras 39 siguen; el supervisor la reinicia sola. |
| Unidades **antes** que el despachador (`rest_for_one`) | Si cae la flota, el despachador se reinicia para re-vigilar; si cae el despachador, la flota sigue en camino. |
| Bitácora primero y en disco (DETS + `sync`) | "¿Qué no puede perderse jamás?": la línea de tiempo. Ninguna falla posterior la reinicia. |
| Hash SHA-256 encadenado | Detecta si alguien altera un registro (`/api/bitacora/verificar`). |
| Incidentes en DETS | Matar el despachador no pierde incidentes: los recupera y reconcilia con la flota. |
| "Más cercana" = **ETA**: ruta Manhattan / velocidad, cruzando el cañón sólo por puentes | Una unidad a 1 km del otro lado del cañón tarda más que una a 3 km del mismo lado. |
| Duplicadas: mismo tipo, < 500 m, < 30 min | 12 llamadas del mismo accidente = 1 incidente con 12 llamadas (sube a la prioridad más alta reportada). |
| P1 sin unidades → retirar la más cercana de un P3 | "Todas las ambulancias ocupadas y entra una P1". El P3 vuelve a la cola. |
| `erlang:monitor` + latidos + timeout de aceptación | Unidad caída, sin radio o que no acepta: se marca fuera de servicio y se reasigna. |
| Llamadas improcedentes se registran pero no se despachan | La mayoría de llamadas al 911 en México no son emergencias. |

Estados del incidente: `recibido → asignando → despachado → en_sitio → cerrado` (y `en_espera`).
Estados de la unidad: `disponible → despachada → en_camino → en_escena → [trasladando] → disponible`, y `fuera_de_servicio`.

## Escenario simulado

`POST /api/simulacion/turno`: 40 unidades de 4 tipos (16 ambulancias, 12 patrullas,
8 bomberos, 4 protección civil), 200 incidentes reales + 800 improcedentes en un turno de 8 h
(1 min simulado = 250 ms; el turno dura 2 min reales). También `accidente_multiple` y `sin_ambulancias`.

## Pruebas de caos

| Qué se mató / falló | Qué se esperaba | Qué ocurrió |
|---|---|---|
| Proceso de una unidad en camino (`exit(Pid, kill)`) | El supervisor la reinicia y el incidente se reasigna | Reiniciada (contador `reinicios`), evento `unidad_caida`, otra unidad asignada en < 1 s |
| Radio de una unidad en camino | Se detecta sin latido y se reasigna | Evento `comunicacion_perdida`, unidad fuera de servicio, reasignación |
| Unidad más cercana no acepta | Timeout de 2 min y pasa a la siguiente | Evento `unidad_no_respondio`, asignada la 2ª más cercana |
| Proceso despachador | Se reinicia y recupera incidentes desde disco, sin tocar la flota | Mismos PIDs de las 40 unidades, incidentes intactos, el turno sigue |
| Alterar un registro de la bitácora | La verificación lo detecta | `{alterado, 1}` (prueba eunit) |

## Supuestos

- Ciudad modelada como rectángulo de 20 × 12 km, calles en cuadrícula, cañón en x = 10 km con puentes en y = 3 y y = 9.
- Velocidades promedio: ambulancia 50, patrulla 60, bomberos 40, protección civil 45 km/h.
- Una unidad por incidente; tipo de unidad según el tipo de incidente.
- Metas de llegada: P1 8 min, P2 15 min, P3 30 min.
- Sólo se retira una unidad de un incidente **P3** para atender un **P1**.

## Cifras de referencia verificadas

- NENA: contestar 90 % de las llamadas en ≤ 15 s y 95 % en ≤ 20 s.
- NFPA 1710: primera unidad de bomberos ≈ 4 min (240 s) de viaje; soporte vital avanzado ≈ 8 min (480 s).
- 911 México: entre 70 % y ~87 % de las llamadas son improcedentes según distintos reportes; se simuló 80 %.

## Licencia

MIT, igual que el repositorio del curso.
