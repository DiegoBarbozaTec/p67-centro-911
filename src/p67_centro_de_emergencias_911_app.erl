%%% Aplicacion OTP del Centro de emergencias 911.
%%% Arranca el arbol de supervision y despues el servidor HTTP (cowboy).
-module(p67_centro_de_emergencias_911_app).
-behaviour(application).

-export([start/2, stop/1]).

-define(APP, p67_centro_de_emergencias_911).

start(_StartType, _StartArgs) ->
  {ok, Sup} = p67_centro_de_emergencias_911_sup:start_link(),
  ok = iniciar_http(),
  {ok, Sup}.

stop(_State) ->
  _ = cowboy:stop_listener(p67_http),
  ok.

%% Rutas del servidor web: panel estatico, API REST, WebSocket y metricas.
iniciar_http() ->
  Puerto = application:get_env(?APP, http_port, 8080),
  Rutas = cowboy_router:compile([
    {'_', [
      {"/",                         cowboy_static, {priv_file, ?APP, "www/index.html"}},
      {"/static/[...]",             cowboy_static, {priv_dir, ?APP, "www"}},
      {"/api/incidentes",           p67_http_api, incidentes},
      {"/api/incidentes/:id",       p67_http_api, incidente},
      {"/api/unidades",             p67_http_api, unidades},
      {"/api/unidades/:id",         p67_http_api, unidad},
      {"/api/bitacora",             p67_http_api, bitacora},
      {"/api/bitacora/verificar",   p67_http_api, verificar},
      {"/api/estadisticas",         p67_http_api, estadisticas},
      {"/api/simulacion/:nombre",   p67_http_api, simulacion},
      {"/api/caos/:tipo",           p67_http_api, caos},
      {"/api/reiniciar",            p67_http_api, reiniciar},
      {"/metrics",                  p67_http_api, metrics},
      {"/ws",                       p67_ws, []}
    ]}
  ]),
  {ok, _} = cowboy:start_clear(p67_http, [{port, Puerto}],
                               #{env => #{dispatch => Rutas}}),
  logger:info("Panel 911 escuchando en http://0.0.0.0:~p", [Puerto]),
  ok.
