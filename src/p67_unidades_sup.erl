%%% Supervisor de la flota: un proceso (gen_server) por unidad de emergencia.
%%%
%%% one_for_one: si una unidad falla, solo esa se reinicia; las otras 39 siguen
%%% trabajando. Este supervisor es dueno de la tabla ETS p67_unidades, donde
%%% cada unidad publica su estado para que el despachador y el panel lo lean
%%% rapido sin bloquear a la unidad.
-module(p67_unidades_sup).
-behaviour(supervisor).

-export([start_link/0, flota/0]).
-export([init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  ets:new(p67_unidades, [named_table, public, set, {read_concurrency, true}]),
  Hijos = [#{id => Id,
             start => {p67_unidad, start_link, [Id, Tipo, Base]},
             restart => permanent,
             shutdown => 2000,
             type => worker}
           || {Id, Tipo, Base} <- flota()],
  {ok, {#{strategy => one_for_one, intensity => 100, period => 10}, Hijos}}.

%% 40 unidades de 4 tipos con bases repartidas a ambos lados del canon.
flota() ->
  grupo(<<"AMB">>, ambulancia, 16, 0) ++
  grupo(<<"PAT">>, patrulla, 12, 16) ++
  grupo(<<"BOM">>, bomberos, 8, 28) ++
  grupo(<<"PC">>,  proteccion_civil, 4, 36).

grupo(Prefijo, Tipo, N, Desfase) ->
  [{iolist_to_binary(io_lib:format("~s-~2..0B", [Prefijo, I])), Tipo, base(I + Desfase)}
   || I <- lists:seq(1, N)].

%% Posiciones deterministas (siempre las mismas) dentro del mapa de 20x12 km.
base(I) ->
  X = ((I * 37) rem 190) / 10 + 0.5,
  Y = ((I * 53) rem 110) / 10 + 0.5,
  {X, Y}.
