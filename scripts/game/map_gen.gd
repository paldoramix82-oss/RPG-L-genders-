class_name MapGen
extends RefCounted
## Générateur de cartes : une carte jouable en un clic (forêt, village, donjon,
## grotte, plaine, île), que le MJ retouche ensuite au pinceau. Même graine,
## même carte.

const KINDS := {
	"foret": "Forêt (clairières, sentier, étang)",
	"village": "Village (rues, maisons, place)",
	"donjon": "Donjon (salles et couloirs)",
	"grotte": "Grotte (galeries naturelles)",
	"plaine": "Plaine (rivière, pont, champs)",
	"ile": "Île (plage, forêt, sommet)",
}
const SIZES := {"petite": Vector2i(24, 16), "moyenne": Vector2i(34, 22), "grande": Vector2i(48, 32)}


## Renvoie {cells, w, h, spawn: {x, y}, labels: [{x, y, text, hidden}]}.
static func generate(kind: String, w: int, h: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var g := {"w": w, "h": h, "cells": PackedStringArray(), "spawn": Vector2i(1, h / 2), "labels": []}
	g.cells.resize(w * h)
	match kind:
		"village":
			_village(g, rng)
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
	_fix_spawn(g)
	return {"cells": "".join(g.cells), "w": w, "h": h, "spawn": {"x": g.spawn.x, "y": g.spawn.y}, "labels": g.labels}


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
	g.spawn = Vector2i(0, mid)
	_label(g, cx, mid - 3, "Place du puits")
	var names := ["Auberge", "Forge", "Échoppe", "Maison du chef", "Grange", "Chapelle", "Herboriste"]
	names.shuffle()
	var placed := 0
	for attempt in 60:
		var bw := rng.randi_range(3, 5)
		var bh := rng.randi_range(2, 4)
		var x := rng.randi_range(1, int(g.w) - bw - 1)
		var y := rng.randi_range(1, int(g.h) - bh - 1)
		var r := Rect2i(x, y, bw, bh)
		var ok := true
		for yy in range(y - 1, y + bh + 1):
			for xx in range(x - 1, x + bw + 1):
				if _at(g, xx, yy) in ["r", "p", "R", "w"]:
					ok = false
		if not ok:
			continue
		_rect(g, r, "R")
		# Porte côté rue (case pavée devant).
		_put(g, x + bw / 2, y + bh, "p")
		if placed < names.size():
			_label(g, x + bw / 2, y, names[placed])
		placed += 1
		if placed >= 9:
			break


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
