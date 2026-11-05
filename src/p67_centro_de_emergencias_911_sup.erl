%%% Supervisor raiz del Centro 911.
%%%
%%%   p67_centro_de_emergencias_911_sup   (rest_for_one)
%%%   |-- p67_bitacora        lo que NUNCA se puede perder; arranca primero
%%%   |-- p67_nucleo_sup      (rest_for_one)
%%%   |   |-- p67_unidades_sup   (one_for_one) -> 40 procesos p67_unidad
%%%   |   `-- p67_despachador
%%%   `-- p67_simulador       genera llamadas y fallas para la demo
%%%
%%% rest_for_one: si cae un hijo se reinician el y los que estan despues de el,
%%% nunca los de antes. La bitacora es la primera: ninguna falla la reinicia.
%%% El simulador esta fuera del nucleo: si matamos el despachador (prueba de
%%% caos) las llamadas programadas del escenario no se pierden.
-module(p67_centro_de_emergencias_911_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  Hijos = [
    #{id => p67_bitacora, start => {p67_bitacora, start_link, []},
      restart => permanent, shutdown => 5000, type => worker},
    #{id => p67_nucleo_sup, start => {p67_nucleo_sup, start_link, []},
      restart => permanent, shutdown => infinity, type => supervisor},
    #{id => p67_simulador, start => {p67_simulador, start_link, []},
      restart => permanent, shutdown => 5000, type => worker}
  ],
  %% Hasta 20 reinicios en 10 s antes de rendirse (permite pruebas de caos).
  {ok, {#{strategy => rest_for_one, intensity => 20, period => 10}, Hijos}}.
