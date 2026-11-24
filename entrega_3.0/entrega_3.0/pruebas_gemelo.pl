:- encoding(utf8).
% Pruebas plunit del gemelo 911.   Correr:  swipl -g run_tests -t halt pruebas_gemelo.pl
:- use_module(library(plunit)).
:- ensure_loaded(gemelo_911).

:- begin_tests(gemelo_911).

% Situación 1: sin ambulancia libre a tiempo, se retira la de un P3, no la que traslada.
test(retira_la_del_incidente_menos_urgente) :-
    decision(inc5, amb1, retirar_de(inc1), 3).
test(no_retira_ambulancia_trasladando, [fail]) :-
    retirable(amb3, inc5).

% Situación 2: la ruta más rápida cruza por el puente norte, no por el sur.
test(ruta_por_el_puente_norte) :-
    ruta_mas_rapida(playas, centro, Camino, 12),
    memberchk(puente_norte, Camino).

% Situación 4: la patrulla sin reportar es "no sé", y su incidente P1 queda en riesgo.
test(silencio_es_no_se, [nondet]) :-
    situacion_llegada(pat1, no_se).
test(incidente_en_riesgo_por_silencio) :-
    en_riesgo(inc3, unidad_sin_contacto(pat1)).

% Hipótesis: cerrar un tramo cambia la llegada y la red queda igual después.
test(hipotesis_no_modifica_la_red) :-
    hipotesis_cierre(canon_oeste, puente_norte, inc5, amb1, 13),
    tramo(canon_oeste, puente_norte, 3).

:- end_tests(gemelo_911).
