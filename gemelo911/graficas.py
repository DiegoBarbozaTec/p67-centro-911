"""Gráficas del gemelo 911, llamadas DESDE Prolog con Janus (py_call/2).

Este módulo no decide nada: recibe listas ya deducidas por Prolog (puntos,
tramos, unidades, la ruta elegida, los tiempos de llegada) y solo las dibuja.
Usa la API de objetos de matplotlib (Figure), sin pyplot, para funcionar en
un servidor sin pantalla.
"""

from matplotlib.figure import Figure

FONDO = "#0f1216"
TEXTO = "#e6e9ef"
TENUE = "#3a4350"
ESTADO = {  # color por estado de la unidad
    "disponible": "#3fb950",
    "despachada": "#d29922",
    "en_camino": "#d29922",
    "en_escena": "#58a6ff",
    "trasladando": "#a371f7",
    "fuera_de_servicio": "#f85149",
}
PRIORIDAD = {1: "#f85149", 2: "#d29922", 3: "#58a6ff"}


def _ejes(titulo, ancho=9, alto=5.6):
    fig = Figure(figsize=(ancho, alto), facecolor=FONDO, layout="constrained")
    ax = fig.subplots()
    ax.set_facecolor(FONDO)
    ax.set_title(titulo, color=TEXTO, fontsize=13, loc="left", pad=12)
    ax.tick_params(colors=TEXTO)
    for lado in ("top", "right"):
        ax.spines[lado].set_visible(False)
    for lado in ("bottom", "left"):
        ax.spines[lado].set_color(TENUE)
    return fig, ax


def mapa(titulo, puntos, tramos, unidades, incidentes, ruta, archivo):
    """Dibuja la red de calles.

    puntos:     [[nombre, x, y], ...]
    tramos:     [[a, b, segundos, estado], ...]   estado: normal | lento | cerrado
    unidades:   [[id, estado, punto], ...]
    incidentes: [[id, punto, prioridad], ...]
    ruta:       [punto, punto, ...]  (la ruta elegida, puede ir vacía)
    """
    pos = {p: (x, y) for p, x, y in puntos}
    fig, ax = _ejes(titulo)
    ax.axis("off")
    ax.axvspan(9.15, 9.85, color="#3b2a1a", alpha=0.55, zorder=0)
    ax.text(9.5, 10.1, "cañón", color="#c69c6d", ha="center", fontsize=9)

    en_ruta = set(zip(ruta, ruta[1:])) | set(zip(ruta[1:], ruta))
    for a, b, seg, estado in tramos:
        (x1, y1), (x2, y2) = pos[a], pos[b]
        color, ancho, estilo = TENUE, 1.6, "-"
        if estado == "lento":
            color, estilo = "#d29922", "--"
        if estado == "cerrado":
            color, estilo = "#f85149", ":"
        if (a, b) in en_ruta:
            color, ancho = "#e6e9ef", 3.4
        ax.plot([x1, x2], [y1, y2], estilo, color=color, lw=ancho, zorder=1)
        ax.text((x1 + x2) / 2, (y1 + y2) / 2 + 0.15, f"{seg // 60}′", color="#8b949e",
                fontsize=7, ha="center", zorder=2)

    for p, (x, y) in pos.items():
        ax.scatter([x], [y], s=60, color="#1c2128", edgecolor=TENUE, zorder=3)
        ax.text(x, y - 0.45, p, color="#8b949e", fontsize=8.5, ha="center", zorder=3)

    for inc, p, prio in incidentes:
        x, y = pos[p]
        ax.scatter([x], [y], marker="D", s=170, color=PRIORIDAD.get(prio, "#888"),
                   edgecolor="black", zorder=5)
        ax.text(x + 0.25, y + 0.25, f"{inc} P{prio}", color=TEXTO, fontsize=9, zorder=6)

    vistos = {}
    for u, estado, p in unidades:
        x, y = pos[p]
        k = vistos.get(p, 0)
        vistos[p] = k + 1
        dx, dy = -0.35 + 0.3 * (k % 3), -0.2 - 0.3 * (k // 3)
        ax.scatter([x + dx], [y + dy - 0.5], s=90, color=ESTADO.get(estado, "#888"),
                   edgecolor="black", zorder=4)
        ax.text(x + dx, y + dy - 0.85, u, color=TEXTO, fontsize=7.5, ha="center", zorder=4)

    ax.set_xlim(0.5, 20.5)
    ax.set_ylim(1.5, 10.8)
    fig.savefig(archivo, dpi=150)
    return archivo


def llegadas(titulo, unidades, segundos, meta, elegida, archivo):
    """Barras horizontales con el tiempo de llegada de cada unidad y la meta."""
    fig, ax = _ejes(titulo, 9, 4.2)
    minutos = [s / 60 for s in segundos]
    colores = ["#3fb950" if u == elegida else ("#d29922" if s <= meta else "#6e7681")
               for u, s in zip(unidades, segundos)]
    ax.barh(unidades[::-1], minutos[::-1], color=colores[::-1])
    ax.axvline(meta / 60, color="#f85149", lw=2, ls="--")
    ax.text(meta / 60, len(unidades) - 0.4, f" meta {meta // 60} min", color="#f85149", fontsize=9)
    ax.set_xlabel("minutos para llegar (por calles)", color=TEXTO)
    fig.savefig(archivo, dpi=120)
    return archivo
