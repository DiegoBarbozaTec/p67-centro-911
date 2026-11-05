%%% Simulador de escenarios y pruebas de caos para la demo.
%%%
%%% Escenarios (del documento del problema):
%%%   turno               -> 200 incidentes reales + 800 improcedentes (80 %) en un
%%%                          turno de 8 h (480 min simulados).
%%%   accidente_multiple  -> 12 llamadas del mismo accidente en pocos minutos.
%%%   sin_ambulancias     -> todas las ambulancias ocupadas con prioridad 3 y
%%%                          entra una prioridad 1.
%%%
%%% Caos:
%%%   matar_unidad        -> mata el proceso de una unidad en camino.
%%%   matar_despachador   -> mata el proceso del despachador.
%%%   perder_comunicacion -> una unidad en camino deja de mandar latidos.
%%%   no_acepta           -> la unidad mas cercana tiene el radio caido y entra
%%%                          un incidente: se debe reasignar a la siguiente.
-module(p67_simulador).
-behaviour(gen_server).

-export([start_link/0, escenario/1, caos/1, escenarios/0, cancelar/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TIPOS_REALES, [{medica, 30}, {accidente, 20}, {delito, 20}, {rina, 8},
                       {incendio, 8}, {fuga_gas, 4}, {derrumbe, 5}, {inundacion, 5}]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

escenarios() -> [turno, accidente_multiple, sin_ambulancias].

escenario(Nombre) -> gen_server:call(?MODULE, {escenario, Nombre}, 30000).
caos(Tipo)        -> gen_server:call(?MODULE, {caos, Tipo}, 30000).
%% Cancela las llamadas programadas que aun no llegan.
cancelar()        -> gen_server:call(?MODULE, cancelar).

init([]) ->
  {ok, #{}}.

%%% ---------------------------------------------------------------- escenarios
handle_call({escenario, turno}, _From, S) ->
  rand:seed(exsss, {9, 1, 1}),
  Duracion = 480,
  Reales = [{rand:uniform() * Duracion, llamada_real()} || _ <- lists:seq(1, 200)],
  Improc = [{rand:uniform() * Duracion, llamada_improcedente()} || _ <- lists:seq(1, 800)],
  lists:foreach(fun({Min, Datos}) -> programar(Min, Datos) end, Reales ++ Improc),
  {reply, {ok, #{escenario => turno, incidentes_reales => 200, improcedentes => 800,
                 minutos_simulados => Duracion,
                 segundos_reales => round(p67_conf:ms(Duracion) / 1000)}}, S};

handle_call({escenario, accidente_multiple}, _From, S) ->
  Centro = {6.2, 4.4},
  lists:foreach(
    fun(I) ->
        {X, Y} = Centro,
        Pos = {X + (rand:uniform() - 0.5) * 0.3, Y + (rand:uniform() - 0.5) * 0.3},
        programar(I * 0.4, #{tipo => accidente, prioridad => 1 + (I rem 2), pos => Pos,
                             descripcion => <<"Choque multiple en Via Rapida Oriente">>,
                             origen => simulador})
    end, lists:seq(1, 12)),
  {reply, {ok, #{escenario => accidente_multiple, llamadas => 12,
                 esperado => <<"un solo incidente con 12 llamadas">>}}, S};

handle_call({escenario, sin_ambulancias}, _From, S) ->
  Ambulancias = [U || U = #{tipo := ambulancia} <- p67_unidad:todas()],
  N = length(Ambulancias),
  %% Incidentes leves lejos entre si (no deben contarse como duplicados).
  lists:foreach(
    fun(I) ->
        Pos = {1.0 + (I rem 6) * 3.2, 1.0 + (I div 6) * 4.5},
        programar(I * 0.05, #{tipo => medica, prioridad => 3, pos => Pos,
                              descripcion => <<"Persona con malestar leve">>,
                              origen => simulador})
    end, lists:seq(0, N - 1)),
  %% Cuando ya estan todas ocupadas entra la prioridad 1.
  programar(6, #{tipo => medica, prioridad => 1, pos => {12.5, 6.0},
                 descripcion => <<"Paro cardiorrespiratorio">>, origen => simulador}),
  {reply, {ok, #{escenario => sin_ambulancias, ambulancias => N,
                 esperado => <<"se retira la ambulancia mas cercana de un P3">>}}, S};

handle_call({escenario, Otro}, _From, S) ->
  {reply, {error, {escenario_desconocido, Otro}}, S};

%%% ---------------------------------------------------------------- caos
handle_call({caos, matar_unidad}, _From, S) ->
  {reply, matar(en_movimiento()), S};
handle_call({caos, matar_despachador}, _From, S) ->
  Pid = whereis(p67_despachador),
  exit(Pid, kill),
  p67_bitacora:registrar(undefined, caos_matar_despachador, #{pid => fmt(Pid)}),
  {reply, {ok, #{muerto => fmt(Pid),
                 esperado => <<"se reinicia y recupera incidentes desde disco">>}}, S};
handle_call({caos, perder_comunicacion}, _From, S) ->
  case en_movimiento() ++ [U || U = #{estado := despachada} <- p67_unidad:todas()] of
    [] -> {reply, {error, <<"no hay unidades en camino; corre un escenario primero">>}, S};
    [#{id := U} | _] ->
      p67_unidad:perder_comunicacion(U),
      p67_bitacora:registrar(undefined, caos_perder_comunicacion, #{unidad => U}),
      {reply, {ok, #{unidad => U, esperado => <<"se detecta sin latido y se reasigna">>}}, S}
  end;
handle_call({caos, no_acepta}, _From, S) ->
  Destino = punto_libre(),
  Libres = [{p67_geo:eta_min(ambulancia, P, Destino), U}
            || #{id := U, tipo := ambulancia, estado := disponible, pos_mapa := P} <- p67_unidad:todas()],
  case lists:sort(Libres) of
    [] -> {reply, {error, <<"no hay ambulancias libres">>}, S};
    [{_, U} | _] ->
      p67_unidad:perder_comunicacion(U),
      p67_bitacora:registrar(undefined, caos_radio_caido, #{unidad => U}),
      R = p67_despachador:nuevo_incidente(
            #{tipo => medica, prioridad => 1, pos => Destino,
              descripcion => <<"Caida de altura (prueba de caos)">>, origen => caos}),
      Inc = case R of {ok, Id} -> Id; Otro -> fmt(Otro) end,
      {reply, {ok, #{unidad_sin_radio => U, incidente => Inc,
                     esperado => <<"no acepta en 2 min y se reasigna a la siguiente">>}}, S}
  end;
handle_call({caos, Otro}, _From, S) ->
  {reply, {error, {caos_desconocido, Otro}}, S};

handle_call(cancelar, _From, S) ->
  N = vaciar_buzon(0),
  {reply, {ok, N}, S}.

handle_cast(_Msg, S) -> {noreply, S}.

handle_info({timeout, Ref, {llamada, Datos}}, S) ->
  erase({timer, Ref}),
  _ = catch p67_despachador:nuevo_incidente(Datos),
  {noreply, S};
handle_info(_Otro, S) -> {noreply, S}.

%%% ---------------------------------------------------------------- internas
programar(Minutos, Datos) ->
  Ref = erlang:start_timer(p67_conf:ms(Minutos), self(), {llamada, Datos}),
  put({timer, Ref}, true),
  Ref.

%% Cancela todos los timers pendientes (guardados en el diccionario del proceso).
vaciar_buzon(N0) ->
  N = lists:foldl(fun({{timer, Ref}, _}, Acc) ->
                      erase({timer, Ref}),
                      case erlang:cancel_timer(Ref) of false -> Acc; _ -> Acc + 1 end;
                     (_, Acc) -> Acc
                  end, N0, get()),
  receive {timeout, _, {llamada, _}} -> vaciar_buzon(N) after 0 -> N end.

llamada_real() ->
  Tipo = elegir(?TIPOS_REALES),
  P = case rand:uniform(100) of N when N =< 20 -> 1; N when N =< 55 -> 2; _ -> 3 end,
  #{tipo => Tipo, prioridad => P, pos => p67_geo:punto_aleatorio(),
    descripcion => descripcion(Tipo), origen => simulador}.

llamada_improcedente() ->
  #{tipo => improcedente, prioridad => 3, pos => p67_geo:punto_aleatorio(),
    descripcion => lists:nth(rand:uniform(3), [<<"Broma">>, <<"Marcacion por error">>,
                                               <<"Solicita informacion">>]),
    origen => simulador}.

elegir(Pesos) ->
  Total = lists:sum([W || {_, W} <- Pesos]),
  elegir(rand:uniform(Total), Pesos).
elegir(N, [{T, W} | _]) when N =< W -> T;
elegir(N, [{_, W} | R]) -> elegir(N - W, R).

descripcion(medica)     -> <<"Persona inconsciente">>;
descripcion(accidente)  -> <<"Choque con lesionados">>;
descripcion(delito)     -> <<"Reporte de asalto">>;
descripcion(rina)       -> <<"Rina en via publica">>;
descripcion(incendio)   -> <<"Incendio en vivienda">>;
descripcion(fuga_gas)   -> <<"Olor a gas en edificio">>;
descripcion(derrumbe)   -> <<"Deslave en ladera">>;
descripcion(inundacion) -> <<"Calle inundada con autos atrapados">>.

%% Un punto sin incidentes abiertos cerca (para que no cuente como duplicado).
punto_libre() ->
  Abiertos = [P || #{pos := P, estado := E} <- p67_despachador:incidentes(), E =/= cerrado],
  Opciones = [{4.0, 8.0}, {15.0, 2.0}, {2.0, 11.0}, {17.0, 10.0}, {8.0, 1.0}, {13.0, 6.0}],
  Libres = [O || O <- Opciones, lists:all(fun(P) -> p67_geo:distancia_recta(O, P) > 1.0 end, Abiertos)],
  case Libres of
    [P | _] -> P;
    [] -> p67_geo:punto_aleatorio()
  end.

en_movimiento() ->
  [U || U = #{estado := E} <- p67_unidad:todas(), E =:= en_camino].

matar([]) ->
  {error, <<"no hay unidades en camino; corre un escenario primero">>};
matar([#{id := U, incidente := Inc} | _]) ->
  Pid = p67_unidad:pid(U),
  p67_bitacora:registrar(Inc, caos_matar_unidad, #{unidad => U, pid => fmt(Pid)}),
  exit(Pid, kill),
  {ok, #{unidad => U, incidente => Inc,
         esperado => <<"el supervisor la reinicia y el incidente se reasigna">>}}.

fmt(T) -> iolist_to_binary(io_lib:format("~p", [T])).
