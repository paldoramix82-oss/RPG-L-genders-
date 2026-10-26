#!/usr/bin/env python3
"""Génère les cartes prédéfinies (data/maps/*.json).

Codes de terrain : voir scripts/game/map_data.gd (TERRAINS).
Usage : python3 tools/generate_maps.py   (nécessite numpy et scipy pour les grandes cartes)
"""
import json, math, os, random

import numpy as np
from scipy.ndimage import zoom as nd_zoom

OUT = os.path.join(os.path.dirname(__file__), "..", "data", "maps")


class Grid:
    def __init__(self, w, h, fill="."):
        self.w, self.h = w, h
        self.c = [[fill] * w for _ in range(h)]

    def set(self, x, y, v):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.c[y][x] = v

    def get(self, x, y):
        return self.c[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def rect(self, x0, y0, x1, y1, v):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, v)

    def frame(self, x0, y0, x1, y1, v):
        for x in range(x0, x1 + 1):
            self.set(x, y0, v); self.set(x, y1, v)
        for y in range(y0, y1 + 1):
            self.set(x0, y, v); self.set(x1, y, v)

    def disc(self, cx, cy, r, v, rng=None, rough=0.0):
        for y in range(self.h):
            for x in range(self.w):
                d = math.hypot(x - cx, (y - cy) * 1.0)
                rr = r + (rng.uniform(-rough, rough) if rng else 0)
                if d <= rr:
                    self.set(x, y, v)

    def line(self, pts, v, width=0):
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = max(abs(x1 - x0), abs(y1 - y0), 1)
            for i in range(n + 1):
                x = round(x0 + (x1 - x0) * i / n); y = round(y0 + (y1 - y0) * i / n)
                for dx in range(-width, width + 1):
                    for dy in range(-width, width + 1):
                        self.set(x + dx, y + dy, v)

    def scatter(self, v, p, rng, only=None):
        for y in range(self.h):
            for x in range(self.w):
                if rng.random() < p and (only is None or self.c[y][x] in only):
                    self.c[y][x] = v

    def rows(self):
        return ["".join(r) for r in self.c]


def save(mid, name, desc, universe, g, spawn, labels=(), tokens=()):
    data = {
        "id": mid, "name": name, "description": desc, "universe": universe,
        "w": g.w, "h": g.h, "rows": g.rows(), "spawn": {"x": spawn[0], "y": spawn[1]},
        "labels": [dict(x=x, y=y, text=t, hidden=h) for (x, y, t, h) in labels],
        "tokens": [dict(name=n, kind=k, x=x, y=y, color=c, hp=hp, hp_max=hp, hidden=h) for (n, k, x, y, c, hp, h) in tokens],
    }
    with open(os.path.join(OUT, mid + ".json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)


def valombre():
    rng = random.Random(1)
    g = Grid(34, 22, ".")
    g.scatter("f", 0.08, rng)
    g.rect(0, 0, 33, 2, "f"); g.rect(0, 19, 33, 21, "f"); g.scatter(".", 0.25, rng, only="f")
    g.line([(20, 0), (19, 6), (21, 11), (20, 16), (22, 21)], "w", 1)
    g.rect(4, 6, 17, 16, "p")
    g.line([(0, 11), (33, 11)], "r"); g.line([(11, 3), (11, 19)], "r")
    for x in range(19, 24):
        if g.get(x, 11) == "w" or g.get(x, 11) == "r":
            g.set(x, 11, "B")
    g.rect(19, 10, 23, 12, "w"); g.rect(18, 11, 23, 11, "B")
    g.rect(5, 7, 8, 9, "R"); g.rect(13, 7, 16, 9, "b"); g.rect(5, 13, 9, 15, "R")
    g.rect(13, 13, 16, 15, "R"); g.rect(9, 7, 10, 8, "R")
    g.scatter("y", 0.05, rng, only=".")
    g.rect(26, 4, 31, 8, "c"); g.scatter("x", 0.2, rng, only="c")
    g.rect(26, 14, 30, 17, "k")
    g.rect(10, 10, 12, 12, "p"); g.set(11, 11, "a")
    labels = [(6, 8, "Taverne du Corbeau Rieur", False), (14, 8, "Temple aux cloches", False),
              (7, 14, "Forge", False), (14, 14, "Maison du bourgmestre", False), (11, 12, "Place du puits", False),
              (28, 6, "Champ calciné", False), (28, 15, "Marais", False), (31, 11, "Vers la forêt", False),
              (28, 5, "Cendres encore tièdes : quelque chose a brûlé ici sans flammes", True)]
    tokens = [("Garde de Valombre", "npc", 3, 11, "#6f7f9a", 12, False)]
    save("valombre_ville", "Valombre — la petite ville", "Bourg fluvial sous une pluie de cendres. Taverne, temple, forge, place du puits.", "*", g, (2, 11), labels, tokens)


def taverne():
    g = Grid(22, 15, "d")
    g.frame(0, 0, 21, 14, "#")
    g.rect(14, 1, 14, 9, "#"); g.set(14, 5, "d")
    g.rect(15, 10, 20, 10, "#"); g.set(17, 10, "d")
    g.rect(2, 2, 10, 2, "t")
    for (x, y) in [(3, 6), (7, 6), (3, 10), (7, 10), (11, 9)]:
        g.rect(x, y, x + 1, y, "t")
    g.rect(16, 2, 19, 3, "t")
    g.rect(15, 12, 20, 13, "o"); g.set(19, 12, "x")
    g.set(10, 14, "d"); g.set(11, 14, "d")
    labels = [(6, 1, "Comptoir", False), (17, 1, "Cuisine", False), (17, 13, "Cave", False),
              (11, 13, "Entrée", False), (19, 12, "Trappe cachée sous un tonneau", True)]
    tokens = [("Bertrand le tavernier", "npc", 6, 3, "#a77d4c", 10, False),
              ("Voyageur encapuchonné", "npc", 12, 9, "#55506a", 14, False)]
    save("taverne_corbeau", "Taverne du Corbeau Rieur", "Intérieur de taverne : salle commune, comptoir, cuisine et cave.", "*", g, (10, 12), labels, tokens)


def foret():
    rng = random.Random(3)
    g = Grid(34, 22, "f")
    g.scatter("F", 0.35, rng); g.scatter(".", 0.12, rng)
    g.disc(16, 11, 4.2, ".", rng, 0.8); g.disc(16, 11, 2.0, "c")
    g.line([(0, 15), (8, 13), (16, 11), (25, 8), (33, 6)], "r")
    g.line([(5, 0), (6, 6), (4, 12), (7, 21)], "w")
    g.disc(27, 17, 2.5, "k", rng, 0.6)
    g.set(16, 11, "a"); g.rect(24, 2, 26, 3, "m")
    labels = [(16, 9, "Clairière des cendres", False), (26, 2, "Rochers moussus", False),
              (16, 11, "Pierre levée — cristal noirci (AEC ?)", True)]
    tokens = [("Loup cendré", "monster", 22, 14, "#8a4a3c", 9, True), ("Loup cendré", "monster", 23, 15, "#8a4a3c", 9, True)]
    save("foret_cendres", "Forêt des Cendres", "Forêt dense traversée d'un chemin, avec une clairière brûlée et un ruisseau.", "*", g, (1, 15), labels, tokens)


def ruines():
    rng = random.Random(5)
    g = Grid(30, 20, ".")
    g.scatter("f", 0.1, rng)
    g.rect(6, 4, 23, 15, "o")
    g.frame(6, 4, 23, 15, "#")
    g.scatter("x", 0.18, rng, only="o#")
    g.rect(14, 4, 15, 4, "o"); g.rect(6, 9, 6, 10, "x")
    g.rect(13, 7, 16, 9, "#"); g.rect(14, 8, 15, 8, "v"); g.set(14, 9, "o")
    for x in (9, 20):
        for y in (7, 12):
            g.set(x, y, "#")
    g.rect(14, 0, 15, 3, "r")
    labels = [(14, 3, "Portail effondré", False), (14, 6, "Autel fendu", False),
              (14, 8, "Escalier vers la crypte", True)]
    tokens = [("Gardien de pierre", "monster", 18, 12, "#7d7a70", 30, True)]
    save("ruines_temple", "Ruines de l'ancien temple", "Temple effondré avec un autel central et une crypte cachée.", "*", g, (14, 1), labels, tokens)


def arene():
    g = Grid(22, 22, "v")
    g.disc(10.5, 10.5, 10.5, "#"); g.disc(10.5, 10.5, 9.3, "s")
    for (x, y) in [(7, 7), (14, 7), (7, 14), (14, 14)]:
        g.set(x, y, "#")
    g.set(10, 1, "o"); g.set(11, 1, "o"); g.set(10, 20, "o"); g.set(11, 20, "o")
    save("arene", "Arène", "Arène circulaire pour les combats, quatre piliers.", "*", g, (10, 18), [(10, 1, "Porte nord", False), (10, 20, "Porte sud", False)])


def vierge():
    g = Grid(24, 16, ".")
    save("vierge", "Carte vierge", "Une prairie vide, prête à être peinte par le MJ.", "*", g, (2, 8))


def shima():
    rng = random.Random(7)
    g = Grid(34, 22, "p")
    g.rect(0, 0, 4, 21, "w"); g.rect(5, 0, 5, 21, "s")
    for y in range(1, 21, 4):
        for x in range(8, 32, 6):
            g.rect(x, y, x + 3, y + 2, "b")
    g.line([(6, 10), (33, 10)], "r", 0); g.line([(19, 0), (19, 21)], "r", 0)
    g.rect(22, 12, 31, 20, "."); g.frame(22, 12, 31, 20, "#"); g.set(26, 12, "."); g.rect(24, 14, 29, 18, "s")
    g.scatter("f", 0.15, rng, only=".")
    g.rect(13, 13, 17, 16, "a"); g.frame(13, 13, 17, 16, "b")
    labels = [(15, 14, "QG de la magie", False), (26, 13, "Terrain d'entraînement — Division de l'Encre", False),
              (2, 10, "Mer Occidentale", False), (19, 0, "Vers les autres divisions", False)]
    save("shima_encre", "Shima — Division de l'Encre", "Quartier de Shima (RAC) : le QG de la magie et le terrain d'entraînement d'une division.", "legenders", g, (6, 10), labels)


def ile():
    rng = random.Random(9)
    g = Grid(36, 24, "W")
    g.disc(18, 12, 10.5, "w", rng, 1.0); g.disc(18, 12, 9.2, "s", rng, 1.0); g.disc(18, 12, 7.8, "f", rng, 1.2)
    g.scatter("F", 0.3, rng, only="f"); g.disc(20, 10, 2.6, "m", rng, 0.5); g.set(20, 10, "n")
    g.disc(12, 15, 1.6, "k"); g.line([(9, 12), (14, 11), (20, 13), (26, 12)], "r")
    g.disc(25, 16, 1.2, "w")
    labels = [(10, 12, "Point d'arrivée aléatoire", False), (20, 9, "Pic central", False),
              (25, 15, "Point de rendez-vous (10 jours max)", True)]
    tokens = [("Ombré chapardeur", "npc", 14, 14, "#2a2733", 6, True), ("Bête de l'île", "monster", 22, 15, "#7b5a3a", 25, True)]
    save("ile_test", "Île du test de survie", "L'île hostile de la 2e épreuve du test de la magie : atteindre le rendez-vous caché.", "legenders", g, (9, 12), labels, tokens)


def caldeira():
    rng = random.Random(11)
    g = Grid(32, 20, "c")
    g.scatter("m", 0.12, rng); g.disc(16, 10, 6, "l", rng, 1.0); g.disc(16, 10, 3, "x")
    g.line([(16, 10), (22, 3), (31, 1)], "l"); g.line([(0, 15), (8, 13), (12, 12)], "r")
    g.rect(2, 2, 6, 5, "b"); g.frame(1, 1, 7, 6, "#"); g.set(4, 6, "r")
    save("grande_caldeira", "Grande Caldeira — colonie Volcano", "La cicatrice de Sol'fyr : rivières de lave, cendres, et la colonie scientifique Volcano.", "legenders", g, (0, 15),
         [(4, 3, "Volcano (colonie scientifique)", False), (16, 10, "Cœur du brasier", False)])


# ---------------------------------------------------------------------------
# Grandes cartes (campagnes longues)
# ---------------------------------------------------------------------------

def noise(w, h, scale, seed, octaves=4):
    """Bruit de valeur lissé dans [0, 1]."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = max(2, int(scale * 2 ** o))
        grid = rng.random((cells + 3, cells + 3))
        big = nd_zoom(grid, ((h + 8) / cells, (w + 8) / cells), order=3)
        out += big[:h, :w] * amp
        total += amp
        amp *= 0.5
    out /= total
    return (out - out.min()) / (out.max() - out.min() + 1e-9)


def river(g, pts, width=1, code="w", rng=None):
    """Rivière qui serpente entre des points de passage."""
    path = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0), 1) * 2
        for i in range(n + 1):
            k = i / n
            wob = math.sin(k * math.pi * 3 + x0) * 1.2 if rng else 0
            path.append((x0 + (x1 - x0) * k + wob, y0 + (y1 - y0) * k))
    for x, y in path:
        for dx in range(-width, width + 1):
            for dy in range(-width, width + 1):
                if dx * dx + dy * dy <= width * width + 1:
                    g.set(int(round(x + dx)), int(round(y + dy)), code)


def town(g, x0, y0, x1, y1, rng, street_every=4):
    """Quartier : pavés, pâtés de maisons aux toits variés, rues en grille."""
    g.rect(x0, y0, x1, y1, "p")
    for y in range(y0 + 1, y1, street_every):
        for x in range(x0 + 1, x1, street_every):
            w = rng.randint(1, street_every - 2)
            h = rng.randint(1, street_every - 2)
            g.rect(x, y, min(x + w, x1 - 1), min(y + h, y1 - 1), "R" if rng.random() < 0.6 else "b")


def region_valombre():
    rng = random.Random(201)
    W, H = 96, 64
    g = Grid(W, H, ".")
    hn = noise(W, H, 3, 1)
    fn = noise(W, H, 5, 2)
    for y in range(H):
        for x in range(W):
            e, f = hn[y, x], fn[y, x]
            if y < 12 and e > 0.55:
                g.set(x, y, "m" if e > 0.68 else "h")
            elif f > 0.62 and x > 48:
                g.set(x, y, "F" if f > 0.75 else "f")
            elif f > 0.7:
                g.set(x, y, "f")
            elif e < 0.18 and y > 44:
                g.set(x, y, "k")
    g.scatter("y", 0.03, rng, only=".")
    g.scatter("q", 0.02, rng, only="h")
    for y in range(0, 6):
        for x in range(W):
            if hn[y, x] > 0.45:
                g.set(x, y, "n" if hn[y, x] > 0.7 else "m")
    river(g, [(30, 0), (28, 14), (33, 26), (30, 38), (36, 50), (34, 63)], 1, rng=rng)
    g.disc(70, 46, 5, "w", rng, 1.0); g.disc(70, 46, 3, "W")
    town(g, 14, 22, 27, 34, rng)
    g.rect(19, 27, 22, 29, "p"); g.set(20, 28, "a")
    g.rect(36, 22, 38, 34, "z")
    for (fx, fy) in [(8, 36), (38, 18), (10, 18)]:
        g.rect(fx, fy, fx + 5, fy + 3, "z")
    for x in range(26, 37):
        if g.get(x, 28) == "w":
            g.set(x, 28, "B")
    g.line([(0, 28), (14, 28)], "r"); g.line([(27, 28), (60, 30), (80, 22), (95, 20)], "r")
    g.line([(20, 34), (22, 50), (44, 58), (60, 63)], "r"); g.line([(20, 22), (24, 8)], "r")
    g.disc(64, 32, 4, ".", rng, 0.6); g.disc(64, 32, 2, "c"); g.set(64, 32, "a")
    g.rect(78, 8, 90, 16, "o"); g.frame(78, 8, 90, 16, "#"); g.scatter("x", 0.25, rng, only="o#"); g.rect(83, 11, 85, 12, "v")
    g.rect(52, 4, 54, 5, "u"); g.set(53, 6, "u")
    for (hx, hy) in [(44, 44), (8, 52)]:
        g.rect(hx, hy, hx + 5, hy + 4, ".")
        for i in range(3):
            g.rect(hx + i * 2, hy + 1, hx + i * 2, hy + 1, "R")
    labels = [(20, 21, "Valombre", False), (20, 30, "Place du puits", False), (64, 28, "Clairière des cendres", False),
              (84, 7, "Ruines de l'ancien temple", False), (84, 12, "Crypte", True), (53, 3, "Grotte du Murmure", False),
              (70, 41, "Lac Gris", False), (46, 43, "Hameau des Saules", False), (10, 51, "Les Tourbières", False),
              (64, 33, "Pierre levée — cristal noirci", True), (30, 12, "Moulin abandonné", False), (8, 26, "Route de la capitale", False)]
    save("region_valombre", "Région de Valombre (grande carte)", "La ville, ses campagnes, la forêt des Cendres, les ruines, le lac et les montagnes : de quoi tenir une longue campagne.", "*", g, (2, 28), labels)


def kurtzuma():
    rng = random.Random(301)
    W, H = 120, 80
    g = Grid(W, H, "W")
    n = noise(W, H, 4, 11)
    for y in range(H):
        for x in range(W):
            dx, dy = (x - 66) / 40.0, (y - 40) / 31.0
            d = math.sqrt(dx * dx + dy * dy) - (n[y, x] - 0.5) * 0.55
            if d < 1.0:
                g.set(x, y, ".")
            elif d < 1.12:
                g.set(x, y, "w")
    # Forêt-Monde à l'ouest, Désert de Cristal au nord, Grande Caldeira au sud
    for y in range(H):
        for x in range(W):
            if x < 16 and 8 < y < 70 and n[y, x] > 0.3:
                g.set(x, y, "F" if n[y, x] > 0.45 else "f")
            if y < 6 and 30 < x < 100 and n[y, x] > 0.35:
                g.set(x, y, "g" if n[y, x] > 0.55 else "n")
    g.disc(66, 76, 3.5, "c", rng, 0.6); g.disc(66, 76, 1.6, "l")
    # Régions
    for y in range(H):
        for x in range(W):
            if g.get(x, y) != ".":
                continue
            v = n[y, x]
            if y < 22 and x > 82:
                g.set(x, y, "n" if v > 0.4 else "g")
            elif y < 22 and 66 < x <= 82:
                g.set(x, y, "s")
            elif y < 22:
                g.set(x, y, "h" if v > 0.6 else ".")
            elif 58 <= x <= 72 and 24 <= y <= 36:
                g.set(x, y, "s")
            elif x < 44 and 32 <= y <= 52:
                g.set(x, y, "z" if v > 0.55 else ".")
            elif x > 92:
                g.set(x, y, "h" if v > 0.5 else ".")
            elif y > 54:
                g.set(x, y, "f" if v > 0.62 else ".")
    # Croissant montagneux
    for i in range(80):
        k = i / 79
        ang = math.pi * (0.15 + 1.25 * k)
        cx, cy = 68 + 20 * math.cos(ang), 42 - 18 * math.sin(ang)
        for dx in range(-2, 3):
            for dy in range(-1, 2):
                if g.get(int(cx + dx), int(cy + dy)) not in (None, "W", "w"):
                    g.set(int(cx + dx), int(cy + dy), "n" if (abs(dx) < 1 and 0.35 < k < 0.65) else "m")
    for x in range(88, 92):
        for y in range(26, 56):
            if g.get(x, y) not in ("W", "w"):
                g.set(x, y, "m")
    g.disc(64, 58, 5, "w", rng, 1.2); g.disc(64, 58, 3, "W")  # mer intérieure chaude
    river(g, [(50, 22), (46, 34), (40, 44), (34, 52)], 0, rng=rng)
    river(g, [(80, 46), (76, 56), (70, 62)], 0, rng=rng)
    # Villes
    cities = [(31, 26, "Shima"), (38, 44, "Capitale de Trèfle"), (52, 12, "Citadelle de Pik"), (98, 40, "Karoh"),
              (80, 64, "Keurd"), (64, 30, "Alsaora"), (40, 30, "Napo"), (40, 22, "Mako")]
    for cx, cy, name in cities:
        g.rect(cx - 1, cy - 1, cx + 1, cy + 1, "p"); g.set(cx, cy, "R"); g.set(cx - 1, cy, "R")
    g.line([(31, 26), (40, 30), (52, 12)], "r"); g.line([(40, 30), (64, 30), (80, 40), (98, 40)], "r"); g.line([(38, 44), (31, 26)], "r")
    g.line([(64, 30), (70, 48), (80, 64)], "r")
    # Îles
    for (ix, iy, code) in [(24, 44, "a"), (22, 40, "a"), (20, 46, "a"), (110, 58, "s"), (106, 66, "s"), (50, 6, "n"), (24, 24, ".")]:
        g.disc(ix, iy, 1.6, code); g.set(ix, iy, code)
    g.disc(108, 30, 3, "a"); g.disc(108, 30, 1, "o")  # dômes de l'Abîme
    labels = [(56, 15, "PIK", False), (44, 27, "RAC", False), (31, 24, "Shima", False), (38, 46, "TRÈFLE", False),
              (98, 37, "KAROH", False), (82, 61, "KEURD", False), (64, 27, "Alsaora", False), (40, 32, "Napo", False),
              (24, 22, "Mapo", False), (8, 30, "Forêt-Monde", False), (65, 2, "Désert de Cristal", False),
              (110, 26, "Abîme Englouti", False), (66, 73, "Grande Caldeira", False), (64, 54, "Mer intérieure", False),
              (22, 49, "Îles Flottantes", False), (110, 56, "Îles Bawlies", False), (106, 69, "Îles Hier", False),
              (50, 4, "Îles Enneigées", False), (40, 20, "Mako", False), (92, 58, "Lidaknie", False),
              (76, 20, "Lac Retourné", True)]
    save("kurtzuma_monde", "Kurtzuma — carte du monde", "Le continent, ses nations, ses mers et les quatre cicatrices des Légenders. Idéale pour les voyages.", "legenders", g, (31, 28), labels)


def shima_capitale():
    rng = random.Random(401)
    W, H = 96, 64
    g = Grid(W, H, ".")
    g.rect(0, 0, 9, H - 1, "W"); g.rect(10, 0, 11, H - 1, "w"); g.rect(12, 0, 13, H - 1, "s")
    for y in (14, 30, 46):
        g.rect(8, y, 16, y + 1, "B")
    cx, cy = 54, 32
    town(g, 18, 6, 90, 58, rng, 5)
    for y in range(H):
        for x in range(14, W):
            d = math.hypot(x - cx, (y - cy) * 1.4)
            if 22 < d < 25:
                g.set(x, y, "r")
    g.disc(cx, cy, 8, "p"); g.disc(cx, cy, 4, "y"); g.rect(cx - 2, cy - 2, cx + 2, cy + 2, "R"); g.set(cx, cy, "a")
    for i in range(13):
        a = 2 * math.pi * i / 13
        dx, dy = int(cx + 31 * math.cos(a)), int(cy + 22 * math.sin(a))
        g.disc(dx, dy, 3.2, "." if i % 3 else "y"); g.rect(dx - 1, dy - 1, dx + 1, dy, "b")
    g.line([(14, 32), (cx - 8, 32)], "r"); g.line([(cx, 0), (cx, 23)], "r"); g.line([(cx, 41), (cx, 63)], "r")
    river(g, [(95, 10), (80, 20), (70, 22)], 0, rng=rng)
    labels = [(cx, cy - 3, "QG de la magie", False), (12, 14, "Port", False), (6, 30, "Mer Occidentale", False)]
    for i in range(13):
        a = 2 * math.pi * i / 13
        dx, dy = int(cx + 31 * math.cos(a)), int(cy + 22 * math.sin(a))
        labels.append((dx, dy - 3, "Division de l'Encre" if i == 9 else "Division %d" % (i + 1), False))
    save("shima_capitale", "Shima — la capitale (grande carte)", "La capitale économique de la RAC : le QG de la magie au centre et les treize divisions de mages d'État en cercle.", "legenders", g, (14, 32), labels)


def foret_monde():
    rng = random.Random(501)
    W, H = 96, 72
    g = Grid(W, H, "F")
    n = noise(W, H, 5, 21)
    for y in range(H):
        for x in range(W):
            if n[y, x] < 0.28:
                g.set(x, y, "f")
            if n[y, x] < 0.14:
                g.set(x, y, ".")
            if n[y, x] > 0.86:
                g.set(x, y, "k")
    g.rect(84, 0, 95, H - 1, "w"); g.rect(88, 0, 95, H - 1, "W"); g.rect(80, 0, 83, H - 1, "s")
    g.rect(76, 30, 81, 36, "s"); g.rect(77, 31, 79, 33, "b")
    for k in range(6):
        y0 = rng.randint(4, H - 5)
        g.line([(0, y0), (rng.randint(20, 40), y0 + rng.randint(-8, 8)), (rng.randint(50, 75), y0 + rng.randint(-10, 10))], "h", 0)
    river(g, [(10, 0), (24, 20), (40, 34), (60, 40), (84, 44)], 1, rng=rng)
    for (vx, vy, name) in [(24, 50, "Village des hommes-lézards"), (50, 16, "Cité des branches"), (14, 30, "Clairière des Ombrés")]:
        g.disc(vx, vy, 4, "."); 
        for i in range(4):
            g.set(vx - 2 + i, vy + (i % 2), "d")
    for (ax, ay) in [(38, 58), (62, 24), (30, 10), (70, 60)]:
        g.disc(ax, ay, 1.4, "a")
    labels = [(78, 29, "Campement scientifique", False), (24, 46, "Village des hommes-lézards", False),
              (50, 12, "Cité des branches", False), (14, 26, "Clairière des Ombrés", False), (62, 21, "Veine d'AEC vert", False),
              (40, 61, "Racines-fleuves", False), (30, 8, "Champ magnétique : la technologie s'éteint", True)]
    save("foret_monde", "Forêt-Monde — la lisière (grande carte)", "La forêt primaire d'Aor'Mehn : micro-civilisations de monstres, racines géantes, veines d'AEC vert.", "legenders", g, (82, 34), labels)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for f in (valombre, taverne, foret, ruines, arene, vierge, shima, ile, caldeira,
              region_valombre, kurtzuma, shima_capitale, foret_monde):
        f()
    print("Cartes générées dans", os.path.abspath(OUT))
