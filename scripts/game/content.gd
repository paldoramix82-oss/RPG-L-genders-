class_name Content
extends RefCounted
## Catalogue de jeu d'une campagne : règles, caractéristiques, classes,
## capacités, effets de statut, objets, tables de butin et monstres.
##
## Le catalogue par défaut vient de data/content/<univers>.json. Chaque
## campagne en garde sa propre copie, que le MJ modifie librement en cours de
## partie (ses créations sont sauvegardées avec la campagne). Tout ce qui est
## référencé porte un identifiant stable.

const DIR := "res://data/content"
const KINDS := ["classes", "abilities", "statuses", "items", "loot", "monsters"]
## Ce que les joueurs reçoivent (le reste — objets, monstres, butin — reste chez le MJ).
const PLAYER_KINDS := ["classes", "abilities", "statuses"]

const RARITIES := ["commun", "peu_commun", "rare", "epique", "legendaire"]
const RARITY_NAMES := {"commun": "Commun", "peu_commun": "Peu commun", "rare": "Rare", "epique": "Épique", "legendaire": "Légendaire"}
const RARITY_COLORS := {"commun": "#b8b4ab", "peu_commun": "#7fbf6a", "rare": "#6fa3d9", "epique": "#b07fd9", "legendaire": "#e3b55a"}
const CATEGORIES := ["arme", "armure", "accessoire", "consommable", "potion", "materiau", "quete", "livre", "unique"]
const CATEGORY_NAMES := {"arme": "Arme", "armure": "Armure", "accessoire": "Accessoire", "consommable": "Consommable", "potion": "Potion",
	"materiau": "Matériau", "quete": "Objet de quête", "livre": "Livre", "unique": "Objet unique"}
const SLOTS := {"arme": 1, "armure": 1, "accessoire": 2}
const TARGETS := ["self", "ally", "enemy", "any", "area_enemy", "area_ally"]
const TARGET_NAMES := {"self": "Soi-même", "ally": "Un allié", "enemy": "Un ennemi", "any": "N'importe qui",
	"area_enemy": "Zone (ennemis)", "area_ally": "Zone (alliés)"}
const EFFECT_TYPES := ["damage", "heal", "restore", "status", "cleanse", "push", "pull", "ap", "stat", "drain", "summon", "if", "narrate"]
const EFFECT_NAMES := {"damage": "Dégâts", "heal": "Soin", "restore": "Restaurer ressource", "status": "Appliquer un effet",
	"cleanse": "Retirer des effets négatifs", "push": "Repousser", "pull": "Attirer", "ap": "Points d'action", "stat": "Modifier une caractéristique",
	"drain": "Vol de vie", "summon": "Invoquer", "if": "Si… alors…", "narrate": "Texte narratif"}
const MOD_KEYS := ["Force", "Dextérité", "Constitution", "Intelligence", "Esprit", "Charisme", "hp_max", "res_max", "defense",
	"to_hit", "damage", "resist_phys", "resist_mag", "speed", "heal_pct", "crit", "ap", "damage_taken", "vision"]
const MOD_NAMES := {"hp_max": "PV max", "res_max": "Ressource max", "defense": "Défense", "to_hit": "Toucher", "damage": "Dégâts",
	"resist_phys": "Résistance physique", "resist_mag": "Résistance magique", "speed": "Vitesse", "heal_pct": "Soins (%)",
	"crit": "Critique", "ap": "PA", "damage_taken": "Dégâts subis", "vision": "Vision"}

const DEFAULT_RULES := {
	"stat_base": 5, "stat_pool": 15, "stat_min": 1, "stat_max": 10, "stat_cap": 14,
	"ap_per_turn": 2, "move_ap": 1, "quick_attack_ap": 1, "power_attack_ap": 2, "defend_ap": 1, "item_ap": 1,
	"defense_base": 8, "hp_per_con": 2, "res_per_stat": 2, "res_regen_turn": 1,
	"ult_gain_deal": 15, "ult_gain_taken": 10, "ult_gain_turn": 10,
	"xp_base": 100, "level_max": 20, "stat_points_per_level": 1, "pick_every_levels": 1,
	"slots_basic": 3, "slots_ultimate": 1, "swap_in_combat": false,
	"rest_hp_pct": 50, "start_gold": 20, "max_ability_rank": 3,
	"vision_base": 3, "vision_dex_div": 2, "shared_vision": false,
}
## Réglages des règles exposés au MJ : [clé, libellé, min, max].
const RULE_FIELDS := [
	["stat_base", "Valeur de départ de chaque caractéristique", 1, 10],
	["stat_pool", "Points à répartir à la création", 0, 60],
	["stat_min", "Minimum par caractéristique (création)", 1, 10],
	["stat_max", "Maximum par caractéristique (création)", 1, 20],
	["ap_per_turn", "Points d'action par tour", 1, 6],
	["move_ap", "Coût d'un déplacement (PA)", 0, 3],
	["quick_attack_ap", "Coût de l'attaque rapide (PA)", 0, 3],
	["power_attack_ap", "Coût de l'attaque puissante (PA)", 1, 4],
	["defend_ap", "Coût de « Se défendre » (PA)", 0, 3],
	["item_ap", "Coût d'un objet en combat (PA)", 0, 3],
	["defense_base", "Défense de base (+ Dextérité + armure)", 0, 20],
	["hp_per_con", "PV par point de Constitution", 0, 10],
	["res_per_stat", "Ressource par point de caractéristique", 0, 10],
	["res_regen_turn", "Ressource récupérée par tour de combat", 0, 10],
	["ult_gain_deal", "Jauge d'ultime : gain en infligeant des dégâts", 0, 100],
	["ult_gain_taken", "Jauge d'ultime : gain en subissant des dégâts", 0, 100],
	["ult_gain_turn", "Jauge d'ultime : gain à chaque tour", 0, 100],
	["xp_base", "XP pour le niveau 2 (palier de base)", 10, 10000],
	["level_max", "Niveau maximum", 1, 99],
	["stat_points_per_level", "Points de caractéristique par niveau", 0, 5],
	["slots_basic", "Emplacements de capacités de base", 1, 8],
	["rest_hp_pct", "PV récupérés au repos (%)", 0, 100],
	["start_gold", "Or de départ", 0, 10000],
	["max_ability_rank", "Rang maximum d'une capacité", 1, 5],
	["vision_base", "Vision de base (cases, avant la Dextérité)", 0, 20],
	["vision_dex_div", "Vision : +1 case tous les N points de Dextérité", 1, 10],
]

static var _defaults := {}


## Catalogue par défaut d'un univers (copie profonde : modifiable sans risque).
static func default_for(universe_id: String) -> Dictionary:
	var id := universe_id if FileAccess.file_exists("%s/%s.json" % [DIR, universe_id]) else "fantasy"
	if not _defaults.has(id):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [DIR, id]))
		_defaults[id] = normalize(parsed if parsed is Dictionary else {})
	return (_defaults[id] as Dictionary).duplicate(true)


## Complète un catalogue (ancien ou incomplet) avec les sections et règles manquantes.
static func normalize(data: Dictionary) -> Dictionary:
	for kind in KINDS:
		if not data.get(kind) is Dictionary:
			data[kind] = {}
	var rules: Dictionary = data.get("rules", {}) if data.get("rules") is Dictionary else {}
	for key in DEFAULT_RULES:
		if not rules.has(key):
			rules[key] = DEFAULT_RULES[key]
	data["rules"] = rules
	if not data.get("stats") is Array or (data.stats as Array).is_empty():
		data["stats"] = [
			{"name": "Force", "short": "FOR", "description": "Puissance physique."},
			{"name": "Dextérité", "short": "DEX", "description": "Précision, agilité et vision."},
			{"name": "Constitution", "short": "CON", "description": "Résistance physique."},
			{"name": "Intelligence", "short": "INT", "description": "Savoir et analyse."},
			{"name": "Esprit", "short": "ESP", "description": "Volonté et magie."},
			{"name": "Charisme", "short": "CHA", "description": "Influence."},
		]
	return data


## Vue envoyée aux joueurs : règles, caractéristiques, classes, capacités et statuts.
static func for_player(content: Dictionary) -> Dictionary:
	var view := {"rules": content.get("rules", {}), "stats": content.get("stats", []), "universe": content.get("universe", "")}
	for kind in PLAYER_KINDS:
		view[kind] = content.get(kind, {})
	# Objets des kits et choix de classe (pour l'assistant de création), pas le reste du catalogue.
	var items := {}
	for cls in content.get("classes", {}).values():
		for k in cls.get("kit", []):
			var id := String(k.get("item", ""))
			if content.get("items", {}).has(id):
				items[id] = content.items[id]
		for ch in cls.get("choices", []):
			for id in ch.get("options", []):
				if content.get("items", {}).has(String(id)):
					items[String(id)] = content.items[String(id)]
	view["items"] = items
	return view


static func rules(content: Dictionary) -> Dictionary:
	return content.get("rules", DEFAULT_RULES)


static func rule(content: Dictionary, key: String) -> Variant:
	return content.get("rules", {}).get(key, DEFAULT_RULES.get(key, 0))


static func stat_names(content: Dictionary) -> Array:
	var names: Array = []
	for s in content.get("stats", []):
		names.append(String(s.get("name", "")))
	return names if not names.is_empty() else ["Force", "Dextérité", "Constitution", "Intelligence", "Esprit", "Charisme"]


static func stat_info(content: Dictionary, stat_name: String) -> Dictionary:
	for s in content.get("stats", []):
		if s.get("name", "") == stat_name:
			return s
	return {"name": stat_name, "short": stat_name.substr(0, 3).to_upper(), "description": ""}


static func get_entry(content: Dictionary, kind: String, id: String) -> Dictionary:
	return content.get(kind, {}).get(id, {})


static func list(content: Dictionary, kind: String) -> Array:
	var out: Array = content.get(kind, {}).values()
	out.sort_custom(func(a, b): return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0)
	return out


## Copie d'une capacité du catalogue, prête à être apprise par un personnage.
static func ability_copy(content: Dictionary, id: String, equipped: bool = false) -> Dictionary:
	var a := get_entry(content, "abilities", id)
	if a.is_empty():
		return {}
	var copy: Dictionary = a.duplicate(true)
	copy["rank"] = 1
	copy["equipped"] = equipped
	return copy


## Instance d'objet (identifiant unique) à partir d'un identifiant du catalogue ou d'une définition complète.
static func item_instance(content: Dictionary, source: Variant, qty: int = 1) -> Dictionary:
	var def: Dictionary = get_entry(content, "items", String(source)) if source is String else (source as Dictionary)
	if def.is_empty():
		return {}
	var inst: Dictionary = def.duplicate(true)
	inst["item_id"] = String(def.get("item_id", def.get("id", "")))
	inst.erase("id")
	inst["uid"] = "i_" + Protocol.random_hex(5)
	inst["qty"] = maxi(1, qty)
	inst["equipped"] = false
	return inst


static func rarity_color(rarity: String) -> Color:
	return Color(String(RARITY_COLORS.get(rarity, RARITY_COLORS.commun)))


static func make_id(prefix: String, text: String) -> String:
	var base := text.to_lower().strip_edges()
	for pair in [["é", "e"], ["è", "e"], ["ê", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ô", "o"], ["û", "u"], ["ù", "u"], ["ç", "c"], ["œ", "oe"], ["'", "_"], [" ", "_"], ["-", "_"]]:
		base = base.replace(pair[0], pair[1])
	var clean := ""
	for ch in base:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			clean += ch
	return "%s%s_%s" % [prefix, clean.substr(0, 24), Protocol.random_hex(2)]


# ---------------------------------------------------------------------------
# Validation des créations du MJ (champs connus, types et bornes)
# ---------------------------------------------------------------------------

static func sanitize(kind: String, input: Dictionary, content: Dictionary) -> Dictionary:
	match kind:
		"items":
			return sanitize_item(input, content)
		"abilities":
			return sanitize_ability(input)
		"statuses":
			return sanitize_status(input)
		"classes":
			return sanitize_class(input, content)
		"monsters":
			return sanitize_monster(input, content)
		"loot":
			return sanitize_loot(input)
	return {}


static func _text(v: Variant, n: int = 80) -> String:
	return Protocol.sanitize_text(v, n)


static func _int(v: Variant, lo: int, hi: int, fallback: int = 0) -> int:
	if v is int or v is float:
		return clampi(int(v), lo, hi)
	if v is String and (v as String).is_valid_int():
		return clampi(int(v), lo, hi)
	return fallback


static func _dice(v: Variant, fallback: String = "") -> String:
	var s := String(v).strip_edges() if v != null else ""
	if s == "":
		return fallback
	return s if Dice.roll(s, RandomNumberGenerator.new()).ok else fallback


static func sanitize_mods(raw: Variant) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for key in MOD_KEYS:
			if raw.has(key):
				var v := _int(raw[key], -99, 999)
				if v != 0:
					out[key] = v
	return out


static func sanitize_effects(raw: Variant, depth: int = 0) -> Array:
	var out: Array = []
	if not raw is Array or depth > 2:
		return out
	for e in raw:
		if not e is Dictionary or out.size() >= 12:
			continue
		var type := String(e.get("type", ""))
		if type not in EFFECT_TYPES:
			continue
		var f := {"type": type}
		var on := String(e.get("on", "target"))
		f.on = on if on in ["target", "self", "allies"] else "target"
		match type:
			"damage":
				f.dice = _dice(e.get("dice", "1d6"), "1d6")
				f.bonus = _int(e.get("bonus", 0), -99, 999)
				f.element = "magique" if String(e.get("element", "")) == "magique" else "physique"
				if String(e.get("stat", "")) != "":
					f.stat = _text(e.stat, 20)
			"heal":
				f.dice = _dice(e.get("dice", ""), "")
				f.amount = _int(e.get("amount", 0), 0, 999)
				f.bonus = _int(e.get("bonus", 0), -99, 999)
			"restore":
				f.resource = "hp" if String(e.get("resource", "res")) == "hp" else "res"
				f.amount = _int(e.get("amount", 1), -999, 999)
			"status":
				f.status = _text(e.get("status", ""), 40)
				f.turns = _int(e.get("turns", 1), 0, 99, 1)
				f.chance = _int(e.get("chance", 100), 0, 100, 100)
				f.value = _int(e.get("value", 0), 0, 999)
				if String(e.get("scale", "")) != "":
					f.scale = _text(e.scale, 20)
				if e.has("radius"):
					f.radius = _int(e.radius, 0, 10)
			"cleanse":
				f.count = _int(e.get("count", 1), 1, 10, 1)
			"push", "pull":
				f.cells = _int(e.get("cells", 1), 1, 6, 1)
			"ap":
				f.amount = _int(e.get("amount", 1), -4, 4, 1)
			"stat":
				f.stat = _text(e.get("stat", "Force"), 20)
				f.amount = _int(e.get("amount", 1), -10, 10, 1)
				f.turns = _int(e.get("turns", 2), 1, 99, 2)
			"drain":
				f.pct = _int(e.get("pct", 30), 1, 100, 30)
			"summon":
				f.name = _text(e.get("name", "Invocation"), 40)
				f.hp = _int(e.get("hp", 10), 1, 999, 10)
				f.attack = _dice(e.get("attack", "1d6"), "1d6")
				f.defense = _int(e.get("defense", 10), 0, 40, 10)
				f.color = String(e.get("color", "#9fc3d4")) if Color.html_is_valid(String(e.get("color", ""))) else "#9fc3d4"
			"if":
				var cond: Dictionary = e.get("cond", {}) if e.get("cond") is Dictionary else {}
				f.cond = sanitize_cond(cond)
				f.then = sanitize_effects(e.get("then", []), depth + 1)
				f["else"] = sanitize_effects(e.get("else", []), depth + 1)
			"narrate":
				f.text = _text(e.get("text", ""), 300)
		out.append(f)
	return out


static func sanitize_cond(raw: Dictionary) -> Dictionary:
	var c := {}
	for key in ["self_hp_below", "target_hp_below", "distance_min", "chance"]:
		if raw.has(key) and _int(raw[key], 0, 100) > 0:
			c[key] = _int(raw[key], 0, 100)
	for key in ["target_weak", "target_debuffed"]:
		if raw.get(key, false):
			c[key] = true
	if String(raw.get("target_has", "")) != "":
		c.target_has = _text(raw.target_has, 40)
	if String(raw.get("element", "")) != "":
		c.element = _text(raw.element, 20)
	return c


static func sanitize_ability(input: Dictionary) -> Dictionary:
	var a := {
		"id": _text(input.get("id", ""), 60), "name": _text(input.get("name", "Capacité"), 40),
		"short": _text(input.get("short", input.get("name", "")), 14), "icon": _text(input.get("icon", "star"), 20),
		"description": _text(input.get("description", ""), 500),
		"cost": _int(input.get("cost", 0), 0, 999), "ap": _int(input.get("ap", 1), 0, 6, 1),
		"range": _int(input.get("range", 1), 0, 30, 1), "cooldown": _int(input.get("cooldown", 0), 0, 99),
		"target": String(input.get("target", "enemy")) if String(input.get("target", "")) in TARGETS else "enemy",
		"radius": _int(input.get("radius", 0), 0, 6), "roll": "attack" if String(input.get("roll", "")) == "attack" else "none",
		"stat": _text(input.get("stat", "Force"), 20), "element": _text(input.get("element", "physique"), 20),
		"effects": sanitize_effects(input.get("effects", [])), "ultimate": bool(input.get("ultimate", false)),
	}
	if input.get("conditions") is Dictionary:
		a.conditions = sanitize_cond(input.conditions)
	if a.short == "":
		a.short = a.name.substr(0, 14)
	return a


static func sanitize_status(input: Dictionary) -> Dictionary:
	var s := {
		"id": _text(input.get("id", ""), 60), "name": _text(input.get("name", "Effet"), 40), "icon": _text(input.get("icon", "sparkle"), 20),
		"color": String(input.get("color", "#a07cc9")) if Color.html_is_valid(String(input.get("color", ""))) else "#a07cc9",
		"kind": "buff" if String(input.get("kind", "")) == "buff" else "debuff",
		"description": _text(input.get("description", ""), 300), "mods": sanitize_mods(input.get("mods", {})),
	}
	var flags: Array = []
	for f in input.get("flags", []):
		if String(f) in ["stun", "root", "silence", "shield", "untargetable", "break_on_attack"]:
			flags.append(String(f))
	s.flags = flags
	if input.get("tick") is Dictionary and String(input.tick.get("type", "")) in ["damage", "heal"]:
		s.tick = {"type": String(input.tick.type), "dice": _dice(input.tick.get("dice", "1d4"), "1d4")}
	return s


static func sanitize_item(input: Dictionary, _content: Dictionary) -> Dictionary:
	var category := String(input.get("category", "materiau"))
	if category not in CATEGORIES:
		category = "materiau"
	var rarity := String(input.get("rarity", "commun"))
	if rarity not in RARITIES:
		rarity = "commun"
	var slot := String(input.get("slot", ""))
	if slot not in SLOTS:
		slot = {"arme": "arme", "armure": "armure", "accessoire": "accessoire"}.get(category, "")
	var i := {
		"id": _text(input.get("id", ""), 60), "name": _text(input.get("name", "Objet"), 40), "icon": _text(input.get("icon", "bag"), 20),
		"category": category, "rarity": rarity, "description": _text(input.get("description", ""), 500),
		"value": _int(input.get("value", 0), 0, 999999), "slot": slot,
		"stackable": bool(input.get("stackable", category in ["consommable", "potion", "materiau"])), "unique": bool(input.get("unique", false)),
		"mods": sanitize_mods(input.get("mods", {})),
	}
	if input.get("weapon") is Dictionary or category == "arme":
		var w: Dictionary = input.get("weapon", {}) if input.get("weapon") is Dictionary else {}
		i.weapon = {"damage": _dice(w.get("damage", "1d6"), "1d6"), "stat": _text(w.get("stat", "Force"), 20),
			"crit": _int(w.get("crit", 20), 2, 20, 20), "range": _int(w.get("range", 1), 1, 30, 1),
			"element": "magique" if String(w.get("element", "")) == "magique" else "physique"}
	var use := sanitize_effects(input.get("use", []))
	if not use.is_empty():
		i.use = use
	var on_hit := sanitize_effects(input.get("on_hit", []))
	if not on_hit.is_empty():
		i.on_hit = on_hit
	var grants: Array = []
	for g in input.get("grants", []):
		grants.append(_text(g, 60))
	if not grants.is_empty():
		i.grants = grants
	if String(input.get("teaches", "")) != "":
		i.teaches = _text(input.teaches, 60)
	return i


static func sanitize_class(input: Dictionary, content: Dictionary) -> Dictionary:
	var stats := stat_names(content)
	var bonus := {}
	for s in stats:
		var v := _int(input.get("bonus", {}).get(s, 0), -5, 5) if input.get("bonus") is Dictionary else 0
		if v != 0:
			bonus[s] = v
	var res: Dictionary = input.get("resource", {}) if input.get("resource") is Dictionary else {}
	var abilities: Array = []
	for a in input.get("abilities", []):
		if String(a) != "" and abilities.size() < 6:
			abilities.append(_text(a, 60))
	var learnable: Array = []
	for l in input.get("learnable", []):
		if l is Dictionary and String(l.get("ability", "")) != "":
			learnable.append({"ability": _text(l.ability, 60), "level": _int(l.get("level", 2), 1, 99, 2)})
	var passive: Dictionary = input.get("passive", {}) if input.get("passive") is Dictionary else {}
	var rec := {}
	for s in stats:
		rec[s] = _int(input.get("recommended", {}).get(s, 0), -10, 20) if input.get("recommended") is Dictionary else 0
	return {
		"id": _text(input.get("id", ""), 60), "name": _text(input.get("name", "Classe"), 40), "tagline": _text(input.get("tagline", ""), 120),
		"role": _text(input.get("role", ""), 40), "description": _text(input.get("description", ""), 600),
		"color": String(input.get("color", "#8a8f9a")) if Color.html_is_valid(String(input.get("color", ""))) else "#8a8f9a",
		"emblem": _text(input.get("emblem", "sword"), 20), "difficulty": _int(input.get("difficulty", 1), 1, 3, 1),
		"bonus": bonus, "hp_base": _int(input.get("hp_base", 14), 1, 999, 14), "hp_per_level": _int(input.get("hp_per_level", 5), 0, 99, 5),
		"resource": {"name": _text(res.get("name", "Mana"), 20), "stat": _text(res.get("stat", "Esprit"), 20), "base": _int(res.get("base", 8), 0, 999, 8)},
		"speed": _int(input.get("speed", 5), 1, 20, 5), "crit_bonus": _int(input.get("crit_bonus", 0), 0, 10),
		"defense_bonus": _int(input.get("defense_bonus", 0), -5, 20), "attack_bonus": _int(input.get("attack_bonus", 0), -5, 20),
		"passive": sanitize_passive(passive), "abilities": abilities, "ultimate": _text(input.get("ultimate", ""), 60),
		"learnable": learnable, "kit": input.get("kit", []) if input.get("kit") is Array else [],
		"choices": input.get("choices", []) if input.get("choices") is Array else [], "recommended": rec,
		"magic": input.get("magic", {}) if input.get("magic") is Dictionary else {},
	}


static func sanitize_passive(p: Dictionary) -> Dictionary:
	var trigger := String(p.get("trigger", "always"))
	if trigger not in ["always", "turn_start", "on_hit", "on_kill", "on_damaged", "ally_damaged", "on_heal"]:
		trigger = "always"
	var out := {
		"name": _text(p.get("name", ""), 40), "description": _text(p.get("description", ""), 300), "icon": _text(p.get("icon", "star"), 20),
		"trigger": trigger, "cond": sanitize_cond(p.get("cond", {}) if p.get("cond") is Dictionary else {}),
		"mods": sanitize_mods(p.get("mods", {})), "effects": sanitize_effects(p.get("effects", [])),
		"reduce": _int(p.get("reduce", 0), 0, 99), "range": _int(p.get("range", 0), 0, 10),
	}
	if String(p.get("mods", {}).get("damage_dice", "") if p.get("mods") is Dictionary else "") != "":
		out.mods["damage_dice"] = _dice(p.mods.damage_dice, "1d6")
	return out


static func sanitize_monster(input: Dictionary, content: Dictionary) -> Dictionary:
	var stats := {}
	for s in stat_names(content):
		stats[s] = _int(input.get("stats", {}).get(s, 5), 1, 30, 5) if input.get("stats") is Dictionary else 5
	var w: Dictionary = input.get("weapon", {}) if input.get("weapon") is Dictionary else {}
	var abilities: Array = []
	for a in input.get("abilities", []):
		abilities.append(_text(a, 60))
	return {
		"id": _text(input.get("id", ""), 60), "name": _text(input.get("name", "Monstre"), 40), "description": _text(input.get("description", ""), 500),
		"color": String(input.get("color", "#8a6a4a")) if Color.html_is_valid(String(input.get("color", ""))) else "#8a6a4a",
		"icon": _text(input.get("icon", "skull"), 20), "stats": stats, "hp": _int(input.get("hp", 20), 1, 99999, 20),
		"weapon": {"damage": _dice(w.get("damage", "1d6"), "1d6"), "stat": _text(w.get("stat", "Force"), 20), "crit": _int(w.get("crit", 20), 2, 20, 20),
			"range": _int(w.get("range", 1), 1, 30, 1), "element": "magique" if String(w.get("element", "")) == "magique" else "physique"},
		"abilities": abilities, "xp": _int(input.get("xp", 20), 0, 999999, 20), "loot": _text(input.get("loot", ""), 60),
		"defense_bonus": _int(input.get("defense_bonus", 0), -10, 30), "boss": bool(input.get("boss", false)),
		"speed": _int(input.get("speed", 5), 1, 20, 5), "res": _int(input.get("res", 10), 0, 999, 10),
		"power": _int(input.get("power", 2), 0, 99, 2),
	}


static func sanitize_loot(input: Dictionary) -> Dictionary:
	var entries: Array = []
	for e in input.get("entries", []):
		if e is Dictionary and String(e.get("item", "")) != "":
			var lo := _int(e.get("min", 1), 1, 999, 1)
			entries.append({"item": _text(e.item, 60), "chance": _int(e.get("chance", 50), 0, 100, 50), "min": lo, "max": maxi(lo, _int(e.get("max", lo), 1, 999, lo))})
	var guaranteed: Array = []
	for g in input.get("guaranteed", []):
		if g is Dictionary and String(g.get("item", "")) != "":
			guaranteed.append({"item": _text(g.item, 60), "qty": _int(g.get("qty", 1), 1, 999, 1)})
	var gold: Array = input.get("gold", [0, 0]) if input.get("gold") is Array and (input.gold as Array).size() == 2 else [0, 0]
	var glo := _int(gold[0], 0, 999999)
	return {"id": _text(input.get("id", ""), 60), "name": _text(input.get("name", "Butin"), 40), "entries": entries,
		"guaranteed": guaranteed, "gold": [glo, maxi(glo, _int(gold[1], 0, 999999))]}
