%%% Una unidad de emergencia (ambulancia, patrulla, bomberos o proteccion civil).
%%%
%%% Estados: disponible -> despachada -> en_camino -> en_escena
%%%          [-> trasladando (solo ambulancias)] -> disponible
%%%          y fuera_de_servicio cuando se pierde comunicacion.
%%%
%%% Cada unidad es un proceso independiente: si una falla, el supervisor la
%%% reinicia sin afectar a las demas. Publica su estado en la tabla ETS
%%% p67_unidades y manda un "latido" periodico; si deja de latir mientras va en
%%% camino, el despachador la da por perdida y reasigna el incidente.
-module(p67_unidad).
-behaviour(gen_server).

-export([start_link/3, asignar/3, liberar/1, perder_comunicacion/1,
         restaurar_comunicacion/1, fuera_de_servicio/1, reactivar/1,
         todas/0, info/1, pid/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TABLA, p67_unidades).
-define(LATIDO_MIN, 1).

%%% ---------------------------------------------------------------- API
start_link(Id, Tipo, Base) ->
  gen_server:start_link(?MODULE, {Id, Tipo, Base}, []).

%% El despachador le asigna un incidente. Asincrono: si la unidad perdio
%% comunicacion simplemente no contesta, y el despachador reasigna por timeout.
asignar(Id, Incidente, Destino) -> cast(Id, {asignar, Incidente, Destino}).
%% La retira de su incidente actual (para mandarla a uno mas grave).
liberar(Id)                -> cast(Id, liberar).
perder_comunicacion(Id)    -> cast(Id, perder_comunicacion).
restaurar_comunicacion(Id) -> cast(Id, restaurar_comunicacion).
fuera_de_servicio(Id)      -> cast(Id, fuera_de_servicio).
reactivar(Id)              -> cast(Id, reactivar).

todas() ->
  lists:sort(fun(A, B) -> maps:get(id, A) =< maps:get(id, B) end,
             [U || {_Id, _Pid, U} <- ets:tab2list(?TABLA)]).

info(Id) ->
  case ets:lookup(?TABLA, Id) of
    [{_, _, U}] -> {ok, U};
    [] -> {error, no_existe}
  end.

pid(Id) ->
  case ets:lookup(?TABLA, Id) of
    [{_, Pid, _}] -> Pid;
    [] -> undefined
  end.

cast(Id, Msg) ->
  case pid(Id) of
    undefined -> {error, no_existe};
    Pid -> gen_server:cast(Pid, Msg)
  end.

%%% ---------------------------------------------------------------- callbacks
init({Id, Tipo, Base}) ->
  S = #{id => Id, tipo => Tipo, base => Base, pos => Base,
        estado => disponible, incidente => undefined, destino => undefined,
        comunicacion => ok, timer => undefined,
        salida_ms => undefined, eta_min => undefined,
        ultimo_latido => p67_conf:ahora_ms(), reinicios => reinicios_previos(Id)},
  erlang:send_after(p67_conf:ms(?LATIDO_MIN), self(), latido),
  {ok, publicar(S)}.

handle_call(_Msg, _From, S) ->
  {reply, ok, S}.

%% Sin comunicacion no recibe ordenes (simula radio caido).
handle_cast({asignar, _Inc, _Dest}, S = #{comunicacion := perdida}) ->
  {noreply, S};
handle_cast({asignar, Inc, Dest}, S = #{estado := disponible}) ->
  T = programar(0.5, aceptar, cancelar(S)),
  {noreply, publicar(S#{estado := despachada, incidente := Inc, destino := Dest, timer := T})};
handle_cast({asignar, Inc, _Dest}, S = #{id := Id}) ->
  %% Ocupada: rechaza para que el despachador busque otra.
  p67_despachador:unidad_rechaza(Id, Inc),
  {noreply, S};

handle_cast(liberar, S) ->
  {noreply, publicar(volver_disponible(S))};

handle_cast(perder_comunicacion, S) ->
  {noreply, publicar(S#{comunicacion := perdida})};
handle_cast(restaurar_comunicacion, S) ->
  {noreply, publicar(S#{comunicacion := ok, ultimo_latido := p67_conf:ahora_ms()})};

handle_cast(fuera_de_servicio, S) ->
  {noreply, publicar((cancelar_y_limpiar(S))#{estado := fuera_de_servicio})};
handle_cast(reactivar, S = #{estado := fuera_de_servicio}) ->
  {noreply, publicar(S#{estado := disponible, comunicacion := ok,
                        ultimo_latido := p67_conf:ahora_ms()})};
handle_cast(reactivar, S) ->
  {noreply, S}.

%% Acepta el despacho y sale hacia el incidente.
handle_info(aceptar, S = #{id := Id, tipo := Tipo, pos := Pos, destino := Dest,
                           incidente := Inc, estado := despachada}) ->
  Eta = p67_geo:eta_min(Tipo, Pos, Dest),
  avisar(S, fun() -> p67_despachador:unidad_acepta(Id, Inc, Eta) end),
  T = programar(Eta, llegada, S#{timer := undefined}),
  {noreply, publicar(S#{estado := en_camino, timer := T,
                        salida_ms := p67_conf:ahora_ms(), eta_min := Eta})};
handle_info(llegada, S = #{id := Id, incidente := Inc, destino := Dest, estado := en_camino}) ->
  avisar(S, fun() -> p67_despachador:unidad_en_escena(Id, Inc) end),
  T = programar(10 + rand:uniform(15), fin_atencion, S#{timer := undefined}),
  {noreply, publicar(S#{estado := en_escena, pos := Dest, timer := T})};
handle_info(fin_atencion, S = #{tipo := ambulancia, estado := en_escena}) ->
  T = programar(8 + rand:uniform(7), fin_traslado, S#{timer := undefined}),
  {noreply, publicar(S#{estado := trasladando, timer := T})};
handle_info(fin_atencion, S = #{estado := en_escena}) ->
  {noreply, publicar(terminar(S))};
handle_info(fin_traslado, S = #{estado := trasladando}) ->
  {noreply, publicar(terminar(S))};

%% Latido periodico: si hay comunicacion actualiza la marca; si va en camino,
%% avanza su posicion en el mapa.
handle_info(latido, S0) ->
  erlang:send_after(p67_conf:ms(?LATIDO_MIN), self(), latido),
  S1 = avanzar(S0),
  S2 = case maps:get(comunicacion, S1) of
         ok -> S1#{ultimo_latido := p67_conf:ahora_ms()};
         perdida -> S1
       end,
  {noreply, publicar(S2)};
handle_info(_Otro, S) ->
  {noreply, S}.

%%% ---------------------------------------------------------------- internas
terminar(S = #{id := Id, incidente := Inc}) ->
  avisar(S, fun() -> p67_despachador:unidad_libre(Id, Inc) end),
  volver_disponible(S).

%% Sin radio, los avisos de la unidad no llegan a la central.
avisar(#{comunicacion := ok}, Aviso) -> Aviso();
avisar(_, _Aviso) -> ok.

%% Queda disponible donde va (si iba en camino, en el punto intermedio).
volver_disponible(S) ->
  PosActual = maps:get(pos_mapa, avanzar(S), maps:get(pos, S)),
  (cancelar_y_limpiar(S))#{estado := disponible, pos := PosActual, pos_mapa => PosActual}.

cancelar_y_limpiar(S) ->
  (cancelar(S))#{incidente := undefined, destino := undefined, timer := undefined,
                 salida_ms := undefined, eta_min := undefined}.

avanzar(S = #{estado := en_camino, salida_ms := Salida, eta_min := Eta,
              destino := Dest, pos := Pos}) when Eta > 0 ->
  F = p67_conf:minutos_entre(Salida, p67_conf:ahora_ms()) / Eta,
  S#{pos_mapa => p67_geo:interpolar(Pos, Dest, F)};
avanzar(S = #{pos := Pos}) ->
  S#{pos_mapa => Pos}.

programar(Minutos, Msg, _S) ->
  erlang:send_after(p67_conf:ms(Minutos), self(), Msg).

cancelar(S = #{timer := undefined}) -> S;
cancelar(S = #{timer := T}) ->
  _ = erlang:cancel_timer(T),
  receive aceptar -> ok; llegada -> ok; fin_atencion -> ok; fin_traslado -> ok
  after 0 -> ok end,
  S#{timer := undefined}.

%% Lo que se publica en ETS (sin timers ni datos internos).
publicar(S = #{id := Id}) ->
  Publico = maps:with([id, tipo, base, pos, estado, incidente, destino,
                       comunicacion, eta_min, ultimo_latido, reinicios], S),
  Pub2 = Publico#{pos_mapa => maps:get(pos_mapa, S, maps:get(pos, S))},
  ets:insert(?TABLA, {Id, self(), Pub2}),
  S.

%% Si la unidad ya existia en ETS es porque se reinicio (prueba de caos).
reinicios_previos(Id) ->
  case ets:lookup(?TABLA, Id) of
    [{_, _, #{reinicios := N}}] -> N + 1;
    _ -> 0
  end.
