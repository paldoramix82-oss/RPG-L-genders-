class_name Effects
extends RefCounted
## Effets composables : description en français clair (capacités, objets,
## passifs). L'application des effets est faite par Combat, sur l'hôte.


static func describe_list(effects: Array, content: Dictionary = {}, stat_name: String = "") -> String:
	var parts: PackedStringArray = []
	for e in effects:
		if e is Dictionary:
			var t := describe(e, content, stat_name)
			if t != "":
				parts.append(t)
	return " ; ".join(parts)


static func _who(e: Dictionary) -> String:
	match String(e.get("on", "target")):
		"self":
			return " (sur soi)"
		"allies":
			return " (alliés à %d cases)" % int(e.get("radius", 2))
	return ""


static func describe(e: Dictionary, content: Dictionary = {}, stat_name: String = "") -> String:
	match String(e.get("type", "")):
		"damage":
			var st := String(e.get("stat", stat_name))
			var bonus := int(e.get("bonus", 0))
			var txt := String(e.get("dice", "1d6"))
			if st != "" and not e.get("flat_stat", false):
				txt += " + %s÷2" % Content.stat_info(content, st).get("short", st)
			if bonus != 0:
				txt += " %+d" % bonus
			return "%s dégâts%s" % [txt, " magiques" if String(e.get("element", "")) == "magique" else ""]
		"heal":
			var txt := String(e.get("dice", ""))
			if txt != "":
				var st := String(e.get("stat", stat_name if stat_name != "" else "Esprit"))
				txt += " + %s÷2" % Content.stat_info(content, st).get("short", "ESP")
			if int(e.get("amount", 0)) > 0:
				txt = ("%s + %d" % [txt, int(e.amount)]) if txt != "" else str(int(e.amount))
			if int(e.get("bonus", 0)) != 0:
				txt += " %+d" % int(e.bonus)
			return "soigne %s PV%s" % [txt, _who(e)]
		"restore":
			return "%+d %s%s" % [int(e.get("amount", 0)), "PV" if String(e.get("resource", "")) == "hp" else "ressource", _who(e)]
		"status":
			var def := Content.get_entry(content, "statuses", String(e.get("status", "")))
			var txt := String(def.get("name", e.get("status", "?")))
			if int(e.get("value", 0)) > 0:
				txt += " %d%s" % [int(e.value), (" + " + String(e.scale)) if String(e.get("scale", "")) != "" else ""]
			txt += " %d tour%s" % [int(e.get("turns", 1)), "s" if int(e.get("turns", 1)) > 1 else ""]
			if int(e.get("chance", 100)) < 100:
				txt += " (%d %%)" % int(e.chance)
			return txt + _who(e)
		"cleanse":
			return "retire %d effet%s négatif%s%s" % [int(e.get("count", 1)), "s" if int(e.get("count", 1)) > 1 else "", "s" if int(e.get("count", 1)) > 1 else "", _who(e)]
		"push":
			return "repousse de %d case%s" % [int(e.get("cells", 1)), "s" if int(e.get("cells", 1)) > 1 else ""]
		"pull":
			return "attire de %d case%s" % [int(e.get("cells", 1)), "s" if int(e.get("cells", 1)) > 1 else ""]
		"ap":
			return "%+d PA%s" % [int(e.get("amount", 1)), _who(e)]
		"stat":
			return "%s %+d pendant %d tours%s" % [e.get("stat", "?"), int(e.get("amount", 1)), int(e.get("turns", 2)), _who(e)]
		"drain":
			return "rend %d %% des dégâts en PV" % int(e.get("pct", 30))
		"summon":
			return "invoque %s (%d PV)" % [e.get("name", "?"), int(e.get("hp", 10))]
		"if":
			var c := describe_cond(e.get("cond", {}))
			var then := describe_list(e.get("then", []), content, stat_name)
			var other := describe_list(e.get("else", []), content, stat_name)
			return "si %s : %s%s" % [c, then, ("; sinon : " + other) if other != "" else ""]
		"narrate":
			return String(e.get("text", ""))
	return ""


static func describe_cond(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	if c.has("self_hp_below"):
		parts.append("vos PV sous %d %%" % int(c.self_hp_below))
	if c.has("target_hp_below"):
		parts.append("cible sous %d %% de PV" % int(c.target_hp_below))
	if c.get("target_weak", false):
		parts.append("cible blessée (sous 50 %) ou affaiblie")
	if c.get("target_debuffed", false):
		parts.append("cible sous un effet négatif")
	if c.has("distance_min"):
		parts.append("cible à %d cases ou plus" % int(c.distance_min))
	if String(c.get("target_has", "")) != "":
		parts.append("cible affectée par « %s »" % c.target_has)
	if String(c.get("element", "")) != "":
		parts.append("attaque %s" % c.element)
	if c.has("chance"):
		parts.append("%d %% de chances" % int(c.chance))
	return " et ".join(parts) if not parts.is_empty() else "toujours"


## Ligne de coûts d'une capacité : « 3 Mana · 1 PA · portée 6 · recharge 2 tours ».
static func ability_costs(a: Dictionary, res_name: String = "Énergie") -> String:
	var parts: PackedStringArray = []
	var cost := maxi(0, int(a.get("cost", 0)) - (int(a.get("rank", 1)) - 1))
	if a.get("ultimate", false):
		parts.append("Jauge d'ultime pleine")
	if cost > 0:
		parts.append("%d %s" % [cost, res_name])
	parts.append("%d PA" % int(a.get("ap", 1)))
	var rng := int(a.get("range", 1))
	var target := String(a.get("target", "enemy"))
	if target == "self" or rng == 0:
		parts.append("sur soi" if target == "self" else "autour de soi")
	else:
		parts.append("portée %d" % rng)
	if int(a.get("radius", 0)) > 0:
		parts.append("zone de rayon %d" % int(a.radius))
	if int(a.get("cooldown", 0)) > 0 and int(a.cooldown) < 99:
		parts.append("recharge %d tour%s" % [int(a.cooldown), "s" if int(a.cooldown) > 1 else ""])
	elif int(a.get("cooldown", 0)) >= 99:
		parts.append("une fois par combat")
	return " · ".join(parts)


## Description complète d'une capacité (cible, jet, effets).
static func ability_text(a: Dictionary, content: Dictionary = {}) -> String:
	var target := String(Content.TARGET_NAMES.get(String(a.get("target", "enemy")), ""))
	var roll := "jet d'attaque contre la Défense" if String(a.get("roll", "")) == "attack" else "touche automatiquement"
	var fx := describe_list(a.get("effects", []), content, String(a.get("stat", "")))
	if int(a.get("rank", 1)) > 1:
		fx += " (rang %d : +%d)" % [int(a.rank), (int(a.rank) - 1) * 2]
	return "%s — %s. %s." % [target, roll, fx.capitalize() if false else fx]


static func passive_text(p: Dictionary, content: Dictionary = {}) -> String:
	if p.is_empty():
		return ""
	return String(p.get("description", "")) if String(p.get("description", "")) != "" else describe_list(p.get("effects", []), content)
