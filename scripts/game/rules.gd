class_name Rules
extends RefCounted
## Règles automatiques : classes, répartition des points, valeurs dérivées
## (PV, énergie, défense, initiative, vitesse, attaques) et résolution des attaques.
##
## Une fiche « auto » (créée avec l'assistant) est recalculée par l'hôte à chaque
## enregistrement ; une fiche « libre » garde les valeurs saisies à la main.

const STATS := ["Force", "Agilité", "Endurance", "Intelligence", "Perception", "Charisme"]
const STAT_BASE := 10
## Points à répartir à la création.
const POINT_POOL := 12
## Chaque caractéristique peut être baissée de 4 (pour gagner des points) ou montée de 6.
const ALLOC_MIN := -4
const ALLOC_MAX := 6
const DIR := "res://data/classes"

static var _cache := {}


static func classes(universe_id: String) -> Array:
	var id := universe_id if FileAccess.file_exists("%s/%s.json" % [DIR, universe_id]) else "fantasy"
	if not _cache.has(id):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [DIR, id]))
		_cache[id] = parsed if parsed is Array else []
	return _cache[id]


static func get_class_def(universe_id: String, class_id: String) -> Dictionary:
	for c in classes(universe_id):
		if c.id == class_id:
			return c
	return {}


static func mod(value: int) -> int:
	return floori((value - 10) / 2.0)


static func points_spent(alloc: Dictionary) -> int:
	var total := 0
	for s in STATS:
		total += int(alloc.get(s, 0))
	return total


## Répartition valide : dans les bornes et sans dépasser la réserve.
static func valid_alloc(alloc: Dictionary) -> bool:
	for s in STATS:
		var v := int(alloc.get(s, 0))
		if v < ALLOC_MIN or v > ALLOC_MAX:
			return false
	return points_spent(alloc) <= POINT_POOL


static func stat_values(alloc: Dictionary, cls: Dictionary) -> Dictionary:
	var out := {}
	var bonus: Dictionary = cls.get("bonus", {})
	for s in STATS:
		out[s] = STAT_BASE + int(alloc.get(s, 0)) + int(bonus.get(s, 0))
	return out


static func stat(sheet: Dictionary, stat_name: String) -> int:
	for s in sheet.get("stats", []):
		if String(s.get("name", "")) == stat_name:
			return int(s.get("value", 10))
	return 10


static func equipped(sheet: Dictionary, category: String) -> Array:
	return sheet.get("inventory", []).filter(func(i): return i.get("category", "") == category and i.get("equipped", false))


static func weapons(sheet: Dictionary) -> Array:
	var list := equipped(sheet, "arme")
	if list.is_empty():
		list = [{"name": "Mains nues", "damage": "1d4", "stat": "Force", "crit": 20, "range": 1}]
	return list


## Valeurs dérivées d'une fiche (que la fiche soit auto ou non).
static func derived(sheet: Dictionary, universe_id: String) -> Dictionary:
	var cls := get_class_def(universe_id, String(sheet.get("class_id", "")))
	var level := maxi(1, int(sheet.get("level", 1)))
	var armor := 0
	for a in equipped(sheet, "armure") + equipped(sheet, "bouclier"):
		armor += int(a.get("defense", 0))
	var res_stat := String(cls.get("res_stat", "Intelligence"))
	var d := {
		"hp_max": int(cls.get("hp_base", 14)) + mod(stat(sheet, "Endurance")) * 3 + (level - 1) * int(cls.get("hp_per_level", 5)),
		"res_max": int(cls.get("res_base", 8)) + maxi(0, mod(stat(sheet, res_stat))) * 2 + (level - 1) * 2,
		"defense": 10 + mod(stat(sheet, "Agilité")) + armor + int(cls.get("defense_bonus", 0)),
		"initiative": mod(stat(sheet, "Agilité")) + mod(stat(sheet, "Perception")),
		"speed": int(cls.get("speed", 5)),
		"attack_bonus": int(cls.get("attack_bonus", 0)) + (level - 1) / 3,
		"crit_bonus": int(cls.get("crit_bonus", 0)),
	}
	if int(sheet.get("defense", 0)) > 0 and not sheet.get("auto", false):
		d.defense = int(sheet.defense)
	if int(sheet.get("speed", 0)) > 0 and not sheet.get("auto", false):
		d.speed = int(sheet.speed)
	d.hp_max = maxi(1, d.hp_max)
	return d


## Description d'une attaque : bonus de toucher, dés de dégâts, seuil de critique.
static func attack_profile(sheet: Dictionary, universe_id: String, weapon: Dictionary) -> Dictionary:
	var d := derived(sheet, universe_id)
	var stat_name := String(weapon.get("stat", "Force"))
	var m := mod(stat(sheet, stat_name)) if stat_name != "" else 0
	return {
		"name": String(weapon.get("name", "Attaque")),
		"to_hit": m + int(d.attack_bonus),
		"damage": String(weapon.get("damage", "1d4")),
		"damage_mod": m,
		"crit": clampi(int(weapon.get("crit", 20)) - int(d.crit_bonus), 15, 20),
		"range": maxi(1, int(weapon.get("range", 1))),
		"ignore_defense": 1 if String(weapon.get("effect", "")) == "ignore_defense_1" else 0,
	}


## Applique la classe, la répartition et l'équipement choisi : fiche « auto » complète.
static func build_sheet(base: Dictionary, universe_id: String, class_id: String, alloc: Dictionary, choices: Array) -> Dictionary:
	var sheet := base.duplicate(true)
	var cls := get_class_def(universe_id, class_id)
	if cls.is_empty():
		return sheet
	sheet.class_id = class_id
	sheet.auto = true
	sheet.alloc = {}
	for s in STATS:
		sheet.alloc[s] = int(alloc.get(s, 0))
	var values := stat_values(sheet.alloc, cls)
	sheet.stats = STATS.map(func(s): return {"name": s, "value": values[s]})
	sheet.skills = cls.get("skills", []).duplicate(true)
	sheet.abilities = cls.get("abilities", []).duplicate(true)
	var inventory: Array = cls.get("kit", []).duplicate(true)
	var groups: Array = cls.get("choices", [])
	for i in groups.size():
		var options: Array = groups[i].get("options", [])
		if options.is_empty():
			continue
		var pick := clampi(int(choices[i]) if i < choices.size() else 0, 0, options.size() - 1)
		inventory.push_front(options[pick].duplicate(true))
	sheet.inventory = inventory
	var magic: Dictionary = cls.get("magic", {})
	if not magic.is_empty():
		var m: Dictionary = sheet.get("magic", {})
		for key in ["category", "name", "description"]:
			if String(m.get(key, "")) == "":
				m[key] = magic.get(key, "")
		sheet.magic = m
	if String(sheet.get("concept", "")) == "":
		sheet.concept = String(cls.name)
	return refresh(sheet, universe_id, true)


## Recalcule les valeurs dérivées d'une fiche auto (PV conservés, plafonnés).
static func refresh(sheet: Dictionary, universe_id: String, full_heal: bool = false) -> Dictionary:
	if not sheet.get("auto", false):
		return sheet
	var cls := get_class_def(universe_id, String(sheet.get("class_id", "")))
	if not cls.is_empty() and sheet.get("alloc") is Dictionary:
		var values := stat_values(sheet.alloc, cls)
		var stats: Array = sheet.get("stats", [])
		for s in stats:
			if values.has(s.name):
				s.value = values[s.name]
	var d := derived(sheet, universe_id)
	sheet.hp_max = d.hp_max
	sheet.res_max = d.res_max
	sheet.defense = d.defense
	sheet.speed = d.speed
	if full_heal:
		sheet.hp = d.hp_max
		sheet.res = d.res_max
	else:
		sheet.hp = mini(int(sheet.get("hp", d.hp_max)), d.hp_max)
		sheet.res = mini(int(sheet.get("res", d.res_max)), d.res_max)
	return sheet


static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
