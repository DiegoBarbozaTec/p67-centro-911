# Guía para explicar tu gemelo 911 (léela antes de presentar)

El profe califica que **tú** entiendas y defiendas el gemelo. Esto es lo que debes poder decir con tus palabras.

## La idea en 30 segundos
"En Erlang mi sistema **hacía**: procesos, latidos y reinicios. En Prolog mi gemelo **deduce**. Le doy hechos (dónde está cada unidad, qué tramos hay, qué dicen las llamadas) y reglas (cómo se despacha), y me contesta a quién mandar, a quién le quito una unidad, por qué esa y no otra, y cuándo **no sabe**."

## Cómo correrlo frente al profe
```bash
swipl gemelo.pl
?- cargar_escenario(s1_retiro).
?- decide([inc_paro], D, E).          % decisión + explicación
?- por_que_no(amb2, inc_paro, M).     % ¿por qué no la más cercana?
?- que_falta(inc_paro, C).            % la pregunta al revés
?- cargar_escenario(s5_sismo).
?- decide([inc_herido,inc_fuego,inc_atrapados], D, E).   % y presiona ; para ver más repartos
?- voraz([inc_herido,inc_fuego,inc_atrapados], A, Sin).  % lo intuitivo, que falla
```
Y las pruebas: `swipl -g run_tests -t halt tests/reglas_tests.pl` → 33 pasan.

## Preguntas que te pueden hacer

| Pregunta | Qué contestar |
|---|---|
| ¿Qué significa "más cercana"? | El menor **tiempo** por las calles, no la línea recta. `ruta/4` es recursiva: prueba un tramo, sigue y, si se atora, regresa a probar otro (backtracking). Por eso amb1, a 1 km pero del otro lado del cañón, pierde contra amb2, que está a 3 km. |
| ¿Por qué no retiras la ambulancia más cercana? | Porque está en escena de un P2. Mi regla quita primero al incidente **menos urgente**, y prefiere a quien va en camino sobre quien ya está atendiendo. A quien traslada un paciente nunca lo retiro. |
| ¿Qué pasa con el incidente al que le quitas la unidad? | Queda **pendiente**, no se pierde. `decide/3` lo devuelve en la lista `Desplazados` y la explicación lo dice. |
| ¿Cómo sabes que dos llamadas son el mismo choque? | No viene en ningún dato; se **deduce** de lugar, tiempo y relato. Hay tres respuestas: sí, no y **no se sabe**. La dudosa queda marcada, ni unida ni descartada. |
| ¿Cómo distingues "no ha llegado" de "no sé si va"? | Con el silencio: si la unidad lleva más de 5 min sin reportar, `estado_llegada` dice **no_se**. Una unidad dudosa no cuenta como cobertura, así que el gemelo pide refuerzo. Si reaparece, la respuesta se corrige sola. |
| ¿Por qué el reparto voraz falla en el sismo? | Porque reparte en orden de llegada sin ver el conjunto. El herido se lleva una ambulancia que hacía falta para los atrapados. Mi gemelo busca **todos** los repartos y encuentra 4 que cubren todo. |
| ¿Qué hace Python? | Solo **dibuja** (matplotlib). Prolog le pasa la ruta elegida y los tiempos ya deducidos con `py_call/2` (Janus). Ninguna decisión vive en Python ni en la página. |
| ¿Por qué el "ahora" es un hecho? | Para que las respuestas se puedan repetir: si usara el reloj del sistema, cada vez saldría algo distinto. |
| ¿Qué es `si_pasara/4`? | Aplica un cambio temporal (cerrar un tramo, una unidad que falla), hace la consulta y **deshace** el cambio. Así respondo "¿qué pasaría si…?" sin tocar el estado real. |
| ¿Qué hiciste en Erlang y qué en Prolog? | Erlang para lo concurrente y tolerante a fallas; Prolog para deducir y explicar. El estado del Erlang podría alimentar los hechos de este gemelo. |
