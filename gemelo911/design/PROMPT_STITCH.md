# Prompt para Google Stitch — Gemelo Digital 911 (proyecto #67, fase Prolog)

Pégalo en https://stitch.withgoogle.com (modo **Web**). Después exporta el diseño a esta carpeta.

```text
Diseña una interfaz web responsive (mobile-first) llamada "Gemelo Digital · Centro de Emergencias Tijuana", con el subtítulo "Prolog deduce y explica · Python solo dibuja". Todo el texto en español. Es el panel de un MODELO LÓGICO que razona sobre un centro de despacho 911: no captura datos, solo pregunta al gemelo y muestra su decisión con la explicación.

Estilo: tema oscuro de sala de control. Fondo #0b0e12, tarjetas #141a21 con radio de 16 px y borde fino, texto #e6e9ef. Acento ámbar #e6a23c para lo que viene de Prolog y azul #6cb6ff para lo que dibuja Python. Colores de estado: verde = disponible, ámbar = en camino, azul = en escena, violeta = trasladando, rojo = fuera de servicio o prioridad 1. Tipografía Inter y monoespaciada para nombres de reglas. Áreas táctiles de al menos 44 px.

Una sola página, de arriba hacia abajo:
1. Encabezado fijo con el logo "911" en rojo, el título y un selector de escenario (Situación 1 a 5).
2. Tarjeta con el título y la descripción del escenario.
3. Dos columnas en escritorio (una en celular): a la izquierda, "Mapa de la red" con una imagen PNG que genera el servidor (proporción 9:5.6, no dibujes el mapa con HTML) y su leyenda de colores; a la derecha, "Incidentes abiertos" ordenados por prioridad, cada uno con chips de prioridad, unidades asignadas y situaciones deducidas ("desprotegido", "por atender").
4. "Despacho y explicación": el mejor reparto destacado en verde con una lista de frases que lo justifican (unidad → incidente, tiempo de llegada, ruta, meta, si se retiró de otro incidente y qué incidente quedó pendiente), luego las alternativas y una comparación con el "reparto voraz". Debajo, dos columnas: "¿Por qué no las otras?" y "¿Qué falta?", más una gráfica PNG de barras con el tiempo de llegada de cada unidad y una línea roja de meta.
5. "Llamadas agrupadas": grupos de llamadas que son el mismo incidente, la llamada dudosa marcada en ámbar como "no se sabe" y una tabla de todas las llamadas; al final "Qué cuesta equivocarse".
6. "Unidades en camino: ¿llegan?": tarjetas con tres estados posibles "llega", "no llega", "no se sabe", el tiempo desde el último reporte y el refuerzo sugerido.
7. "Hipótesis": texto "¿Y si se cierra el tramo…?" con un botón "Probar la hipótesis" que muestra lado a lado "Hoy" y "Si pasara".
8. Tabla de unidades (unidad, tipo, estado, último reporte, incidente).
9. "Las 5 preguntas, mismas reglas" con un botón que muestra cada pregunta, la consulta Prolog en monoespaciada ámbar y su respuesta.
10. Pie: "Ninguna regla vive en esta página: todo lo deduce el gemelo en Prolog."

Cada tarjeta que viene de una regla lleva una etiqueta pequeña con el nombre de la regla (decide/3, que_falta/2, estado_llegada/3, si_pasara/4) y las gráficas llevan una franja "Cómo se hizo": regla de Prolog → función de Python.
```
