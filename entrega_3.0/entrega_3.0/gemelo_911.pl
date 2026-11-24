:- encoding(utf8).
% ============================================================================
%  gemelo_911.pl — Gemelo digital (base mínima) del Centro de Emergencias 911
%  Proyecto #67 · Programación Lógica y Funcional · TecNM / IT Tijuana
%  Alumno: Diego Antonio Barboza Carballo · No. Control 23212702
%
%  Cómo usarlo (SWI-Prolog):
%     $ swipl gemelo_911.pl
%     ?- reporte.                 % corre todas las consultas de la entrega
%     ?- decision(inc5, Unidad, Accion, Min).
%
%  El "ahora" es un hecho del modelo (segundos desde que empezó el turno),
%  no el reloj del sistema, para que las respuestas sean repetibles.
% ============================================================================

:- dynamic tramo/3, estado/2, atiende/2, ultimo_reporte/2.
:- discontiguous tramo/3.

% ---------------------------------------------------------------------------
% HECHOS (estado del centro en este instante)
% ---------------------------------------------------------------------------

ahora(1800).                       % 30 min de turno

% --- Red de calles: tramo(PuntoA, PuntoB, MinutosDeViaje) (doble sentido).
%     Un cañón separa el oeste del este; solo se cruza por dos puentes.
tramo(playas,        canon_oeste,   4).
tramo(canon_oeste,   puente_norte,  3).
tramo(canon_oeste,   puente_sur,    5).
tramo(puente_norte,  canon_este,    2).
tramo(puente_sur,    canon_este,    6).
tramo(canon_este,    centro,        3).
tramo(centro,        zona_rio,      4).
tramo(zona_rio,      garita,        3).    % tramo lento por la fila de la garita
tramo(zona_rio,      otay,          7).
tramo(garita,        otay,         12).
tramo(centro,        hospital,      5).

% --- Unidades: unidad(Id, Tipo).  8 unidades de 4 tipos.
unidad(amb1, ambulancia).
unidad(amb2, ambulancia).
unidad(amb3, ambulancia).
unidad(amb4, ambulancia).
unidad(pat1, patrulla).
unidad(pat2, patrulla).
unidad(bom1, bomberos).
unidad(pc1,  proteccion_civil).

% --- Estado de cada unidad: estado(Unidad, Estado).
estado(amb1, en_camino).
estado(amb2, en_escena).
estado(amb3, trasladando).
estado(amb4, disponible).
estado(pat1, en_camino).
estado(pat2, disponible).
estado(bom1, disponible).
estado(pc1,  fuera_de_servicio).

% --- Dónde se reportó cada unidad por última vez: ubicada(Unidad, Punto).
ubicada(amb1, canon_oeste).
ubicada(amb2, zona_rio).
ubicada(amb3, hospital).
ubicada(amb4, otay).
ubicada(pat1, garita).
ubicada(pat2, centro).
ubicada(bom1, centro).
ubicada(pc1,  playas).

% --- Instante (s) del último reporte de posición: ultimo_reporte(Unidad, Seg).
ultimo_reporte(amb1, 1750).
ultimo_reporte(amb2, 1790).
ultimo_reporte(amb3, 1780).
ultimo_reporte(amb4, 1795).
ultimo_reporte(pat1, 1200).        % lleva 10 minutos sin reportar
ultimo_reporte(pat2, 1798).
ultimo_reporte(bom1, 1799).
ultimo_reporte(pc1,   900).

% --- Incidentes: incidente(Id, Tipo, Punto, Prioridad).  1 = riesgo de vida.
incidente(inc1, medica,    playas,       3).   % malestar leve
incidente(inc2, accidente, zona_rio,     2).
incidente(inc3, delito,    otay,         1).   % asalto con arma
incidente(inc4, incendio,  canon_este,   2).
incidente(inc5, medica,    puente_norte, 1).   % NUEVO: paro cardiaco

% --- Qué unidad atiende qué incidente: atiende(Unidad, Incidente).
atiende(amb1, inc1).
atiende(amb2, inc2).
atiende(pat1, inc3).

% --- Qué tipo de unidad pide cada clase de incidente (supuesto propio).
pide(medica,    ambulancia).
pide(accidente, ambulancia).
pide(delito,    patrulla).
pide(incendio,  bomberos).

% --- Parámetros del modelo (supuestos declarados).
meta_min(1, 8).                    % prioridad 1: ~8 min (soporte vital avanzado)
meta_min(2, 15).
meta_min(3, 30).
umbral_silencio(300).              % 5 min sin reportar = dudosa

% ---------------------------------------------------------------------------
% REGLAS
% ---------------------------------------------------------------------------

% R1. conectado/3: los tramos se recorren en ambos sentidos.
conectado(A, B, M) :- tramo(A, B, M).
conectado(A, B, M) :- tramo(B, A, M).

% R2. ruta/4 (recursiva): un camino sin ciclos de A a B y su tiempo total.
%     Prolog prueba un tramo, sigue y, si se atora, regresa (backtracking).
ruta(A, B, Camino, Min) :-
    ruta_(A, B, [A], Inv, Min),
    reverse(Inv, Camino).

ruta_(B, B, Visitados, Visitados, 0).
ruta_(A, B, Visitados, Camino, Min) :-
    conectado(A, X, M1),
    \+ memberchk(X, Visitados),
    ruta_(X, B, [X|Visitados], Camino, M2),
    Min is M1 + M2.

% R3. ruta_mas_rapida/4: la ruta de menor tiempo entre todas las posibles.
ruta_mas_rapida(A, B, Camino, Min) :-
    aggregate_all(min(M, C), ruta(A, B, C, M), min(Min, Camino)).

% R4. eta/4: cuánto tarda una unidad en llegar a un incidente y por dónde.
eta(Unidad, Inc, Min, Camino) :-
    ubicada(Unidad, Desde),
    incidente(Inc, _, Hacia, _),
    ruta_mas_rapida(Desde, Hacia, Camino, Min).

% R5. sirve/2: la unidad es del tipo que el incidente pide.
sirve(Unidad, Inc) :-
    incidente(Inc, TipoInc, _, _),
    pide(TipoInc, TipoUnidad),
    unidad(Unidad, TipoUnidad).

% R6. libre/2: sirve, está disponible y no tiene incidente asignado.
libre(Unidad, Inc) :-
    sirve(Unidad, Inc),
    estado(Unidad, disponible),
    \+ atiende(Unidad, _).

% R7. retirable/2: una unidad ocupada se puede retirar solo si atiende un
%     incidente MENOS urgente (número de prioridad mayor) y no va trasladando
%     a un paciente (no se abandona a alguien que ya va en la ambulancia).
retirable(Unidad, IncNuevo) :-
    sirve(Unidad, IncNuevo),
    atiende(Unidad, IncActual),
    incidente(IncActual, _, _, PActual),
    incidente(IncNuevo, _, _, PNuevo),
    PActual > PNuevo,
    \+ estado(Unidad, trasladando).

% R8. por_que_no_retirable/3: explica por qué una unidad ocupada NO se retira.
por_que_no_retirable(Unidad, IncNuevo, trasladando_paciente) :-
    sirve(Unidad, IncNuevo), estado(Unidad, trasladando).
por_que_no_retirable(Unidad, IncNuevo, atiende_prioridad_igual_o_mayor(IncActual, P)) :-
    sirve(Unidad, IncNuevo),
    atiende(Unidad, IncActual),
    incidente(IncActual, _, _, P),
    incidente(IncNuevo, _, _, PNuevo),
    P =< PNuevo.

% R9. decision/4: QUÉ unidad mandar y QUÉ hacer.
%   a) Si hay una unidad libre que llega dentro de la meta, se manda esa.
%   b) Si no, se retira la unidad retirable que llegue antes, siempre que
%      llegue dentro de la meta.
%   c) Si nada llega a tiempo, se manda la libre más rápida y se avisa.
decision(Inc, Unidad, mandar_libre, Min) :-
    mejor_libre(Inc, Unidad, Min),
    incidente(Inc, _, _, P), meta_min(P, Meta),
    Min =< Meta, !.
decision(Inc, Unidad, retirar_de(IncViejo), Min) :-
    incidente(Inc, _, _, P), meta_min(P, Meta),
    % Candidatas que llegan a tiempo. Se prefiere quitarle la unidad al
    % incidente MENOS urgente (clave -PViejo) y, a igualdad, la que llega antes.
    findall(Clave-M-U,
            ( retirable(U, Inc), eta(U, Inc, M, _), M =< Meta,
              atiende(U, IV), incidente(IV, _, _, PV), Clave is -PV ),
            Cands),
    msort(Cands, [_-Min-Unidad|_]), !,
    atiende(Unidad, IncViejo).
decision(Inc, Unidad, mandar_libre_fuera_de_meta, Min) :-
    mejor_libre(Inc, Unidad, Min).

mejor_libre(Inc, Unidad, Min) :-
    aggregate_all(min(M, U), (libre(U, Inc), eta(U, Inc, M, _)), min(Min, Unidad)).

% R10. sin_contacto/2: unidad que "va en camino" pero lleva más del umbral
%      sin reportar. El sistema dice "en camino"; el gemelo dice "no lo sé".
sin_contacto(Unidad, Segundos) :-
    estado(Unidad, en_camino),
    ultimo_reporte(Unidad, T),
    ahora(Ahora),
    Segundos is Ahora - T,
    umbral_silencio(U),
    Segundos > U.

% R11. situacion_llegada/2: tres respuestas posibles, no dos.
situacion_llegada(Unidad, llega)    :- estado(Unidad, en_camino), \+ sin_contacto(Unidad, _).
situacion_llegada(Unidad, no_se)    :- sin_contacto(Unidad, _).
situacion_llegada(Unidad, no_llega) :- atiende(Unidad, _), estado(Unidad, fuera_de_servicio).

% R12. en_riesgo/2: incidente de prioridad 1 sin cobertura confiable.
en_riesgo(Inc, sin_unidad) :-
    incidente(Inc, _, _, 1),
    \+ atiende(_, Inc).
en_riesgo(Inc, unidad_sin_contacto(U)) :-
    incidente(Inc, _, _, 1),
    atiende(U, Inc),
    sin_contacto(U, _).

% R13. desatendido/1: incidente abierto sin ninguna unidad asignada.
desatendido(Inc) :-
    incidente(Inc, _, _, _),
    \+ atiende(_, Inc).

% R14. hipotesis_cierre/5: "¿qué pasaría si se cierra un tramo?".
%      Quita el tramo, calcula, y lo vuelve a poner (assert/retract).
hipotesis_cierre(A, B, Inc, Unidad, Min) :-
    retract(tramo(A, B, T)),
    (   eta(Unidad, Inc, Min, _) -> Res = ok ; Res = sin_ruta ),
    assertz(tramo(A, B, T)),
    Res == ok.

% ---------------------------------------------------------------------------
% CONSULTAS DE LA ENTREGA (imprimen pregunta, respuesta y explicación)
% ---------------------------------------------------------------------------

reporte :-
    nl, writeln('=== Gemelo digital 911: consultas ==='), nl,
    c1, c2, c3, c4, c5.

% C1. Situación 1 + 2: entra un paro cardiaco (inc5) y no hay ambulancia libre cerca.
c1 :-
    writeln('C1. ?- decision(inc5, Unidad, Accion, Min).'),
    decision(inc5, U, A, M),
    format('    Unidad = ~w, Accion = ~w, Min = ~w~n', [U, A, M]),
    eta(U, inc5, M, Ruta),
    format('    Ruta: ~w~n', [Ruta]),
    (   mejor_libre(inc5, UL, ML)
    ->  format('    Por que no la libre: ~w tarda ~w min y la meta P1 es 8 min.~n', [UL, ML])
    ;   true ),
    forall(( retirable(X, inc5), eta(X, inc5, MX, _), atiende(X, IX), incidente(IX, _, _, PX) ),
           format('    Retirable: ~w (atiende ~w de prioridad ~w, llegaria en ~w min)~n', [X, IX, PX, MX])),
    forall(por_que_no_retirable(X, inc5, R),
           format('    ~w no se retira: ~w~n', [X, R])),
    (   A = retirar_de(Viejo)
    ->  format('    Queda pendiente: ~w vuelve a la cola sin unidad (no se olvida).~n', [Viejo])
    ;   true ), nl.

% C2. Situación 2: "la más cercana" en línea recta no es la que llega primero.
c2 :-
    writeln('C2. ?- ruta_mas_rapida(playas, centro, Camino, Min).'),
    ruta_mas_rapida(playas, centro, C, M),
    format('    Camino = ~w, Min = ~w~n', [C, M]),
    findall(Mi-Ca, ruta(playas, centro, Ca, Mi), Todas),
    msort(Todas, Ord),
    format('    Todas las rutas (backtracking): ~w~n~n', [Ord]).

% C3. Situación 4: la unidad que dejó de contestar.
c3 :-
    writeln('C3. ?- en_riesgo(Inc, Motivo).'),
    forall(en_riesgo(I, Mo), format('    Inc = ~w, Motivo = ~w~n', [I, Mo])),
    forall(sin_contacto(U, S),
           ( situacion_llegada(U, Sit),
             format('    ~w lleva ~w s sin reportar -> llegada: ~w~n', [U, S, Sit]) )),
    (   mejor_libre(inc3, R, MR)
    ->  format('    Refuerzo sugerido para inc3: ~w (~w min)~n', [R, MR])
    ;   true ), nl.

% C4. Colecciones: incidentes sin unidad (setof + negación).
c4 :-
    writeln('C4. ?- setof(I, desatendido(I), L).'),
    setof(I, desatendido(I), L),
    format('    L = ~w~n~n', [L]).

% C5. Hipótesis: ¿qué pasa si se cierra el puente norte?
c5 :-
    writeln('C5. ?- hipotesis_cierre(canon_oeste, puente_norte, inc5, amb1, Min).'),
    eta(amb1, inc5, Antes, _),
    hipotesis_cierre(canon_oeste, puente_norte, inc5, amb1, Despues),
    format('    amb1 hoy llega a inc5 en ~w min; si cierran ese tramo, en ~w min (meta 8).~n', [Antes, Despues]),
    eta(amb4, inc5, A5, _),
    hipotesis_cierre(puente_norte, canon_este, inc5, amb4, D5),
    format('    amb4 a inc5: hoy ~w min; si cierran puente_norte-canon_este, ~w min.~n~n', [A5, D5]).
