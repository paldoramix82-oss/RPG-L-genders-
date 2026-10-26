class_name MapGen
extends RefCounted
## Générateur de cartes : une carte jouable en un clic (forêt, village, donjon,
## grotte, plaine, île), que le MJ retouche ensuite au pinceau. Même graine,
## même carte.

const KINDS := {
	"foret": "Forêt (clairières, sentier, étang)",
	"village": "Village (rues, maisons, place, habitants)",
	"ville": "Ville (remparts, quartiers, marché, habitants)",
	"donjon": "Donjon (salles et couloirs)",
	"grotte": "Grotte (galeries naturelles)",
	"plaine": "Plaine (rivière, pont, champs)",
	"ile": "Île (plage, forêt, sommet)",
}
const SIZES := {"petite": Vector2i(24, 16), "moyenne": Vector2i(34, 22), "grande": Vector2i(48, 32),
	"tres_grande": Vector2i(72, 48), "immense": Vector2i(100, 68)}
const SIZE_NAMES := {"petite": "Petite (24 × 16)", "moyenne": "Moyenne (34 × 22)", "grande": "Grande (48 × 32)",
	"tres_grande": "Très grande (72 × 48)", "immense": "Immense (100 × 68)"}


## Renvoie {cells, w, h, spawn: {x, y}, labels: [{x, y, text, hidden}],
## buildings: [{id, x, y}]} — bâtiments prêts (Prefabs) à poser par l'hôte,
## centrés sur (x, y), avec leurs habitants.
static func generate(kind: String, w: int, h: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var g := {"w": w, "h": h, "cells": PackedStringArray(), "spawn": Vector2i(1, h / 2), "labels": [], "buildings": [], "rects": []}
	g.cells.resize(w * h)
	match kind:
		"village":
			_village(g, rng)
		"ville":
			_city(g, rng)
		"donjon":
			_dungeon(g, rng)
		"grotte":
			_cave(g, rng)
		"plaine":
			_plain(g, rng)
		"ile":
			_island(g, rng)
		_:
			_forest(g, rng)
	# Grandes cartes sauvages : quelques lieux à découvrir.
	var extra := (w * h) / 900
	var pois: Array = {"foret": ["campement", "ruine", "crypte"], "plaine": ["ferme", "campement", "ruine", "tour_garde"],
		"ile": ["campement", "ruine"], "grotte": [], "donjon": []}.get(kind, [])
	for i in mini(extra, 6):
		if not pois.is_empty():
			_try_building(g, rng, String(pois[i % pois.size()]), Rect2i(2, 2, w - 4, h - 4), ["W", "w", "#", "r", "p", "B", "m", "s"])
	_fix_spawn(g)
	return {"cells": "".join(g.cells), "w": w, "h": h, "spawn": {"x": g.spawn.x, "y": g.spawn.y}, "labels": g.labels, "buildings": g.buildings}


## Cherche une place pour un bâtiment prêt dans la zone (sans chevaucher les
## routes, l'eau, les autres bâtiments). Renvoie true s'il est placé.
static func _try_building(g: Dictionary, rng: RandomNumberGenerator, id: String, area: Rect2i, avoid: Array, tries: int = 40) -> bool:
	var sz := Prefabs.size_of(id)
	if sz.x == 0 or area.size.x < sz.x or area.size.y < sz.y:
		return false
	for attempt in tries:
		var cx := rng.randi_range(area.position.x + sz.x / 2, area.end.x - 1 - (sz.x - 1 - sz.x / 2))
		var cy := rng.randi_range(area.position.y + sz.y / 2, area.end.y - 1 - (sz.y - 1 - sz.y / 2))
		var rect := Rect2i(cx - sz.x / 2, cy - sz.y / 2, sz.x, sz.y)
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > int(g.w) or rect.end.y > int(g.h):
			continue
		var ok := true
		for o in g.rects:
			if (o as Rect2i).grow(1).intersects(rect):
				ok = false
				break
		if ok:
			for y in range(rect.position.y - 1, rect.end.y + 1):
				for x in range(rect.position.x - 1, rect.end.x + 1):
					if _at(g, x, y) in avoid and x >= 0 and y >= 0 and x < int(g.w) and y < int(g.h):
						ok = false
		if not ok:
			continue
		g.rects.append(rect)
		g.buildings.append({"id": id, "x": cx, "y": cy})
		# Un chemin devant la porte (bas du bâtiment), s'il y a de la place.
		if rect.end.y < int(g.h) and _at(g, cx, rect.end.y) in [".", "y", "f", "z"]:
			_put(g, cx, rect.end.y, "r")
		return true
	return false


## Le départ doit être praticable : sinon, la case praticable la plus proche.
static func _fix_spawn(g: Dictionary) -> void:
	var s: Vector2i = g.spawn
	for r in maxi(int(g.w), int(g.h)):
		for y in range(s.y - r, s.y + r + 1):
			for x in range(s.x - r, s.x + r + 1):
				if maxi(absi(x - s.x), absi(y - s.y)) != r:
					continue
				if MapData.TERRAINS.get(_at(g, x, y), ["", "", false])[2] and x >= 0 and y >= 0 and x < int(g.w) and y < int(g.h):
					g.spawn = Vector2i(x, y)
					return


static func _put(g: Dictionary, x: int, y: int, code: String) -> void:
	if x >= 0 and y >= 0 and x < int(g.w) and y < int(g.h):
		g.cells[y * int(g.w) + x] = code


static func _at(g: Dictionary, x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= int(g.w) or y >= int(g.h):
		return "#"
	return g.cells[y * int(g.w) + x]


static func _fill(g: Dictionary, code: String) -> void:
	for i in g.cells.size():
		g.cells[i] = code


static func _rect(g: Dictionary, r: Rect2i, code: String) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_put(g, x, y, code)


static func _noise(rng: RandomNumberGenerator, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = freq
	return n


## Chemin sinueux d'un bord à l'autre (horizontal).
static func _path(g: Dictionary, rng: RandomNumberGenerator, code: String, y0: int, width: int = 1) -> Array:
	var pts: Array = []
	var y := y0
	for x in int(g.w):
		for k in width:
			_put(g, x, y + k, code)
		pts.append(Vector2i(x, y))
		if rng.randf() < 0.3:
			y = clampi(y + (1 if rng.randf() < 0.5 else -1), 1, int(g.h) - 1 - width)
	return pts


static func _label(g: Dictionary, x: int, y: int, text: String, hidden: bool = false) -> void:
	g.labels.append({"x": x, "y": y, "text": text, "hidden": hidden})


static func _forest(g: Dictionary, rng: RandomNumberGenerator) -> void:
	var n := _noise(rng, 0.11)
	for y in int(g.h):
		for x in int(g.w):
			var v := n.get_noise_2d(x, y)
			_put(g, x, y, "F" if v > 0.25 else ("f" if v > 0.0 else ("y" if v < -0.35 else ".")))
	var mid := int(g.h) / 2
	var pts := _path(g, rng, "r", mid)
	g.spawn = pts[0]
	# Clairière et étang.
	var c := Vector2i(int(g.w) * 2 / 3, clampi(mid + rng.randi_range(-4, 4), 4, int(g.h) - 5))
	for y in range(c.y - 3, c.y + 4):
		for x in range(c.x - 4, c.x + 5):
			if Vector2(x - c.x, (y - c.y) * 1.3).length() < 4.2:
				_put(g, x, y, ".")
	var pond := Vector2i(rng.randi_range(4, int(g.w) / 3), rng.randi_range(2, int(g.h) - 4))
	for y in range(pond.y - 2, pond.y + 3):
		for x in range(pond.x - 3, pond.x + 4):
			var d := Vector2(x - pond.x, (y - pond.y) * 1.4).length()
			if d < 2.0:
				_put(g, x, y, "w")
			elif d < 2.8 and _at(g, x, y) != "r":
				_put(g, x, y, "k")
	_label(g, c.x, c.y, "Clairière")
	_label(g, pond.x, pond.y, "Étang")
	_label(g, c.x + 1, c.y + 1, "Traces de pas fraîches", true)


static func _village(g: Dictionary, rng: RandomNumberGenerator) -> void:
	var n := _noise(rng, 0.15)
	for y in int(g.h):
		for x in int(g.w):
			_put(g, x, y, "f" if n.get_noise_2d(x, y) > 0.45 else ".")
	var mid := int(g.h) / 2
	var cx := int(g.w) / 2
	_rect(g, Rect2i(0, mid, int(g.w), 2), "r")
	_rect(g, Rect2i(cx, 1, 2, int(g.h) - 2), "r")
	_rect(g, Rect2i(cx - 3, mid - 2, 8, 6), "p")
	_put(g, cx, mid, "w")
	_put(g, cx + 1, mid, "w")
	g.rects.append(Rect2i(cx - 3, mid - 2, 8, 6))
	g.spawn = Vector2i(0, mid)
	_label(g, cx, mid - 3, "Place du puits")
	# Bâtiments prêts, avec leurs habitants : les incontournables d'abord.
	var wanted := ["auberge", "forge", "echoppe", "temple", "herboristerie", "tour_garde", "grange", "ferme"]
	var houses := maxi(2, (int(g.w) * int(g.h)) / 260)
	for i in houses:
		wanted.append("maison" if i % 3 != 2 else "grande_maison")
	var area := Rect2i(1, 1, int(g.w) - 2, int(g.h) - 2)
	for id in wanted:
		_try_building(g, rng, String(id), area, ["r", "p", "w", "W"])


## Ville fortifiée : remparts et portes, avenues pavées, marché central, quartiers.
static func _city(g: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := int(g.w)
	var h := int(g.h)
	var n := _noise(rng, 0.12)
	for y in h:
		for x in w:
			_put(g, x, y, "f" if n.get_noise_2d(x, y) > 0.35 else ("y" if n.get_noise_2d(x, y) < -0.4 else "."))
	var wall := Rect2i(3, 3, w - 6, h - 6)
	for x in range(wall.position.x, wall.end.x):
		_put(g, x, wall.position.y, "#")
		_put(g, x, wall.end.y - 1, "#")
	for y in range(wall.position.y, wall.end.y):
		_put(g, wall.position.x, y, "#")
		_put(g, wall.end.x - 1, y, "#")
	_rect(g, wall.grow(-1), ".")
	var cx := w / 2
	var cy := h / 2
	# Avenues et portes.
	_rect(g, Rect2i(0, cy - 1, w, 3), "p")
	_rect(g, Rect2i(cx - 1, 0, 3, h), "p")
	_rect(g, Rect2i(0, cy - 1, 3, 3), "r")
	_rect(g, Rect2i(w - 3, cy - 1, 3, 3), "r")
	_label(g, wall.position.x, cy - 2, "Porte de l'Ouest")
	_label(g, wall.end.x - 1, cy - 2, "Porte de l'Est")
	_label(g, cx, wall.position.y - 1 if wall.position.y > 0 else 0, "Porte du Nord")
	# Ruelles secondaires.
	for i in (w / 30 if w >= 60 else 0):
		var yy := rng.randi_range(wall.position.y + 3, wall.end.y - 4)
		_rect(g, Rect2i(wall.position.x + 1, yy, wall.size.x - 2, 1), "p")
		var xx := rng.randi_range(wall.position.x + 3, wall.end.x - 4)
		_rect(g, Rect2i(xx, wall.position.y + 1, 1, wall.size.y - 2), "p")
	g.spawn = Vector2i(0, cy)
	# Marché au centre, puis les grands bâtiments, puis les maisons.
	var msz := Prefabs.size_of("marche")
	g.rects.append(Rect2i(cx - 1, cy - 1, 3, 3))
	g.buildings.append({"id": "marche", "x": cx + msz.x / 2 + 2, "y": cy - msz.y / 2 - 2})
	g.rects.append(Rect2i(cx + 2, cy - msz.y - 2, msz.x, msz.y))
	var inside := wall.grow(-2)
	var wanted := ["caserne", "temple", "manoir", "maison_mage", "auberge", "auberge", "forge", "echoppe", "echoppe", "herboristerie", "tour_garde", "puits"]
	var houses := maxi(4, (w * h) / 220)
	for i in houses:
		wanted.append("maison" if i % 3 != 2 else "grande_maison")
	for id in wanted:
		_try_building(g, rng, String(id), inside, ["p", "#", "w", "W", "r"], 60)
	_label(g, cx, cy - 3, "Grand-Place")

static func _dungeon(g: Dictionary, rng: RandomNumberGenerator) -> void:
	_fill(g, "#")
	var rooms: Array = []
	for attempt in 80:
		var rw := rng.randi_range(4, 8)
		var rh := rng.randi_range(3, 6)
		var r := Rect2i(rng.randi_range(1, int(g.w) - rw - 2), rng.randi_range(1, int(g.h) - rh - 2), rw, rh)
		var ok := true
		for o in rooms:
			if (o as Rect2i).grow(1).intersects(r):
				ok = false
				break
		if ok:
			rooms.append(r)
		if rooms.size() >= 8:
			break
	rooms.sort_custom(func(a, b): return a.position.x < b.position.x)
	for i in rooms.size():
		_rect(g, rooms[i], "o")
		if i > 0:
			var a: Vector2i = rooms[i - 1].get_center()
			var b: Vector2i = rooms[i].get_center()
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				_put(g, x, a.y, "o")
			for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
				_put(g, b.x, y, "o")
	if not rooms.is_empty():
		g.spawn = rooms[0].get_center()
		_label(g, rooms[0].get_center().x, rooms[0].position.y, "Entrée")
		var last: Rect2i = rooms[-1]
		_label(g, last.get_center().x, last.position.y, "Salle du trésor")
		_label(g, last.get_center().x, last.get_center().y, "Le gardien attend ici", true)
		if rooms.size() > 3:
			var mid: Rect2i = rooms[rooms.size() / 2]
			_rect(g, Rect2i(mid.get_center().x, mid.get_center().y, 1, 1), "x")
			_label(g, mid.get_center().x, mid.position.y, "Salle effondrée")


static func _cave(g: Dictionary, rng: RandomNumberGenerator) -> void:
	for y in int(g.h):
		for x in int(g.w):
			var edge := x == 0 or y == 0 or x == int(g.w) - 1 or y == int(g.h) - 1
			_put(g, x, y, "#" if edge or rng.randf() < 0.44 else "u")
	for step in 4:
		var next: PackedStringArray = g.cells.duplicate()
		for y in range(1, int(g.h) - 1):
			for x in range(1, int(g.w) - 1):
				var walls := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if (dx != 0 or dy != 0) and _at(g, x + dx, y + dy) == "#":
							walls += 1
				next[y * int(g.w) + x] = "#" if walls >= 5 else ("u" if walls <= 3 else g.cells[y * int(g.w) + x])
		g.cells = next
	# Un couloir garanti d'ouest en est, pour que tout soit atteignable.
	_path(g, rng, "u", int(g.h) / 2)
	g.spawn = Vector2i(1, int(g.h) / 2)
	for i in 3:
		var p := Vector2i(rng.randi_range(4, int(g.w) - 4), rng.randi_range(3, int(g.h) - 3))
		if _at(g, p.x, p.y) == "u":
			_put(g, p.x, p.y, "a" if i == 0 else "q")
	_label(g, int(g.w) - 4, int(g.h) / 2, "Fond de la grotte")
	_label(g, int(g.w) / 2, int(g.h) / 2 - 1, "Ossements rongés", true)


static func _plain(g: Dictionary, rng: RandomNumberGenerator) -> void:
	var n := _noise(rng, 0.09)
	for y in int(g.h):
		for x in int(g.w):
			var v := n.get_noise_2d(x, y)
			_put(g, x, y, "z" if v > 0.3 else ("y" if v < -0.3 else ("f" if v > 0.22 else ".")))
	# Rivière nord-sud et route est-ouest qui la traverse sur un pont.
	var x := int(g.w) / 2 + rng.randi_range(-3, 3)
	for y in int(g.h):
		_put(g, x, y, "w")
		_put(g, x + 1, y, "w")
		if rng.randf() < 0.25:
			x = clampi(x + (1 if rng.randf() < 0.5 else -1), 3, int(g.w) - 5)
	var road := _path(g, rng, "r", int(g.h) / 2)
	# Là où la route coupe la rivière (eau au-dessus ou au-dessous) : un pont.
	for p in road:
		if _at(g, p.x, p.y - 1) == "w" or _at(g, p.x, p.y + 1) == "w":
			_put(g, p.x, p.y, "B")
	g.spawn = road[0]
	_label(g, x, int(g.h) / 2 - 1, "Vieux pont")
	_label(g, int(g.w) - 6, 3, "Ferme isolée")


static func _island(g: Dictionary, rng: RandomNumberGenerator) -> void:
	var n := _noise(rng, 0.08)
	var c := Vector2(int(g.w) * 0.5, int(g.h) * 0.5)
	for y in int(g.h):
		for x in int(g.w):
			var d := Vector2((x - c.x) / (int(g.w) * 0.5), (y - c.y) / (int(g.h) * 0.5)).length()
			var v := 1.0 - d + n.get_noise_2d(x, y) * 0.35
			var code := "W"
			if v > 0.75:
				code = "m"
			elif v > 0.5:
				code = "F"
			elif v > 0.32:
				code = "f" if n.get_noise_2d(x * 2, y * 2) > 0 else "."
			elif v > 0.2:
				code = "s"
			elif v > 0.1:
				code = "w"
			_put(g, x, y, code)
	# Débarcadère à l'ouest.
	var y0 := int(g.h) / 2
	for x in int(g.w) / 2:
		if _at(g, x, y0) == "s":
			g.spawn = Vector2i(x, y0)
			break
	_label(g, int(c.x), int(c.y) - 1, "Sommet")
	_label(g, g.spawn.x, g.spawn.y - 1, "Plage du naufrage")
	_label(g, int(c.x) + 2, int(c.y) + 2, "Grotte cachée", true)
