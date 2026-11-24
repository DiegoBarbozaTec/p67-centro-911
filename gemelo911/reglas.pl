:- encoding(utf8).
% ============================================================================
%  reglas.pl — Cómo razona el centro de despacho. Mismas reglas para:
%    decidir (¿qué unidad mando?), explicar (¿por qué no la otra?),
%    enumerar (¿qué repartos hay?), invertir (¿qué falta?) e
%    hipótesis (¿qué pasaría si…?).
%  Toda condición distingue tres resultados: si, no, no_se.
% ============================================================================

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).
:- use_module(library(pairs)).

% ============================================================================
% 1. LA RED: "más cercana" es menor tiempo por calles, no línea recta
% ============================================================================

% conecta(A, B, Segundos): tramo transitable en cualquier sentido, con su
% tiempo real (multiplicado si está afectado) y excluyendo tramos cerrados.
conecta(A, B, T) :-
    ( tramo(A, B, T0) ; tramo(B, A, T0) ),
    \+ cerrado_entre(A, B),
    factor(A, B, F),
    T is round(T0 * F).

cerrado_entre(A, B) :- cerrado(A, B), !.
cerrado_entre(A, B) :- cerrado(B, A).

factor(A, B, F) :- ( afectado(A, B, F) ; afectado(B, A, F) ), !.
factor(_, _, 1).

% ruta(A, B, Camino, Segundos) — recursiva: prueba un tramo, sigue y, si se
% atora, regresa a probar otro (backtracking). No repite puntos.
ruta(A, B, Camino, T) :-
    ruta_(A, B, [A], Inv, T),
    reverse(Inv, Camino).

ruta_(B, B, Vistos, Vistos, 0).
ruta_(A, B, Vistos, Camino, T) :-
    A \== B,
    conecta(A, X, T1),
    \+ memberchk(X, Vistos),
    ruta_(X, B, [X|Vistos], Camino, T2),
    T is T1 + T2.

ruta_mas_rapida(A, B, Camino, T) :-
    aggregate_all(min(T0, C0), ruta(A, B, C0, T0), min(T, Camino)).

rutas_empatadas(A, B, T, Caminos) :-
    ruta_mas_rapida(A, B, _, T),
    findall(C, ruta(A, B, C, T), Cs0),
    sort(Cs0, Caminos).

dist_recta(P1, P2, Km) :-
    coord(P1, X1, Y1), coord(P2, X2, Y2),
    Km is round(sqrt((X1-X2)**2 + (Y1-Y2)**2) * 10) / 10.

obstaculos(Camino, Obs) :-
    findall(O, ( nextto(A, B, Camino), ( cruza(A, B, O) ; cruza(B, A, O) ) ), Os),
    sort(Os, Obs).

% ============================================================================
% 2. UNIDADES: de dónde salen, cuánto esperan y cuándo llegan
% ============================================================================

ultima_posicion(U, P, S) :-
    aggregate_all(max(S0, P0), posicion(U, P0, S0), max(S, P)).

silencio(U, Seg) :-
    ultima_posicion(U, _, S), ahora(N), Seg is N - S.

libre(U) :- estado_unidad(U, disponible).

atiende(U, I) :-
    asignacion(U, I, _),
    estado_unidad(U, E),
    memberchk(E, [despachada, en_camino, en_escena, trasladando]).

% salida(U, Punto, Espera, Modo): desde dónde y tras cuánto tiempo puede salir.
salida(U, P, 0, libre) :-
    libre(U), ultima_posicion(U, P, _).
salida(U, P, Espera, se_libera) :-
    estado_unidad(U, trasladando),
    liberacion(U, P, S), ahora(N),
    Espera is max(0, S - N).

% llegada(U, Destino, Total, Ruta, Espera, Modo)
llegada(U, Destino, Total, Ruta, Espera, Modo) :-
    salida(U, P, Espera, Modo),
    ruta_mas_rapida(P, Destino, Ruta, T),
    Total is Espera + T.

% Una unidad retirada sale de donde reportó por última vez, sin esperar.
llegada_retiro(U, Destino, T, Ruta) :-
    ultima_posicion(U, P, _),
    ruta_mas_rapida(P, Destino, Ruta, T).

meta_para(I, TipoU, M) :-
    incidente(I, _, _, P),
    (   meta_tipo(P, TipoU, M0) -> M = M0 ; meta(P, M) ).

necesita(I, TipoU, K) :-
    incidente(I, Tipo, _, _), requiere(Tipo, TipoU, K).

% Incidentes abiertos sin todas sus unidades.
por_atender(I) :-
    incidente(I, _, _, _),
    necesita(I, T, K),
    aggregate_all(count, ( atiende(U, I), unidad(U, T) ), N),
    N < K, !.

% ============================================================================
% 3. SITUACIÓN 1 — RETIRO: quién se puede quitar y quién no
% ============================================================================

% Una unidad ocupada solo se retira por una prioridad SUPERIOR (número menor)
% y nunca si va trasladando a un paciente.
retirable(U, Nuevo, desde(IncV, PV, E)) :-
    incidente(Nuevo, _, _, PN),
    necesita(Nuevo, T, _), unidad(U, T),
    atiende(U, IncV), IncV \== Nuevo,
    incidente(IncV, _, _, PV),
    estado_unidad(U, E), E \== trasladando,
    PV > PN.

no_retirable(U, Nuevo, lleva_paciente(IncV)) :-
    incidente(Nuevo, _, _, _),
    necesita(Nuevo, T, _), unidad(U, T),
    atiende(U, IncV), IncV \== Nuevo,
    estado_unidad(U, trasladando).
no_retirable(U, Nuevo, prioridad_no_menor(IncV, PV, PN)) :-
    incidente(Nuevo, _, _, PN),
    necesita(Nuevo, T, _), unidad(U, T),
    atiende(U, IncV), IncV \== Nuevo,
    \+ estado_unidad(U, trasladando),
    incidente(IncV, _, _, PV),
    PV =< PN.

% Costo de retirar: primero del incidente menos urgente; a igualdad, mejor
% quitarla de quien va en camino que de quien ya atiende en escena.
costo_retiro(desde(_, PV, E), C) :-
    ( E == en_escena -> R = 1 ; R = 0 ),
    C is (4 - PV) * 10 + R.

% ============================================================================
% 4. CANDIDATAS Y REPARTO (situaciones 1, 2 y 5)
% ============================================================================

% candidata(I, TipoU, c(U, Eta, Modo, Ruta)): unidad del tipo que llega
% dentro de la meta. Modo: libre | se_libera(Espera) | retiro(desde(...)).
candidata(I, TipoU, c(U, Eta, Modo, Ruta)) :-
    incidente(I, _, P, _), meta_para(I, TipoU, Meta),
    unidad(U, TipoU),
    llegada(U, P, Eta, Ruta, Espera, M0),
    Eta =< Meta,
    ( M0 == libre -> Modo = libre ; Modo = se_libera(Espera) ).
candidata(I, TipoU, c(U, Eta, retiro(D), Ruta)) :-
    % Solo se piensa en retirar si nadie libre llega a tiempo.
    \+ candidata_sin_retiro(I, TipoU),
    incidente(I, _, P, _), meta_para(I, TipoU, Meta),
    unidad(U, TipoU),
    retirable(U, I, D),
    llegada_retiro(U, P, Eta, Ruta),
    Eta =< Meta.

candidata_sin_retiro(I, TipoU) :-
    incidente(I, _, P, _), meta_para(I, TipoU, Meta),
    unidad(U, TipoU), llegada(U, P, Eta, _, _, _), Eta =< Meta, !.

% Necesidades ordenadas: primero prioridad, luego orden de llegada.
necesidades(Incs, Ns) :-
    findall(n(P, Ll, I, T, K),
            ( member(I, Incs), incidente(I, _, _, P),
              llegada_inc(I, Ll), necesita(I, T, K0),
              aggregate_all(count, ( atiende(U, I), unidad(U, T), confiable(U) ), Ya),
              K is K0 - Ya, K > 0 ),
            N0),
    msort(N0, Ns).

% Una unidad asignada cuenta como cobertura solo si se sabe que llega o ya está ahí.
% Una unidad "en camino" sin reportes (no se sabe) NO cuenta: hace falta refuerzo.
confiable(U) :- estado_unidad(U, E), memberchk(E, [en_escena, trasladando]), !.
confiable(U) :- estado_llegada(U, llega, _), !.

llegada_inc(I, Ll) :- ( llegada_incidente(I, L0) -> Ll = L0 ; Ll = 0 ).

% reparto(Necesidades, Usadas, Asignaciones, Faltantes) — enumera por
% backtracking TODAS las formas de cubrir las necesidades sin repetir unidad.
% Cada hueco puede quedar sin cubrir; el costo decide después.
reparto([], _, [], []).
reparto([n(P, _, I, T, K)|R], Us, Asig, Faltan) :-
    elegir(K, I, T, Us, '', Elegidas, F),
    findall(U, member(a(_, _, U, _, _, _), Elegidas), Nuevas),
    append(Us, Nuevas, Us2),
    reparto(R, Us2, Asig0, Faltan0),
    append(Elegidas, Asig0, Asig),
    (   F =:= 0 -> Faltan = Faltan0
    ;   Faltan = [falta(I, T, F, P)|Faltan0] ).

% elegir(K, I, T, Usadas, Anterior, Elegidas, SinCubrir)
elegir(K, _, _, _, _, [], K).
elegir(K, I, T, Us, Ant, [a(I, T, U, Eta, Modo, Ruta)|R], F) :-
    K > 0,
    candidata(I, T, c(U, Eta, Modo, Ruta)),
    \+ memberchk(U, Us),
    U @> Ant,                       % evita repetir el mismo reparto en otro orden
    K1 is K - 1,
    elegir(K1, I, T, [U|Us], U, R, F).

% Costo lexicográfico: [necesidades sin cubrir (pesadas por prioridad),
%                       retiros, a quién se le retira, suma de llegadas].
costo(Asig, Faltan, [CF, NR, CR, SE]) :-
    aggregate_all(sum(W*F), ( member(falta(_, _, F, P), Faltan), peso_prioridad(P, W) ), CF),
    aggregate_all(count, member(a(_, _, _, _, retiro(_), _), Asig), NR),
    aggregate_all(sum(C), ( member(a(_, _, _, _, retiro(D), _), Asig), costo_retiro(D, C) ), CR),
    aggregate_all(sum(E), member(a(_, _, _, E, _, _), Asig), SE).

repartos_ordenados(Incs, Ordenados) :-
    necesidades(Incs, Ns),
    findall(C-r(A, F), ( reparto(Ns, [], A, F), costo(A, F, C) ), L0),
    sort(L0, Ordenados).

% ----------------------------------------------------------------------------
% decide(+Incidentes, -Despacho, -Explicacion)  — PREDICADO CENTRAL
%   Despacho = despacho(Completo, Asignaciones, Desplazados, SinCubrir)
%   Da primero el mejor reparto y, al pedir más (;), los demás válidos.
%   Si ninguno cubre todo, Completo = no y SinCubrir dice qué y por qué.
% ----------------------------------------------------------------------------
decide(Incs, despacho(Completo, A, Ds, Faltan), Explicacion) :-
    repartos_ordenados(Incs, Ls),
    Ls \== [],
    include(es_completo, Ls, Completos),
    (   Completos \== []
    ->  Completo = si, member(_-r(A, Faltan), Completos)
    ;   Completo = no,
        Ls = [[CF|_]-_|_],
        include(misma_falta(CF), Ls, Mejores),
        member(_-r(A, Faltan), Mejores)
    ),
    desplazados(A, Ds),
    explicar_despacho(despacho(Completo, A, Ds, Faltan), Explicacion).

decide_uno(Incs, D, E) :- once(decide(Incs, D, E)).

es_completo(_-r(_, [])).
misma_falta(CF, [CF2|_]-_) :- CF2 =:= CF.

desplazados(A, Ds) :-
    findall(desplazado(IncV, por(I, U)),
            member(a(I, _, U, _, retiro(desde(IncV, _, _)), _), A), Ds).

% Reparto "voraz": cada incidente, en orden de llegada, toma su unidad libre
% más rápida que llegue a tiempo. Es lo intuitivo... y puede fallar.
voraz(Incs, Asig, SinCubrir) :-
    findall(Ll-I, ( member(I, Incs), llegada_inc(I, Ll) ), P0),
    keysort(P0, P1), pairs_values(P1, Orden),
    voraz_(Orden, [], Asig, SinCubrir).

voraz_([], _, [], []).
voraz_([I|R], Us, Asig, Sin) :-
    findall(T-K, necesita(I, T, K), Necs),
    voraz_necs(Necs, I, Us, Us2, A1, S1),
    voraz_(R, Us2, A2, S2),
    append(A1, A2, Asig), append(S1, S2, Sin).

voraz_necs([], _, Us, Us, [], []).
voraz_necs([T-K|R], I, Us, UsF, Asig, Sin) :-
    findall(E-U, ( candidata(I, T, c(U, E, Modo, _)), Modo \= retiro(_), \+ memberchk(U, Us) ), Cs0),
    keysort(Cs0, Cs),
    length(Cs, NC), Toma is min(K, NC),
    length(Pref, Toma), append(Pref, _, Cs),
    findall(a(I, T, U, E), member(E-U, Pref), A1),
    pairs_values(Pref, Us1), append(Us, Us1, Us2),
    Falta is K - Toma,
    ( Falta > 0 -> S1 = [falta(I, T, Falta)] ; S1 = [] ),
    voraz_necs(R, I, Us2, UsF, A2, S2),
    append(A1, A2, Asig), append(S1, S2, Sin).

% ============================================================================
% 5. EXPLICACIÓN (pregunta "¿por qué no la otra?")
% ============================================================================

% por_que_no(U, I, Motivo): por qué la unidad U no es la que va a I.
por_que_no(U, I, Motivo) :-
    necesita(I, T, _), unidad(U, T),
    once(motivo_no(U, I, T, Motivo)).

motivo_no(U, _, _, fuera_de_servicio) :- estado_unidad(U, fuera_de_servicio).
motivo_no(U, I, T, es_la_elegida) :-
    decide_uno([I], despacho(_, A, _, _), _), memberchk(a(I, T, U, _, _, _), A).
motivo_no(U, I, _, ya_asignada(I, Llega)) :-
    atiende(U, I), ( estado_llegada(U, Llega, _) -> true ; Llega = en_escena ).
motivo_no(U, I, T, se_libera_tarde(Esp, Eta, Meta)) :-
    incidente(I, _, P, _), meta_para(I, T, Meta),
    llegada(U, P, Eta, _, Esp, se_libera), Eta > Meta.
motivo_no(U, I, _, M) :- no_retirable(U, I, M).
motivo_no(U, I, T, retirarla_cuesta_mas(D, U2, D2)) :-
    retirable(U, I, D),
    decide_uno([I], despacho(_, A, _, _), _),
    member(a(I, T, U2, _, retiro(D2), _), A), U2 \== U,
    costo_retiro(D, C), costo_retiro(D2, C2), C > C2.
motivo_no(U, I, T, no_se_retira_hay_libre(D, U2, Eta2)) :-
    retirable(U, I, D),
    decide_uno([I], despacho(_, A, _, _), _),
    member(a(I, T, U2, Eta2, M2, _), A), M2 \= retiro(_).
motivo_no(U, I, T, no_llega_a_tiempo(Eta, Meta, recta_km(Km))) :-
    incidente(I, _, P, _), meta_para(I, T, Meta),
    (   llegada(U, P, Eta, _, _, _) -> true ; llegada_retiro(U, P, Eta, _) ),
    Eta > Meta,
    ultima_posicion(U, PU, _), dist_recta(PU, P, Km).
motivo_no(U, I, T, otra_llega_antes(U2, Eta2, Eta, recta(Km, Km2))) :-
    decide_uno([I], despacho(_, A, _, _), _),
    member(a(I, T, U2, Eta2, _, _), A), U2 \== U,
    incidente(I, _, P, _),
    (   llegada(U, P, Eta, _, _, _) -> true ; llegada_retiro(U, P, Eta, _) ),
    Eta2 =< Eta,
    ultima_posicion(U, PU, _), dist_recta(PU, P, Km),
    ultima_posicion(U2, PU2, _), dist_recta(PU2, P, Km2).
motivo_no(_, _, _, no_hace_falta).

% ============================================================================
% 6. ¿QUÉ FALTA? (la pregunta al revés)
% ============================================================================

% que_falta(I, Cambio): qué tendría que cambiar para que I tenga sus unidades
% con unidades libres a tiempo, sin retirar a nadie.
que_falta(I, nada) :-
    incidente(I, _, _, _),
    forall(necesita(I, T, _), candidata_sin_retiro(I, T)), !.
que_falta(I, Cambio) :-
    necesita(I, T, _),
    \+ candidata_sin_retiro(I, T),
    cambio_para(I, T, Cambio).

% Que haya una unidad libre en alguno de los puntos desde donde se llega a tiempo.
cambio_para(I, T, unidad_libre_en(T, Puntos, Meta)) :-
    incidente(I, _, P, _), meta_para(I, T, Meta),
    findall(Q, ( coord(Q, _, _), ruta_mas_rapida(Q, P, _, S), S =< Meta ), Qs),
    sort(Qs, Puntos).
% Que una unidad que va trasladando se libere antes.
cambio_para(I, T, se_libere_antes(U, Segundos)) :-
    incidente(I, _, P, _), meta_para(I, T, Meta),
    unidad(U, T), estado_unidad(U, trasladando),
    llegada(U, P, Eta, _, _, _),
    Eta > Meta, Segundos is Eta - Meta.
% Que una unidad fuera de servicio vuelva (si desde ahí llegaría).
cambio_para(I, T, vuelva_a_servicio(U, Eta)) :-
    incidente(I, _, P, _), meta_para(I, T, Meta),
    unidad(U, T), estado_unidad(U, fuera_de_servicio),
    ultima_posicion(U, Q, _), ruta_mas_rapida(Q, P, _, Eta), Eta =< Meta.
% Que se despeje un tramo afectado.
cambio_para(I, T, se_despeje(A, B, U, Eta)) :-
    afectado(A, B, _),
    si_pasara(despejar(A, B), U-E,
              ( incidente(I, _, P, _), meta_para(I, T, Meta), unidad(U, T),
                llegada(U, P, E, _, _, _), E =< Meta ),
              Rs),
    Rs = [U-Eta|_].

% ============================================================================
% 7. HIPÓTESIS: "¿qué pasaría si…?" sin tocar el estado real
% ============================================================================

% si_pasara(+Cambio, ?Plantilla, :Meta, -Resultados)
si_pasara(Cambio, Plantilla, Meta, Resultados) :-
    setup_call_cleanup(
        aplicar(Cambio, Deshacer),
        findall(Plantilla, Meta, Resultados),
        call(Deshacer)).

aplicar(cerrar(A, B), retract(cerrado(A, B))) :-
    assertz(cerrado(A, B)).
aplicar(afectar(A, B, F), retract(afectado(A, B, F))) :-
    asserta(afectado(A, B, F)).
aplicar(despejar(A, B), forall(member(H, Hs), assertz(H))) :-
    findall(afectado(X, Y, F),
            ( afectado(X, Y, F), ( X-Y == A-B ; X-Y == B-A ) ), Hs),
    forall(member(H, Hs), retract(H)).
aplicar(fuera_de_servicio(U), ( retract(estado_unidad(U, fuera_de_servicio)),
                                assertz(estado_unidad(U, E0)) )) :-
    retract(estado_unidad(U, E0)),
    assertz(estado_unidad(U, fuera_de_servicio)).
aplicar(reaparece(U, P), retract(posicion(U, P, N))) :-
    ahora(N), assertz(posicion(U, P, N)).

% ============================================================================
% 8. SITUACIÓN 3 — ¿Estas llamadas son el mismo incidente?
% ============================================================================

dist_llamadas(L1, L2, Km) :-
    llamada_lugar(L1, X1, Y1), llamada_lugar(L2, X2, Y2),
    Km is round(sqrt((X1-X2)**2 + (Y1-Y2)**2) * 100) / 100.

% mismo_incidente(L1, L2, Resultado, Evidencia) — Resultado: si | no | no_se
mismo_incidente(L1, L2, R, ev(km(Km), seg(DT), tipo(T1, T2), vehiculos(V1, V2))) :-
    llamada(L1, _, S1, reporte(T1, V1, _)),
    llamada(L2, _, S2, reporte(T2, V2, _)),
    L1 \== L2,
    dist_llamadas(L1, L2, Km),
    DT is abs(S1 - S2),
    radio_mismo_km(RM), radio_distinto_km(RD),
    ventana_misma_s(VM), ventana_distinta_s(VD),
    (   ( T1 \== T2 ; Km > RD ; DT > VD )      -> R = no
    ;   Km =< RM, DT =< VM, V1 =:= V2          -> R = si
    ;   R = no_se
    ).

% Grupos: llamadas unidas por "si" (cierre transitivo).
grupos_llamadas(Gs) :-
    findall(L, llamada(L, _, _, _), Ls0), sort(Ls0, Ls),
    agrupar(Ls, Gs).

agrupar([], []).
agrupar([L|R], [G|Gs]) :-
    componente([L], [L], G0), sort(G0, G),
    subtract(R, G, R2),
    agrupar(R2, Gs).

componente([], Vistos, Vistos).
componente([X|Cola], Vistos, G) :-
    findall(Y, ( mismo_incidente(X, Y, si, _), \+ memberchk(Y, Vistos) ), Ys0),
    sort(Ys0, Ys),
    append(Vistos, Ys, V2), append(Cola, Ys, C2),
    componente(C2, V2, G).

% Llamada dudosa: ni unida ni descartada respecto de un grupo.
llamada_dudosa(L, G, Ev) :-
    grupos_llamadas(Gs),
    member([L], Gs),
    member(G, Gs), G = [_, _|_],
    member(M, G), mismo_incidente(L, M, no_se, Ev), !.

% El incidente que resulta de unir un grupo: toma prioridad y unidades de
% la información de TODAS sus llamadas.
incidente_de_grupo(G, incidente_unido(Tipo, Punto, Prioridad, Necesita, llamadas(N))) :-
    G = [L1|_], llamada(L1, Punto, _, reporte(Tipo, _, _)),
    length(G, N),
    aggregate_all(max(H), ( member(L, G), llamada(L, _, _, reporte(_, _, H)) ), MaxH),
    prioridad_por_lesionados(MaxH, Prioridad),
    unidades_por_reporte(Tipo, MaxH, Necesita).

prioridad_por_lesionados(H, 1) :- H >= 2, !.
prioridad_por_lesionados(1, 2) :- !.
prioridad_por_lesionados(_, 3).

unidades_por_reporte(accidente, H, [ambulancia-NA, patrulla-1]) :- !,
    NA is max(1, ceiling(H / 2)).
unidades_por_reporte(Tipo, _, Ns) :-
    findall(T-K, requiere(Tipo, T, K), Ns).

costo_error(fusionar_mal, "Si la llamada dudosa era un segundo accidente y la uno, ese accidente real se queda sin unidad.").
costo_error(no_fusionar,  "Si era el mismo choque y la trato como otro incidente, mando unidades que hacen falta en otra parte.").

% ¿Alcanzan las unidades libres si la dudosa fuera otro incidente?
alcanzan_para_dos(G, L, Resultado) :-
    incidente_de_grupo(G, incidente_unido(_, _, _, Ns, _)),
    llamada(L, _, _, reporte(Tipo, _, H)),
    unidades_por_reporte(Tipo, H, Ns2),
    append(Ns, Ns2, Todas),
    (   forall(member(T-_, Todas),
               ( aggregate_all(sum(K), member(T-K, Todas), Pide),
                 aggregate_all(count, ( unidad(U, T), libre(U) ), Hay),
                 Hay >= Pide ))
    ->  Resultado = si
    ;   Resultado = no
    ).

% ============================================================================
% 9. SITUACIÓN 4 — La unidad que dejó de contestar
% ============================================================================

% estado_llegada(U, Resultado, Evidencia) — llega | no_llega | no_se
estado_llegada(U, no_llega, falla(S)) :-
    evento(U, falla, S).
estado_llegada(U, no_llega, fuera_de_servicio) :-
    atiende(U, _), estado_unidad(U, fuera_de_servicio),
    \+ evento(U, falla, _).
estado_llegada(U, llega, reporte_reciente(P, Silencio, faltan(Eta))) :-
    estado_unidad(U, en_camino), \+ evento(U, falla, _),
    silencio(U, Silencio), umbral_silencio(Um), Silencio =< Um,
    ultima_posicion(U, P, _),
    once(( atiende(U, I), incidente(I, _, Dest, _) )),
    ruta_mas_rapida(P, Dest, _, Eta).
estado_llegada(U, no_se, sin_reporte(P, Silencio, umbral(Um))) :-
    estado_unidad(U, en_camino), \+ evento(U, falla, _),
    silencio(U, Silencio), umbral_silencio(Um), Silencio > Um,
    ultima_posicion(U, P, _).

% ¿El incidente sigue cubierto?
cubierto(I, si, U) :- atiende(U, I), estado_llegada(U, llega, _), !.
cubierto(I, si, U) :- atiende(U, I), estado_unidad(U, en_escena), !.
cubierto(I, no_se, U) :- atiende(U, I), estado_llegada(U, no_se, _), !.
cubierto(I, no, ninguna) :- incidente(I, _, _, _).

% Refuerzo: otra unidad para I que no sea la que ya va; dice qué descubre.
refuerzo(I, U, Eta, Modo, Descubre) :-
    necesita(I, T, _), incidente(I, _, P, _), meta_para(I, T, Meta),
    findall(C-r(U0, E0, M0),
            ( unidad(U0, T), \+ atiende(U0, I),
              (   llegada(U0, P, E0, _, _, M1), M0 = M1, C = 0
              ;   retirable(U0, I, D), llegada_retiro(U0, P, E0, _), M0 = retiro(D),
                  costo_retiro(D, C0), C is 100 + C0 ),
              E0 =< Meta ),
            Cs0),
    keysort(Cs0, [_-r(U, Eta, Modo)|_]),
    descubre(U, Modo, Descubre).

descubre(_, retiro(desde(IncV, _, _)), incidente(IncV)) :- !.
descubre(U, _, zona_sin(T, Z)) :-
    unidad(U, T), ultima_posicion(U, P, _), zona(P, Z),
    \+ ( libre(U2), U2 \== U, unidad(U2, T), ultima_posicion(U2, P2, _), zona(P2, Z) ), !.
descubre(_, _, nada).

% La consulta inversa: qué tendría que pasar para pedir refuerzo.
pedir_refuerzo_si(I, ya(sin_reporte(U, Silencio))) :-
    cubierto(I, no_se, U), silencio(U, Silencio), !.
pedir_refuerzo_si(I, si_calla_mas_de(U, Faltan)) :-
    cubierto(I, si, U), estado_unidad(U, en_camino),
    silencio(U, S), umbral_silencio(Um), Faltan is Um - S + 1, !.
pedir_refuerzo_si(I, si_falla(U)) :-
    cubierto(I, si, U).

% ============================================================================
% 10. situacion/3 — situaciones deducidas, consultables en cualquier dirección
% ============================================================================

situacion(L, misma_que(L2), Ev)   :- mismo_incidente(L, L2, si, Ev).
situacion(L, dudosa_con(G), Ev)   :- llamada_dudosa(L, G, Ev).
situacion(U, sin_contacto, Ev)    :- estado_llegada(U, no_se, Ev).
situacion(U, retirable(I), Ev)    :- retirable(U, I, Ev).
situacion(I, desprotegido, Ev)    :-
    incidente(I, _, _, 1),
    (   \+ atiende(_, I) -> Ev = sin_unidad
    ;   cubierto(I, no_se, U) -> Ev = unidad_sin_contacto(U)
    ).
situacion(I, por_atender, faltan(Fs)) :-
    por_atender(I),
    findall(T-F, ( necesita(I, T, K),
                   aggregate_all(count, ( atiende(U, I), unidad(U, T) ), N),
                   F is K - N, F > 0 ), Fs).

% Cualquier condición con tres resultados.
cumple(llega(U), R)              :- estado_llegada(U, R, _).
cumple(cubierto(I), R)           :- cubierto(I, R, _).
cumple(mismo_incidente(A, B), R) :- mismo_incidente(A, B, R, _).

% ============================================================================
% 11. LAS CINCO PREGUNTAS de "Por qué no basta un script": cinco consultas
%     sobre las MISMAS reglas, sin un predicado nuevo por pregunta.
% ============================================================================
pregunta(1, decision,     "¿Qué unidad mando al incidente?",                   Inc, R) :-
    decide_uno([Inc], R, _).
pregunta(2, explicacion,  "¿Por qué no la ambulancia que está más cerca?",     Inc, U-M) :-
    incidente(Inc, _, P, _),
    aggregate_all(min(Km, U0), ( unidad(U0, ambulancia), ultima_posicion(U0, Q, _), dist_recta(Q, P, Km) ), min(_, U)),
    por_que_no(U, Inc, M).
pregunta(3, todas,        "¿Qué repartos cubren todos los incidentes?",        Incs, Rs) :-
    findall(A, decide(Incs, despacho(si, A, _, _), _), Rs).
pregunta(4, al_reves,     "¿Qué falta para que el incidente tenga ambulancia sin retirar a nadie?", Inc, Cs) :-
    findall(C, que_falta(Inc, C), Cs).
pregunta(5, hipotesis,    "¿Qué pasaría si se cierra un tramo?",               cerrar(A, B)-Inc, antes(D0)-despues(D1)) :-
    decide_uno([Inc], D0, _),
    si_pasara(cerrar(A, B), D, decide_uno([Inc], D, _), [D1]).
