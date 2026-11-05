%%% Nucleo operativo: la flota y el despachador.
%%%
%%% rest_for_one con las unidades ANTES que el despachador:
%%% - si cae el supervisor de la flota, se reinicia tambien el despachador
%%%   (sus monitores ya no sirven) y este recupera los incidentes desde disco;
%%% - si cae el despachador, la flota NO se toca: las unidades siguen en camino.
-module(p67_nucleo_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  Hijos = [
    #{id => p67_unidades_sup, start => {p67_unidades_sup, start_link, []},
      restart => permanent, shutdown => infinity, type => supervisor},
    #{id => p67_despachador, start => {p67_despachador, start_link, []},
      restart => permanent, shutdown => 5000, type => worker}
  ],
  {ok, {#{strategy => rest_for_one, intensity => 20, period => 10}, Hijos}}.
