%%% Geografia simplificada de Tijuana para calcular "la unidad mas cercana".
%%%
%%% El mapa es un rectangulo de 20 km (oeste-este) por 12 km (sur-norte).
%%% Un canon corta la ciudad en x = 10 km y solo se cruza por dos puentes
%%% (y = 3 km y y = 9 km). Las calles forman cuadricula, asi que la ruta se mide
%%% con distancia Manhattan, no en linea recta.
%%%
%%% Por eso "mas cercana" = MENOR TIEMPO DE VIAJE, no menor distancia:
%%% una ambulancia a 1 km pero del otro lado del canon puede tardar mas que
%%% una a 3 km del mismo lado.
-module(p67_geo).

-export([distancia_recta/2, ruta_km/2, eta_min/3, velocidad_kmh/1,
         lado/1, puentes/0, limites/0, punto_aleatorio/0, interpolar/3]).

-define(CANON_X, 10.0).

limites() -> {20.0, 12.0}.

puentes() -> [{?CANON_X, 3.0}, {?CANON_X, 9.0}].

distancia_recta({X1, Y1}, {X2, Y2}) ->
  math:sqrt(math:pow(X1 - X2, 2) + math:pow(Y1 - Y2, 2)).

manhattan({X1, Y1}, {X2, Y2}) ->
  abs(X1 - X2) + abs(Y1 - Y2).

lado({X, _}) when X < ?CANON_X -> oeste;
lado(_) -> este.

%% Kilometros reales de ruta, cruzando por el mejor puente si hace falta.
ruta_km(Origen, Destino) ->
  case lado(Origen) =:= lado(Destino) of
    true  -> manhattan(Origen, Destino);
    false -> lists:min([manhattan(Origen, P) + manhattan(P, Destino) || P <- puentes()])
  end.

%% Velocidad promedio en ciudad por tipo de unidad (km/h).
velocidad_kmh(ambulancia)       -> 50;
velocidad_kmh(patrulla)         -> 60;
velocidad_kmh(bomberos)         -> 40;
velocidad_kmh(proteccion_civil) -> 45.

%% Tiempo estimado de llegada en minutos simulados.
eta_min(TipoUnidad, Origen, Destino) ->
  ruta_km(Origen, Destino) / velocidad_kmh(TipoUnidad) * 60.

punto_aleatorio() ->
  {W, H} = limites(),
  {redondear(rand:uniform() * W), redondear(rand:uniform() * H)}.

%% Posicion intermedia (fraccion 0..1) para dibujar la unidad en camino.
interpolar({X1, Y1}, {X2, Y2}, F0) ->
  F = min(1.0, max(0.0, F0)),
  {redondear(X1 + (X2 - X1) * F), redondear(Y1 + (Y2 - Y1) * F)}.

redondear(V) -> round(V * 100) / 100.
