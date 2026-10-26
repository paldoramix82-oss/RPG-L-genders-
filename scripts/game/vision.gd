class_name Vision
extends RefCounted
## Brouillard de guerre : ce que chaque joueur voit de la carte.
##
## Un personnage voit les cases à moins de « vision » cases de lui (vision =
## base + Dextérité ÷ diviseur, + bonus d'objets), sauf derrière un obstacle
## qui bloque la vue (mur, forêt dense, montagne, toits). Les cases déjà vues
## restent connues (assombries) : c'est l'exploration, mémorisée par l'hôte.
##
## L'hôte ne transmet à un joueur que les pions et étiquettes qu'il voit :
## le brouillard n'est pas qu'un effet d'affichage.

## Terrains qui bloquent la vue (la case elle-même reste visible).
const OPAQUE := ["#", "F", "m", "R"]


## Rayon de vision d'un personnage (en cases).
static func radius(sheet: Dictionary, content: Dictionary) -> int:
	return int(Rules.derived(sheet, content).get("vision", 5))


static func enabled(map: Dictionary) -> bool:
	return bool(map.get("fog_of_war", true))


## Cases visibles depuis `origin` : {indice de case: true}.
static func visible_from(map: Dictionary, origin: Vector2i, r: int, out: Dictionary = {}) -> Dictionary:
	var w := int(map.get("w", 0))
	var h := int(map.get("h", 0))
	if not MapData.in_bounds(map, origin.x, origin.y):
		return out
	var cells := String(map.get("cells", ""))
	var limit := (float(r) + 0.5) * (float(r) + 0.5)
	for y in range(maxi(0, origin.y - r), mini(h, origin.y + r + 1)):
		for x in range(maxi(0, origin.x - r), mini(w, origin.x + r + 1)):
			var idx := y * w + x
			if out.has(idx):
				continue
			var d := Vector2(x - origin.x, y - origin.y)
			if d.length_squared() > limit:
				continue
			if _line_clear(cells, w, origin, Vector2i(x, y)):
				out[idx] = true
	return out


## Ligne de vue (Bresenham) : aucune case opaque entre les deux extrémités.
static func _line_clear(cells: String, w: int, a: Vector2i, b: Vector2i) -> bool:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while p != b:
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
		if p == b:
			return true
		if OPAQUE.has(cells[p.y * w + p.x]):
			return false
	return true


## Pions dont la vue profite à ce joueur : les siens (et ceux du groupe si la
## vision est partagée).
static func viewers(map: Dictionary, player_id: String, shared: bool) -> Array:
	var out: Array = []
	for t in map.get("tokens", []):
		if String(t.get("kind", "")) != "pc":
			continue
		if String(t.get("owner", "")) == player_id or (shared and String(t.get("owner", "")) != "" and not t.get("hidden", false)):
			out.append(t)
	return out


## Ensemble des cases visibles par un joueur. `sheets` : char_id -> fiche.
static func visible_for(map: Dictionary, player_id: String, sheets: Dictionary, content: Dictionary) -> Dictionary:
	var shared := bool(Content.rule(content, "shared_vision"))
	var out := {}
	for t in viewers(map, player_id, shared):
		var sheet: Dictionary = sheets.get(String(t.get("char_id", "")), {})
		var r := radius(sheet, content) if not sheet.is_empty() else int(Content.rule(content, "vision_base"))
		visible_from(map, Vector2i(int(t.x), int(t.y)), r, out)
	return out


## Ajoute les cases visibles à la mémoire d'exploration (chaîne de « 0 »/« 1 »).
## Renvoie la nouvelle chaîne.
static func explore(map: Dictionary, explored: String, seen: Dictionary) -> String:
	var n := int(map.w) * int(map.h)
	var buf := explored.to_ascii_buffer() if explored.length() == n else "0".repeat(n).to_ascii_buffer()
	for idx in seen:
		if int(idx) < n:
			buf[int(idx)] = 49  # "1"
	return buf.get_string_from_ascii()


static func mask(map: Dictionary, seen: Dictionary) -> String:
	var n := int(map.w) * int(map.h)
	var buf := "0".repeat(n).to_ascii_buffer()
	for idx in seen:
		if int(idx) < n:
			buf[int(idx)] = 49
	return buf.get_string_from_ascii()


static func is_set(bits: String, map: Dictionary, x: int, y: int) -> bool:
	var i := y * int(map.get("w", 0)) + x
	return i >= 0 and i < bits.length() and bits[i] == "1"
