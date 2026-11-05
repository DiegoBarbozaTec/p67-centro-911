%%% API REST del Centro 911 (cowboy).
%%%
%%%   GET  /api/incidentes             lista de incidentes
%%%   POST /api/incidentes             crea uno: {"tipo","prioridad","x","y","descripcion"}
%%%   GET  /api/incidentes/:id         detalle + linea de tiempo de la bitacora
%%%   GET  /api/unidades               flota completa
%%%   GET  /api/unidades/:id           una unidad
%%%   GET  /api/bitacora               ultimos eventos
%%%   GET  /api/bitacora/verificar     verifica la cadena de hashes
%%%   GET  /api/estadisticas           indicadores
%%%   POST /api/simulacion/:nombre     turno | accidente_multiple | sin_ambulancias
%%%   POST /api/caos/:tipo             matar_unidad | matar_despachador |
%%%                                    perder_comunicacion | no_acepta
%%%   POST /api/reiniciar              limpia incidentes y libera la flota
%%%   GET  /metrics                    metricas en formato Prometheus
-module(p67_http_api).

-export([init/2]).

init(Req0, Ruta) ->
  Metodo = cowboy_req:method(Req0),
  {Codigo, Cuerpo, Req1} =
    try atender(Ruta, Metodo, Req0)
    catch Clase:Razon:Pila ->
        logger:error("error en ~p: ~p:~p ~p", [Ruta, Clase, Razon, Pila]),
        {500, #{error => <<"error interno">>}, Req0}
    end,
  Req = responder(Ruta, Codigo, Cuerpo, Req1),
  {ok, Req, Ruta}.

%%% ---------------------------------------------------------------- rutas
atender(incidentes, <<"GET">>, Req) ->
  {200, [publico(I) || I <- p67_despachador:incidentes()], Req};
atender(incidentes, <<"POST">>, Req0) ->
  {ok, Body, Req} = cowboy_req:read_body(Req0),
  case p67_json:decode(Body) of
    {ok, M} when is_map(M) ->
      Datos = #{tipo => maps:get(<<"tipo">>, M, <<>>),
                prioridad => maps:get(<<"prioridad">>, M, 3),
                pos => {maps:get(<<"x">>, M, null), maps:get(<<"y">>, M, null)},
                descripcion => maps:get(<<"descripcion">>, M, <<>>),
                origen => api},
      case p67_despachador:nuevo_incidente(Datos) of
        {ok, Id}        -> {201, #{resultado => creado, id => Id}, Req};
        {duplicado, Id} -> {200, #{resultado => duplicado, id => Id}, Req};
        improcedente    -> {200, #{resultado => improcedente}, Req};
        {error, R}      -> {400, #{error => R}, Req}
      end;
    _ -> {400, #{error => json_invalido}, Req}
  end;
atender(incidente, <<"GET">>, Req) ->
  Id = cowboy_req:binding(id, Req),
  case p67_despachador:incidente(Id) of
    {ok, I} -> {200, #{incidente => publico(I),
                       linea_de_tiempo => p67_bitacora:de_incidente(Id)}, Req};
    error -> {404, #{error => no_existe}, Req}
  end;
atender(unidades, <<"GET">>, Req) ->
  {200, p67_unidad:todas(), Req};
atender(unidad, <<"GET">>, Req) ->
  case p67_unidad:info(cowboy_req:binding(id, Req)) of
    {ok, U} -> {200, U, Req};
    _ -> {404, #{error => no_existe}, Req}
  end;
atender(bitacora, <<"GET">>, Req) ->
  {200, #{total => p67_bitacora:total(), eventos => p67_bitacora:recientes(100)}, Req};
atender(verificar, <<"GET">>, Req) ->
  case p67_bitacora:verificar() of
    {ok, N} -> {200, #{integra => true, eventos_verificados => N}, Req};
    {alterado, Seq} -> {200, #{integra => false, alterado_en => Seq}, Req}
  end;
atender(estadisticas, <<"GET">>, Req) ->
  {200, p67_despachador:estadisticas(), Req};
atender(simulacion, <<"POST">>, Req) ->
  resultado(p67_simulador:escenario(nombre(cowboy_req:binding(nombre, Req))), Req);
atender(caos, <<"POST">>, Req) ->
  resultado(p67_simulador:caos(nombre(cowboy_req:binding(tipo, Req))), Req);
atender(reiniciar, <<"POST">>, Req) ->
  {ok, _} = p67_simulador:cancelar(),
  ok = p67_despachador:reiniciar(),
  {200, #{resultado => reiniciado}, Req};
atender(metrics, <<"GET">>, Req) ->
  {200, metricas(), Req};
atender(_, _, Req) ->
  {405, #{error => metodo_no_permitido}, Req}.

%%% ---------------------------------------------------------------- internas
resultado({ok, M}, Req) -> {200, M, Req};
resultado({error, R}, Req) -> {400, #{error => fmt(R)}, Req}.

nombre(B) ->
  try binary_to_existing_atom(B, utf8) catch _:_ -> desconocido end.

%% Campos del incidente que se exponen (sin listas internas).
publico(I) ->
  maps:with([id, tipo, prioridad, pos, descripcion, estado, unidad, tipo_unidad,
             llamadas, recibido_ms, asignado_ms, en_sitio_ms, cerrado_ms, eta_min, intentos], I).

responder(metrics, Codigo, Texto, Req) ->
  cowboy_req:reply(Codigo, #{<<"content-type">> => <<"text/plain; version=0.0.4">>}, Texto, Req);
responder(_, Codigo, Cuerpo, Req) ->
  cowboy_req:reply(Codigo, #{<<"content-type">> => <<"application/json; charset=utf-8">>,
                             <<"access-control-allow-origin">> => <<"*">>},
                   p67_json:encode(Cuerpo), Req).

%% Metricas en formato de texto de Prometheus.
metricas() ->
  E = p67_despachador:estadisticas(),
  #{abiertos_por_prioridad := PP, contadores := C, disponibles_por_tipo := DT} = E,
  Lineas =
    [linea("p67_incidentes_total", maps:get(incidentes_total, E)),
     linea("p67_incidentes_en_espera", maps:get(en_espera, E)),
     linea("p67_tiempo_asignacion_promedio_min", maps:get(prom_min_asignacion, E)),
     linea("p67_tiempo_llegada_promedio_min", maps:get(prom_min_llegada, E)),
     linea("p67_cumplimiento_meta_pct", maps:get(pct_cumple_meta, E)),
     linea("p67_unidades_fuera_servicio", maps:get(unidades_fuera_servicio, E)),
     linea("p67_bitacora_eventos_total", p67_bitacora:total()),
     linea("p67_procesos_erlang", erlang:system_info(process_count))]
    ++ [linea(io_lib:format("p67_incidentes_abiertos{prioridad=\"~p\"}", [P]), N)
        || {P, N} <- lists:sort(maps:to_list(PP))]
    ++ [linea(io_lib:format("p67_unidades_disponibles{tipo=\"~s\"}", [T]), N)
        || {T, N} <- lists:sort(maps:to_list(DT))]
    ++ [linea(io_lib:format("p67_eventos_total{tipo=\"~s\"}", [K]), V)
        || {K, V} <- lists:sort(maps:to_list(C))],
  iolist_to_binary(Lineas).

linea(Nombre, Valor) -> io_lib:format("~s ~p~n", [Nombre, Valor]).

fmt(B) when is_binary(B) -> B;
fmt(T) -> iolist_to_binary(io_lib:format("~p", [T])).
