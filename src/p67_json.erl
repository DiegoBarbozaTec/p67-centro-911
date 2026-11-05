%%% Codificador/decodificador JSON minimo (sin dependencias, compatible con OTP 25+).
%%% Mapas <-> objetos, listas <-> arreglos, binarios <-> cadenas,
%%% atomos true/false/null y numeros.
-module(p67_json).

-export([encode/1, decode/1]).

%%% ---------------------------------------------------------------- encode
encode(T) -> iolist_to_binary(enc(T)).

enc(true)  -> <<"true">>;
enc(false) -> <<"false">>;
enc(null)  -> <<"null">>;
enc(undefined) -> <<"null">>;
enc(A) when is_atom(A) -> enc(atom_to_binary(A, utf8));
enc(I) when is_integer(I) -> integer_to_binary(I);
enc(F) when is_float(F) -> float_to_binary(F, [{decimals, 2}, compact]);
enc(B) when is_binary(B) -> [$", esc(B), $"];
enc({X, Y}) when is_number(X), is_number(Y) -> enc([X, Y]);
enc(M) when is_map(M) ->
  Pares = [[enc(clave(K)), $:, enc(V)] || {K, V} <- maps:to_list(M)],
  [${, lists:join($,, Pares), $}];
enc(L) when is_list(L) ->
  case io_lib:printable_unicode_list(L) andalso L =/= [] of
    true  -> enc(unicode:characters_to_binary(L));
    false -> [$[, lists:join($,, [enc(E) || E <- L]), $]]
  end;
enc(Otro) -> enc(iolist_to_binary(io_lib:format("~p", [Otro]))).

clave(K) when is_binary(K) -> K;
clave(K) when is_atom(K) -> atom_to_binary(K, utf8);
clave(K) -> iolist_to_binary(io_lib:format("~p", [K])).

esc(B) -> << <<(esc_c(C))/binary>> || <<C/utf8>> <= B >>.
esc_c($")  -> <<"\\\"">>;
esc_c($\\) -> <<"\\\\">>;
esc_c($\n) -> <<"\\n">>;
esc_c($\r) -> <<"\\r">>;
esc_c($\t) -> <<"\\t">>;
esc_c(C) when C < 32 -> iolist_to_binary(io_lib:format("\\u~4.16.0b", [C]));
esc_c(C) -> <<C/utf8>>.

%%% ---------------------------------------------------------------- decode
decode(Bin) when is_binary(Bin) ->
  try
    {V, Resto} = valor(ws(Bin)),
    <<>> = ws(Resto),
    {ok, V}
  catch _:_ -> {error, json_invalido}
  end.

ws(<<C, R/binary>>) when C =:= $\s; C =:= $\n; C =:= $\r; C =:= $\t -> ws(R);
ws(B) -> B.

valor(<<${, R/binary>>) -> objeto(ws(R), #{});
valor(<<$[, R/binary>>) -> arreglo(ws(R), []);
valor(<<$", R/binary>>) -> cadena(R, <<>>);
valor(<<"true", R/binary>>)  -> {true, R};
valor(<<"false", R/binary>>) -> {false, R};
valor(<<"null", R/binary>>)  -> {null, R};
valor(B) -> numero(B).

objeto(<<$}, R/binary>>, M) -> {M, R};
objeto(<<$", R/binary>>, M) ->
  {K, R1} = cadena(R, <<>>),
  <<$:, R2/binary>> = ws(R1),
  {V, R3} = valor(ws(R2)),
  M2 = M#{K => V},
  case ws(R3) of
    <<$,, R4/binary>> -> objeto(ws(R4), M2);
    <<$}, R4/binary>> -> {M2, R4}
  end.

arreglo(<<$], R/binary>>, Acc) -> {lists:reverse(Acc), R};
arreglo(B, Acc) ->
  {V, R1} = valor(B),
  case ws(R1) of
    <<$,, R2/binary>> -> arreglo(ws(R2), [V | Acc]);
    <<$], R2/binary>> -> {lists:reverse([V | Acc]), R2}
  end.

cadena(<<$", R/binary>>, Acc) -> {Acc, R};
cadena(<<$\\, $n, R/binary>>, Acc) -> cadena(R, <<Acc/binary, $\n>>);
cadena(<<$\\, $t, R/binary>>, Acc) -> cadena(R, <<Acc/binary, $\t>>);
cadena(<<$\\, $r, R/binary>>, Acc) -> cadena(R, <<Acc/binary, $\r>>);
cadena(<<$\\, $u, H:4/binary, R/binary>>, Acc) ->
  C = binary_to_integer(H, 16),
  cadena(R, <<Acc/binary, C/utf8>>);
cadena(<<$\\, C, R/binary>>, Acc) -> cadena(R, <<Acc/binary, C>>);
cadena(<<C, R/binary>>, Acc) -> cadena(R, <<Acc/binary, C>>).

numero(B) ->
  {Txt, R} = tomar_num(B, <<>>),
  V = case binary:match(Txt, [<<".">>, <<"e">>, <<"E">>]) of
        nomatch -> binary_to_integer(Txt);
        _ -> binary_to_float(normalizar(Txt))
      end,
  {V, R}.

tomar_num(<<C, R/binary>>, Acc)
  when (C >= $0 andalso C =< $9); C =:= $-; C =:= $+; C =:= $.; C =:= $e; C =:= $E ->
  tomar_num(R, <<Acc/binary, C>>);
tomar_num(R, Acc) -> {Acc, R}.

%% "3e2" no es valido para binary_to_float; se convierte a "3.0e2".
normalizar(T) ->
  case binary:match(T, <<".">>) of
    nomatch -> binary:replace(binary:replace(T, <<"e">>, <<".0e">>), <<"E">>, <<".0e">>);
    _ -> T
  end.
