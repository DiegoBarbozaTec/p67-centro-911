%%% Bitacora auditable del 911 (lo que NUNCA debe perderse).
%%%
%%% - Cada evento se guarda en disco (DETS) y se sincroniza antes de responder,
%%%   asi que si el proceso o la VM se caen, lo ya registrado sobrevive.
%%% - Los registros se encadenan con SHA-256: cada uno incluye el hash del
%%%   anterior. Si alguien modifica un registro viejo, verificar/0 lo detecta.
%%% - Es el primer hijo del supervisor rest_for_one: si se reinicia otro proceso,
%%%   la bitacora no se toca.
-module(p67_bitacora).
-behaviour(gen_server).

-export([start_link/0, registrar/3, de_incidente/1, recientes/1, verificar/0, total/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLA, p67_bitacora_dets).
-define(MAX_RECIENTES, 300).
-define(GENESIS, <<"0000000000000000">>).

%%% ---------------------------------------------------------------- API
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Registra un evento. Es sincrono: cuando regresa, el evento ya esta en disco.
registrar(Incidente, Evento, Datos) ->
  gen_server:call(?MODULE, {registrar, Incidente, Evento, Datos}).

%% Linea de tiempo completa de un incidente, en orden.
de_incidente(Incidente) ->
  Regs = dets:match_object(?TABLA, {'_', '_', Incidente, '_', '_', '_', '_'}),
  [a_mapa(R) || R <- lists:keysort(1, Regs)].

recientes(N) ->
  gen_server:call(?MODULE, {recientes, N}).

total() ->
  gen_server:call(?MODULE, total).

%% Recorre toda la cadena y recalcula los hashes.
verificar() ->
  gen_server:call(?MODULE, verificar, 60000).

%%% ---------------------------------------------------------------- callbacks
init([]) ->
  Archivo = filename:join(p67_conf:data_dir(), "bitacora.dets"),
  {ok, ?TABLA} = dets:open_file(?TABLA, [{file, Archivo}, {type, set}]),
  Todos = lists:keysort(1, dets:match_object(?TABLA, '_')),
  {Seq, Hash} = case Todos of
                  [] -> {0, ?GENESIS};
                  _  -> {S, _, _, _, _, _, H} = lists:last(Todos), {S, H}
                end,
  Recientes = lists:reverse(lists:nthtail(max(0, length(Todos) - ?MAX_RECIENTES), Todos)),
  logger:info("bitacora abierta con ~p eventos", [Seq]),
  {ok, #{seq => Seq, hash => Hash, recientes => [a_mapa(R) || R <- Recientes]}}.

handle_call({registrar, Inc, Evento, Datos}, _From,
            S = #{seq := Seq0, hash := Prev, recientes := Rec}) ->
  Seq = Seq0 + 1,
  Ts = p67_conf:ahora_ms(),
  Hash = calcular_hash(Seq, Ts, Inc, Evento, Datos, Prev),
  Reg = {Seq, Ts, Inc, Evento, Datos, Prev, Hash},
  ok = dets:insert(?TABLA, Reg),
  ok = dets:sync(?TABLA),
  Rec2 = lists:sublist([a_mapa(Reg) | Rec], ?MAX_RECIENTES),
  {reply, {ok, Seq}, S#{seq := Seq, hash := Hash, recientes := Rec2}};
handle_call({recientes, N}, _From, S = #{recientes := Rec}) ->
  {reply, lists:sublist(Rec, N), S};
handle_call(total, _From, S = #{seq := Seq}) ->
  {reply, Seq, S};
handle_call(verificar, _From, S) ->
  Todos = lists:keysort(1, dets:match_object(?TABLA, '_')),
  {reply, verificar_cadena(Todos, ?GENESIS, 0), S}.

handle_cast(_Msg, S) -> {noreply, S}.
handle_info(_Info, S) -> {noreply, S}.

terminate(_Razon, _S) ->
  dets:close(?TABLA).

%%% ---------------------------------------------------------------- internas
calcular_hash(Seq, Ts, Inc, Evento, Datos, Prev) ->
  Bin = term_to_binary({Seq, Ts, Inc, Evento, Datos, Prev}),
  binary:encode_hex(crypto:hash(sha256, Bin)).

verificar_cadena([], _Prev, N) ->
  {ok, N};
verificar_cadena([{Seq, Ts, Inc, Ev, Datos, Prev, Hash} | Resto], Prev, _N) ->
  case calcular_hash(Seq, Ts, Inc, Ev, Datos, Prev) of
    Hash -> verificar_cadena(Resto, Hash, Seq);
    _    -> {alterado, Seq}
  end;
verificar_cadena([{Seq, _, _, _, _, _, _} | _], _Prev, _N) ->
  {alterado, Seq}.

a_mapa({Seq, Ts, Inc, Evento, Datos, _Prev, Hash}) ->
  #{seq => Seq, ts => Ts, incidente => Inc, evento => Evento,
    datos => Datos, hash => binary:part(Hash, 0, 12)}.
