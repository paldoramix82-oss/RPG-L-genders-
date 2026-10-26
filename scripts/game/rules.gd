class_name Rules
extends RefCounted
## Règles automatiques : répartition des points, valeurs dérivées (PV, ressource,
## Défense, résistances, initiative, vitesse, PA), profils d'attaque et paliers d'XP.
##
## Toutes les fonctions prennent le catalogue de la campagne (`content`, voir
## Content) : le MJ peut modifier les règles et les classes en cours de partie.
## Une fiche « auto » (assistant) est recalculée par l'hôte ; une fiche « libre »
## garde ses PV / Défense saisis, mais profite des mêmes formules de combat.
##
## Formules (échelle 1–10, 5 = moyen) :
##   PV max      = PV de classe + Constitution × hp_per_con (2) + gain par niveau
##   Ressource   = base de classe + carac. de la ressource × res_per_stat
##   Défense     = defense_base + Dextérité + armure + bonus
##   Résistances = Constitution ÷ 4 (physique), Esprit ÷ 4 (magique) + équipement
##   Toucher     = d20 + carac. de l'arme + bonus ≥ Défense
##   Dégâts      = dés + carac. ÷ 2 + bonus − résistance (minimum 1)
##   Soins       = dés + Esprit ÷ 2, augmentés des bonus de soins (%)

const UNARMED := {"name": "Mains nues", "weapon": {"damage": "1d4", "stat": "Force", "crit": 20, "range": 1, "element": "physique"}}


static func classes(content: Dictionary) -> Array:
	return Content.list(content, "classes")


static func get_class_def(content: Dictionary, class_id: String) -> Dictionary:
	return Content.get_entry(content, "classes", class_id)


# ---------------------------------------------------------------------------
# Création : répartition des points
# ---------------------------------------------------------------------------

## alloc : points ajoutés (ou retirés) à la valeur de départ de chaque caractéristique.
static func points_spent(alloc: Dictionary, content: Dictionary = {}) -> int:
	var total := 0
	for s in Content.stat_names(content):
		total += int(alloc.get(s, 0))
	return total


static func points_left(alloc: Dictionary, content: Dictionary) -> int:
	return int(Content.rule(content, "stat_pool")) - points_spent(alloc, content)


static func alloc_bounds(content: Dictionary) -> Vector2i:
	var base := int(Content.rule(content, "stat_base"))
	return Vector2i(int(Content.rule(content, "stat_min")) - base, int(Content.rule(content, "stat_max")) - base)


## Répartition valide : chaque caractéristique dans les bornes, réserve non dépassée.
static func valid_alloc(alloc: Dictionary, content: Dictionary) -> bool:
	var b := alloc_bounds(content)
	for s in Content.stat_names(content):
		var v := int(alloc.get(s, 0))
		if v < b.x or v > b.y:
			return false
	return points_spent(alloc, content) <= int(Content.rule(content, "stat_pool"))


static func get_species(content: Dictionary, species_id: String) -> Dictionary:
	return Content.get_entry(content, "species", species_id)


## Synergie entre le peuple et la classe d'une fiche ({} s'il n'y en a pas).
static func synergy(content: Dictionary, species_id: String, class_id: String) -> Dictionary:
	return get_species(content, species_id).get("synergies", {}).get(class_id, {})


static func stat_values(alloc: Dictionary, cls: Dictionary, content: Dictionary, trained: Dictionary = {}, species: Dictionary = {}) -> Dictionary:
	var out := {}
	var bonus: Dictionary = cls.get("bonus", {})
	var sp: Dictionary = species.get("stats", {})
	var base := int(Content.rule(content, "stat_base"))
	var cap := int(Content.rule(content, "stat_cap"))
	for s in Content.stat_names(content):
		out[s] = clampi(base + int(alloc.get(s, 0)) + int(bonus.get(s, 0)) + int(sp.get(s, 0)) + int(trained.get(s, 0)), 1, maxi(cap, 30))
	return out


# ---------------------------------------------------------------------------
# Caractéristiques effectives et bonus
# ---------------------------------------------------------------------------

static func base_stat(sheet: Dictionary, stat_name: String) -> int:
	for s in sheet.get("stats", []):
		if String(s.get("name", "")) == stat_name:
			return int(s.get("value", 5))
	return 5


## Somme des bonus : peuple (et synergie avec la classe) + objets équipés + effets en cours (statuts).
static func mods(sheet: Dictionary, content: Dictionary) -> Dictionary:
	var total := {}
	var sid := String(sheet.get("species_id", ""))
	if sid != "":
		_add_mods(total, get_species(content, sid).get("mods", {}))
		_add_mods(total, synergy(content, sid, String(sheet.get("class_id", ""))).get("mods", {}))
	for item in sheet.get("inventory", []):
		if item.get("equipped", false):
			_add_mods(total, item.get("mods", {}))
	for e in sheet.get("effects", []):
		_add_mods(total, status_mods(e, content))
	return total


static func status_mods(effect: Dictionary, content: Dictionary) -> Dictionary:
	if effect.get("mods") is Dictionary and not (effect.mods as Dictionary).is_empty():
		return effect.mods
	return Content.get_entry(content, "statuses", String(effect.get("id", ""))).get("mods", {})


static func _add_mods(total: Dictionary, add: Variant) -> void:
	if not add is Dictionary:
		return
	for key in add:
		if add[key] is int or add[key] is float:
			total[key] = int(total.get(key, 0)) + int(add[key])


## Caractéristique effective (équipement et effets compris).
static func stat(sheet: Dictionary, stat_name: String, content: Dictionary = {}, m: Dictionary = {}) -> int:
	if m.is_empty() and not content.is_empty():
		m = mods(sheet, content)
	return maxi(0, base_stat(sheet, stat_name) + int(m.get(stat_name, 0)))


## Valeurs dérivées d'une fiche.
static func derived(sheet: Dictionary, content: Dictionary) -> Dictionary:
	var cls := get_class_def(content, String(sheet.get("class_id", "")))
	var r := Content.rules(content)
	var m := mods(sheet, content)
	var level := maxi(1, int(sheet.get("level", 1)))
	var dex := stat(sheet, "Dextérité", content, m)
	var con := stat(sheet, "Constitution", content, m)
	var esp := stat(sheet, "Esprit", content, m)
	var res: Dictionary = cls.get("resource", {})
	var res_stat := String(res.get("stat", sheet.get("res_stat", "Esprit")))
	var d := {
		"hp_max": int(cls.get("hp_base", 14)) + con * int(r.get("hp_per_con", 3)) + (level - 1) * int(cls.get("hp_per_level", 5)) + int(m.get("hp_max", 0)),
		"res_max": int(res.get("base", 8)) + stat(sheet, res_stat, content, m) * int(r.get("res_per_stat", 2)) + (level - 1) * 2 + int(m.get("res_max", 0)),
		"res_name": String(res.get("name", sheet.get("res_name", "Énergie"))),
		"defense": int(r.get("defense_base", 8)) + dex + int(m.get("defense", 0)) + int(cls.get("defense_bonus", 0)) + int(sheet.get("defense_bonus", 0)),
		"resist_phys": con / 4 + int(m.get("resist_phys", 0)),
		"resist_mag": esp / 4 + int(m.get("resist_mag", 0)),
		"initiative": dex,
		"speed": maxi(1, int(cls.get("speed", sheet.get("speed", 5) if int(sheet.get("speed", 0)) > 0 else 5)) + int(m.get("speed", 0))),
		"to_hit": int(cls.get("attack_bonus", 0)) + (level - 1) / 4 + int(m.get("to_hit", 0)),
		"damage": int(m.get("damage", 0)),
		"damage_taken": int(m.get("damage_taken", 0)),
		"heal_pct": int(m.get("heal_pct", 0)),
		"crit_bonus": int(cls.get("crit_bonus", 0)) + int(m.get("crit", 0)),
		"ap": maxi(0, int(r.get("ap_per_turn", 2)) + int(m.get("ap", 0))),
		"vision": maxi(1, int(r.get("vision_base", 3)) + dex / maxi(1, int(r.get("vision_dex_div", 2))) + int(m.get("vision", 0))),
		"mods": m,
	}
	var passive: Dictionary = sheet.get("passive", {})
	if String(passive.get("trigger", "")) == "always" and (passive.get("cond", {}) as Dictionary).is_empty():
		var pm: Dictionary = passive.get("mods", {})
		d.heal_pct += int(pm.get("heal_pct", 0))
		d.defense += int(pm.get("defense", 0))
		d.damage += int(pm.get("damage", 0))
		d.to_hit += int(pm.get("to_hit", 0))
	if not sheet.get("auto", false):
		# Fiche libre ou monstre : les valeurs saisies priment (avec les bonus d'équipement).
		if int(sheet.get("hp_max", 0)) > 0:
			d.hp_max = int(sheet.hp_max) + int(m.get("hp_max", 0))
		if int(sheet.get("res_max", -1)) >= 0 and cls.is_empty():
			d.res_max = int(sheet.get("res_max", 0)) + int(m.get("res_max", 0))
		if int(sheet.get("defense", 0)) > 0:
			d.defense = int(sheet.defense) + int(m.get("defense", 0))
		if int(sheet.get("speed", 0)) > 0 and cls.is_empty():
			d.speed = maxi(1, int(sheet.speed) + int(m.get("speed", 0)))
		if cls.is_empty() and String(sheet.get("res_name", "")) != "":
			d.res_name = String(sheet.res_name)
	d.hp_max = maxi(1, d.hp_max)
	d.res_max = maxi(0, d.res_max)
	return d


# ---------------------------------------------------------------------------
# Armes et attaques
# ---------------------------------------------------------------------------

static func equipped(sheet: Dictionary, slot: String = "") -> Array:
	return sheet.get("inventory", []).filter(func(i): return i.get("equipped", false) and (slot == "" or String(i.get("slot", "")) == slot))


static func weapons(sheet: Dictionary) -> Array:
	var list := equipped(sheet, "arme").filter(func(i): return i.get("weapon") is Dictionary)
	if list.is_empty():
		list = [UNARMED]
	return list


## Profil d'une attaque à l'arme : bonus de toucher, dés et bonus de dégâts, seuil de critique, portée.
static func attack_profile(sheet: Dictionary, content: Dictionary, weapon_item: Dictionary) -> Dictionary:
	var d := derived(sheet, content)
	var w: Dictionary = weapon_item.get("weapon", UNARMED.weapon)
	var stat_name := String(w.get("stat", "Force"))
	var sv := stat(sheet, stat_name, content, d.mods)
	return {
		"name": String(weapon_item.get("name", "Attaque")),
		"to_hit": sv + int(d.to_hit),
		"damage": String(w.get("damage", "1d4")),
		"damage_bonus": sv / 2 + int(d.damage),
		"crit": clampi(int(w.get("crit", 20)) - int(d.crit_bonus), 2, 20),
		"range": maxi(1, int(w.get("range", 1))),
		"element": String(w.get("element", "physique")),
		"stat": stat_name,
		"on_hit": weapon_item.get("on_hit", []),
	}


## Capacités équipées (barre rapide) : de base puis ultime.
static func equipped_abilities(sheet: Dictionary) -> Array:
	var basics: Array = []
	var ults: Array = []
	for a in sheet.get("abilities", []):
		if a.get("equipped", false):
			(ults if a.get("ultimate", false) else basics).append(a)
	return basics + ults


## Capacités utilisables : équipées + accordées par l'équipement.
static func usable_abilities(sheet: Dictionary, content: Dictionary) -> Array:
	var list := equipped_abilities(sheet)
	for item in equipped(sheet):
		for id in item.get("grants", []):
			var a := Content.ability_copy(content, String(id), true)
			if not a.is_empty() and list.filter(func(x): return x.get("id", "") == a.id).is_empty():
				a["granted"] = String(item.get("name", ""))
				list.append(a)
	return list


static func find_ability(sheet: Dictionary, content: Dictionary, ability_id: String) -> Dictionary:
	for a in usable_abilities(sheet, content):
		if String(a.get("id", "")) == ability_id:
			return a
	return {}


# ---------------------------------------------------------------------------
# Construction et recalcul d'une fiche
# ---------------------------------------------------------------------------

## Fiche complète à partir d'une classe, d'une répartition et des choix d'équipement.
static func build_sheet(base: Dictionary, content: Dictionary, class_id: String, alloc: Dictionary, choices: Array, species_id: String = "") -> Dictionary:
	var sheet := base.duplicate(true)
	var cls := get_class_def(content, class_id)
	if cls.is_empty():
		return sheet
	sheet.class_id = class_id
	var sp := get_species(content, species_id)
	sheet.species_id = species_id if not sp.is_empty() else ""
	if not sp.is_empty():
		sheet.species = String(sp.name)
	sheet.auto = true
	sheet.alloc = {}
	for s in Content.stat_names(content):
		sheet.alloc[s] = int(alloc.get(s, 0))
	sheet.trained = {}
	var values := stat_values(sheet.alloc, cls, content, {}, sp)
	sheet.stats = Content.stat_names(content).map(func(s): return {"name": s, "value": values[s]})
	var abilities: Array = []
	for id in cls.get("abilities", []):
		var a := Content.ability_copy(content, String(id), true)
		if not a.is_empty():
			abilities.append(a)
	var ult := Content.ability_copy(content, String(cls.get("ultimate", "")), true)
	if not ult.is_empty():
		ult.ultimate = true
		abilities.append(ult)
	# Capacités innées du peuple (et de la synergie peuple + classe) : toujours
	# équipées, elles ne prennent pas d'emplacement.
	var innate: Array = sp.get("abilities", []).duplicate()
	innate.append_array(synergy(content, species_id, class_id).get("abilities", []))
	for id in innate:
		var a := Content.ability_copy(content, String(id), true)
		if not a.is_empty():
			a.innate = true
			abilities.append(a)
	sheet.abilities = abilities
	sheet.passive = (cls.get("passive", {}) as Dictionary).duplicate(true)
	var inventory: Array = []
	for k in cls.get("kit", []):
		var inst := Content.item_instance(content, String(k.get("item", "")), int(k.get("qty", 1)))
		if not inst.is_empty():
			inst.equipped = bool(k.get("equip", false)) and String(inst.get("slot", "")) != ""
			inventory.append(inst)
	var groups: Array = cls.get("choices", [])
	for i in groups.size():
		var options: Array = groups[i].get("options", [])
		if options.is_empty():
			continue
		var pick := clampi(int(choices[i]) if i < choices.size() else 0, 0, options.size() - 1)
		var inst := Content.item_instance(content, String(options[pick]), 1)
		if inst.is_empty():
			continue
		var slot := String(inst.get("slot", ""))
		if slot != "":
			var used := inventory.filter(func(x): return x.equipped and String(x.get("slot", "")) == slot).size()
			if used >= int(Content.SLOTS.get(slot, 1)):
				for x in inventory:
					if x.equipped and String(x.get("slot", "")) == slot:
						x.equipped = false
						break
			inst.equipped = true
		inventory.push_front(inst)
	# Équipement de départ commun (potion, rations, torche, corde…).
	for k in content.get("starter_kit", []):
		var inst := Content.item_instance(content, String(k.get("item", "")), int(k.get("qty", 1)))
		if not inst.is_empty():
			inst.equipped = false
			Inventory.add({"inventory": inventory}, inst)
	sheet.inventory = inventory
	sheet.gold = int(Content.rule(content, "start_gold"))
	sheet.res_name = String(cls.get("resource", {}).get("name", "Énergie"))
	sheet.ult = 0
	sheet.cooldowns = {}
	sheet.pending = {"stat_points": 0, "picks": 0}
	var magic: Dictionary = cls.get("magic", {})
	if not magic.is_empty():
		var mg: Dictionary = sheet.get("magic", {})
		for key in ["category", "name", "description"]:
			if String(mg.get(key, "")) == "":
				mg[key] = magic.get(key, "")
		sheet.magic = mg
	if String(sheet.get("concept", "")) == "":
		sheet.concept = String(cls.name)
	return refresh(sheet, content, true)


## Recalcule les valeurs d'une fiche (PV et ressource conservés, plafonnés).
static func refresh(sheet: Dictionary, content: Dictionary, full_heal: bool = false) -> Dictionary:
	if sheet.get("auto", false):
		var cls := get_class_def(content, String(sheet.get("class_id", "")))
		if not cls.is_empty() and sheet.get("alloc") is Dictionary:
			var values := stat_values(sheet.alloc, cls, content, sheet.get("trained", {}), get_species(content, String(sheet.get("species_id", ""))))
			var stats: Array = []
			for s in Content.stat_names(content):
				stats.append({"name": s, "value": values[s]})
			sheet.stats = stats
	var d := derived(sheet, content)
	if sheet.get("auto", false):
		sheet.hp_max = d.hp_max
		sheet.res_max = d.res_max
		sheet.defense = d.defense
		sheet.speed = d.speed
		sheet.res_name = d.res_name
	if full_heal:
		sheet.hp = d.hp_max
		sheet.res = d.res_max
	else:
		sheet.hp = clampi(int(sheet.get("hp", d.hp_max)), 0, d.hp_max)
		sheet.res = clampi(int(sheet.get("res", d.res_max)), 0, d.res_max)
	return sheet


# ---------------------------------------------------------------------------
# Progression
# ---------------------------------------------------------------------------

## XP totale nécessaire pour atteindre un niveau (palier triangulaire : 100, 300, 600, 1000…).
static func xp_for_level(level: int, content: Dictionary) -> int:
	var base := int(Content.rule(content, "xp_base"))
	return base * (level - 1) * level / 2


static func level_progress(sheet: Dictionary, content: Dictionary) -> Dictionary:
	var level := maxi(1, int(sheet.get("level", 1)))
	var lo := xp_for_level(level, content)
	var hi := xp_for_level(level + 1, content)
	return {"level": level, "xp": int(sheet.get("xp", 0)), "from": lo, "to": hi,
		"ratio": clampf(float(int(sheet.get("xp", 0)) - lo) / maxf(1.0, hi - lo), 0.0, 1.0)}


## Capacités que la classe peut encore apprendre à ce niveau.
static func learnable_now(sheet: Dictionary, content: Dictionary) -> Array:
	var cls := get_class_def(content, String(sheet.get("class_id", "")))
	var known: Array = sheet.get("abilities", []).map(func(a): return String(a.get("id", "")))
	var out: Array = []
	for l in cls.get("learnable", []):
		var id := String(l.get("ability", ""))
		if int(l.get("level", 2)) <= int(sheet.get("level", 1)) and not known.has(id):
			var a := Content.get_entry(content, "abilities", id)
			if not a.is_empty():
				out.append(a)
	return out


static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
