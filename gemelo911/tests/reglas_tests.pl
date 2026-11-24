:- encoding(utf8).
% Pruebas plunit del gemelo 911.
%   swipl -g run_tests -t halt tests/reglas_tests.pl
:- use_module(library(plunit)).
:- ensure_loaded('../hechos').
:- ensure_loaded('../escenarios').
:- ensure_loaded('../reglas').
:- ensure_loaded('../explica').

% ---------------------------------------------------------------- Situación 1
:- begin_tests(s1_retiro, [setup(cargar_escenario(s1_retiro))]).

test(retira_la_del_incidente_menos_urgente_no_la_mas_cercana, [nondet]) :-
    decide_uno([inc_paro], despacho(si, [a(inc_paro, ambulancia, U, _, retiro(desde(V, 3, _)), _)], _, []), _),
    U == amb1, V == inc_leve.
test(la_mas_cercana_era_otra, [nondet]) :-
    llegada_retiro(amb2, puente_norte, T2, _), llegada_retiro(amb1, puente_norte, T1, _),
    T2 < T1.
test(no_retira_a_quien_traslada_paciente, [nondet]) :-
    \+ retirable(amb3, inc_paro, _),
    no_retirable(amb3, inc_paro, lleva_paciente(inc_caida)).
test(el_desplazado_queda_pendiente, [nondet]) :-
    decide_uno([inc_paro], despacho(_, _, [desplazado(inc_leve, por(inc_paro, amb1))], _), E),
    once(( member(F, E), sub_string(F, _, _, _, "PENDIENTE") )).
test(con_prioridad_igual_o_menor_no_retira_a_nadie, [nondet]) :-
    \+ retirable(_, inc_leve, _).
test(que_falta_para_no_retirar, [nondet]) :-
    que_falta(inc_paro, se_libere_antes(amb3, _)).

:- end_tests(s1_retiro).

% ---------------------------------------------------------------- Situación 2
:- begin_tests(s2_cercania, [setup(cargar_escenario(s2_cercania))]).

test(gana_la_de_menor_tiempo_no_la_de_menor_distancia, [nondet]) :-
    decide_uno([inc_s2], despacho(si, [a(_, _, U, 180, _, Ruta)], _, _), _),
    U == amb2, Ruta == [centro, canon_este],
    dist_recta(canon_oeste, canon_este, K1), dist_recta(centro, canon_este, K2), K1 < K2.
test(cuenta_cuando_se_libera_la_ocupada, [nondet]) :-
    llegada(amb3, canon_este, 540, _, 60, se_libera).
test(tramo_afectado_por_garita_alarga_el_viaje, [nondet]) :-
    conecta(zona_rio, garita, 540).
test(si_cierran_un_tramo_la_respuesta_cambia, [nondet]) :-
    si_pasara(cerrar(canon_este, centro), U, decide_uno([inc_s2], despacho(_, [a(_, _, U, _, _, _)], _, _), _), [amb1]),
    \+ cerrado(_, _).

:- end_tests(s2_cercania).

% ---------------------------------------------------------------- Situación 3
:- begin_tests(s3_llamadas, [setup(cargar_escenario(s3_llamadas))]).

test(cinco_llamadas_son_un_solo_choque, [nondet]) :-
    grupos_llamadas(Gs), memberchk([c1, c2, c3, c4, c5], Gs).
test(la_llamada_de_la_esquina_es_dudosa_no_unida_ni_descartada, [nondet]) :-
    mismo_incidente(c6, c1, no_se, _),
    llamada_dudosa(c6, [c1, c2, c3, c4, c5], _).
test(otro_tipo_de_hecho_no_es_el_mismo, [nondet]) :-
    mismo_incidente(c7, c1, no, _).
test(el_incidente_unido_toma_prioridad_y_unidades_de_todas, [nondet]) :-
    grupos_llamadas([G|_]),
    incidente_de_grupo(G, incidente_unido(accidente, centro, 1, [ambulancia-2, patrulla-1], llamadas(5))).
test(no_alcanzan_unidades_para_dos_accidentes, [nondet]) :-
    alcanzan_para_dos([c1, c2, c3, c4, c5], c6, no).

:- end_tests(s3_llamadas).

% ---------------------------------------------------------------- Situación 4
:- begin_tests(s4_sin_contacto, [setup(cargar_escenario(s4_sin_contacto))]).

test(silencio_no_es_llegada_ni_perdida, [nondet]) :-
    estado_llegada(amb1, no_se, sin_reporte(canon_oeste, 600, _)),
    \+ estado_llegada(amb1, llega, _), \+ estado_llegada(amb1, no_llega, _).
test(la_que_si_reporta_llega, [nondet]) :-
    estado_llegada(pat1, llega, _).
test(incidente_p1_queda_desprotegido, [nondet]) :-
    situacion(inc_p1, desprotegido, unidad_sin_contacto(amb1)).
test(refuerzo_libre_y_que_descubre, [nondet]) :-
    refuerzo(inc_p1, amb2, 300, libre, zona_sin(ambulancia, centro)).
test(si_reaparece_la_respuesta_se_corrige, [nondet]) :-
    si_pasara(reaparece(amb1, puente_norte), R, estado_llegada(amb1, R, _), [llega]),
    estado_llegada(amb1, no_se, _).
test(si_falla_no_llega, [cleanup(retractall(user:evento(amb1, falla, _)))]) :-
    assertz(user:evento(amb1, falla, 1500)),
    once(estado_llegada(amb1, R, _)),
    R == no_llega.

test(una_unidad_que_no_se_sabe_si_llega_no_cuenta_como_cobertura, [nondet]) :-
    decide_uno([inc_p1], despacho(si, [a(inc_p1, ambulancia, amb2, _, libre, _)], [], []), _).
test(si_reaparece_ya_no_hace_falta_refuerzo, [nondet]) :-
    si_pasara(reaparece(amb1, puente_norte), A, decide_uno([inc_p1], despacho(_, A, _, _), _), [[]]).

:- end_tests(s4_sin_contacto).

% ---------------------------------------------------------------- Situación 5
:- begin_tests(s5_sismo, [setup(cargar_escenario(s5_sismo))]).

incs([inc_herido, inc_fuego, inc_atrapados]).

test(el_voraz_deja_sin_cubrir_a_los_atrapados, [nondet]) :-
    incs(I), voraz(I, _, [falta(inc_atrapados, ambulancia, 1)]).
test(el_gemelo_encuentra_un_reparto_completo, [nondet]) :-
    incs(I), decide_uno(I, despacho(si, A, [], []), _),
    memberchk(a(inc_atrapados, ambulancia, amb1, _, _, _), A).
test(ninguna_unidad_se_usa_dos_veces, [nondet]) :-
    incs(I), forall(decide(I, despacho(_, A, _, _), _),
                    ( findall(U, member(a(_, _, U, _, _, _), A), Us), sort(Us, S), length(Us, N), length(S, N) )).
test(da_los_demas_repartos_validos, [nondet]) :-
    incs(I), findall(A, decide(I, despacho(si, A, _, _), _), Rs), length(Rs, 4).
test(sin_reparto_completo_dice_que_falta_y_por_que, [nondet]) :-
    incs(I),
    si_pasara(fuera_de_servicio(amb1), D-E, decide_uno(I, D, E), [despacho(no, _, _, F)-E1]),
    F == [falta(inc_atrapados, ambulancia, 1, 1)],
    once(( member(X, E1), sub_string(X, _, _, _, "SIN CUBRIR") )).

:- end_tests(s5_sismo).

% ---------------------------------------------- Las cinco preguntas (mismas reglas)
:- begin_tests(cinco_preguntas).

test(decision, [nondet]) :- cargar_escenario(s2_cercania), pregunta(1, _, _, inc_s2, despacho(si, [a(_, _, amb2, _, _, _)], _, _)).
test(explicacion, [nondet]) :- cargar_escenario(s2_cercania), pregunta(2, _, _, inc_s2, amb1-otra_llega_antes(amb2, _, _, _)).
test(todas, [nondet]) :- cargar_escenario(s5_sismo), pregunta(3, _, _, [inc_herido, inc_fuego, inc_atrapados], Rs), length(Rs, 4).
test(al_reves, [nondet]) :- cargar_escenario(s1_retiro), pregunta(4, _, _, inc_paro, Cs), memberchk(unidad_libre_en(ambulancia, _, 480), Cs).
test(hipotesis, [nondet]) :- cargar_escenario(s2_cercania),
    pregunta(5, _, _, cerrar(canon_este, centro)-inc_s2,
             antes(despacho(_, [a(_, _, amb2, _, _, _)], _, _))-despues(despacho(_, [a(_, _, amb1, _, _, _)], _, _))).

:- end_tests(cinco_preguntas).
