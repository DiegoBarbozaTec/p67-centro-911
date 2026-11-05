%%% Pruebas eunit del Centro 911. Arrancan la aplicacion completa con una
%%% escala rapida (50 ms = 1 minuto simulado) y una carpeta de datos temporal.
-module(p67_centro_de_emergencias_911_tests).
-include_lib("eunit/include/eunit.hrl").

-define(APP, p67_centro_de_emergencias_911).

%%% ---------------------------------------------------------------- unitarias puras
canon_cambia_la_unidad_mas_cercana_test() ->
  Incidente = {9.0, 6.0},
  CruzandoCanon = {10.5, 6.0},   % 1.5 km en linea recta, pero del otro lado
  MismoLado     = {7.0, 7.0},    % 2.2 km en linea recta, mismo lado
  ?assert(p67_geo:distancia_recta(CruzandoCanon, Incidente) <
          p67_geo:distancia_recta(MismoLado, Incidente)),
  ?assert(p67_geo:eta_min(ambulancia, MismoLado, Incidente) <
          p67_geo:eta_min(ambulancia, CruzandoCanon, Incidente)).

json_ida_y_vuelta_test() ->
  Bin = p67_json:encode(#{<<"a">> => 1, <<"b">> => [true, null, <<"hola \"911\"">>], <<"c">> => 2.5}),
  ?assertEqual({ok, #{<<"a">> => 1, <<"b">> => [true, null, <<"hola \"911\"">>], <<"c">> => 2.5}},
               p67_json:decode(Bin)),
  ?assertEqual({error, json_invalido}, p67_json:decode(<<"{malo">>)).

%%% ---------------------------------------------------------------- integracion
sistema_test_() ->
  {setup, fun arrancar/0, fun detener/1,
   fun(_) ->
     {inorder,
      [{"arbol de supervision y 40 unidades", fun arbol/0},
       {"despacha la unidad con menor tiempo de viaje", {timeout, 20, fun despacho_mas_cercana/0}},
       {"llamadas duplicadas se suman al mismo incidente", fun duplicados/0},
       {"llamadas improcedentes no se despachan", fun improcedente/0},
       {"prioridad 1 sin ambulancias retira una de prioridad 3", {timeout, 30, fun retiro_por_prioridad/0}},
       {"caos: unidad que no acepta se reasigna", {timeout, 20, fun no_acepta/0}},
       {"caos: matar el proceso de una unidad en camino", {timeout, 20, fun matar_unidad/0}},
       {"caos: perder comunicacion de una unidad en camino", {timeout, 20, fun perder_comunicacion/0}},
       {"caos: matar el despachador no pierde incidentes", {timeout, 20, fun matar_despachador/0}},
       {"bitacora detecta alteraciones", fun bitacora_integridad/0}]}
   end}.

arrancar() ->
  Dir = filename:join(["/tmp", "p67_test_" ++ integer_to_list(erlang:unique_integer([positive]))]),
  application:load(?APP),
  application:set_env(?APP, data_dir, Dir),
  application:set_env(?APP, http_port, 0),
  application:set_env(?APP, escala_ms_por_min, 50),
  logger:set_primary_config(level, warning),
  {ok, _} = application:ensure_all_started(?APP),
  Dir.

detener(Dir) ->
  application:stop(?APP),
  os:cmd("rm -rf " ++ Dir).

arbol() ->
  ?assert(is_pid(whereis(p67_bitacora))),
  ?assert(is_pid(whereis(p67_despachador))),
  ?assertEqual(40, length(p67_unidad:todas())),
  ?assertMatch({ok, _}, p67_bitacora:verificar()).

despacho_mas_cercana() ->
  limpiar(),
  Pos = {3.0, 3.0},
  Esperada = mas_cercana(ambulancia, Pos),
  {ok, Id} = nuevo(medica, 2, Pos),
  esperar(fun() -> estado(Id) =:= despachado end),
  {ok, #{unidad := U}} = p67_despachador:incidente(Id),
  ?assertEqual(Esperada, U),
  esperar(fun() -> estado(Id) =:= cerrado end, 15000).

duplicados() ->
  limpiar(),
  {ok, Id} = nuevo(accidente, 2, {5.0, 5.0}),
  ?assertEqual({duplicado, Id}, nuevo(accidente, 1, {5.2, 5.1})),
  ?assertEqual({duplicado, Id}, nuevo(accidente, 2, {4.9, 5.0})),
  {ok, #{llamadas := 3, prioridad := 1}} = p67_despachador:incidente(Id),
  %% Mismo tipo pero lejos: es otro incidente.
  ?assertMatch({ok, _}, nuevo(accidente, 2, {15.0, 10.0})).

improcedente() ->
  limpiar(),
  ?assertEqual(improcedente, nuevo(improcedente, 3, {1.0, 1.0})),
  ?assertEqual([], p67_despachador:incidentes()).

retiro_por_prioridad() ->
  limpiar(),
  Leves = [begin {ok, I} = nuevo(medica, 3, {1.0 + (N rem 6) * 3.2, 1.0 + (N div 6) * 4.5}), I end
           || N <- lists:seq(0, 15)],
  esperar(fun() -> lists:all(fun(I) -> lists:member(estado(I), [despachado, en_sitio]) end, Leves) end),
  ?assertEqual(0, maps:get(ambulancia, maps:get(disponibles_por_tipo, p67_despachador:estadisticas()))),
  {ok, Grave} = nuevo(medica, 1, {12.5, 6.0}),
  esperar(fun() -> lists:member(estado(Grave), [despachado, en_sitio]) end),
  #{contadores := #{retiros_por_prioridad := R}} = p67_despachador:estadisticas(),
  ?assert(R >= 1),
  Eventos = [E || #{evento := E} <- lists:flatmap(fun p67_bitacora:de_incidente/1, Leves)],
  ?assert(lists:member(unidad_retirada, Eventos)).

no_acepta() ->
  limpiar(),
  Pos = {4.0, 8.0},
  SinRadio = mas_cercana(ambulancia, Pos),
  p67_unidad:perder_comunicacion(SinRadio),
  {ok, Id} = nuevo(medica, 1, Pos),
  esperar(fun() -> estado(Id) =:= despachado end),
  {ok, #{unidad := Otra, intentos := Intentos}} = p67_despachador:incidente(Id),
  ?assertNotEqual(SinRadio, Otra),
  ?assert(lists:member(SinRadio, Intentos)),
  {ok, #{estado := fuera_de_servicio}} = p67_unidad:info(SinRadio).

matar_unidad() ->
  limpiar(),
  {ok, Id} = nuevo(incendio, 1, {18.0, 1.0}),
  esperar(fun() -> estado(Id) =:= despachado end),
  {ok, #{unidad := U}} = p67_despachador:incidente(Id),
  Pid = p67_unidad:pid(U),
  exit(Pid, kill),
  esperar(fun() -> is_pid(p67_unidad:pid(U)) andalso p67_unidad:pid(U) =/= Pid end),
  {ok, #{reinicios := N}} = p67_unidad:info(U),
  ?assert(N >= 1),
  esperar(fun() -> lists:member(estado(Id), [asignando, despachado, en_sitio]) end),
  Eventos = [E || #{evento := E} <- p67_bitacora:de_incidente(Id)],
  ?assert(lists:member(unidad_caida, Eventos)).

perder_comunicacion() ->
  limpiar(),
  {ok, Id} = nuevo(delito, 1, {19.5, 11.5}),
  esperar(fun() -> estado(Id) =:= despachado end),
  {ok, #{unidad := U}} = p67_despachador:incidente(Id),
  p67_unidad:perder_comunicacion(U),
  esperar(fun() -> {ok, #{unidad := U2}} = p67_despachador:incidente(Id), U2 =/= U end),
  Eventos = [E || #{evento := E} <- p67_bitacora:de_incidente(Id)],
  ?assert(lists:member(comunicacion_perdida, Eventos)).

matar_despachador() ->
  limpiar(),
  Ids = [begin {ok, I} = nuevo(rina, 2, {2.0 + N * 3, 2.0}), I end || N <- lists:seq(0, 4)],
  Viejo = whereis(p67_despachador),
  Simulador = whereis(p67_simulador),
  UnidadesAntes = [p67_unidad:pid(U) || #{id := U} <- p67_unidad:todas()],
  exit(Viejo, kill),
  esperar(fun() -> is_pid(whereis(p67_despachador)) andalso whereis(p67_despachador) =/= Viejo end),
  %% Los incidentes siguen ahi (estaban en disco).
  [?assertMatch({ok, _}, p67_despachador:incidente(I)) || I <- Ids],
  %% rest_for_one: la flota NO se reinicio.
  ?assertEqual(UnidadesAntes, [p67_unidad:pid(U) || #{id := U} <- p67_unidad:todas()]),
  %% El simulador esta fuera del nucleo: tampoco se reinicio.
  ?assertEqual(Simulador, whereis(p67_simulador)).

bitacora_integridad() ->
  {ok, N} = p67_bitacora:verificar(),
  ?assert(N > 0),
  [{1, Ts, Inc, Ev, _Datos, Prev, Hash}] = dets:lookup(p67_bitacora_dets, 1),
  ok = dets:insert(p67_bitacora_dets, {1, Ts, Inc, Ev, #{alterado => true}, Prev, Hash}),
  ?assertEqual({alterado, 1}, p67_bitacora:verificar()).

%%% ---------------------------------------------------------------- ayudantes
limpiar() ->
  ok = p67_despachador:reiniciar(),
  esperar(fun() -> length([x || #{estado := disponible} <- p67_unidad:todas()]) =:= 40 end).

nuevo(Tipo, P, Pos) ->
  p67_despachador:nuevo_incidente(#{tipo => Tipo, prioridad => P, pos => Pos,
                                    descripcion => <<"prueba">>}).

estado(Id) ->
  {ok, #{estado := E}} = p67_despachador:incidente(Id),
  E.

mas_cercana(Tipo, Pos) ->
  {_, U} = lists:min([{p67_geo:eta_min(Tipo, P, Pos), Id}
                      || #{id := Id, tipo := T, estado := disponible, pos_mapa := P} <- p67_unidad:todas(),
                         T =:= Tipo]),
  U.

esperar(F) -> esperar(F, 8000).
esperar(F, Ms) when Ms =< 0 -> ?assert(F());
esperar(F, Ms) ->
  case catch F() of
    true -> ok;
    _ -> timer:sleep(25), esperar(F, Ms - 25)
  end.
