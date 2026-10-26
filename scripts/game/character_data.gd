class_name CharacterData
extends RefCounted
## Fiche de personnage (joueur ou PNJ) : un dictionnaire libre mais validé.
## Toute donnée venant du réseau passe par sanitize() avant d'être enregistrée.

const SHORT := 80
const LONG := 3000
const MAX_ROWS := 40
const PAWN_COLORS := ["#c9a96e", "#b0605a", "#6f9fc9", "#8fb28a", "#a07cc9", "#d1a15e", "#5fb3a8", "#d27aa0", "#9a9a9a", "#e0e0d0"]

## Champs texte et longueur maximale.
const TEXT_FIELDS := {
	"name": SHORT, "age": 20, "species": SHORT, "origin": SHORT, "concept": SHORT,
	"appearance": LONG, "background": LONG, "personality": LONG, "goals": LONG,
	"relations": LONG, "notes": LONG, "secret": LONG, "status": SHORT, "rank": 10, "kind": 10,
}
## Champs visibles par les autres joueurs (le reste : propriétaire + MJ).
const PUBLIC_FIELDS := ["id", "owner", "name", "species", "origin", "concept", "appearance", "rank", "level", "hp", "hp_max", "pawn", "status", "magic_public"]


static func create(universe: Dictionary, id: String, owner: String, char_name: String = "") -> Dictionary:
	var cfg: Dictionary = universe.get("character", {})
	var stats: Array = []
	for s in cfg.get("stats", ["Force", "Agilité", "Endurance", "Intelligence", "Perception", "Charisme"]):
		stats.append({"name": s, "value": 10})
	var hp := int(cfg.get("hp_default", 20))
	var res := int(cfg.get("resource_default", 10))
	return {
		"id": id, "owner": owner, "name": char_name, "age": "", "species": "", "origin": "", "concept": "",
		"appearance": "", "background": "", "personality": "", "goals": "", "relations": "",
		"notes": "", "secret": "", "status": "", "rank": "", "kind": "npc",
		"level": 1, "xp": 0, "hp": hp, "hp_max": hp, "res": res, "res_max": res,
		"stats": stats, "skills": [],
		"magic": {"category": "", "name": "", "origin": "", "description": "", "limits": "", "public": true},
		"abilities": [], "inventory": [], "effects": [],
		"pawn": {"color": PAWN_COLORS[abs(hash(id)) % PAWN_COLORS.size()], "symbol": ""},
	}


## Fusionne `input` (non fiable) dans une copie de `base` en validant chaque champ.
static func sanitize(input: Variant, base: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	if not input is Dictionary:
		return out
	for key in TEXT_FIELDS:
		if input.has(key):
			out[key] = Protocol.sanitize_text(input[key], TEXT_FIELDS[key])
	out.name = Protocol.sanitize_name(out.name)
	for key in ["level", "xp", "hp", "hp_max", "res", "res_max"]:
		if input.has(key):
			out[key] = clampi(_int(input[key]), -9999, 99999)
	out.hp_max = maxi(1, out.hp_max)
	out.res_max = maxi(0, out.res_max)
	if input.has("stats"):
		out.stats = _rows(input.stats, {"name": SHORT}, ["value"])
	if input.has("skills"):
		out.skills = _rows(input.skills, {"name": SHORT}, ["value"])
	if input.has("abilities"):
		out.abilities = _rows(input.abilities, {"name": SHORT, "description": LONG, "cost": SHORT, "range": SHORT, "limits": LONG, "effects": LONG}, [])
	if input.has("inventory"):
		out.inventory = _rows(input.inventory, {"name": SHORT, "description": LONG, "category": SHORT, "value": SHORT}, ["qty"])
	if input.has("effects"):
		out.effects = _rows(input.effects, {"name": SHORT, "description": LONG}, [])
	if input.get("magic") is Dictionary:
		var m: Dictionary = input.magic
		out.magic = {
			"category": Protocol.sanitize_text(m.get("category", ""), SHORT),
			"name": Protocol.sanitize_text(m.get("name", ""), SHORT),
			"origin": Protocol.sanitize_text(m.get("origin", ""), SHORT),
			"description": Protocol.sanitize_text(m.get("description", ""), LONG),
			"limits": Protocol.sanitize_text(m.get("limits", ""), LONG),
			"public": bool(m.get("public", true)),
		}
	if input.get("pawn") is Dictionary:
		var color := String(input.pawn.get("color", out.pawn.color))
		if not Color.html_is_valid(color):
			color = out.pawn.color
		out.pawn = {"color": color, "symbol": Protocol.sanitize_name(input.pawn.get("symbol", "")).substr(0, 2)}
	return out


## Ce que les autres joueurs voient d'une fiche.
static func public_view(c: Dictionary) -> Dictionary:
	var view := {}
	for key in PUBLIC_FIELDS:
		if c.has(key):
			view[key] = c[key]
	var magic: Dictionary = c.get("magic", {})
	if magic.get("public", true):
		view["magic"] = {"category": magic.get("category", ""), "name": magic.get("name", "")}
	view["public"] = true
	return view


static func initials(c: Dictionary) -> String:
	var symbol := String(c.get("pawn", {}).get("symbol", ""))
	if symbol != "":
		return symbol
	return initials_of(String(c.get("name", "?")))


static func initials_of(text: String) -> String:
	var words := text.strip_edges().split(" ", false)
	if words.is_empty():
		return "?"
	if words.size() == 1:
		return words[0].substr(0, 2).to_upper()
	return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()


static func _rows(raw: Variant, text_keys: Dictionary, int_keys: Array) -> Array:
	var rows: Array = []
	if not raw is Array:
		return rows
	for item in raw:
		if not item is Dictionary or rows.size() >= MAX_ROWS:
			continue
		var row := {}
		for key in text_keys:
			row[key] = Protocol.sanitize_text(item.get(key, ""), text_keys[key])
		for key in int_keys:
			row[key] = clampi(_int(item.get(key, 0)), -9999, 99999)
		if String(row.get("name", "")).strip_edges() != "":
			rows.append(row)
	return rows


static func _int(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	if v is String and (v as String).is_valid_int():
		return int(v)
	return 0
