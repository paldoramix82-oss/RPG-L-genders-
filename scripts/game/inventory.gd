class_name Inventory
extends RefCounted
## Inventaire d'une fiche : instances d'objets (identifiant unique `uid`),
## empilement, emplacements d'équipement, aperçu des changements, butin.

const MAX_ITEMS := 60


static func find(sheet: Dictionary, uid: String) -> Dictionary:
	for i in sheet.get("inventory", []):
		if String(i.get("uid", "")) == uid:
			return i
	return {}


## Ajoute une instance (empile si l'objet est empilable et déjà présent). Renvoie l'instance finale.
static func add(sheet: Dictionary, inst: Dictionary) -> Dictionary:
	if not sheet.get("inventory") is Array:
		sheet.inventory = []
	var inv: Array = sheet.inventory
	if inst.get("stackable", false):
		for i in inv:
			if i.get("stackable", false) and String(i.get("name", "")) == String(inst.get("name", "")) \
					and String(i.get("item_id", "")) == String(inst.get("item_id", "")):
				i.qty = int(i.get("qty", 1)) + int(inst.get("qty", 1))
				return i
	if inv.size() >= MAX_ITEMS:
		return {}
	var copy := inst.duplicate(true)
	copy.equipped = false
	if String(copy.get("uid", "")) == "":
		copy.uid = "i_" + Protocol.random_hex(5)
	inv.append(copy)
	return copy


## Retire `qty` exemplaires. Renvoie le nombre réellement retiré.
static func consume(sheet: Dictionary, uid: String, qty: int = 1) -> int:
	var inv: Array = sheet.get("inventory", [])
	for i in inv.size():
		if String(inv[i].get("uid", "")) == uid:
			var have := int(inv[i].get("qty", 1))
			var take := mini(have, qty)
			if have - take <= 0:
				inv.remove_at(i)
			else:
				inv[i].qty = have - take
			return take
	return 0


## Objets équipés dans le même emplacement (pour remplacer le plus ancien si plein).
static func slot_items(sheet: Dictionary, slot: String) -> Array:
	return sheet.get("inventory", []).filter(func(i): return i.get("equipped", false) and String(i.get("slot", "")) == slot)


## Équipe un objet (en retirant l'objet du même emplacement si besoin). Renvoie une erreur ou "".
static func equip(sheet: Dictionary, uid: String) -> String:
	var item := find(sheet, uid)
	if item.is_empty():
		return "Objet introuvable."
	var slot := String(item.get("slot", ""))
	if slot == "":
		return "%s ne s'équipe pas." % item.name
	if item.get("equipped", false):
		return ""
	var current := slot_items(sheet, slot)
	if current.size() >= int(Content.SLOTS.get(slot, 1)):
		current[0].equipped = false
	item.equipped = true
	return ""


static func unequip(sheet: Dictionary, uid: String) -> String:
	var item := find(sheet, uid)
	if item.is_empty():
		return "Objet introuvable."
	item.equipped = false
	return ""


## Aperçu des valeurs qui changeraient en équipant / déséquipant cet objet.
## Renvoie [{label, before, after}] (ex. Défense 12 → 16).
static func preview(sheet: Dictionary, content: Dictionary, uid: String) -> Array:
	var item := find(sheet, uid)
	if item.is_empty() or String(item.get("slot", "")) == "":
		return []
	var after := sheet.duplicate(true)
	if item.get("equipped", false):
		unequip(after, uid)
	else:
		equip(after, uid)
	var a := Rules.derived(sheet, content)
	var b := Rules.derived(after, content)
	var out: Array = []
	for spec in [["hp_max", "PV max"], ["res_max", String(a.res_name) + " max"], ["defense", "Défense"], ["resist_phys", "Résistance physique"],
			["resist_mag", "Résistance magique"], ["speed", "Vitesse"], ["to_hit", "Toucher"], ["damage", "Dégâts"], ["heal_pct", "Soins (%)"], ["crit_bonus", "Critique"]]:
		if int(a[spec[0]]) != int(b[spec[0]]):
			out.append({"label": spec[1], "before": int(a[spec[0]]), "after": int(b[spec[0]])})
	for st in Content.stat_names(content):
		var x := Rules.stat(sheet, st, content)
		var y := Rules.stat(after, st, content)
		if x != y:
			out.append({"label": st, "before": x, "after": y})
	var wa := Rules.weapons(sheet)
	var wb := Rules.weapons(after)
	if String(wa[0].get("name", "")) != String(wb[0].get("name", "")):
		var pa := Rules.attack_profile(sheet, content, wa[0])
		var pb := Rules.attack_profile(after, content, wb[0])
		out.append({"label": "Arme", "before_text": "%s %+d" % [pa.damage, pa.damage_bonus], "after_text": "%s %+d" % [pb.damage, pb.damage_bonus]})
	return out


## Tire une table de butin. Renvoie {gold, items: [instances]}.
static func roll_loot(content: Dictionary, table_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var table := Content.get_entry(content, "loot", table_id)
	var out := {"gold": 0, "items": []}
	if table.is_empty():
		return out
	var g: Array = table.get("gold", [0, 0])
	if g.size() == 2:
		out.gold = rng.randi_range(int(g[0]), maxi(int(g[0]), int(g[1])))
	for e in table.get("guaranteed", []):
		var inst := Content.item_instance(content, String(e.get("item", "")), int(e.get("qty", 1)))
		if not inst.is_empty():
			out.items.append(inst)
	for e in table.get("entries", []):
		if rng.randi_range(1, 100) <= int(e.get("chance", 0)):
			var inst := Content.item_instance(content, String(e.get("item", "")), rng.randi_range(int(e.get("min", 1)), maxi(int(e.get("min", 1)), int(e.get("max", 1)))))
			if not inst.is_empty():
				out.items.append(inst)
	return out


## Court texte des effets d'un objet (pour les fiches et infobulles).
static func describe(item: Dictionary, content: Dictionary = {}) -> String:
	var parts: PackedStringArray = []
	var w: Dictionary = item.get("weapon", {})
	if not w.is_empty():
		var crit := int(w.get("crit", 20))
		parts.append("Dégâts %s (%s)%s · critique %s · portée %d" % [w.get("damage", "1d4"), w.get("stat", "Force"),
			" magiques" if String(w.get("element", "")) == "magique" else "", ("%d-20" % crit) if crit < 20 else "20", int(w.get("range", 1))])
	var mods: Dictionary = item.get("mods", {})
	var mm: PackedStringArray = []
	for k in mods:
		mm.append("%s %+d" % [Content.MOD_NAMES.get(k, k), int(mods[k])])
	if not mm.is_empty():
		parts.append(", ".join(mm))
	if not (item.get("use", []) as Array).is_empty():
		parts.append("Utilisation : " + Effects.describe_list(item.use, content))
	if not (item.get("on_hit", []) as Array).is_empty():
		parts.append("À l'impact : " + Effects.describe_list(item.on_hit, content))
	for g in item.get("grants", []):
		var a := Content.get_entry(content, "abilities", String(g))
		parts.append("Accorde : %s" % a.get("name", g))
	if String(item.get("teaches", "")) != "":
		var a := Content.get_entry(content, "abilities", String(item.teaches))
		parts.append("Apprend : %s" % a.get("name", item.teaches))
	return " · ".join(parts)
