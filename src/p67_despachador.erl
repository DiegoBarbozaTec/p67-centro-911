%%% Despachador del 911: recibe incidentes, asigna prioridad y manda la unidad
%%% adecuada con menor TIEMPO DE VIAJE.
%%%
%%% Estados de un incidente:
%%%   recibido -> asignando -> despachado -> en_sitio -> cerrado
%%%   (en_espera cuando no hay unidad libre del tipo necesario)
%%%
%%% Decisiones de diseno frente a los casos dificiles:
%%% - Llamadas duplicadas: mismo tipo, a menos de 500 m y dentro de 30 min
%%%   simulados se suman al incidente abierto (no se despacha otra unidad).
%%% - Prioridad 1 sin unidades libres: se retira la unidad mas cercana que este
%%%   atendiendo un incidente de prioridad 3; ese incidente regresa a la cola.
%%% - Unidad que no acepta a tiempo o deja de mandar latidos: se marca fuera de
%%%   servicio y el incidente se reasigna a la siguiente mas cercana.
%%% - Unidad cuyo proceso muere: el despachador la monitorea (erlang:monitor) y
%%%   reasigna su incidente.
%%% - Si el propio despachador muere, los incidentes estan en disco (DETS) y se
%%%   recuperan al reiniciar; la flota no se reinicia (rest_for_one).
-module(p67_despachador).
-behaviour(gen_server).

-export([start_link/0, nuevo_incidente/1, incidentes/0, incidente/1,
         estadisticas/0, reiniciar/0, metas/0]).
-export([unidad_acepta/3, unidad_rechaza/2, unidad_en_escena/2, unidad_libre/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLA, p67_incidentes_dets).
-define(TICK_MS, 500).
-define(RADIO_DUPLICADO_KM, 0.5).
-define(VENTANA_DUPLICADO_MIN, 30).
-define(ABIERTOS, [recibido, en_espera, asignando, despachado, en_sitio]).

-define(TIPOS, [medica, accidente, incendio, fuga_gas, delito, rina,
                derrumbe, inundacion, improcedente]).

%%% ---------------------------------------------------------------- API
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Datos: #{tipo, prioridad (1..3), pos {X,Y}, descripcion}
%% Respuestas: {ok, Id} | {duplicado, Id} | improcedente | {error, Razon}
nuevo_incidente(Datos) ->
  gen_server:call(?MODULE, {nuevo, Datos}).

incidentes() -> gen_server:call(?MODULE, incidentes).
incidente(Id) -> gen_server:call(?MODULE, {incidente, Id}).
estadisticas() -> gen_server:call(?MODULE, estadisticas).
reiniciar() -> gen_server:call(?MODULE, reiniciar, 15000).

%% Tiempo de llegada meta por prioridad (minutos), referencia NFPA 1710.
metas() -> #{1 => 8, 2 => 15, 3 => 30}.

%% Avisos que mandan las unidades.
unidad_acepta(U, Inc, Eta) -> gen_server:cast(?MODULE, {acepta, U, Inc, Eta}).
unidad_rechaza(U, Inc)     -> gen_server:cast(?MODULE, {rechaza, U, Inc}).
unidad_en_escena(U, Inc)   -> gen_server:cast(?MODULE, {en_escena, U, Inc}).
unidad_libre(U, Inc)       -> gen_server:cast(?MODULE, {libre, U, Inc}).

%%% ---------------------------------------------------------------- init
init([]) ->
  Archivo = filename:join(p67_conf:data_dir(), "incidentes.dets"),
  {ok, ?TABLA} = dets:open_file(?TABLA, [{file, Archivo}, {type, set}]),
  Incs = maps:from_list([{Id, I} || {Id, I} <- dets:match_object(?TABLA, '_'),
                                    is_binary(Id)]),
  Stats = case dets:lookup(?TABLA, '$stats') of
            [{_, St}] -> St;
            [] -> stats_vacias()
          end,
  Seq = lists:foldl(fun(Id, Max) -> max(Max, num_id(Id)) end, 0, maps:keys(Incs)),
  S0 = #{incs => Incs, seq => Seq, reservas => #{}, monitores => #{},
         timers => #{}, stats => Stats},
  S = reconciliar(S0),
  Abiertos = length([I || I <- maps:values(Incs), lists:member(maps:get(estado, I), ?ABIERTOS)]),
  log(undefined, despachador_iniciado, #{incidentes_recuperados => maps:size(Incs),
                                         abiertos => Abiertos}),
  erlang:send_after(?TICK_MS, self(), tick),
  {ok, S}.

%% Tras un reinicio: re-monitorear unidades que siguen en su incidente, y
%% regresar a la cola los incidentes cuya unidad ya no los atiende.
reconciliar(S = #{incs := Incs}) ->
  maps:fold(
    fun(Id, Inc = #{estado := Est, unidad := U}, Acc)
          when Est =:= asignando; Est =:= despachado; Est =:= en_sitio ->
        case p67_unidad:info(U) of
          {ok, #{incidente := Id}} when Est =/= asignando ->
            vigilar(U, Id, Acc);
          _ ->
            log(Id, recuperado_tras_reinicio, #{unidad_anterior => U}),
            guardar(Inc#{estado := en_espera, unidad := undefined}, Acc)
        end;
       (_Id, _Inc, Acc) -> Acc
    end, S, Incs).

%%% ---------------------------------------------------------------- calls
handle_call({nuevo, Datos}, _From, S) ->
  case validar(Datos) of
    {error, R} ->
      {reply, {error, R}, S};
    {ok, #{tipo := improcedente} = D} ->
      log(undefined, llamada_improcedente, #{descripcion => maps:get(descripcion, D)}),
      {reply, improcedente, contar(improcedentes, S)};
    {ok, D} ->
      case buscar_duplicado(D, S) of
        {ok, Id} ->
          {reply, {duplicado, Id}, sumar_llamada(Id, D, S)};
        none ->
          {Id, S2} = crear(D, S),
          {reply, {ok, Id}, intentar_despachar(Id, S2)}
      end
  end;
handle_call(incidentes, _From, S = #{incs := Incs}) ->
  L = lists:sort(fun(A, B) -> maps:get(recibido_ms, A) >= maps:get(recibido_ms, B) end,
                 maps:values(Incs)),
  {reply, L, S};
handle_call({incidente, Id}, _From, S = #{incs := Incs}) ->
  {reply, maps:find(Id, Incs), S};
handle_call(estadisticas, _From, S) ->
  {reply, calcular_estadisticas(S), S};
handle_call(reiniciar, _From, S = #{timers := Ts, monitores := Ms}) ->
  [erlang:cancel_timer(T) || T <- maps:values(Ts)],
  [erlang:demonitor(M, [flush]) || {M, _} <- maps:values(Ms)],
  ok = dets:delete_all_objects(?TABLA),
  lists:foreach(fun(#{id := U}) ->
                    p67_unidad:restaurar_comunicacion(U),
                    p67_unidad:liberar(U),
                    p67_unidad:reactivar(U)
                end, p67_unidad:todas()),
  log(undefined, sistema_reiniciado, #{}),
  {reply, ok, S#{incs := #{}, seq := 0, reservas := #{}, monitores := #{},
                 timers := #{}, stats := stats_vacias()}}.

%%% ---------------------------------------------------------------- casts
handle_cast({acepta, U, Id, Eta}, S) ->
  case incidente_de(Id, U, S) of
    {ok, Inc = #{estado := asignando}} ->
      S1 = quitar_reserva(U, Id, S),
      Ahora = p67_conf:ahora_ms(),
      log(Id, unidad_acepto, #{unidad => U, eta_min => redondear(Eta),
                               min_desde_llamada => min_desde(Inc, Ahora)}),
      {noreply, guardar(Inc#{estado := despachado, asignado_ms := Ahora,
                             eta_min := redondear(Eta)}, S1)};
    _ ->
      %% Aceptacion tardia de algo ya reasignado: se libera la unidad.
      p67_unidad:liberar(U),
      {noreply, S}
  end;
handle_cast({rechaza, U, Id}, S) ->
  case incidente_de(Id, U, S) of
    {ok, Inc = #{estado := asignando}} ->
      S1 = soltar(U, Id, S),
      log(Id, unidad_rechazo, #{unidad => U, motivo => ocupada}),
      Inc2 = Inc#{unidad := undefined, estado := en_espera,
                  intentos := [U | maps:get(intentos, Inc)]},
      {noreply, intentar_despachar(Id, guardar(Inc2, S1))};
    _ -> {noreply, S}
  end;
handle_cast({en_escena, U, Id}, S) ->
  case incidente_de(Id, U, S) of
    {ok, Inc = #{prioridad := P}} ->
      Ahora = p67_conf:ahora_ms(),
      Min = min_desde(Inc, Ahora),
      Meta = maps:get(P, metas()),
      log(Id, llegada_a_escena, #{unidad => U, min_desde_llamada => Min,
                                  meta_min => Meta, cumple_meta => Min =< Meta}),
      {noreply, guardar(Inc#{estado := en_sitio, en_sitio_ms := Ahora}, S)};
    _ -> {noreply, S}
  end;
handle_cast({libre, U, Id}, S) ->
  case incidente_de(Id, U, S) of
    {ok, Inc} ->
      S1 = soltar(U, Id, S),
      log(Id, incidente_cerrado, #{unidad => U}),
      S2 = guardar(Inc#{estado := cerrado, cerrado_ms := p67_conf:ahora_ms()}, S1),
      {noreply, despachar_cola(S2)};
    _ -> {noreply, S}
  end.

%%% ---------------------------------------------------------------- infos
%% La unidad no acepto a tiempo (radio caido): fuera de servicio y reasignar.
handle_info({no_acepta, U, Id}, S) ->
  case incidente_de(Id, U, S) of
    {ok, Inc = #{estado := asignando}} ->
      p67_unidad:fuera_de_servicio(U),
      S1 = soltar(U, Id, S),
      log(Id, unidad_no_respondio, #{unidad => U, accion => reasignar}),
      Inc2 = Inc#{unidad := undefined, estado := en_espera,
                  intentos := [U | maps:get(intentos, Inc)]},
      {noreply, intentar_despachar(Id, guardar(Inc2, contar(reasignaciones, S1)))};
    _ -> {noreply, S}
  end;
%% El proceso de una unidad murio (prueba de caos): reasignar su incidente.
handle_info({'DOWN', Ref, process, _Pid, Razon}, S = #{monitores := Ms}) ->
  case [{U, Id} || {U, {R, Id}} <- maps:to_list(Ms), R =:= Ref] of
    [{U, Id}] ->
      S1 = soltar(U, Id, S),
      case maps:find(Id, maps:get(incs, S1)) of
        {ok, Inc = #{unidad := U, estado := Est}} when Est =/= cerrado ->
          log(Id, unidad_caida, #{unidad => U, razon => fmt(Razon), accion => reasignar}),
          Inc2 = Inc#{unidad := undefined, estado := en_espera},
          S2 = contar(caidas_unidad, contar(reasignaciones, S1)),
          {noreply, intentar_despachar(Id, guardar(Inc2, S2))};
        _ -> {noreply, S1}
      end;
    [] -> {noreply, S}
  end;
%% Cada medio segundo: detectar unidades sin latido y despachar la cola.
handle_info(tick, S) ->
  erlang:send_after(?TICK_MS, self(), tick),
  {noreply, despachar_cola(revisar_latidos(S))};
handle_info(_Otro, S) ->
  {noreply, S}.

terminate(_Razon, _S) ->
  dets:close(?TABLA).

%%% ---------------------------------------------------------------- despacho
intentar_despachar(Id, S = #{incs := Incs}) ->
  case maps:find(Id, Incs) of
    {ok, Inc = #{estado := Est, unidad := undefined}}
      when Est =:= recibido; Est =:= en_espera ->
      case candidatas(Inc, S) of
        [] when map_get(prioridad, Inc) =:= 1 -> intentar_retirar(Inc, S);
        [] -> poner_en_espera(Inc, S);
        Cs ->
          {Eta, U} = lists:min(Cs),
          asignar(U, Inc, Eta, S)
      end;
    _ -> S
  end.

%% Unidades libres del tipo correcto, con su tiempo de viaje [{Eta, Unidad}].
%% Se evitan las que ya fallaron con este incidente, salvo que no haya otras.
candidatas(#{tipo_unidad := TU, pos := Pos, intentos := Intentos}, #{reservas := Res}) ->
  Libres = [{p67_geo:eta_min(TU, maps:get(pos_mapa, U), Pos), U}
            || U = #{id := UId, tipo := T, estado := disponible} <- p67_unidad:todas(),
               T =:= TU, not maps:is_key(UId, Res)],
  case [C || C = {_, #{id := UId}} <- Libres, not lists:member(UId, Intentos)] of
    [] -> Libres;
    Mejores -> Mejores
  end.

%% Prioridad 1 sin unidades: retirar la mas cercana que atienda una prioridad 3.
intentar_retirar(Inc = #{id := Id, tipo_unidad := TU, pos := Pos}, S = #{incs := Incs, reservas := Res}) ->
  Opciones = [{p67_geo:eta_min(TU, maps:get(pos_mapa, U), Pos), U, Victima}
              || U = #{id := UId, tipo := T, incidente := VicId} <- p67_unidad:todas(),
                 T =:= TU, not maps:is_key(UId, Res),
                 {ok, Victima = #{prioridad := 3, estado := VEst, unidad := VU}} <- [maps:find(VicId, Incs)],
                 VU =:= UId, VEst =:= despachado orelse VEst =:= en_sitio],
  case Opciones of
    [] ->
      poner_en_espera(Inc, S);
    _ ->
      {Eta, U = #{id := UId}, Victima = #{id := VicId}} =
        lists:min([{E, U0, V} || {E, U0, V} <- Opciones]),
      p67_unidad:liberar(UId),
      S1 = soltar(UId, VicId, S),
      log(VicId, unidad_retirada, #{unidad => UId, hacia => Id,
                                    motivo => <<"prioridad 1 sin unidades libres">>}),
      S2 = guardar(Victima#{estado := en_espera, unidad := undefined}, S1),
      asignar(U, Inc, Eta, contar(retiros_por_prioridad, S2))
  end.

asignar(#{id := UId, pos_mapa := UPos}, Inc = #{id := Id, pos := Pos}, Eta, S) ->
  ok = p67_unidad:asignar(UId, Id, Pos),
  T = erlang:send_after(p67_conf:ms(p67_conf:get(timeout_aceptacion_min, 2)),
                        self(), {no_acepta, UId, Id}),
  log(Id, unidad_asignada, #{unidad => UId, eta_min => redondear(Eta),
                             ruta_km => redondear(p67_geo:ruta_km(UPos, Pos)),
                             linea_recta_km => redondear(p67_geo:distancia_recta(UPos, Pos))}),
  S1 = vigilar(UId, Id, S),
  S2 = S1#{reservas := (maps:get(reservas, S1))#{UId => Id},
           timers := (maps:get(timers, S1))#{Id => T}},
  guardar(Inc#{estado := asignando, unidad := UId}, S2).

poner_en_espera(#{estado := en_espera}, S) -> S;
poner_en_espera(Inc = #{id := Id, tipo_unidad := TU}, S) ->
  log(Id, en_espera, #{motivo => <<"sin unidades libres">>, tipo_unidad => TU}),
  guardar(Inc#{estado := en_espera}, S).

%% Cola: primero prioridad 1, y dentro de cada prioridad el mas antiguo.
despachar_cola(S = #{incs := Incs}) ->
  Pend = lists:sort([{P, R, Id} || #{id := Id, prioridad := P, recibido_ms := R,
                                     estado := Est, unidad := undefined} <- maps:values(Incs),
                                   Est =:= en_espera orelse Est =:= recibido]),
  lists:foldl(fun({_, _, Id}, Acc) -> intentar_despachar(Id, Acc) end, S, Pend).

%% Unidad en camino o en escena que dejo de mandar latidos: se da por perdida.
revisar_latidos(S = #{monitores := Ms, incs := Incs}) ->
  Umbral = p67_conf:ms(p67_conf:get(latido_perdido_min, 4)),
  Ahora = p67_conf:ahora_ms(),
  Perdidas = [{U, Id} || {U, {_, Id}} <- maps:to_list(Ms),
                         {ok, #{estado := despachado}} <- [maps:find(Id, Incs)],
                         {ok, #{ultimo_latido := L}} <- [p67_unidad:info(U)],
                         Ahora - L > Umbral],
  lists:foldl(
    fun({U, Id}, Acc) ->
        p67_unidad:fuera_de_servicio(U),
        Acc1 = soltar(U, Id, Acc),
        log(Id, comunicacion_perdida, #{unidad => U, accion => reasignar}),
        Inc = maps:get(Id, maps:get(incs, Acc1)),
        Inc2 = Inc#{unidad := undefined, estado := en_espera,
                    intentos := [U | maps:get(intentos, Inc)]},
        Acc2 = contar(unidades_perdidas, contar(reasignaciones, Acc1)),
        intentar_despachar(Id, guardar(Inc2, Acc2))
    end, S, Perdidas).

%%% ---------------------------------------------------------------- incidentes
validar(D) ->
  try
    Tipo = a_atomo(maps:get(tipo, D)),
    true = lists:member(Tipo, ?TIPOS),
    P = maps:get(prioridad, D, 3),
    true = is_integer(P) andalso P >= 1 andalso P =< 3,
    {X, Y} = maps:get(pos, D),
    true = is_number(X) andalso is_number(Y),
    Desc = maps:get(descripcion, D, <<>>),
    {ok, #{tipo => Tipo, prioridad => P, pos => {X * 1.0, Y * 1.0},
           descripcion => Desc, origen => maps:get(origen, D, manual)}}
  catch _:_ -> {error, datos_invalidos}
  end.

a_atomo(A) when is_atom(A) -> A;
a_atomo(B) when is_binary(B) -> binary_to_existing_atom(B, utf8).

crear(D = #{tipo := Tipo}, S = #{seq := Seq}) ->
  N = Seq + 1,
  Id = iolist_to_binary(io_lib:format("INC-~4..0B", [N])),
  Inc = D#{id => Id, estado => recibido, unidad => undefined,
           tipo_unidad => tipo_unidad(Tipo), llamadas => 1,
           recibido_ms => p67_conf:ahora_ms(), asignado_ms => undefined,
           en_sitio_ms => undefined, cerrado_ms => undefined,
           eta_min => undefined, intentos => []},
  log(Id, incidente_recibido, maps:with([tipo, prioridad, pos, descripcion, origen], D)),
  {Id, guardar(Inc, S#{seq := N})}.

tipo_unidad(medica)     -> ambulancia;
tipo_unidad(accidente)  -> ambulancia;
tipo_unidad(incendio)   -> bomberos;
tipo_unidad(fuga_gas)   -> bomberos;
tipo_unidad(delito)     -> patrulla;
tipo_unidad(rina)       -> patrulla;
tipo_unidad(derrumbe)   -> proteccion_civil;
tipo_unidad(inundacion) -> proteccion_civil.

buscar_duplicado(#{tipo := T, pos := Pos}, #{incs := Incs}) ->
  Ahora = p67_conf:ahora_ms(),
  Cand = [{p67_geo:distancia_recta(Pos, P), Id}
          || #{id := Id, tipo := T2, pos := P, estado := Est, recibido_ms := R} <- maps:values(Incs),
             T2 =:= T, Est =/= cerrado,
             p67_conf:minutos_entre(R, Ahora) =< ?VENTANA_DUPLICADO_MIN,
             p67_geo:distancia_recta(Pos, P) =< ?RADIO_DUPLICADO_KM],
  case Cand of
    [] -> none;
    _ -> {_, Id} = lists:min(Cand), {ok, Id}
  end.

%% Llamada duplicada: se suma y, si es mas grave, se sube la prioridad.
sumar_llamada(Id, #{prioridad := PNueva}, S = #{incs := Incs}) ->
  Inc = #{llamadas := N, prioridad := P} = maps:get(Id, Incs),
  P2 = min(P, PNueva),
  log(Id, llamada_duplicada, #{llamadas => N + 1, prioridad => P2}),
  contar(duplicados, guardar(Inc#{llamadas := N + 1, prioridad := P2}, S)).

%%% ---------------------------------------------------------------- estadisticas
calcular_estadisticas(#{incs := Incs, stats := St}) ->
  L = maps:values(Incs),
  Abiertos = [I || I = #{estado := E} <- L, lists:member(E, ?ABIERTOS)],
  PorPrioridad = maps:from_list(
    [{P, length([x || #{prioridad := P2} <- Abiertos, P2 =:= P])} || P <- [1, 2, 3]]),
  Llegadas = [{P, p67_conf:minutos_entre(R, E)}
              || #{prioridad := P, recibido_ms := R, en_sitio_ms := E} <- L, is_integer(E)],
  Asign = [p67_conf:minutos_entre(R, A)
           || #{recibido_ms := R, asignado_ms := A} <- L, is_integer(A)],
  Metas = metas(),
  Cumplen = length([x || {P, M} <- Llegadas, M =< maps:get(P, Metas)]),
  Unidades = p67_unidad:todas(),
  #{incidentes_total => length(L),
    abiertos => length(Abiertos),
    abiertos_por_prioridad => PorPrioridad,
    en_espera => length([x || #{estado := en_espera} <- L]),
    cerrados => length([x || #{estado := cerrado} <- L]),
    prom_min_asignacion => redondear(promedio(Asign)),
    prom_min_llegada => redondear(promedio([M || {_, M} <- Llegadas])),
    prom_min_llegada_p1 => redondear(promedio([M || {1, M} <- Llegadas])),
    pct_cumple_meta => case Llegadas of [] -> 0; _ -> round(100 * Cumplen / length(Llegadas)) end,
    unidades_disponibles => length([x || #{estado := disponible} <- Unidades]),
    unidades_ocupadas => length([x || #{estado := E} <- Unidades,
                                      E =/= disponible, E =/= fuera_de_servicio]),
    unidades_fuera_servicio => length([x || #{estado := fuera_de_servicio} <- Unidades]),
    disponibles_por_tipo => maps:from_list(
      [{T, length([x || #{tipo := T2, estado := disponible} <- Unidades, T2 =:= T])}
       || T <- [ambulancia, patrulla, bomberos, proteccion_civil]]),
    contadores => St}.

stats_vacias() ->
  #{duplicados => 0, improcedentes => 0, reasignaciones => 0,
    retiros_por_prioridad => 0, unidades_perdidas => 0, caidas_unidad => 0}.

contar(Clave, S = #{stats := St}) ->
  St2 = St#{Clave => maps:get(Clave, St, 0) + 1},
  ok = dets:insert(?TABLA, {'$stats', St2}),
  S#{stats := St2}.

promedio([]) -> 0;
promedio(L) -> lists:sum(L) / length(L).

%%% ---------------------------------------------------------------- utilidades
guardar(Inc = #{id := Id}, S = #{incs := Incs}) ->
  ok = dets:insert(?TABLA, {Id, Inc}),
  S#{incs := Incs#{Id => Inc}}.

incidente_de(Id, U, #{incs := Incs}) ->
  case maps:find(Id, Incs) of
    {ok, Inc = #{unidad := U}} -> {ok, Inc};
    _ -> error
  end.

vigilar(U, Id, S = #{monitores := Ms}) ->
  case p67_unidad:pid(U) of
    undefined -> S;
    Pid ->
      case maps:find(U, Ms) of
        {ok, {Viejo, _}} -> erlang:demonitor(Viejo, [flush]);
        error -> ok
      end,
      S#{monitores := Ms#{U => {erlang:monitor(process, Pid), Id}}}
  end.

quitar_reserva(U, Id, S = #{reservas := Res, timers := Ts}) ->
  case maps:find(Id, Ts) of
    {ok, T} -> erlang:cancel_timer(T);
    error -> ok
  end,
  S#{reservas := maps:remove(U, Res), timers := maps:remove(Id, Ts)}.

%% Deja de seguir a la unidad para este incidente.
soltar(U, Id, S0) ->
  S = #{monitores := Ms} = quitar_reserva(U, Id, S0),
  case maps:find(U, Ms) of
    {ok, {Ref, Id}} -> erlang:demonitor(Ref, [flush]), S#{monitores := maps:remove(U, Ms)};
    _ -> S
  end.

min_desde(#{recibido_ms := R}, Ahora) -> redondear(p67_conf:minutos_entre(R, Ahora)).

log(Inc, Evento, Datos) ->
  {ok, _} = p67_bitacora:registrar(Inc, Evento, Datos),
  ok.

num_id(<<"INC-", N/binary>>) -> binary_to_integer(N);
num_id(_) -> 0.

redondear(V) when is_number(V) -> round(V * 10) / 10;
redondear(V) -> V.

fmt(T) -> iolist_to_binary(io_lib:format("~p", [T])).
