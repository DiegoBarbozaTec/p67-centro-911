:- encoding(utf8).
% ============================================================================
%  hechos.pl — Lo que NO cambia durante el turno: la red de calles, las zonas,
%  la flota y los parámetros del modelo.
%  Proyecto #67 Centro de emergencias 911 · Gemelo digital (fase 2, Prolog)
%  Diego Antonio Barboza Carballo · 23212702
%
%  Lo que SÍ cambia (estado de unidades, incidentes, llamadas, reportes) está
%  en escenarios.pl como hechos dinámicos.
% ============================================================================

:- discontiguous tramo/3, coord/3, zona/2.

% ---------------------------------------------------------------------------
% RED DE CALLES — tramo(PuntoA, PuntoB, SegundosDeViaje). Doble sentido.
% Un cañón separa el oeste del centro; solo se cruza por dos puentes.
% La garita alarga los tramos que pasan por ella cuando hay fila.
% ---------------------------------------------------------------------------
tramo(playas,       canon_oeste,  240).
tramo(canon_oeste,  puente_norte, 180).
tramo(canon_oeste,  puente_sur,   300).
tramo(puente_norte, canon_este,   120).
tramo(puente_sur,   canon_este,   360).
tramo(canon_este,   centro,       180).
tramo(centro,       zona_rio,     240).
tramo(centro,       hospital,     300).
tramo(hospital,     zona_rio,     360).
tramo(zona_rio,     garita,       180).
tramo(garita,       otay,         300).
tramo(zona_rio,     otay,         420).

% Qué obstáculo cruza un tramo (para explicar las rutas).
cruza(canon_oeste, puente_norte, canon).
cruza(canon_oeste, puente_sur,   canon).
cruza(zona_rio,    garita,       garita).
cruza(garita,      otay,         garita).

% Coordenadas en km, solo para comparar con la "distancia en línea recta".
% Ninguna decisión usa línea recta: se decide por tiempo sobre la red.
coord(playas,        2.0, 5.0).
coord(canon_oeste,   9.0, 6.0).
coord(puente_norte,  9.5, 8.0).
coord(puente_sur,    9.5, 3.5).
coord(canon_este,   10.0, 6.0).
coord(centro,       13.0, 6.0).
coord(hospital,     14.0, 4.0).
coord(zona_rio,     15.0, 7.0).
coord(garita,       16.0, 9.5).
coord(otay,         19.0, 7.0).

% ZONAS (4) — zona(Punto, Zona).
zona(playas,       oeste).
zona(canon_oeste,  oeste).
zona(puente_norte, canon).
zona(puente_sur,   canon).
zona(canon_este,   canon).
zona(centro,       centro).
zona(hospital,     centro).
zona(zona_rio,     este).
zona(garita,       este).
zona(otay,         este).

% ---------------------------------------------------------------------------
% FLOTA — 8 unidades de 4 tipos. unidad(Unidad, Tipo).
% ---------------------------------------------------------------------------
unidad(amb1, ambulancia).
unidad(amb2, ambulancia).
unidad(amb3, ambulancia).
unidad(amb4, ambulancia).
unidad(pat1, patrulla).
unidad(pat2, patrulla).
unidad(bom1, bomberos).
unidad(pc1,  proteccion_civil).

% ---------------------------------------------------------------------------
% QUÉ PIDE CADA CLASE DE INCIDENTE — requiere(TipoIncidente, TipoUnidad, Cantidad).
% Supuesto propio (el problema original no lo fija).
% ---------------------------------------------------------------------------
requiere(medica,              ambulancia,       1).
requiere(herido,              ambulancia,       1).
requiere(accidente,           ambulancia,       1).
requiere(accidente,           patrulla,         1).
requiere(asalto,              patrulla,         1).
requiere(incendio,            bomberos,         1).
requiere(incendio_lesionados, bomberos,         1).
requiere(incendio_lesionados, ambulancia,       1).
requiere(atrapados,           proteccion_civil, 1).
requiere(atrapados,           ambulancia,       1).

% ---------------------------------------------------------------------------
% METAS DE LLEGADA (segundos de viaje) — supuestos declarados.
% P1: ~8 min soporte vital avanzado y ~4 min primera unidad de bomberos
%     (referencias internacionales citadas en el problema original).
% P2 y P3: definidas por el alumno.
% ---------------------------------------------------------------------------
meta(1, 480).
meta(2, 900).
meta(3, 1800).
meta_tipo(1, bomberos, 240).

% ---------------------------------------------------------------------------
% UMBRALES DEL MODELO — supuestos declarados.
% ---------------------------------------------------------------------------
umbral_silencio(300).        % más de 5 min sin reportar: "no se sabe" si avanza
radio_mismo_km(0.3).         % dos llamadas a ≤ 300 m pueden ser el mismo hecho
radio_distinto_km(1.5).      % a más de 1.5 km son hechos distintos
ventana_misma_s(600).        % dentro de 10 min pueden ser el mismo hecho
ventana_distinta_s(1800).    % a más de 30 min son hechos distintos

% Peso de dejar sin cubrir una necesidad, según la prioridad del incidente.
peso_prioridad(1, 1000).
peso_prioridad(2, 100).
peso_prioridad(3, 10).
