# #67 — Centro de emergencias 911: el problema

## Contexto
Desde 2017 el numero unico de emergencias en Mexico es el 911. Una llamada se contesta, se clasifica por tipo y gravedad, y se despacha la unidad adecuada (policia, ambulancia, bomberos, proteccion civil). Cada minuto de retraso cuenta, y los recursos siempre son menos que los incidentes. Proyecto educativo de simulacion.

## Datos del mundo real
- Estandares de referencia internacionales: contestar 90 % de las llamadas en menos de 10-15 s (NENA); primera unidad de bomberos en ~4 min y soporte vital avanzado en ~8 min (NFPA 1710).
- En el 911 de Mexico, la gran mayoria de las llamadas recibidas son improcedentes (bromas, errores, informacion); solo una fraccion pequeña son emergencias reales, y el filtro rapido es clave.
- Las prioridades usuales: 1 (riesgo inminente de vida), 2 (urgente), 3 (no urgente), con tiempos de respuesta meta distintos.
- La unidad "mas cercana" se mide por **tiempo de viaje**, no por distancia en linea recta: una ambulancia a 1 km pero al otro lado de un cañon o de la garita puede tardar mas que una a 3 km.
- Estados de una unidad: disponible, despachada, en camino, en escena, trasladando, fuera de servicio. Una unidad ocupada no puede despacharse a otro incidente, salvo orden de prioridad superior.
- El sistema debe funcionar durante la crisis misma (sismo, evento masivo) cuando el volumen se multiplica.

## El problema
Recibir incidentes, asignar prioridad, escoger y despachar la unidad adecuada considerando su tipo, estado y cercania real, reasignar cuando surge algo mas urgente, y mantener una linea de tiempo auditable de cada incidente, sin caerse cuando el volumen de llamadas se dispara.

## Escenario a simular
- 40 unidades de 4 tipos, 200 incidentes en un turno de 8 horas.
- Accidente multiple con 12 llamadas por el mismo hecho.
- Todas las ambulancias ocupadas y entra una prioridad 1.

## Casos dificiles
- Detectar llamadas duplicadas del mismo incidente.
- Retirar una unidad de un incidente leve para uno grave.
- Perdida de comunicacion con una unidad en camino.

## Preguntas guia
1. ¿Que significa "mas cercana" y como se calcula?
2. ¿Que no puede perderse jamas aunque todo lo demas falle?

## Que debes entregar (sin que aqui se de la solucion)
- Un diseño OTP explicado brevemente: procesos, supervisores y quien reinicia a quien, justificando cada decision frente a los casos dificiles de arriba.
- La simulacion del escenario descrito, con datos generados y fallas inyectadas.
- Una lista de supuestos propios y de las cifras de este documento que verificaste.
- Una prueba de caos: que mataste, que esperabas y que ocurrio.
- `rebar3 compile` y `rebar3 eunit` en verde; capturas de Stitch y de la app real si hay interfaz.

---
*Las cifras son de referencia (ordenes de magnitud). Verifica la fuente vigente antes de citarlas en tu entrega y anota las que uses en tu README.*
