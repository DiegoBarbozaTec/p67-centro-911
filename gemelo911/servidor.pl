:- encoding(utf8).
% ============================================================================
%  servidor.pl — Servidor web del gemelo 911, 100 % Prolog.
%  La página solo PREGUNTA a estas rutas; todas las decisiones están en reglas.pl.
%  Python (matplotlib) solo dibuja, llamado DESDE Prolog con Janus.
%
%  Uso:  swipl servidor.pl          → http://localhost:8082/
%        swipl servidor.pl 9000     → otro puerto
% ============================================================================

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(yall)).

:- ensure_loaded(hechos).
:- ensure_loaded(escenarios).
:- ensure_loaded(reglas).
:- ensure_loaded(explica).

:- initialization(main, main).

% ---------------------------------------------------------------- Janus
:- dynamic hay_janus/0.
:- prolog_load_context(directory, Dir), asserta(user:dir_gemelo(Dir)).
:- (   catch(use_module(library(janus)), _, fail)
   ->  dir_gemelo(D), py_add_lib_dir(D), assertz(hay_janus)
   ;   print_message(warning, format("Janus no disponible: el gemelo funciona, sin gráficas de Python", []))
   ).

% ---------------------------------------------------------------- rutas
:- http_handler(root(.),                 inicio,          []).
:- http_handler(root(api/escenarios),    api_escenarios,  []).
:- http_handler(root(api/escenario),     api_escenario,   []).
:- http_handler(root(api/estado),        api_estado,      []).
:- http_handler(root(api/despacho),      api_despacho,    []).
:- http_handler(root(api/llamadas),      api_llamadas,    []).
:- http_handler(root(api/sin_contacto),  api_sin_contacto,[]).
:- http_handler(root(api/hipotesis),     api_hipotesis,   []).
:- http_handler(root(api/preguntas),     api_preguntas,   []).
:- http_handler(root(grafica/mapa),      g_mapa,          []).
:- http_handler(root(grafica/llegadas),  g_llegadas,      []).

main(Argv) :-
    (   Argv = [A|_], atom_number(A, Puerto) -> true ; Puerto = 8082 ),
    cargar_escenario(s1_retiro),
    http_server(http_dispatch, [port(Puerto)]),
    format("Gemelo 911 en http://localhost:~w/~n", [Puerto]),
    thread_get_message(_).

inicio(Peticion) :-
    dir_gemelo(D), atom_concat(D, '/web/index.html', F),
    http_reply_file(F, [unsafe(true)], Peticion).

% Todas las consultas se hacen bajo un candado: el estado es uno solo.
seguro(Meta) :- with_mutex(gemelo, Meta).

% ---------------------------------------------------------------- utilidades
t(X, S) :- ( string(X) -> S = X ; format(string(S), "~w", [X]) ).

% Incidentes en foco por escenario (lo que la interfaz muestra primero).
foco(s1_retiro,       [inc_paro]).
foco(s2_cercania,     [inc_s2]).
foco(s3_llamadas,     []).
foco(s4_sin_contacto, [inc_p1]).
foco(s5_sismo,        [inc_herido, inc_fuego, inc_atrapados]).

% Hipótesis sugerida por escenario.
hipotesis_sugerida(s1_retiro,       cerrar(canon_oeste, puente_norte)).
hipotesis_sugerida(s2_cercania,     cerrar(canon_este, centro)).
hipotesis_sugerida(s4_sin_contacto, reaparece(amb1, puente_norte)).
hipotesis_sugerida(s5_sismo,        fuera_de_servicio(amb1)).

incidentes_pedidos(Peticion, Incs) :-
    http_parameters(Peticion, [inc(Txt, [optional(true)])]),
    (   nonvar(Txt), Txt \== ''
    ->  split_string(Txt, ",", " ", Ps), maplist([S, A]>>atom_string(A, S), Ps, Incs)
    ;   escenario_activo(E), foco(E, Incs)
    ).

% ---------------------------------------------------------------- escenarios
api_escenarios(_) :-
    seguro(( escenario_activo(Act),
             findall(_{id:I, titulo:T, descripcion:D, activo:B},
                     ( escenario(I, T, D, _), ( I == Act -> B = true ; B = false ) ), L) )),
    reply_json_dict(L).

api_escenario(Peticion) :-
    http_parameters(Peticion, [nombre(N, [atom])]),
    (   escenario(N, _, _, _)
    ->  seguro(cargar_escenario(N)), api_estado(Peticion)
    ;   reply_json_dict(_{error:"escenario desconocido"}, [status(404)])
    ).

% ---------------------------------------------------------------- estado
api_estado(_) :- seguro(estado_json(J)), reply_json_dict(J).

estado_json(_{escenario:E, titulo:T, descripcion:D, ahora:N, janus:J,
              unidades:Us, incidentes:Is, foco:F, hipotesis:H}) :-
    escenario_activo(E), escenario(E, T, D, _), ahora(N), foco(E, F),
    ( hay_janus -> J = true ; J = false ),
    ( hipotesis_sugerida(E, H0) -> hipotesis_dict(H0, H) ; H = null ),
    findall(U, unidad_json(U), Us),
    findall(I, incidente_json(I), Is).

hipotesis_dict(cerrar(A, B), _{cambio:cerrar, a:A, b:B, texto:Tx}) :-
    format(string(Tx), "¿Y si se cierra el tramo ~w–~w?", [A, B]).
hipotesis_dict(reaparece(U, P), _{cambio:reaparece, unidad:U, punto:P, texto:Tx}) :-
    format(string(Tx), "¿Y si ~w reaparece reportando desde ~w?", [U, P]).
hipotesis_dict(fuera_de_servicio(U), _{cambio:fuera_de_servicio, unidad:U, texto:Tx}) :-
    format(string(Tx), "¿Y si ~w queda fuera de servicio?", [U]).

unidad_json(_{id:U, tipo:T, estado:E, punto:P, zona:Z, ultimo_reporte:S, silencio:Si,
              incidente:Inc, llegada:Ll}) :-
    unidad(U, T), estado_unidad(U, E),
    ultima_posicion(U, P, S), zona(P, Z), silencio(U, Si),
    ( atiende(U, I0) -> Inc = I0 ; Inc = null ),
    (   estado_llegada(U, R, Ev) -> llegada_txt(U, R, Ev, Tx), Ll = _{resultado:R, texto:Tx}
    ;   Ll = null ).

incidente_json(_{id:I, tipo:T, punto:P, zona:Z, prioridad:Pr, llego:Ll,
                 unidades:Us, necesita:Ns, situaciones:Ss}) :-
    incidente(I, T, P, Pr), zona(P, Z), llegada_inc(I, Ll),
    findall(U, atiende(U, I), Us),
    findall(_{tipo:Tu, cantidad:K}, necesita(I, Tu, K), Ns),
    findall(S, ( situacion(I, S0, _), t(S0, S) ), Ss).

% ---------------------------------------------------------------- despacho
api_despacho(Peticion) :-
    incidentes_pedidos(Peticion, Incs),
    seguro(despacho_json(Incs, J)),
    reply_json_dict(J).

despacho_json([], _{incidentes:[], soluciones:[], voraz:null, por_que_no:[], que_falta:[]}) :- !.
despacho_json(Incs, _{incidentes:Incs, soluciones:Sols, total_completos:NC, voraz:V,
                      por_que_no:PQ, que_falta:QF}) :-
    findall(S, ( limit(6, decide(Incs, D, E)), solucion_json(D, E, S) ), Sols),
    aggregate_all(count, decide(Incs, despacho(si, _, _, _), _), NC),
    voraz_json(Incs, V),
    (   Incs = [I1]
    ->  findall(_{unidad:U, incidente:I1, texto:Tx},
                ( necesita(I1, T, _), unidad(U, T),
                  por_que_no(U, I1, M), M \== es_la_elegida, motivo_txt(M, Tx) ), PQ0),
        sort(PQ0, PQ)
    ;   PQ = [_{unidad:"Reparto conjunto", incidente:"todos",
                texto:"Con varios incidentes, cada unidad se explica dentro del reparto: ninguna se repite y la prioridad 1 se cubre primero. Compara el mejor reparto con el voraz."}]
    ),
    findall(_{incidente:I, texto:Tx},
            ( member(I, Incs), que_falta(I, C), cambio_txt(C, Tx) ), QF).

solucion_json(despacho(C, A, Ds, F), E,
              _{completo:C, asignaciones:As, desplazados:DJ, sin_cubrir:FJ, explicacion:E}) :-
    findall(_{incidente:I, tipo:T, unidad:U, eta:Eta, modo:M, ruta:R},
            ( member(a(I, T, U, Eta, M0, R), A), t(M0, M) ), As),
    findall(_{incidente:IV, por:I, unidad:U}, member(desplazado(IV, por(I, U)), Ds), DJ),
    findall(_{incidente:I, tipo:T, faltan:N}, member(falta(I, T, N, _), F), FJ).

voraz_json(Incs, _{asignaciones:As, sin_cubrir:Sin, texto:Tx}) :-
    voraz(Incs, A, S),
    findall(_{incidente:I, tipo:T, unidad:U, eta:E}, member(a(I, T, U, E), A), As),
    findall(_{incidente:I, tipo:T, faltan:N}, member(falta(I, T, N), S), Sin),
    (   S == []
    ->  Tx = "El reparto voraz (cada incidente toma la unidad más rápida, en orden de llegada) también cubre todo aquí."
    ;   Tx = "El reparto voraz (cada incidente toma la unidad más rápida, en orden de llegada) deja necesidades sin cubrir que otro reparto sí cubre."
    ).

% ---------------------------------------------------------------- llamadas
api_llamadas(_) :- seguro(llamadas_json(J)), reply_json_dict(J).

llamadas_json(_{llamadas:Ls, grupos:Gs, dudosas:Ds, costos:Cs}) :-
    findall(_{id:L, punto:P, segundo:S, tipo:T, vehiculos:V, lesionados:H},
            llamada(L, P, S, reporte(T, V, H)), Ls),
    grupos_llamadas(G0),
    findall(_{llamadas:G, incidente:IJ},
            ( member(G, G0), G = [_, _|_],
              incidente_de_grupo(G, incidente_unido(T, P, Pr, Ns, llamadas(N))),
              findall(_{tipo:Tu, cantidad:K}, member(Tu-K, Ns), NJ),
              IJ = _{tipo:T, punto:P, prioridad:Pr, necesita:NJ, llamadas:N} ),
            Gs),
    findall(_{llamada:L, grupo:G, evidencia:EvT, alcanzan_para_dos:A, texto:Tx},
            ( llamada_dudosa(L, G, Ev), t(Ev, EvT), alcanzan_para_dos(G, L, A),
              Ev = ev(km(Km), seg(DT), _, vehiculos(V1, V2)),
              format(string(Tx), "~w: NO SE SABE si es el mismo choque. Está a ~w km y ~w s del grupo (umbral de unión: 0.3 km y 600 s) y reporta ~w vehículos contra ~w. Queda marcada, ni unida ni descartada.",
                     [L, Km, DT, V1, V2]) ),
            Ds),
    findall(_{error:K, texto:Tx}, costo_error(K, Tx), Cs).

% ---------------------------------------------------------------- sin contacto
api_sin_contacto(_) :- seguro(sin_contacto_json(J)), reply_json_dict(J).

sin_contacto_json(L) :-
    findall(_{unidad:U, incidente:I, resultado:R, texto:Tx, refuerzo:RJ, pedir_refuerzo:PJ},
            ( estado_llegada(U, R, Ev), llegada_txt(U, R, Ev, Tx),
              once(atiende(U, I)),
              (   refuerzo(I, U2, Eta, M, Desc)
              ->  min_seg(Eta, TE), t(M, MT), t(Desc, DT),
                  format(string(RT), "Refuerzo posible: ~w, llega en ~w (~w). Descubre: ~w.", [U2, TE, MT, DT]),
                  RJ = _{unidad:U2, eta:Eta, modo:MT, descubre:DT, texto:RT}
              ;   RJ = null ),
              (   once(pedir_refuerzo_si(I, Q)) -> t(Q, PJ) ; PJ = null ) ),
            L).

% ---------------------------------------------------------------- hipótesis
api_hipotesis(Peticion) :-
    http_parameters(Peticion, [cambio(C, [atom]),
                               a(A, [atom, optional(true)]), b(B, [atom, optional(true)]),
                               unidad(U, [atom, optional(true)]), punto(P, [atom, optional(true)])]),
    (   C == cerrar             -> Cambio = cerrar(A, B)
    ;   C == reaparece          -> Cambio = reaparece(U, P)
    ;   C == fuera_de_servicio  -> Cambio = fuera_de_servicio(U)
    ),
    incidentes_pedidos(Peticion, Incs),
    seguro(( despacho_corto(Incs, Antes),
             si_pasara(Cambio, X, despacho_corto(Incs, X), [Despues]),
             llegadas_corto(LA),
             si_pasara(Cambio, Y, llegadas_corto(Y), [LD]) )),
    t(Cambio, CT),
    reply_json_dict(_{cambio:CT, antes:Antes, despues:Despues, llegada_antes:LA, llegada_despues:LD}).

despacho_corto([], []) :- !.
despacho_corto(Incs, J) :-
    (   decide_uno(Incs, D, E) -> solucion_json(D, E, J) ; J = _{completo:no, explicacion:["Sin ruta posible."]} ).

llegadas_corto(L) :-
    findall(Tx, ( estado_llegada(U, R, Ev), llegada_txt(U, R, Ev, Tx) ), L).

% ---------------------------------------------------------------- 5 preguntas
api_preguntas(_) :-
    seguro(( escenario_activo(Act),
             findall(P, pregunta_json(P), Ps),
             cargar_escenario(Act) )),
    reply_json_dict(Ps).

pregunta_json(_{n:1, pregunta:"¿Qué unidad mando al incidente inc_s2?", escenario:s2_cercania, consulta:"decide([inc_s2], D, E)", respuesta:R}) :-
    cargar_escenario(s2_cercania), decide_uno([inc_s2], _, E), atomic_list_concat(E, ' ', R0), atom_string(R0, R).
pregunta_json(_{n:2, pregunta:"¿Por qué no la ambulancia que está más cerca en línea recta?", escenario:s2_cercania, consulta:"por_que_no(amb1, inc_s2, M)", respuesta:R}) :-
    cargar_escenario(s2_cercania), pregunta(2, _, _, inc_s2, U-M), motivo_txt(M, T), format(string(R), "~w: ~w.", [U, T]).
pregunta_json(_{n:3, pregunta:"¿Qué repartos cubren los tres incidentes del sismo?", escenario:s5_sismo, consulta:"findall(A, decide(Is, despacho(si,A,_,_), _), Rs)", respuesta:R}) :-
    cargar_escenario(s5_sismo), pregunta(3, _, _, [inc_herido, inc_fuego, inc_atrapados], Rs),
    length(Rs, N),
    findall(S, ( member(A, Rs), findall(X, ( member(a(I, ambulancia, U, _, _, _), A), format(string(X), "~w→~w", [U, I]) ), Xs),
                 atomic_list_concat(Xs, ', ', S0), atom_string(S0, S) ), Ss),
    atomic_list_concat(Ss, ' | ', Todo),
    format(string(R), "~w repartos completos (ambulancias): ~w", [N, Todo]).
pregunta_json(_{n:4, pregunta:"¿Qué falta para que el paro (inc_paro) tenga ambulancia sin retirar a nadie?", escenario:s1_retiro, consulta:"que_falta(inc_paro, C)", respuesta:R}) :-
    cargar_escenario(s1_retiro), pregunta(4, _, _, inc_paro, Cs),
    findall(T, ( member(C, Cs), cambio_txt(C, T) ), Ts), atomic_list_concat(Ts, ' ', R0), atom_string(R0, R).
pregunta_json(_{n:5, pregunta:"¿Qué pasaría si se cierra el tramo canon_este–centro?", escenario:s2_cercania, consulta:"si_pasara(cerrar(canon_este, centro), D, decide([inc_s2], D, _), R)", respuesta:R}) :-
    cargar_escenario(s2_cercania),
    pregunta(5, _, _, cerrar(canon_este, centro)-inc_s2, antes(despacho(_, [a(_, _, U1, E1, _, _)], _, _))-despues(despacho(_, [a(_, _, U2, E2, _, R2)], _, _))),
    min_seg(E1, T1), min_seg(E2, T2), ruta_txt(R2, TR),
    format(string(R), "Hoy va ~w (~w). Con el tramo cerrado ya no tiene ruta y va ~w (~w) por ~w.", [U1, T1, U2, T2, TR]).

% ---------------------------------------------------------------- gráficas (Janus)
g_mapa(Peticion) :-
    (   hay_janus
    ->  incidentes_pedidos(Peticion, Incs),
        seguro(grafica_mapa(Incs, Archivo)),
        http_reply_file(Archivo, [unsafe(true), cache(false)], Peticion)
    ;   http_404([], Peticion)
    ).

g_llegadas(Peticion) :-
    (   hay_janus
    ->  incidentes_pedidos(Peticion, Incs),
        (   Incs = [I|_], seguro(grafica_llegadas(I, Archivo))
        ->  http_reply_file(Archivo, [unsafe(true), cache(false)], Peticion)
        ;   http_404([], Peticion) )
    ;   http_404([], Peticion)
    ).

salida(Nombre, Ruta) :-
    dir_gemelo(D), atomic_list_concat([D, '/salida'], Dir),
    make_directory_path(Dir),
    escenario_activo(E),
    atomic_list_concat([Dir, '/', E, '_', Nombre], Ruta).

% Prolog deduce QUÉ dibujar (estado, ruta elegida); Python solo lo dibuja.
grafica_mapa(Incs, Archivo) :-
    findall([P, X, Y], coord(P, X, Y), Puntos),
    findall([A, B, T, Est],
            ( tramo(A, B, _), ( conecta(A, B, T) -> true ; tramo(A, B, T) ),
              ( cerrado_entre(A, B) -> Est = cerrado ; factor(A, B, F), F > 1 -> Est = lento ; Est = normal ) ),
            Tramos),
    findall([U, E, P], ( estado_unidad(U, E), ultima_posicion(U, P, _) ), Unidades),
    findall([I, P, Pr], incidente(I, _, P, Pr), Inc),
    (   Incs \== [], decide_uno(Incs, despacho(_, [a(_, _, _, _, _, Ruta)|_], _, _), _) -> true ; Ruta = [] ),
    escenario_activo(Es), escenario(Es, Titulo, _, _),
    salida('mapa.png', Archivo),
    py_call(graficas:mapa(Titulo, Puntos, Tramos, Unidades, Inc, Ruta, Archivo), _).

grafica_llegadas(I, Archivo) :-
    necesita(I, T, _), meta_para(I, T, Meta), incidente(I, _, P, _),
    findall(E-U, ( unidad(U, T), \+ estado_unidad(U, fuera_de_servicio),
                   ( llegada(U, P, E, _, _, _) -> true ; llegada_retiro(U, P, E, _) ) ), Ps0),
    keysort(Ps0, Ps), pairs_keys_values(Ps, Es, Us),
    (   decide_uno([I], despacho(_, A, _, _), _), memberchk(a(I, T, Eleg, _, _, _), A) -> true ; Eleg = ninguna ),
    format(string(Titulo), "¿Quién llega primero a ~w? (~w)", [I, T]),
    salida('llegadas.png', Archivo),
    py_call(graficas:llegadas(Titulo, Us, Es, Meta, Eleg, Archivo), _), !.
