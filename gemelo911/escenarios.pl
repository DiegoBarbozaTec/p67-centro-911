:- encoding(utf8).
% ============================================================================
%  escenarios.pl — El estado del centro en un instante (hechos dinámicos).
%  Cada situación de PROBLEMA.md es un escenario que se carga con
%  cargar_escenario/1. El "ahora" es un hecho, no el reloj del sistema, para
%  que las respuestas se puedan repetir.
% ============================================================================

:- dynamic
    ahora/1,                 % ahora(Segundo) desde que empezó el turno
    estado_unidad/2,         % estado_unidad(Unidad, Estado)
    posicion/3,              % posicion(Unidad, Punto, Segundo): reporte de posición
    incidente/4,             % incidente(Inc, Tipo, Punto, Prioridad)
    llegada_incidente/2,     % llegada_incidente(Inc, Segundo): cuándo entró
    asignacion/3,            % asignacion(Unidad, Inc, Segundo)
    liberacion/3,            % liberacion(Unidad, Punto, Segundo): dónde y cuándo queda libre
    llamada/4,               % llamada(Llamada, Punto, Segundo, reporte(Tipo, Vehiculos, Lesionados))
    llamada_lugar/3,         % llamada_lugar(Llamada, X, Y) en km
    afectado/3,              % afectado(PuntoA, PuntoB, Factor): tramo lento
    cerrado/2,               % cerrado(PuntoA, PuntoB): tramo cerrado
    evento/3,                % evento(Entidad, Evento, Segundo): bitácora
    escenario_activo/1.

dinamico(ahora/1). dinamico(estado_unidad/2). dinamico(posicion/3).
dinamico(incidente/4). dinamico(llegada_incidente/2). dinamico(asignacion/3).
dinamico(liberacion/3). dinamico(llamada/4). dinamico(llamada_lugar/3).
dinamico(afectado/3). dinamico(cerrado/2). dinamico(evento/3).
dinamico(escenario_activo/1).

cargar_escenario(Id) :-
    escenario(Id, _, _, Hechos),
    forall(dinamico(N/A), ( functor(C, N, A), retractall(C) )),
    forall(member(H, Hechos), assertz(H)),
    assertz(escenario_activo(Id)).

% Las unidades que el escenario no menciona quedan disponibles en su base.
base(amb1, canon_oeste). base(amb2, centro). base(amb3, hospital). base(amb4, otay).
base(pat1, centro). base(pat2, zona_rio). base(bom1, centro). base(pc1, playas).

% ---------------------------------------------------------------------------
% escenario(Id, Titulo, Descripcion, Hechos)
% ---------------------------------------------------------------------------

% Situación 1 — Todas las ambulancias ocupadas y entra una prioridad 1.
escenario(s1_retiro,
  "Situación 1 · Todas las ambulancias ocupadas y entra una prioridad 1",
  "Paro cardiaco en puente_norte. amb1 va en camino a un P3, amb2 está en escena de un P2 (y es la más cercana), amb3 va trasladando y amb4 está libre pero lejos.",
  [ ahora(1800),
    estado_unidad(amb1, en_camino),   posicion(amb1, canon_oeste, 1790), asignacion(amb1, inc_leve, 1700),
    estado_unidad(amb2, en_escena),   posicion(amb2, canon_este, 1780),  asignacion(amb2, inc_choque, 1500),
    estado_unidad(amb3, trasladando), posicion(amb3, centro, 1790),      asignacion(amb3, inc_caida, 1200),
    liberacion(amb3, hospital, 2200),
    estado_unidad(amb4, disponible),  posicion(amb4, otay, 1795),
    estado_unidad(pat1, disponible),  posicion(pat1, centro, 1795),
    estado_unidad(pat2, en_escena),   posicion(pat2, canon_este, 1780),  asignacion(pat2, inc_choque, 1500),
    estado_unidad(bom1, disponible),  posicion(bom1, centro, 1795),
    estado_unidad(pc1,  disponible),  posicion(pc1, playas, 1795),
    incidente(inc_leve,   medica,    playas,       3), llegada_incidente(inc_leve, 1650),
    incidente(inc_choque, accidente, canon_este,   2), llegada_incidente(inc_choque, 1450),
    incidente(inc_caida,  medica,    hospital,     2), llegada_incidente(inc_caida, 1100),
    incidente(inc_paro,   medica,    puente_norte, 1), llegada_incidente(inc_paro, 1800)
  ]).

% Situación 2 — La unidad más cercana no es la más cercana.
escenario(s2_cercania,
  "Situación 2 · La unidad más cercana no es la más cercana",
  "Persona inconsciente en canon_este. amb1 está a 1 km en línea recta pero del otro lado del cañón; amb2 está a 3 km por vía directa; amb3 se libera en 1 min; el tramo de la garita está lento.",
  [ ahora(3600),
    estado_unidad(amb1, disponible),  posicion(amb1, canon_oeste, 3590),
    estado_unidad(amb2, disponible),  posicion(amb2, centro, 3595),
    estado_unidad(amb3, trasladando), posicion(amb3, zona_rio, 3590),    asignacion(amb3, inc_previo, 3000),
    liberacion(amb3, hospital, 3660),
    estado_unidad(amb4, disponible),  posicion(amb4, otay, 3590),
    estado_unidad(pat1, disponible),  posicion(pat1, centro, 3590),
    estado_unidad(pat2, disponible),  posicion(pat2, zona_rio, 3590),
    estado_unidad(bom1, disponible),  posicion(bom1, centro, 3590),
    estado_unidad(pc1,  disponible),  posicion(pc1, playas, 3590),
    afectado(zona_rio, garita, 3),
    incidente(inc_previo, medica, zona_rio, 2),   llegada_incidente(inc_previo, 2950),
    incidente(inc_s2,     medica, canon_este, 1), llegada_incidente(inc_s2, 3600)
  ]).

% Situación 3 — Doce llamadas, un solo choque (aquí siete llamadas).
escenario(s3_llamadas,
  "Situación 3 · Varias llamadas, un solo choque",
  "Cinco llamadas describen el mismo choque en el centro; una llega de una esquina cercana con otro relato (dudosa) y otra reporta un incendio en Otay.",
  [ ahora(2400),
    estado_unidad(amb1, disponible),  posicion(amb1, canon_este, 2390),
    estado_unidad(amb2, disponible),  posicion(amb2, hospital, 2390),
    estado_unidad(amb3, en_escena),   posicion(amb3, playas, 2380),     asignacion(amb3, inc_otro, 2100),
    estado_unidad(amb4, fuera_de_servicio), posicion(amb4, otay, 1000),
    estado_unidad(pat1, disponible),  posicion(pat1, centro, 2390),
    estado_unidad(pat2, disponible),  posicion(pat2, zona_rio, 2390),
    estado_unidad(bom1, disponible),  posicion(bom1, centro, 2390),
    estado_unidad(pc1,  disponible),  posicion(pc1, playas, 2390),
    incidente(inc_otro, medica, playas, 3), llegada_incidente(inc_otro, 2050),
    llamada(c1, centro, 2000, reporte(accidente, 3, 2)), llamada_lugar(c1, 13.00, 6.00),
    llamada(c2, centro, 2030, reporte(accidente, 3, 3)), llamada_lugar(c2, 13.10, 6.05),
    llamada(c3, centro, 2060, reporte(accidente, 3, 2)), llamada_lugar(c3, 12.95, 5.90),
    llamada(c4, centro, 2100, reporte(accidente, 3, 1)), llamada_lugar(c4, 13.05, 6.10),
    llamada(c5, centro, 2150, reporte(accidente, 3, 2)), llamada_lugar(c5, 13.00, 5.95),
    llamada(c6, centro, 2200, reporte(accidente, 2, 1)), llamada_lugar(c6, 13.60, 6.30),
    llamada(c7, otay,   2250, reporte(incendio,  0, 0)), llamada_lugar(c7, 19.00, 7.00)
  ]).

% Situación 4 — La unidad que dejó de contestar.
escenario(s4_sin_contacto,
  "Situación 4 · La unidad que dejó de contestar",
  "amb1 va en camino a un paro (P1) en el centro y lleva 10 min sin reportar posición. pat1 va en camino a un asalto y sí reporta.",
  [ ahora(1800),
    estado_unidad(amb1, en_camino),  posicion(amb1, canon_oeste, 1150), posicion(amb1, canon_oeste, 1200),
    asignacion(amb1, inc_p1, 1150),
    estado_unidad(amb2, disponible), posicion(amb2, hospital, 1795),
    estado_unidad(amb3, en_escena),  posicion(amb3, zona_rio, 1790),    asignacion(amb3, inc_rio, 1300),
    estado_unidad(amb4, disponible), posicion(amb4, otay, 1795),
    estado_unidad(pat1, en_camino),  posicion(pat1, garita, 1790),      asignacion(pat1, inc_robo, 1600),
    estado_unidad(pat2, disponible), posicion(pat2, zona_rio, 1790),
    estado_unidad(bom1, disponible), posicion(bom1, centro, 1790),
    estado_unidad(pc1,  disponible), posicion(pc1, playas, 1790),
    incidente(inc_p1,   medica, centro,   1), llegada_incidente(inc_p1, 1100),
    incidente(inc_rio,  medica, zona_rio, 3), llegada_incidente(inc_rio, 1250),
    incidente(inc_robo, asalto, otay,     2), llegada_incidente(inc_robo, 1550),
    evento(amb1, despachada, 1150)
  ]).

% Situación 5 — El sismo: más incidentes que unidades.
escenario(s5_sismo,
  "Situación 5 · El sismo: más incidentes que unidades",
  "Tras un sismo entran un herido (P2, llegó primero), un incendio con lesionados (P1) y personas atrapadas (P1). Solo amb1 llega a tiempo a los atrapados.",
  [ ahora(5400),
    estado_unidad(amb1, disponible), posicion(amb1, canon_este, 5390),
    estado_unidad(amb2, disponible), posicion(amb2, hospital, 5390),
    estado_unidad(amb3, disponible), posicion(amb3, otay, 5390),
    estado_unidad(amb4, disponible), posicion(amb4, garita, 5390),
    estado_unidad(pat1, disponible), posicion(pat1, centro, 5390),
    estado_unidad(pat2, disponible), posicion(pat2, zona_rio, 5390),
    estado_unidad(bom1, disponible), posicion(bom1, centro, 5390),
    estado_unidad(pc1,  disponible), posicion(pc1, canon_oeste, 5390),
    incidente(inc_herido,    herido,              zona_rio,     2), llegada_incidente(inc_herido, 5300),
    incidente(inc_fuego,     incendio_lesionados, centro,       1), llegada_incidente(inc_fuego, 5320),
    incidente(inc_atrapados, atrapados,           puente_norte, 1), llegada_incidente(inc_atrapados, 5340)
  ]).
