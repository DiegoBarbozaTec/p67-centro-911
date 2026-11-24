# 🧠 Práctica 3.0: Prolog Lab y mi Gemelo Digital (Centro 911)

| | |
|---|---|
| **Alumno** | Diego Antonio Barboza Carballo · No. Control 23212702 |
| **Materia** | Programación Lógica y Funcional |
| **Profesor** | René Solís Reyes |
| **Institución** | TecNM / Instituto Tecnológico de Tijuana |
| **Proyecto** | #67 Centro de emergencias 911 (fase 2: gemelo digital en Prolog) |

### 🔗 Contenido de la entrega

| Parte | Dónde está |
|---|---|
| 1. Prolog Lab: 20 niveles completados | [Sección 1](#1-prolog-lab-20-niveles-completados) |
| 2. Base de conocimiento del gemelo (`gemelo_911.pl`) | Archivo `gemelo_911.pl` de este gist y [en el repositorio](https://github.com/DiegoBarbozaTec/p67-centro-911/blob/main/entrega_3.0/gemelo_911.pl) |
| 3. Consultas con sus respuestas | [Sección 3](#3-consultas-y-respuestas) y [`consultas_y_respuestas.txt`](https://github.com/DiegoBarbozaTec/p67-centro-911/blob/main/entrega_3.0/consultas_y_respuestas.txt) |
| 4. Pruebas plunit | [`pruebas_gemelo.pl`](https://github.com/DiegoBarbozaTec/p67-centro-911/blob/main/entrega_3.0/pruebas_gemelo.pl) (6 pruebas, todas pasan) |
| 5. Reflexión | [Sección 5](#5-reflexión) |

---

## 1. Prolog Lab: 20 niveles completados

Completé los 20 niveles del tutorial [prolog-lab.fly.dev](https://prolog-lab.fly.dev): **69/69 retos**, todos validados por el propio laboratorio.

**📸 Menú con los 20 niveles marcados (✓)**

![Menú 1](https://github.com/DiegoBarbozaTec/p67-centro-911/raw/main/entrega_3.0/3.0-menu-1.png)

![Menú 2](https://github.com/DiegoBarbozaTec/p67-centro-911/raw/main/entrega_3.0/3.0-menu-2.png)

**📸 Árbol de búsqueda del nivel 4 (coloreado de mapas):** `21 nodos, 5 fallos, 5 retrocesos, 1 solución`. Cada ✗ es un camino que falla y Prolog regresa (backtracking) a la última elección para probar otro color.

![Árbol de búsqueda](https://github.com/DiegoBarbozaTec/p67-centro-911/raw/main/entrega_3.0/3.0-arbol.png)

**Lo que más se conecta con mi gemelo:**

| Nivel | Tema | Dónde lo usé en el gemelo 911 |
|---|---|---|
| 1–2 | Hechos y reglas | Unidades, incidentes y calles como hechos; `sirve/2` y `libre/2` como reglas |
| 4 | Backtracking | `ruta/4` prueba un tramo, se atora y regresa para probar otro |
| 7 | setof / negación | `desatendido/1` con `\+` y `setof` para listar incidentes sin unidad |
| 11 | Grafos | La red de calles con el cañón y los puentes; `ruta_mas_rapida/4` |
| 12 | Base dinámica | `hipotesis_cierre/5` quita un tramo con `retract`, calcula y lo regresa con `assertz` |
| 13 | Sistema experto | `decision/4` decide y explica por qué no la otra unidad |

---

## 2. Base de conocimiento del gemelo digital

**El caso:** un turno del centro 911 reducido a 8 unidades de 4 tipos, 5 incidentes y una red de 10 puntos con un cañón que solo se cruza por dos puentes. Entra un **paro cardiaco (inc5, prioridad 1)** y ninguna ambulancia libre llega a tiempo.

| Requisito de la práctica | Mi gemelo |
|---|---|
| Al menos 10 hechos | **58 hechos**: tramos de la red, unidades, estados, posiciones, reportes, incidentes, asignaciones y parámetros |
| Al menos 3 reglas | **14 reglas**, entre ellas una recursiva (`ruta/4`) |
| Al menos 3 consultas que deduzcan algo no escrito | **5 consultas** (sección 3) |

**Hechos (ejemplo):**

```prolog
tramo(canon_oeste, puente_norte, 3).      % minutos de viaje
unidad(amb1, ambulancia).
estado(amb1, en_camino).
ubicada(amb1, canon_oeste).
ultimo_reporte(pat1, 1200).               % segundos desde que empezó el turno
incidente(inc5, medica, puente_norte, 1). % paro cardiaco, prioridad 1
atiende(amb1, inc1).
```

**Reglas principales:**

| Regla | Qué deduce |
|---|---|
| `ruta/4` (recursiva) | Todos los caminos sin ciclos entre dos puntos y su tiempo |
| `ruta_mas_rapida/4` | El camino de menor tiempo ("más cercana" = la que llega antes, no la que está más cerca en línea recta) |
| `eta/4` | Cuánto tarda una unidad en llegar a un incidente y por dónde |
| `retirable/2` | Qué unidad ocupada se puede quitar: solo si atiende algo menos urgente y no va trasladando a un paciente |
| `decision/4` | Qué unidad mandar: la libre si llega en la meta; si no, retirar a la del incidente menos urgente |
| `sin_contacto/2` y `situacion_llegada/2` | Tres respuestas: **llega**, **no llega** o **no lo sé** |
| `en_riesgo/2` | Incidentes de prioridad 1 sin cobertura confiable |
| `hipotesis_cierre/5` | "¿Qué pasaría si se cierra un tramo?" sin modificar la red real |

El código completo está en el archivo **`gemelo_911.pl`** de este gist. Para correrlo: `swipl gemelo_911.pl` y luego `?- reporte.`

---

## 3. Consultas y respuestas

Ejecutado en SWI-Prolog con `swipl gemelo_911.pl` y luego `?- reporte.`

**C1. Entra un paro cardiaco y no hay ambulancia libre cerca. ¿A quién mando?**

```prolog
?- decision(inc5, Unidad, Accion, Min).
Unidad = amb1, Accion = retirar_de(inc1), Min = 3
Ruta: [canon_oeste,puente_norte]
Por que no la libre: amb4 tarda 16 min y la meta P1 es 8 min.
Retirable: amb1 (atiende inc1 de prioridad 3, llegaria en 3 min)
Retirable: amb2 (atiende inc2 de prioridad 2, llegaria en 9 min)
amb3 no se retira: trasladando_paciente
Queda pendiente: inc1 vuelve a la cola sin unidad (no se olvida).
```

**Qué dedujo:** en ningún hecho dice "manda amb1". El gemelo combinó estado, prioridad y tiempo de viaje: la única libre (amb4) no llega en la meta de 8 min, amb3 lleva a un paciente y amb1 atiende el caso menos urgente (P3) y llega en 3 min. Además dice a quién le falla: inc1 vuelve a la cola.

**C2. ¿Por dónde se llega más rápido de Playas al Centro?**

```prolog
?- ruta_mas_rapida(playas, centro, Camino, Min).
Camino = [playas,canon_oeste,puente_norte,canon_este,centro], Min = 12
Todas las rutas (backtracking): [12-[...puente_norte...], 18-[...puente_sur...]]
```

**Qué dedujo:** ninguna ruta está escrita. Prolog encontró las dos por backtracking (probó un puente, regresó y probó el otro) y eligió la de 12 min.

**C3. ¿Qué incidente de prioridad 1 está en riesgo?**

```prolog
?- en_riesgo(Inc, Motivo).
Inc = inc5, Motivo = sin_unidad
Inc = inc3, Motivo = unidad_sin_contacto(pat1)
pat1 lleva 600 s sin reportar -> llegada: no_se
Refuerzo sugerido para inc3: pat2 (11 min)
```

**Qué dedujo:** el sistema dice que pat1 está "en camino", pero lleva 10 min sin reportar. El gemelo no afirma que llega ni que no llega: responde **"no lo sé"**, marca el asalto (inc3) en riesgo y sugiere un refuerzo.

**C4. ¿Qué incidentes no tienen unidad?**

```prolog
?- setof(I, desatendido(I), L).
L = [inc4,inc5]
```

**C5. Hipótesis: ¿qué pasa si se cierra un tramo?**

```prolog
?- hipotesis_cierre(canon_oeste, puente_norte, inc5, amb1, Min).
amb1 hoy llega a inc5 en 3 min; si cierran ese tramo, en 13 min (meta 8).
amb4 a inc5: hoy 16 min; si cierran puente_norte-canon_este, 28 min.
```

**Qué dedujo:** con las mismas reglas, sin escribir código nuevo, el gemelo responde una pregunta de "¿qué pasaría si…?". Si ese tramo se cierra, amb1 ya no llega en la meta, y habría que reconsiderar la decisión.

**📸 Así se ve una consulta validada en el Prolog Lab (nivel 1)**

![Terminal](https://github.com/DiegoBarbozaTec/p67-centro-911/raw/main/entrega_3.0/3.0-terminal-nivel1.png)

### Pruebas plunit

```text
$ swipl -g run_tests -t halt pruebas_gemelo.pl
% PL-Unit: gemelo_911 ...... passed 0.009 sec
% All 6 tests passed
```

---

## 4. Supuestos declarados

- El "ahora" es un hecho (`ahora(1800)`, minuto 30 del turno) para que las respuestas se puedan repetir.
- Metas de llegada: P1 8 min (referencia del problema original para soporte vital avanzado), P2 15 min, P3 30 min.
- Una unidad sin reportar más de 5 min (`umbral_silencio(300)`) se vuelve dudosa.
- Solo se retira una unidad de un incidente **menos urgente**, y nunca a una ambulancia que va trasladando a un paciente.
- Los tiempos de los tramos, los nombres de las zonas y los identificadores son datos del ejercicio, no mediciones reales.

---

## 5. Reflexión

En mi gemelo del centro 911 escribí solo lo que se sabe: dónde está cada unidad, en qué estado va, qué incidente atiende, cuánto tarda cada calle y cuándo reportó cada una por última vez. Con reglas, el gemelo dedujo cosas que ningún hecho dice: que la ambulancia que hay que mandar al paro cardiaco es amb1 aunque esté ocupada, que el caso leve que deja queda pendiente, que la patrulla que dejó de reportar no se sabe si llega y que, por eso, el asalto de prioridad 1 está en riesgo. También dedujo la ruta más rápida sin que existiera escrita, porque Prolog la construyó tramo por tramo y regresó cuando un camino no servía.

La ventaja frente a solo guardar datos es que una base de datos me diría "amb1 está en camino a inc1" y "pat1 reportó en el segundo 1200", pero no me diría qué hacer con eso. Para cada pregunta nueva tendría que programar una función nueva. En Prolog, con las mismas reglas contesto preguntas de decisión ("¿a quién mando?"), de explicación ("¿por qué no la libre?"), de colección ("¿qué incidentes no tienen unidad?") y de hipótesis ("¿y si cierran el puente?"). Además, el gemelo puede responder "no lo sé" en lugar de repetir lo que el sistema afirma, y eso en un centro de emergencias es la diferencia entre confiar en un dato viejo y mandar un refuerzo a tiempo.

---

## Referencias

- Prolog Lab: https://prolog-lab.fly.dev
- Reto del gemelo, proyecto #67: https://github.com/tectijuana/logicfun-proyectos/tree/main/proyectos/67-centro-de-emergencias-911/gemelo
- Demo del curso (logicDemo): https://github.com/tectijuana/logicfun-proyectos/tree/main/logicDemo
- Bratko, I. *Prolog Programming for Artificial Intelligence*, cap. 1–4.
- Documentación de SWI-Prolog (aggregate_all, setof, plunit): https://www.swi-prolog.org/pldoc/
