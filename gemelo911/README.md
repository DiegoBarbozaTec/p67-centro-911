# 🧠 3.3 Proyecto final · Gemelo Digital del Centro de Emergencias 911 (Prolog + Python/Janus)

| | |
|---|---|
| **Alumno** | Diego Antonio Barboza Carballo · No. Control 23212702 |
| **Materia** | Programación Lógica y Funcional |
| **Profesor** | René Solís Reyes |
| **Institución** | TecNM / Instituto Tecnológico de Tijuana |
| **Proyecto** | #67 Centro de emergencias 911: extensión lógica del proyecto original en Erlang |
| **Reto** | [`proyectos/67-centro-de-emergencias-911/gemelo/PROBLEMA.md`](https://github.com/tectijuana/logicfun-proyectos/blob/main/proyectos/67-centro-de-emergencias-911/gemelo/PROBLEMA.md) |

### 🔗 Enlaces

| Recurso | Enlace |
|---|---|
| 💻 Código del gemelo | URL_REPO |
| 🌐 Gemelo en vivo (AWS EC2 ARM64) | URL_EN_VIVO |
| 🎨 Diseño en Google Stitch | URL_STITCH |
| 🎬 Demo en video | URL_LOOM |
| ⚙️ Fase 1 (Erlang/OTP) | [gist del proyecto #67 en Erlang](https://gist.github.com/DiegoBarbozaTec/28afdf1678d827d0e5f998622c94b8e7) |

---

## 1. Del simulador al gemelo

En Erlang construí un sistema que **hace** cosas: un proceso por unidad, un despachador supervisado, latidos, reinicios y una bitácora que no se pierde. Respondía *"¿qué está pasando con cada incidente?"*.

El gemelo en Prolog **deduce**: con hechos (dónde está cada unidad, en qué estado, qué tramos hay, qué dicen las llamadas) y reglas (cómo se despacha), contesta *"¿a quién mando, a quién le quito una unidad, a quién le fallo y por qué esa respuesta y no otra?"*. Y cuando no hay datos suficientes, dice **"no lo sé"**.

| Archivo | Qué contiene |
|---|---|
| `hechos.pl` | Lo fijo: red de 10 puntos y 12 tramos (con el cañón y la garita), 4 zonas, 8 unidades de 4 tipos, qué pide cada incidente, metas y umbrales |
| `escenarios.pl` | El estado de cada situación como hechos dinámicos. El **"ahora" es un hecho**, no el reloj, para que las respuestas se repitan |
| `reglas.pl` | Todas las reglas: red, llegada, retiro, reparto, explicación, qué falta, hipótesis, llamadas, sin contacto y las 5 preguntas |
| `explica.pl` | Convierte cada deducción en una frase en español |
| `servidor.pl` | Servidor web 100 % Prolog (`library(http)`), JSON en `/api/...` |
| `graficas.py` | Python **solo dibuja** (matplotlib), llamado desde Prolog con **Janus** (`py_call/2`) |
| `web/index.html` | Interfaz diseñada en Stitch; solo pregunta al gemelo |
| `tests/reglas_tests.pl` | **33 pruebas plunit**: todas las situaciones y las 5 preguntas |

> **Prolog es el programa.** Ninguna regla ni umbral vive en JavaScript ni en Python. Python recibe listas ya deducidas (la ruta elegida, los tiempos) y solo dibuja el mapa y las barras.

---

## 2. Las reglas centrales

```prolog
% "Más cercana" = menor tiempo por la red, no línea recta. Recursiva y con backtracking.
ruta_(B, B, Vistos, Vistos, 0).
ruta_(A, B, Vistos, Camino, T) :-
    A \== B, conecta(A, X, T1), \+ memberchk(X, Vistos),
    ruta_(X, B, [X|Vistos], Camino, T2), T is T1 + T2.

% Una unidad ocupada solo se retira por una prioridad SUPERIOR y nunca si traslada a un paciente.
retirable(U, Nuevo, desde(IncV, PV, E)) :-
    incidente(Nuevo, _, _, PN), necesita(Nuevo, T, _), unidad(U, T),
    atiende(U, IncV), IncV \== Nuevo, incidente(IncV, _, _, PV),
    estado_unidad(U, E), E \== trasladando, PV > PN.

% Predicado central: el mejor reparto primero y, con ";", los demás repartos válidos.
decide(+Incidentes, -despacho(Completo, Asignaciones, Desplazados, SinCubrir), -Explicacion)
```

`decide/3` genera **todos** los repartos posibles por backtracking (`reparto/4`), sin repetir unidad, y los ordena por un costo lexicográfico: **(1)** necesidades sin cubrir, pesadas por prioridad; **(2)** número de retiros; **(3)** a quién se le retira (primero al menos urgente y a quien va en camino antes que a quien ya está en escena); **(4)** suma de tiempos de llegada.

Toda condición tiene **tres resultados**: `si`, `no`, `no_se` (`cumple/2`, `estado_llegada/3`, `mismo_incidente/4`, `cubierto/3`).

---

## 3. Las cinco situaciones

### Situación 1 · Todas las ambulancias ocupadas y entra una prioridad 1

```prolog
?- decide([inc_paro], D, E).
```
- **Decisión:** retirar a **amb1**, que va en camino a un P3 y llega en 3 min por canon_oeste → puente_norte (meta 8 min).
- **Lo intuitivo era otra cosa:** amb2 es la más cercana (2 min), pero está **en escena de un P2**. El gemelo explica: *"se prefiere quitar a amb1… lo intuitivo sería retirar la más cercana, pero dejaría peor atendido un incidente más grave"*.
- **amb3 no se retira:** va trasladando a un paciente. **amb4** está libre, pero tarda 16 min.
- **A quién se le falla:** `inc_leve queda PENDIENTE (no se pierde)`, de vuelta a la cola con su prioridad.
- **Qué tendría que cambiar para no retirar a nadie** (`que_falta/2`): una ambulancia libre en `[canon_este, canon_oeste, centro, playas, puente_norte, puente_sur]`, o que amb3 se libere 8 min 40 s antes.
- Con un incidente de prioridad igual o menor, **no retira a nadie** (`\+ retirable(_, inc_leve, _)`).

### Situación 2 · La unidad más cercana no es la más cercana

```prolog
?- decide([inc_s2], D, E).
```
- **amb2** llega en **3 min** por centro → canon_este, aunque está a **3 km**.
- **amb1** está a **1 km** en línea recta, pero del otro lado del cañón: por calles tarda 5 min.
- **amb3** va trasladando y queda libre en 1 min; **contando esa espera** llegaría en 9 min.
- El tramo de la garita está lento (×3), y eso cambia las rutas que pasan por ahí.
- **Hipótesis:** si se cierra canon_este–centro, amb2 se queda sin ruta y la respuesta cambia a amb1 (5 min).

### Situación 3 · Varias llamadas, un solo choque

```prolog
?- grupos_llamadas(G).            % [[c1,c2,c3,c4,c5],[c6],[c7]]
?- mismo_incidente(c6, c1, R, Ev). % R = no_se
```
- **c1–c5** son el mismo choque: están a ≤ 300 m, en ≤ 10 min, con el mismo tipo y el mismo número de vehículos.
- **c6** está a 0.67 km y reporta 2 vehículos contra 3: **no se sabe**. Queda marcada: ni unida ni descartada.
- **c7** es un incendio en Otay: **no** es el mismo hecho.
- **Incidente unido:** toma la información de **todas** sus llamadas: máximo de lesionados = 3 → **prioridad 1**, **2 ambulancias y 1 patrulla**.
- **¿Alcanzan las unidades si c6 fuera otro accidente?** No.
- **Qué cuesta equivocarse:** fusionar mal deja un accidente real sin unidad; no fusionar manda unidades que hacen falta en otra parte.

### Situación 4 · La unidad que dejó de contestar

```prolog
?- estado_llegada(amb1, R, Ev).
R = no_se, Ev = sin_reporte(canon_oeste, 600, umbral(300)).
```
- El sistema dice "en camino"; el gemelo dice **"no lo sé"**: el último reporte fue hace 10 min (umbral 5 min).
- **pat1** sí reporta → **llega**. Si se registra una falla → **no llega**. Son tres respuestas distintas.
- **El incidente P1 queda desprotegido.** Una unidad que no se sabe si llega **no cuenta como cobertura**, así que `decide` pide refuerzo: **amb2**, libre, en 5 min. **Descubre:** la zona centro se queda sin ambulancia libre.
- **amb3** llegaría antes, pero atiende un P3, y **no se retira a nadie si hay una libre que llega a tiempo**.
- **Si la unidad reaparece** (`si_pasara(reaparece(amb1, puente_norte), …)`), la respuesta se corrige a **llega** y ya no hace falta refuerzo.

### Situación 5 · El sismo: más incidentes que unidades

```prolog
?- decide([inc_herido, inc_fuego, inc_atrapados], D, E).
```
- **Reparto voraz** (cada incidente toma la unidad más rápida, en orden de llegada): el herido (P2, llegó primero) se lleva una ambulancia, el incendio otra… y **los atrapados (P1) se quedan sin ambulancia**.
- **El gemelo** razona sobre el conjunto: solo **amb1** llega a tiempo a los atrapados, así que la reserva para ellos y encuentra **4 repartos completos**. Ninguna unidad se repite.
- **Si amb1 queda fuera de servicio:** no hay reparto completo, y el gemelo lo dice: *"SIN CUBRIR: inc_atrapados [P1] necesita 1 ambulancia más…"*. Cubre todo lo demás, pesando primero la prioridad 1.

---

## 4. Las cinco preguntas, mismas reglas

| Pregunta | Consulta | Respuesta del gemelo |
|---|---|---|
| ¿Qué unidad mando? *(decisión)* | `decide([inc_s2], D, E)` | amb2, 3 min, centro → canon_este |
| ¿Por qué no la más cercana? *(explicación)* | `por_que_no(amb1, inc_s2, M)` | amb2 llega antes (3 min contra 5), aunque amb1 está a 1 km y amb2 a 3 km |
| ¿Qué repartos cubren el sismo? *(todas las respuestas)* | `findall(A, decide(Is, despacho(si,A,_,_), _), Rs)` | 4 repartos completos |
| ¿Qué falta para tener ambulancia? *(al revés)* | `que_falta(inc_paro, C)` | una ambulancia libre en ciertos puntos, o que amb3 se libere 8 min 40 s antes |
| ¿Y si cierran un tramo? *(hipótesis)* | `si_pasara(cerrar(canon_este, centro), D, decide([inc_s2], D, _), R)` | cambia de amb2 a amb1 (5 min) |

En un script, cada pregunta sería una función nueva. Aquí son **cinco consultas sobre las mismas reglas**.

---

## 5. Python desde Prolog (Janus)

```prolog
grafica_mapa(Incs, Archivo) :-
    findall([P, X, Y], coord(P, X, Y), Puntos),          % Prolog deduce QUÉ dibujar…
    ...
    decide_uno(Incs, despacho(_, [a(_, _, _, _, _, Ruta)|_], _, _), _),
    py_call(graficas:mapa(Titulo, Puntos, Tramos, Unidades, Inc, Ruta, Archivo), _).   % …Python solo dibuja
```

| Ruta | Responde |
|---|---|
| `/` | Interfaz |
| `/api/escenarios` · `/api/escenario?nombre=s1_retiro` | Lista y carga escenarios |
| `/api/estado` | Unidades, incidentes y situaciones deducidas |
| `/api/despacho` | Repartos con su explicación, voraz, por qué no, qué falta |
| `/api/llamadas` | Grupos, llamadas dudosas y costo de equivocarse |
| `/api/sin_contacto` | llega / no llega / no se sabe, y el refuerzo |
| `/api/hipotesis?cambio=cerrar&a=..&b=..` | Antes y después de un cambio |
| `/api/preguntas` | Las 5 preguntas |
| `/grafica/mapa` · `/grafica/llegadas` | PNG de matplotlib vía Janus |

---

## 6. Instalación (AWS Academy, Ubuntu 24.04 ARM64)

```bash
git clone URL_REPO
cd p67-centro-911/gemelo911
bash deploy/instalar.sh          # SWI-Prolog (PPA) + Janus + matplotlib, pruebas y servicio
```
Hay que abrir el **puerto 8082** en el grupo de seguridad. Sin instalar nada como servicio: `swipl servidor.pl` → `http://localhost:8082/`.

```text
$ swipl -g run_tests -t halt tests/reglas_tests.pl
% All 33 tests passed
```

---

## 7. Supuestos declarados

- Escala reducida: 8 unidades, 4 zonas y 10 puntos, contra las 40 unidades y 200 incidentes del escenario original.
- Tiempos de tramo, coordenadas, nombres de zonas e identificadores son **datos del ejercicio**, no mediciones.
- Lo que pide cada incidente (`requiere/3`) lo fijé yo.
- **Metas de llegada:** P1 8 min, con bomberos 4 min (referencias del problema original); P2 15 min y P3 30 min (mías).
- **Retiro:** solo por prioridad estrictamente superior; nunca a una ambulancia que traslada; primero al incidente menos urgente y a quien va en camino antes que a quien está en escena.
- **Mismo incidente:** ≤ 0.3 km, ≤ 10 min, mismo tipo y mismo número de vehículos. Es otro hecho con tipo distinto, > 1.5 km o > 30 min. Lo intermedio es **no se sabe**.
- **Prioridad del incidente unido:** ≥ 2 lesionados → P1; 1 → P2; 0 → P3. Ambulancias = máx(1, ⌈lesionados / 2⌉).
- **Sin contacto:** más de 5 min sin reportar vuelve dudosa a una unidad. Una unidad dudosa no cuenta como cobertura.
- El "ahora" es un hecho del escenario.

**Cifras verificadas** (vienen del problema original y son referencias internacionales, no reglas del 911 de México): NFPA 1710, primera unidad de bomberos ≈ 4 min de viaje y soporte vital avanzado ≈ 8 min; NENA, contestar 90 % de las llamadas en 10–15 s.

---

## 8. Qué resolví en Erlang, qué en Prolog y por qué

En **Erlang** resolví lo que **pasa**: muchas cosas a la vez que no deben caerse. Cada unidad es un proceso que cambia de estado y manda latidos, el despachador está supervisado y se recupera desde disco, y la bitácora sobrevive a cualquier falla. Eso es concurrencia y tolerancia a fallas, y Erlang está hecho para eso.

En **Prolog** resolví lo que **se deduce**: a quién mandar, a quién quitarle una unidad, si dos llamadas son el mismo hecho, si una unidad callada sigue en camino, y cómo repartir lo escaso entre varios incidentes. Son relaciones, caminos y restricciones con varias respuestas posibles. Prolog las encuentra por backtracking, explica cada una y contesta "no lo sé" cuando faltan datos. Con las mismas reglas respondo decisión, explicación, todas las soluciones, la pregunta al revés y la hipótesis, cosa que en Erlang habría requerido una función nueva por pregunta.

El puente natural: el estado que publica el sistema en Erlang (`/api/unidades` e incidentes) puede convertirse en los hechos `estado_unidad/2`, `posicion/3` y `asignacion/3` de este gemelo, que entonces razona sobre el estado real.

---

## Referencias

- Reto del proyecto: https://github.com/tectijuana/logicfun-proyectos/tree/main/proyectos/67-centro-de-emergencias-911/gemelo
- Demos del curso: logicDemo y logicDemo2 (Janus) en https://github.com/tectijuana/logicfun-proyectos
- SWI-Prolog: `library(http)`, `plunit`, `aggregate`, Janus (`py_call/2`): https://www.swi-prolog.org/pldoc/
- Bratko, I. *Prolog Programming for Artificial Intelligence*.
- NFPA 1710 (tiempos de respuesta) y NENA (atención de llamadas), citados en el problema original.
