class_name MapData
extends RefCounted
## Cartes en cases : terrain (un caractère par case), étiquettes et pions.
##
## map = {id, name, description, w, h, cells: String, spawn: {x, y},
##        labels: [{id, x, y, text, hidden}],
##        tokens: [{id, kind, name, x, y, color, owner, char_id, hp, hp_max, hidden, note}],
##        players_can_move: bool}
## Les éléments « hidden » ne sont visibles que du MJ : view_for_player() les retire.

const DIR := "res://data/maps"
const MAX_SIZE := 128
const MAX_TOKENS := 120
const MAX_LABELS := 120
const KINDS := ["pc", "npc", "monster", "object"]
const KIND_NAMES := {"pc": "Personnage", "npc": "PNJ", "monster": "Monstre", "object": "Objet"}

## code -> [nom, couleur, franchissable]
const TERRAINS := {
	".": ["Herbe", "4f5e3c", true],
	"f": ["Forêt", "34502f", true],
	"F": ["Forêt dense", "24391f", true],
	"h": ["Colline", "66683f", true],
	"m": ["Montagne", "6e655b", true],
	"s": ["Sable", "b09a69", true],
	"k": ["Marais", "3f4d3b", true],
	"w": ["Eau", "30536f", true],
	"W": ["Eau profonde", "1d3451", false],
	"g": ["Glace", "9fc3d4", true],
	"n": ["Neige", "d9dee4", true],
	"r": ["Chemin", "8a7350", true],
	"p": ["Pavés", "6c6864", true],
	"B": ["Pont", "7e5f3c", true],
	"b": ["Bâtiment", "5b4637", true],
	"d": ["Plancher", "6b5139", true],
	"t": ["Meuble", "45352a", true],
	"o": ["Dalles", "4d4954", true],
	"x": ["Gravats", "5f5850", true],
	"#": ["Mur", "28252e", false],
	"c": ["Cendres", "4a4543", true],
	"l": ["Lave", "b4472a", true],
	"a": ["Cristal AEC", "7b6fab", true],
	"v": ["Vide", "0f0e12", false],
	"y": ["Prairie fleurie", "5a6b3f", true],
	"z": ["Champs", "8b7d45", true],
	"q": ["Rochers", "6a665e", true],
	"R": ["Toits rouges", "8a4a36", true],
	"u": ["Sol de grotte", "3d3833", true],
}

static var _templates: Array = []


## Modèles fournis (data/maps), filtrés par univers (« * » = tous).
static func templates(universe_id: String = "") -> Array:
	if _templates.is_empty():
		var dir := DirAccess.open(DIR)
		if dir:
			var files := Array(dir.get_files()).filter(func(f): return f.ends_with(".json"))
			files.sort()
			for file in files:
				var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + file))
				if parsed is Dictionary and parsed.has("rows"):
					_templates.append(parsed)
	if universe_id == "":
		return _templates
	return _templates.filter(func(t): return t.get("universe", "*") in ["*", universe_id])


static func from_template(t: Dictionary) -> Dictionary:
	var map := blank(String(t.get("name", "Carte")), int(t.get("w", 24)), int(t.get("h", 16)))
	map.description = String(t.get("description", ""))
	map.template = String(t.get("id", ""))
	var cells := ""
	var rows: Array = t.get("rows", [])
	for y in map.h:
		var row: String = rows[y] if y < rows.size() else ""
		for x in map.w:
			var code := row[x] if x < row.length() else "."
			cells += code if TERRAINS.has(code) else "."
	map.cells = cells
	var spawn: Dictionary = t.get("spawn", {})
	map.spawn = {"x": clampi(int(spawn.get("x", 0)), 0, map.w - 1), "y": clampi(int(spawn.get("y", 0)), 0, map.h - 1)}
	for l in t.get("labels", []):
		add_label(map, int(l.x), int(l.y), String(l.text), bool(l.get("hidden", false)))
	for tk in t.get("tokens", []):
		add_token(map, tk)
	return map


static func blank(map_name: String, w: int, h: int, code: String = ".") -> Dictionary:
	w = clampi(w, 4, MAX_SIZE)
	h = clampi(h, 4, MAX_SIZE)
	return {
		"id": "map_" + Protocol.random_hex(4), "name": Protocol.sanitize_name(map_name) if map_name != "" else "Nouvelle carte",
		"description": "", "w": w, "h": h, "cells": code.repeat(w * h),
		"spawn": {"x": 0, "y": h / 2}, "labels": [], "tokens": [], "players_can_move": true,
	}


static func in_bounds(map: Dictionary, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < int(map.w) and y < int(map.h)


static func cell(map: Dictionary, x: int, y: int) -> String:
	if not in_bounds(map, x, y):
		return "v"
	return String(map.cells)[y * int(map.w) + x]


static func set_cell(map: Dictionary, x: int, y: int, code: String) -> bool:
	if not in_bounds(map, x, y) or not TERRAINS.has(code) or cell(map, x, y) == code:
		return false
	var i := y * int(map.w) + x
	var cells: String = map.cells
	map.cells = cells.substr(0, i) + code + cells.substr(i + 1)
	return true


static func passable(map: Dictionary, x: int, y: int) -> bool:
	return in_bounds(map, x, y) and TERRAINS.get(cell(map, x, y), ["", "", false])[2]


## Change la taille en conservant le contenu existant.
static func resize(map: Dictionary, w: int, h: int, code: String = ".") -> void:
	w = clampi(w, 4, MAX_SIZE)
	h = clampi(h, 4, MAX_SIZE)
	var cells := ""
	for y in h:
		for x in w:
			cells += cell(map, x, y) if in_bounds(map, x, y) else code
	map.w = w
	map.h = h
	map.cells = cells
	for t in map.tokens:
		t.x = clampi(int(t.x), 0, w - 1)
		t.y = clampi(int(t.y), 0, h - 1)
	map.labels = map.labels.filter(func(l): return in_bounds(map, int(l.x), int(l.y)))
	map.spawn = {"x": clampi(int(map.spawn.x), 0, w - 1), "y": clampi(int(map.spawn.y), 0, h - 1)}


static func token(map: Dictionary, token_id: String) -> Dictionary:
	for t in map.get("tokens", []):
		if t.id == token_id:
			return t
	return {}


static func token_at(map: Dictionary, x: int, y: int) -> Dictionary:
	var tokens: Array = map.get("tokens", [])
	for i in range(tokens.size() - 1, -1, -1):
		if int(tokens[i].x) == x and int(tokens[i].y) == y:
			return tokens[i]
	return {}


static func add_token(map: Dictionary, data: Dictionary) -> Dictionary:
	if map.tokens.size() >= MAX_TOKENS:
		return {}
	var t := {
		"id": "t_" + Protocol.random_hex(4), "kind": "npc", "name": "Pion", "x": 0, "y": 0,
		"color": "#9a9a9a", "owner": "", "char_id": "", "hp": 0, "hp_max": 0, "hidden": false, "note": "",
	}
	update_token(t, data, map)
	map.tokens.append(t)
	return t


## Applique des modifications validées à un pion.
static func update_token(t: Dictionary, data: Dictionary, map: Dictionary) -> void:
	if data.has("kind") and String(data.kind) in KINDS:
		t.kind = String(data.kind)
	if data.has("name"):
		var n := Protocol.sanitize_name(data.name)
		if n != "":
			t.name = n
	if data.has("color") and Color.html_is_valid(String(data.color)):
		t.color = String(data.color)
	if data.has("x"):
		t.x = clampi(int(data.x), 0, int(map.w) - 1)
	if data.has("y"):
		t.y = clampi(int(data.y), 0, int(map.h) - 1)
	for key in ["hp", "hp_max"]:
		if data.has(key):
			t[key] = clampi(int(data[key]), -9999, 99999)
	if data.has("hidden"):
		t.hidden = bool(data.hidden)
	if data.has("note"):
		t.note = Protocol.sanitize_text(data.note, 500)
	for key in ["owner", "char_id"]:
		if data.has(key):
			t[key] = String(data[key]).substr(0, 40)


static func add_label(map: Dictionary, x: int, y: int, text: String, hidden: bool) -> Dictionary:
	text = Protocol.sanitize_text(text, 60).replace("\n", " ")
	if text == "" or not in_bounds(map, x, y) or map.labels.size() >= MAX_LABELS:
		return {}
	var l := {"id": "l_" + Protocol.random_hex(4), "x": x, "y": y, "text": text, "hidden": hidden}
	map.labels.append(l)
	return l


## Case libre et franchissable la plus proche (recherche en largeur).
static func free_cell_near(map: Dictionary, x: int, y: int) -> Vector2i:
	var occupied := {}
	for t in map.tokens:
		occupied[Vector2i(int(t.x), int(t.y))] = true
	var start := Vector2i(clampi(x, 0, int(map.w) - 1), clampi(y, 0, int(map.h) - 1))
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if passable(map, p.x, p.y) and not occupied.has(p):
			return p
		for d in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var n: Vector2i = p + d
			if in_bounds(map, n.x, n.y) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return start


## Version de la carte envoyée aux joueurs : sans pions ni étiquettes cachés, sans notes du MJ.
static func view_for_player(map: Dictionary) -> Dictionary:
	var view := {
		"id": map.id, "name": map.name, "description": map.get("description", ""),
		"w": map.w, "h": map.h, "cells": map.cells, "players_can_move": map.get("players_can_move", true),
		"labels": [], "tokens": [],
	}
	for l in map.labels:
		if not l.get("hidden", false):
			view.labels.append(l)
	for t in map.tokens:
		if not t.get("hidden", false):
			var copy: Dictionary = t.duplicate()
			copy.erase("note")
			view.tokens.append(copy)
	return view


static func terrain_color(code: String) -> Color:
	return Color(TERRAINS.get(code, TERRAINS["."])[1])
