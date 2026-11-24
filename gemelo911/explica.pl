:- encoding(utf8).
% ============================================================================
%  explica.pl — Convierte las deducciones en frases. La interfaz solo muestra
%  estas frases: ninguna regla ni umbral vive en la página.
% ============================================================================

min_seg(S, Txt) :-
    M is S // 60, R is S mod 60,
    format(string(Txt), "~d min ~|~`0t~d~2+ s", [M, R]).

ruta_txt(Ruta, Txt) :-
    atomic_list_concat(Ruta, ' → ', A), atom_string(A, Txt).

% explicar_despacho(+Despacho, -ListaDeFrases)
explicar_despacho(despacho(Completo, A, Ds, Faltan), Frases) :-
    findall(F, ( member(X, A), frase_asignacion(X, F) ), F1),
    findall(F, ( member(D, Ds), frase_desplazado(D, F) ), F2),
    findall(F, ( member(X, Faltan), frase_falta(X, F) ), F3),
    (   Completo == si, A == []
    ->  F0 = ["No hace falta despachar: los incidentes ya tienen unidades que se sabe que llegan o ya están en escena."]
    ;   Completo == si
    ->  F0 = ["Reparto completo: cada incidente tiene sus unidades y ninguna unidad se usa dos veces."]
    ;   F0 = ["No existe un reparto que cubra todo. Este es el mejor posible: cubre lo más que se puede y pesa primero la prioridad 1."]
    ),
    append([F0, F1, F2, F3], Frases).

frase_asignacion(a(I, T, U, Eta, Modo, Ruta), F) :-
    incidente(I, _, P, Pr), meta_para(I, T, Meta),
    min_seg(Eta, TE), min_seg(Meta, TM), ruta_txt(Ruta, TR),
    obstaculos(Ruta, Obs),
    (   Obs == [] -> TO = "" ; format(string(TO), " (cruza: ~w)", [Obs]) ),
    modo_txt(Modo, TMd),
    ultima_posicion(U, PU, _), dist_recta(PU, P, Km),
    format(string(F),
      "~w (~w) → ~w [P~w]: llega en ~w por ~w~w; meta ~w. ~w Está a ~w km en línea recta.",
      [U, T, I, Pr, TE, TR, TO, TM, TMd, Km]).

modo_txt(libre, "Estaba libre.").
modo_txt(se_libera(E), T) :- min_seg(E, TE), format(string(T), "Va trasladando y queda libre en ~w; se cuenta esa espera.", [TE]).
modo_txt(retiro(desde(IncV, PV, E)), T) :-
    format(string(T), "Se RETIRA de ~w (prioridad ~w, estado ~w) porque ninguna unidad libre llega a tiempo y ese incidente es menos urgente.", [IncV, PV, E]).

frase_desplazado(desplazado(IncV, por(I, U)), F) :-
    format(string(F), "~w queda PENDIENTE (no se pierde): se le quitó ~w para atender ~w. Vuelve a la cola con su prioridad original.", [IncV, U, I]).

frase_falta(falta(I, T, N, P), F) :-
    incidente(I, _, Pt, _), meta_para(I, T, Meta), min_seg(Meta, TM),
    (   aggregate_all(min(E, U), ( unidad(U, T), \+ estado_unidad(U, fuera_de_servicio),
                                    ( llegada(U, Pt, E, _, _, _) ; llegada_retiro(U, Pt, E, _) ) ), min(EM, UM))
    ->  min_seg(EM, TEM),
        format(string(Mejor), "la más rápida sería ~w en ~w", [UM, TEM])
    ;   Mejor = "no hay ruta"
    ),
    format(string(F), "SIN CUBRIR: ~w [P~w] necesita ~w ~w más. Ninguna disponible llega en ~w (~w), o las que llegaban se usaron en incidentes más urgentes.",
           [I, P, N, T, TM, Mejor]).

% Motivo de "por qué no esta unidad"
motivo_txt(fuera_de_servicio, "está fuera de servicio").
motivo_txt(lleva_paciente(I), T) :- format(string(T), "va trasladando a un paciente de ~w: no se abandona a quien ya va en la ambulancia", [I]).
motivo_txt(prioridad_no_menor(I, PV, PN), T) :- format(string(T), "atiende ~w de prioridad ~w, que no es menos urgente que la nueva (~w)", [I, PV, PN]).
motivo_txt(no_llega_a_tiempo(E, M, recta_km(Km)), T) :- min_seg(E, TE), min_seg(M, TM),
    format(string(T), "aunque está a ~w km en línea recta, por calles tarda ~w y la meta es ~w", [Km, TE, TM]).
motivo_txt(otra_llega_antes(U2, E2, E, recta(Km, Km2)), T) :- min_seg(E2, T2), min_seg(E, T1),
    format(string(T), "~w llega antes (~w contra ~w), aunque en línea recta esta está a ~w km y ~w a ~w km", [U2, T2, T1, Km, U2, Km2]).
motivo_txt(se_libera_tarde(Esp, E, M), T) :- min_seg(Esp, TS), min_seg(E, TE), min_seg(M, TM),
    format(string(T), "va trasladando; queda libre en ~w y, contando esa espera, llegaría en ~w (meta ~w)", [TS, TE, TM]).
motivo_txt(es_la_elegida, "es la unidad elegida").
motivo_txt(retirarla_cuesta_mas(desde(I, P, E), U2, desde(I2, P2, E2)), T) :-
    format(string(T), "aunque llegaría antes, está ~w en ~w (prioridad ~w); se prefiere quitar a ~w, que está ~w en ~w (prioridad ~w, menos urgente). Lo intuitivo sería retirar la más cercana, pero dejaría peor atendido un incidente más grave", [E, I, P, U2, E2, I2, P2]).
motivo_txt(ya_asignada(I, L), T) :- format(string(T), "ya está asignada a ~w (¿llega?: ~w)", [I, L]).
motivo_txt(no_se_retira_hay_libre(desde(I, P, _), U2, E2), T) :- min_seg(E2, TE),
    format(string(T), "llegaría antes, pero está atendiendo ~w (prioridad ~w) y ~w está libre y llega a tiempo (~w): no se retira a nadie si no hace falta", [I, P, U2, TE]).
motivo_txt(no_hace_falta, "no hace falta otra unidad de su tipo").

% Qué falta
cambio_txt(nada, "Nada, si se viera solo: tiene unidades libres que llegan a tiempo. Con varios incidentes a la vez, el reto es repartirlas sin repetir ninguna.").
cambio_txt(unidad_libre_en(T, Ps, M), F) :- min_seg(M, TM),
    format(string(F), "Que haya una ~w libre en alguno de estos puntos (desde ahí se llega en ≤ ~w): ~w.", [T, TM, Ps]).
cambio_txt(se_libere_antes(U, S), F) :- min_seg(S, TS),
    format(string(F), "Que ~w se libere ~w antes.", [U, TS]).
cambio_txt(vuelva_a_servicio(U, E), F) :- min_seg(E, TE),
    format(string(F), "Que ~w vuelva a servicio: desde donde está llegaría en ~w.", [U, TE]).
cambio_txt(se_despeje(A, B, U, E), F) :- min_seg(E, TE),
    format(string(F), "Que se despeje el tramo ~w–~w: entonces ~w llegaría en ~w.", [A, B, U, TE]).

% Llegada de unidades sin contacto
llegada_txt(U, llega, reporte_reciente(P, S, faltan(E)), F) :- min_seg(E, TE), min_seg(S, TS),
    format(string(F), "~w LLEGA: reportó en ~w hace ~w; le faltan ~w.", [U, P, TS, TE]).
llegada_txt(U, no_se, sin_reporte(P, S, umbral(Um)), F) :- min_seg(S, TS), min_seg(Um, TU),
    format(string(F), "NO SE SABE si ~w avanza: su último reporte fue en ~w hace ~w (umbral ~w). El sistema dice «en camino», pero eso es lo que se ordenó, no lo que se sabe.", [U, P, TS, TU]).
llegada_txt(U, no_llega, Ev, F) :-
    format(string(F), "~w NO LLEGA: ~w.", [U, Ev]).
