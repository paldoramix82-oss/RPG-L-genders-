class_name Migrate
extends RefCounted
## Conversion des anciennes fiches (format 1 : caractéristiques sur 10 ± modificateur,
## capacités et objets « texte ») vers le format actuel. Utilisée au chargement des
## anciennes sauvegardes et à l'import des anciens packs de PNJ.

const STAT_RENAME := {"Agilité": "Dextérité", "Endurance": "Constitution", "Perception": "Esprit"}
const CLASS_RENAME := {"pretre": "soigneur"}


static func needs(sheet: Dictionary) -> bool:
	return int(sheet.get("schema", 1)) < CharacterData.SCHEMA


static func stat_name(old: String) -> String:
	return String(STAT_RENAME.get(old, old))


## Ancienne fiche → fiche actuelle (les champs narratifs sont conservés tels quels).
static func sheet(old: Dictionary, content: Dictionary, universe: Dictionary) -> Dictionary:
	if not needs(old):
		return old
	var id := String(old.get("id", "npc_" + Protocol.random_hex(4)))
	var out := CharacterData.create(universe, id, String(old.get("owner", "")), String(old.get("name", "")), content)
	for key in CharacterData.NARRATIVE_FIELDS + ["rank", "status", "kind"]:
		if old.has(key):
			out[key] = old[key]
	for key in ["magic", "pawn"]:
		if old.get(key) is Dictionary:
			out[key] = (old[key] as Dictionary).duplicate(true)
	out.level = maxi(1, int(old.get("level", 1)))
	out.xp = int(old.get("xp", 0))
	# Caractéristiques : échelle 10 ± modificateur → échelle 1–10.
	var values := {}
	for s in old.get("stats", []):
		var n := stat_name(String(s.get("name", "")))
		values[n] = clampi(roundi(float(s.get("value", 10)) / 2.0), 1, 10)
	if values.has("Perception") and not values.has("Esprit"):
		values["Esprit"] = values["Perception"]
	out.stats = Content.stat_names(content).map(func(s): return {"name": s, "value": int(values.get(s, 5))})
	var abilities: Array = []
	for a in old.get("abilities", []):
		var conv := ability(a)
		if not conv.is_empty():
			conv.equipped = abilities.size() < int(Content.rule(content, "slots_basic"))
			abilities.append(conv)
	var inventory: Array = []
	for i in old.get("inventory", []):
		var conv := item(i)
		if not conv.is_empty():
			inventory.append(conv)
	var class_id := String(CLASS_RENAME.get(String(old.get("class_id", "")), String(old.get("class_id", ""))))
	if old.get("auto", false) and not Rules.get_class_def(content, class_id).is_empty():
		# Fiche créée avec l'assistant : reconstruite avec la répartition conseillée de sa classe,
		# en gardant l'inventaire du joueur.
		var cls := Rules.get_class_def(content, class_id)
		var built := Rules.build_sheet(out, content, class_id, cls.get("recommended", {}), [0])
		if not inventory.is_empty():
			built.inventory = inventory
		built.level = out.level
		built = Rules.refresh(built, content, true)
		var ratio := float(old.get("hp", 1)) / maxf(1.0, float(old.get("hp_max", 1)))
		built.hp = clampi(roundi(ratio * built.hp_max), 0, built.hp_max)
		built.schema = CharacterData.SCHEMA
		return built
	out.class_id = class_id
	out.abilities = abilities
	out.inventory = inventory
	out.hp_max = maxi(1, int(old.get("hp_max", 20)))
	out.hp = clampi(int(old.get("hp", out.hp_max)), 0, out.hp_max)
	out.res_max = maxi(0, int(old.get("res_max", 10)))
	out.res = clampi(int(old.get("res", out.res_max)), 0, out.res_max)
	out.defense = int(old.get("defense", 0))
	out.speed = int(old.get("speed", 0))
	out.schema = CharacterData.SCHEMA
	return out


## Ancienne capacité (attaque / soin / effet décrit) → capacité en données.
static func ability(a: Dictionary) -> Dictionary:
	var name := String(a.get("name", "")).strip_edges()
	if name == "":
		return {}
	var kind := String(a.get("kind", ""))
	var rng := int(a.get("range", 1))
	var st := stat_name(String(a.get("stat", "Force")))
	var conv := {
		"id": Content.make_id("ab_", name), "name": name, "short": name.substr(0, 14), "icon": "star",
		"description": String(a.get("description", "")), "cost": int(a.get("res_cost", 0)), "ap": 1,
		"range": rng, "cooldown": 0, "target": "any", "radius": 0, "roll": "none", "stat": st,
		"element": "physique", "effects": [], "ultimate": false, "rank": 1, "equipped": false,
	}
	match kind:
		"attack":
			conv.target = "enemy"
			conv.roll = "attack"
			conv.icon = "sword"
			conv.effects = [{"type": "damage", "dice": String(a.get("damage", "1d6")), "on": "target"}]
		"heal":
			conv.target = "ally" if rng > 0 else "self"
			conv.icon = "heart"
			conv.element = "soin"
			conv.effects = [{"type": "heal", "dice": String(a.get("heal", "1d6")), "on": "target"}]
		_:
			conv.icon = "sparkle"
			conv.effects = [{"type": "narrate", "text": String(a.get("description", "")), "on": "target"}]
			if String(a.get("effects", "")) != "":
				conv.description += "\n" + String(a.effects)
	if String(a.get("cost", "")) != "" and kind == "":
		conv.description = "Coût : %s. %s" % [a.cost, conv.description]
	return Content.sanitize_ability(conv).merged({"rank": 1, "equipped": false})


## Ancien objet (ligne d'inventaire) → instance d'objet.
static func item(i: Dictionary) -> Dictionary:
	var name := String(i.get("name", "")).strip_edges()
	if name == "":
		return {}
	var category := String(i.get("category", "objet"))
	var def := {"name": name, "description": String(i.get("description", "")), "rarity": "commun", "icon": "bag", "value": 0}
	match category:
		"arme":
			def.category = "arme"
			def.icon = "sword"
			def.weapon = {"damage": String(i.get("damage", "1d6")), "stat": stat_name(String(i.get("stat", "Force"))) if String(i.get("stat", "")) != "" else "Force",
				"crit": int(i.get("crit", 20)), "range": int(i.get("range", 1)), "element": "physique"}
			if String(i.get("effect", "")) == "ignore_defense_1":
				def.mods = {"to_hit": 1}
		"armure", "bouclier":
			def.category = "armure"
			def.icon = "armor" if category == "armure" else "shield"
			def.slot = "armure" if category == "armure" else "accessoire"
			def.mods = {"defense": maxi(0, int(i.get("defense", 0)) - 1)} if category == "armure" else {"defense": int(i.get("defense", 1))}
		"consommable":
			def.category = "consommable"
			def.icon = "potion"
			var dice := String(i.get("heal", ""))
			if dice != "" and dice != "0":
				def.use = [{"type": "heal", "dice": dice, "on": "self"}]
		_:
			def.category = "materiau"
	var clean := Content.sanitize_item(def, {})
	clean.erase("id")
	clean.item_id = ""
	clean.uid = "i_" + Protocol.random_hex(5)
	clean.qty = maxi(1, int(i.get("qty", 1)))
	clean.equipped = bool(i.get("equipped", false)) and String(clean.get("slot", "")) != ""
	return clean
