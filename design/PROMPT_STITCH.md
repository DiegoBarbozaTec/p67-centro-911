# Prompt para Google Stitch — #67 Centro de emergencias 911

Copia y pega este texto en https://stitch.withgoogle.com (modo "App web").

---

Diseña la interfaz web de un **Centro de Emergencias 911 de Tijuana** para operadores
que despachan unidades (ambulancias, patrullas, bomberos y protección civil) por
prioridad y por **tiempo de viaje real** (no distancia en línea recta). Tema oscuro tipo
sala de control, todo en español, legible en celular y en escritorio.

Colores de estado: verde = disponible / ok, ámbar = en camino / alerta,
azul = en escena, rojo = falla / fuera de servicio / prioridad 1.

Pantallas:

1. **Dashboard en vivo**: barra superior con "911 · Centro de Emergencias · Tijuana" e
   indicador "en vivo". Fila de indicadores: incidentes abiertos, P1 abiertos, en espera,
   unidades libres (x/40), tiempo promedio de llegada, % que cumple la meta.
   Mapa de la ciudad con un cañón vertical al centro y dos puentes, unidades como
   puntos de color por estado e incidentes como rombos de color por prioridad.
   A la derecha, lista de incidentes abiertos ordenada por prioridad
   (folio, tipo, descripción, unidad asignada, ETA, estado).
2. **Detalle de incidente**: folio, tipo, prioridad, número de llamadas recibidas,
   unidad asignada y una **línea de tiempo** vertical: recibido → unidad asignada →
   unidad aceptó → llegada a escena → cerrado (incluyendo reasignaciones en rojo).
3. **Flota de unidades**: tabla con unidad, tipo, estado, incidente, posición, ETA,
   estado del radio y número de reinicios.
4. **Bitácora auditable**: lista de eventos con número, hora, tipo de evento, folio y
   un hash corto; botón "Verificar integridad".
5. **Panel de simulación**: botones "Turno 8 h", "Accidente múltiple",
   "Sin ambulancias + P1" y botones rojos de prueba de caos
   ("Matar unidad", "Perder comunicación", "Unidad no acepta", "Matar despachador").

---

Exporta el zip desde Stitch y descomprímelo en esta carpeta (`design/`), incluyendo `DESIGN.md`.
El panel real del sistema (`priv/www/index.html`) implementa estas mismas pantallas
conectadas en tiempo real al backend Erlang por WebSocket.
