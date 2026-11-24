:- encoding(utf8).
% Carga el gemelo completo:  swipl gemelo.pl
:- ensure_loaded(hechos).
:- ensure_loaded(escenarios).
:- ensure_loaded(reglas).
:- ensure_loaded(explica).
:- initialization(cargar_escenario(s1_retiro)).
