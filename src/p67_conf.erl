%%% Utilidades de configuracion y de tiempo simulado.
-module(p67_conf).

-export([get/2, ms/1, ahora_ms/0, minutos_entre/2, data_dir/0]).

-define(APP, p67_centro_de_emergencias_911).

get(Clave, Defecto) ->
  application:get_env(?APP, Clave, Defecto).

%% Convierte minutos simulados a milisegundos reales.
ms(Minutos) ->
  max(1, round(Minutos * get(escala_ms_por_min, 250))).

ahora_ms() ->
  erlang:system_time(millisecond).

%% Minutos simulados transcurridos entre dos marcas de tiempo reales (ms).
minutos_entre(DesdeMs, HastaMs) ->
  (HastaMs - DesdeMs) / get(escala_ms_por_min, 250).

data_dir() ->
  Dir = get(data_dir, "data"),
  ok = filelib:ensure_dir(filename:join(Dir, "x")),
  Dir.
