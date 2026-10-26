class_name CharacterData
extends RefCounted
## Fiche de personnage (joueur, PNJ ou monstre) : un dictionnaire validé.
## Toute donnée venant du réseau passe par sanitize_narrative() (joueurs : récit
## uniquement) ou sanitize() (MJ, chargement, migration) avant d'être enregistrée.

const SHORT := 80
const LONG := 3000
const MAX_ROWS := 60
## Version du format des fiches (2 : caractéristiques 1–10, capacités et objets en données).
const SCHEMA := 2
const PAWN_COLORS := ["#c9a96e", "#b0605a", "#6f9fc9", "#8fb28a", "#a07cc9", "#d1a15e", "#5fb3a8", "#d27aa0", "#9a9a9a", "#e0e0d0"]

## Champs texte et longueur maximale.
const TEXT_FIELDS := {
	"name": SHORT, "age": 20, "species": SHORT, "origin": SHORT, "concept": SHORT,
	"appearance": LONG, "background": LONG, "personality": LONG, "goals": LONG,
	"relations": LONG, "notes": LONG, "secret": LONG, "status": SHORT, "rank": 10, "kind": 10, "class_id": 60, "species_id": 60, "monster_id": 60,
	"res_name": 20, "loot": 60, "side": 12,
}
## Champs narratifs qu'un joueur peut modifier lui-même (le reste : règles, calculé par l'hôte).
const NARRATIVE_FIELDS := ["name", "age", "species", "origin", "concept", "appearance", "background", "personality",
	"goals", "relations", "notes", "secret"]
const INT_FIELDS := ["level", "xp", "hp", "hp_max", "res", "res_max", "defense", "speed", "gold", "ult", "xp_reward", "defense_bonus", "schema", "aggro"]
## Champs visibles par les autres joueurs (le reste : propriétaire + MJ).
const PUBLIC_FIELDS := ["id", "owner", "name", "species", "origin", "concept", "appearance", "rank", "level", "hp", "hp_max",
	"res", "res_max", "res_name", "pawn", "portrait", "status", "class_id", "species_id", "effects", "kind"]
const PORTRAIT_KEYS := ["face", "skin", "hair", "hair_color", "eyes", "beard", "mark"]


static func create(universe: Dictionary, id: String, owner: String, char_name: String = "", content: Dictionary = {}) -> Dictionary:
	var names: Array = Content.stat_names(content)
	var base := int(Content.rule(content, "stat_base")) if not content.is_empty() else 5
	var stats: Array = []
	for s in names:
		stats.append({"name": s, "value": base})
	var cfg: Dictionary = universe.get("character", {})
	var hp := int(cfg.get("hp_default", 20))
	var res := int(cfg.get("resource_default", 10))
	var h: int = absi(hash(id))
	return {
		"id": id, "owner": owner, "name": char_name, "age": "", "species": "", "origin": "", "concept": "",
		"appearance": "", "background": "", "personality": "", "goals": "", "relations": "",
		"notes": "", "secret": "", "status": "", "rank": "", "kind": "npc", "class_id": "", "species_id": "", "auto": false, "alloc": {}, "trained": {},
		"defense": 0, "speed": 0, "defense_bonus": 0, "side": "",
		"level": 1, "xp": 0, "gold": 0, "hp": hp, "hp_max": hp, "res": res, "res_max": res,
		"res_name": String(cfg.get("resource_name", "Énergie")),
		"stats": stats, "skills": [],
		"magic": {"category": "", "name": "", "origin": "", "description": "", "limits": "", "public": true},
		"abilities": [], "passive": {}, "inventory": [], "effects": [], "cooldowns": {}, "ult": 0,
		"pending": {"stat_points": 0, "picks": 0}, "xp_reward": 0, "loot": "", "schema": SCHEMA,
		"pawn": {"color": PAWN_COLORS[h % PAWN_COLORS.size()], "symbol": ""},
		"portrait": {"face": h % 4, "skin": (h / 4) % 6, "hair": (h / 24) % 8, "hair_color": (h / 192) % 8, "eyes": (h / 1536) % 4, "beard": 0, "mark": 0},
	}


## Champs narratifs envoyés par un joueur : nom, histoire, apparence, magie, pion, portrait.
static func sanitize_narrative(input: Variant, base: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	if not input is Dictionary:
		return out
	for key in NARRATIVE_FIELDS:
		if input.has(key):
			out[key] = Protocol.sanitize_text(input[key], TEXT_FIELDS[key])
	out.name = Protocol.sanitize_name(out.name)
	_sanitize_look(input, out)
	return out


static func _sanitize_look(input: Dictionary, out: Dictionary) -> void:
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
	if input.get("portrait") is Dictionary:
		var p := {}
		for key in PORTRAIT_KEYS:
			p[key] = clampi(_int(input.portrait.get(key, out.get("portrait", {}).get(key, 0))), 0, 15)
		out.portrait = p


## Fusionne `input` dans une copie de `base` en validant chaque champ (MJ, chargement, migration).
static func sanitize(input: Variant, base: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	if not input is Dictionary:
		return out
	for key in TEXT_FIELDS:
		if input.has(key):
			out[key] = Protocol.sanitize_text(input[key], TEXT_FIELDS[key])
	out.name = Protocol.sanitize_name(out.name)
	for key in INT_FIELDS:
		if input.has(key):
			out[key] = clampi(_int(input[key]), -9999, 9999999)
	out.hp_max = maxi(1, int(out.get("hp_max", 1)))
	out.res_max = maxi(0, int(out.get("res_max", 0)))
	out.level = maxi(1, int(out.get("level", 1)))
	if input.has("stats"):
		out.stats = _rows(input.stats, {"name": SHORT}, ["value"])
	if input.has("skills"):
		out.skills = _rows(input.skills, {"name": SHORT}, ["value"])
	if input.has("abilities") and input.abilities is Array:
		var list: Array = []
		for a in input.abilities:
			if a is Dictionary and list.size() < MAX_ROWS and String(a.get("name", "")).strip_edges() != "":
				var clean := Content.sanitize_ability(a)
				clean.rank = clampi(_int(a.get("rank", 1)), 1, 9)
				clean.equipped = bool(a.get("equipped", false))
				if a.get("innate", false):
					clean.innate = true
				if clean.id == "":
					clean.id = Content.make_id("ab_", clean.name)
				list.append(clean)
		out.abilities = list
	if input.has("inventory") and input.inventory is Array:
		var items: Array = []
		for i in input.inventory:
			if i is Dictionary and items.size() < MAX_ROWS and String(i.get("name", "")).strip_edges() != "":
				var clean := Content.sanitize_item(i, {})
				clean.item_id = Protocol.sanitize_text(i.get("item_id", ""), 60)
				clean.erase("id")
				clean.uid = String(i.get("uid", "")) if String(i.get("uid", "")).begins_with("i_") and String(i.uid).length() <= 20 else "i_" + Protocol.random_hex(5)
				clean.qty = clampi(_int(i.get("qty", 1)), 1, 9999)
				clean.equipped = bool(i.get("equipped", false)) and String(clean.get("slot", "")) != ""
				items.append(clean)
		out.inventory = items
	if input.get("passive") is Dictionary:
		out.passive = Content.sanitize_passive(input.passive) if not (input.passive as Dictionary).is_empty() else {}
	if input.has("auto"):
		out.auto = bool(input.auto)
	for key in ["alloc", "trained"]:
		if input.get(key) is Dictionary:
			var d := {}
			for s in input[key]:
				d[Protocol.sanitize_text(s, 20)] = clampi(_int(input[key][s]), -20, 40)
			out[key] = d
	if input.get("cooldowns") is Dictionary:
		var cd := {}
		for k in input.cooldowns:
			cd[Protocol.sanitize_text(k, 60)] = clampi(_int(input.cooldowns[k]), 0, 99)
		out.cooldowns = cd
	if input.get("pending") is Dictionary:
		out.pending = {"stat_points": clampi(_int(input.pending.get("stat_points", 0)), 0, 99), "picks": clampi(_int(input.pending.get("picks", 0)), 0, 99)}
	if input.has("effects") and input.effects is Array:
		out.effects = sanitize_effects_list(input.effects)
	out.ult = clampi(int(out.get("ult", 0)), 0, 100)
	_sanitize_look(input, out)
	return out


## Effets de statut en cours sur une fiche ou un pion.
static func sanitize_effects_list(raw: Array) -> Array:
	var out: Array = []
	for e in raw:
		if not e is Dictionary or out.size() >= 20:
			continue
		var name := Protocol.sanitize_text(e.get("name", ""), 40)
		if name == "":
			continue
		var clean := {
			"id": Protocol.sanitize_text(e.get("id", ""), 60), "name": name,
			"icon": Protocol.sanitize_text(e.get("icon", "sparkle"), 20),
			"color": String(e.get("color", "#a07cc9")) if Color.html_is_valid(String(e.get("color", ""))) else "#a07cc9",
			"kind": "buff" if String(e.get("kind", "")) == "buff" else "debuff",
			"turns": clampi(_int(e.get("turns", 0)), 0, 99), "value": clampi(_int(e.get("value", 0)), 0, 9999),
			"description": Protocol.sanitize_text(e.get("description", ""), 300),
		}
		if e.get("mods") is Dictionary and not (e.mods as Dictionary).is_empty():
			clean.mods = Content.sanitize_mods(e.mods)
		out.append(clean)
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


static func _rows(raw: Variant, text_keys: Dictionary, int_keys: Array, bool_keys: Array = []) -> Array:
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
			if item.has(key):
				row[key] = clampi(_int(item.get(key, 0)), -9999, 99999)
		for key in bool_keys:
			row[key] = bool(item.get(key, false))
		if String(row.get("name", "")).strip_edges() != "":
			rows.append(row)
	return rows


static func _int(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	if v is String and (v as String).is_valid_int():
		return int(v)
	return 0
