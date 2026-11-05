%%% WebSocket del panel: cada segundo envia una "foto" del sistema
%%% (unidades, incidentes, indicadores y ultimos eventos de la bitacora).
%%% Cada navegador conectado es un proceso Erlang independiente.
-module(p67_ws).

-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2]).

-define(INTERVALO_MS, 1000).

init(Req, Estado) ->
  {cowboy_websocket, Req, Estado, #{idle_timeout => 120000}}.

websocket_init(Estado) ->
  self() ! enviar,
  {[], Estado}.

websocket_handle({text, <<"ping">>}, Estado) ->
  {[{text, <<"pong">>}], Estado};
websocket_handle(_Frame, Estado) ->
  {[], Estado}.

websocket_info(enviar, Estado) ->
  erlang:send_after(?INTERVALO_MS, self(), enviar),
  {[{text, p67_json:encode(foto())}], Estado};
websocket_info(_Info, Estado) ->
  {[], Estado}.

foto() ->
  Incs = p67_despachador:incidentes(),
  {Abiertos, Cerrados} = lists:partition(fun(#{estado := E}) -> E =/= cerrado end, Incs),
  Campos = [id, tipo, prioridad, pos, descripcion, estado, unidad, llamadas,
            recibido_ms, eta_min],
  #{ts => p67_conf:ahora_ms(),
    escala_ms_por_min => p67_conf:get(escala_ms_por_min, 250),
    unidades => p67_unidad:todas(),
    incidentes => [maps:with(Campos, I) || I <- Abiertos ++ lists:sublist(Cerrados, 25)],
    estadisticas => p67_despachador:estadisticas(),
    bitacora => p67_bitacora:recientes(40)}.
