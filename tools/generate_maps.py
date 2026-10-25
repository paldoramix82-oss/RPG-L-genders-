#!/usr/bin/env python3
"""Génère les cartes prédéfinies (data/maps/*.json).

Codes de terrain : voir scripts/game/map_data.gd (TERRAINS).
Usage : python3 tools/generate_maps.py
"""
import json, math, os, random

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
    g.rect(5, 7, 8, 9, "b"); g.rect(13, 7, 16, 9, "b"); g.rect(5, 13, 9, 15, "b")
    g.rect(13, 13, 16, 15, "b"); g.rect(9, 7, 10, 8, "b")
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


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for f in (valombre, taverne, foret, ruines, arene, vierge, shima, ile, caldeira):
        f()
    print("Cartes générées dans", os.path.abspath(OUT))
