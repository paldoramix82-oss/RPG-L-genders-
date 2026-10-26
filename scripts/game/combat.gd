class_name Combat
extends RefCounted
## Moteur de combat de l'hôte : points d'action, attaques, capacités, effets
## composables, effets de statut, passifs, jauge d'ultime, victoire et butin.
##
## Le moteur travaille sur l'état officiel du SessionServer (pions, fiches, phase).
## Les téléphones n'envoient que des intentions (« j'utilise X sur Y ») ; tous les
## jets et calculs sont faits ici. Chaque action produit un message « combat »
## lisible (lignes colorées) et des retours visuels (EVT_FX).

var s: SessionServer
var _rng: RandomNumberGenerator
## Lignes et retours visuels de l'action en cours.
var _lines: Array = []
var _fx: Array = []
var _last_damage := 0


func _init(server: SessionServer, rng: RandomNumberGenerator) -> void:
	s = server
	_rng = rng


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

func content() -> Dictionary:
	return s.content


func map() -> Dictionary:
	return s.maps.get(s.active_map, {})


func in_combat() -> bool:
	return String(s.phase.get("type", "")) == "combat"


func token(id: String) -> Dictionary:
	return MapData.token(map(), id)


func sheet_of(t: Dictionary) -> Dictionary:
	return s._sheet_for_token(t)


func has_sheet(t: Dictionary) -> bool:
	var cid: String = t.get("char_id", "") if String(t.get("char_id", "")) != "" else String(t.get("owner", ""))
	return s.characters.has(cid)


## Liste (modifiable) des effets en cours d'un pion : ceux de sa fiche, ou du pion lui-même.
func effects_of(t: Dictionary) -> Array:
	var cid: String = t.get("char_id", "") if String(t.get("char_id", "")) != "" else String(t.get("owner", ""))
	if s.characters.has(cid):
		var c: Dictionary = s.characters[cid]
		if not c.get("effects") is Array:
			c.effects = []
		return c.effects
	if not t.get("effects") is Array:
		t.effects = []
	return t.effects


## Après un changement d'effets : le pion affiche les effets de sa fiche.
func touch(t: Dictionary) -> void:
	if has_sheet(t):
		t.effects = effects_of(t).duplicate(true)
		s._mark("characters")
		s.characters_changed.emit()
	s.map_changed(s.active_map, true)


func side(t: Dictionary) -> String:
	if String(t.get("side", "")) != "":
		return String(t.side)
	if String(t.get("kind", "")) == "pc":
		return "players"
	var sh := sheet_of(t)
	if String(sh.get("side", "")) != "":
		return String(sh.side)
	return "enemies"


func is_ko(t: Dictionary) -> bool:
	return int(t.get("hp_max", 0)) > 0 and int(t.get("hp", 1)) <= 0


func has_flag(t: Dictionary, flag: String) -> bool:
	for e in effects_of(t):
		var def := Content.get_entry(content(), "statuses", String(e.get("id", "")))
		if (def.get("flags", []) as Array).has(flag):
			return true
	return false


func has_debuff(t: Dictionary) -> bool:
	for e in effects_of(t):
		if String(e.get("kind", "")) == "debuff":
			return true
	return false


func pos(t: Dictionary) -> Vector2i:
	return Vector2i(int(t.get("x", 0)), int(t.get("y", 0)))


func dist(a: Dictionary, b: Dictionary) -> int:
	return Rules.distance(pos(a), pos(b))


func hp_pct(t: Dictionary) -> int:
	var mx := int(t.get("hp_max", 0))
	return 100 if mx <= 0 else int(100.0 * int(t.get("hp", 0)) / mx)


## Valeurs de combat d'un pion (fiche, effets du pion compris).
func stats_of(t: Dictionary) -> Dictionary:
	var sh := sheet_of(t)
	if not has_sheet(t):
		sh = sh.duplicate(true)
		sh.effects = effects_of(t)
	var d := Rules.derived(sh, content())
	if not has_sheet(t) and int(t.get("defense", 0)) > 0:
		d.defense = int(t.defense) + int(d.mods.get("defense", 0))
	return d


func _line(kind: String, text: String) -> void:
	_lines.append({"t": kind, "text": text})


func _fxp(t: Dictionary, kind: String, amount: int = 0, text: String = "") -> void:
	_fx.append({"token": String(t.get("id", "")), "type": kind, "amount": amount, "text": text})


# ---------------------------------------------------------------------------
# Tour de jeu
# ---------------------------------------------------------------------------

## Début du tour d'un pion. Renvoie false si le pion perd son tour (étourdi).
func begin_turn(t: Dictionary) -> bool:
	var rules := Phases.def(String(s.phase.type))
	var d := stats_of(t) if not t.is_empty() else {}
	s.phase.ap = int(d.get("ap", 2)) + int(t.get("ap_bonus", 0)) if not t.is_empty() else 0
	t.erase("ap_bonus")
	s.phase.moves_left = 0 if in_combat() else int(d.get("speed", 5))
	if int(t.get("speed", 0)) > 0 and not has_sheet(t) and not in_combat():
		s.phase.moves_left = int(t.speed)
	s.phase.action_used = false
	if t.is_empty() or not in_combat():
		return true
	_lines = []
	_fx = []
	var can_act := true
	if has_flag(t, "stun"):
		can_act = false
		_line("status", "%s est étourdi et perd son tour." % t.name)
	# Effets de début de tour : dégâts / soins sur la durée.
	for e in effects_of(t).duplicate():
		var def := Content.get_entry(content(), "statuses", String(e.get("id", "")))
		var tick: Dictionary = def.get("tick", {})
		if tick.is_empty():
			continue
		var amount := int(Dice.roll(String(tick.get("dice", "1d4")), _rng).get("total", 1)) + int(e.get("value", 0))
		if String(tick.get("type", "")) == "damage":
			_apply_damage(t, amount, {}, String(e.name))
		else:
			_apply_heal(t, amount, String(e.name))
	# Durées.
	var list := effects_of(t)
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		if int(e.get("turns", 0)) <= 0:
			continue
		e.turns = int(e.turns) - 1
		if int(e.turns) <= 0:
			list.remove_at(i)
	if has_sheet(t) and not is_ko(t):
		var c := sheet_of(t)
		var cds: Dictionary = c.get("cooldowns", {})
		for k in cds.keys():
			cds[k] = int(cds[k]) - 1
			if int(cds[k]) <= 0:
				cds.erase(k)
		c.res = mini(int(c.get("res_max", 0)), int(c.get("res", 0)) + int(Content.rule(content(), "res_regen_turn")))
		_gain_ult(t, int(Content.rule(content(), "ult_gain_turn")))
		_trigger_passive(t, "turn_start", {}, {})
	touch(t)
	if not _lines.is_empty():
		_post(t, "Début du tour de %s" % t.name)
	if is_ko(t):
		can_act = false
	check_end()
	return can_act


func _gain_ult(t: Dictionary, amount: int) -> void:
	if amount <= 0 or not has_sheet(t) or not in_combat():
		return
	var c := sheet_of(t)
	var has_ult := false
	for a in c.get("abilities", []):
		if a.get("ultimate", false) and a.get("equipped", false):
			has_ult = true
	if has_ult:
		var before := int(c.get("ult", 0))
		c.ult = mini(100, before + amount)
		if before < 100 and int(c.ult) >= 100:
			_line("ult", "L'ultime de %s est prêt !" % t.name)
			_fxp(t, "ult", 100)


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

## payload : {action: quick|power|defend|ability|item|auto, target, index, id, uid, x, y}
func action(token_id: String, payload: Dictionary) -> String:
	var actor := token(token_id)
	if actor.is_empty():
		return "Pion introuvable."
	if is_ko(actor):
		return "Ce personnage est hors de combat."
	_lines = []
	_fx = []
	_last_damage = 0
	var act := String(payload.get("action", ""))
	var target := token(String(payload.get("target", "")))
	var error := ""
	match act:
		"quick", "attack":
			error = _weapon_attack(actor, target, int(payload.get("index", 0)), false)
		"power":
			error = _weapon_attack(actor, target, int(payload.get("index", 0)), true)
		"defend":
			error = _defend(actor)
		"ability":
			var ability := Rules.find_ability(sheet_of(actor), content(), String(payload.get("id", "")))
			if ability.is_empty():
				var list: Array = Rules.usable_abilities(sheet_of(actor), content())
				var idx := int(payload.get("index", -1))
				if idx >= 0 and idx < list.size():
					ability = list[idx]
			if ability.is_empty():
				return "Capacité introuvable."
			var cell := Vector2i(int(payload.get("x", -1)), int(payload.get("y", -1)))
			error = use_ability(actor, ability, target, cell)
		"item":
			error = use_item(actor, String(payload.get("uid", "")), target)
		"auto":
			error = auto_play(actor)
		_:
			return "Action inconnue."
	return error


## Coût en PA d'une action : vérifie et retire. Hors tour par tour, rien à payer.
func _pay_ap(cost: int) -> String:
	if not Phases.def(String(s.phase.type)).turns:
		return ""
	if int(s.phase.get("ap", 0)) < cost:
		return "Pas assez de points d'action (%d nécessaire%s, %d restant%s)." % [cost, "s" if cost > 1 else "", int(s.phase.ap), "s" if int(s.phase.ap) > 1 else ""]
	s.phase.ap = int(s.phase.ap) - cost
	s.phase.action_used = int(s.phase.ap) <= 0
	return ""


func _ap_rule(key: String) -> int:
	return int(Content.rule(content(), key))


func _weapon_attack(actor: Dictionary, target: Dictionary, index: int, power: bool) -> String:
	var sheet := sheet_of(actor)
	var list := Rules.weapons(sheet)
	var w: Dictionary = list[clampi(index, 0, list.size() - 1)]
	var profile := Rules.attack_profile(sheet, content(), w)
	if not has_sheet(actor):
		profile.to_hit = 5 + int(stats_of(actor).to_hit)
		profile.damage_bonus = 2 + int(stats_of(actor).damage)
	var check := _check_target(actor, target, "enemy", int(profile.range))
	if check != "":
		return check
	var cost := _ap_rule("power_attack_ap" if power else "quick_attack_ap")
	var err := _pay_ap(cost)
	if err != "":
		return err
	_break_invisibility(actor)
	var label := ("Attaque puissante" if power else "Attaque rapide") + " (%s)" % profile.name
	var spec := {
		"name": label, "roll": "attack", "to_hit": int(profile.to_hit) - (2 if power else 0), "crit": int(profile.crit),
		"element": String(profile.element), "power": power,
		"effects": [{"type": "damage", "dice": profile.damage, "bonus": int(profile.damage_bonus), "flat_stat": true, "element": profile.element}] + (profile.on_hit as Array),
	}
	_resolve(actor, spec, [target])
	_post(actor, "%s : %s → %s" % [actor.name, label, target.name])
	return ""


func _defend(actor: Dictionary) -> String:
	var err := _pay_ap(_ap_rule("defend_ap"))
	if err != "":
		return err
	_add_status(actor, actor, {"status": "protege", "turns": 1})
	_line("status", "%s se met en garde (+3 Défense jusqu'à son prochain tour)." % actor.name)
	_post(actor, "%s se défend" % actor.name)
	return ""


## Pourquoi une capacité ne peut pas être utilisée (texte vide : utilisable).
func ability_block_reason(actor: Dictionary, ability: Dictionary) -> String:
	var sheet := sheet_of(actor)
	if has_flag(actor, "silence"):
		return "Vous êtes réduit au silence."
	var cost := maxi(0, int(ability.get("cost", 0)) - (int(ability.get("rank", 1)) - 1))
	if has_sheet(actor) and cost > int(sheet.get("res", 0)):
		return "Pas assez de %s (%d nécessaires, %d restants)." % [String(sheet.get("res_name", "ressource")), cost, int(sheet.get("res", 0))]
	if ability.get("ultimate", false) and has_sheet(actor) and int(sheet.get("ult", 0)) < 100:
		return "Ultime pas encore chargé (%d %%)." % int(sheet.get("ult", 0))
	var cd := int(sheet.get("cooldowns", {}).get(String(ability.get("id", "")), 0))
	if cd > 0:
		return "En recharge : encore %d tour%s." % [cd, "s" if cd > 1 else ""]
	if Phases.def(String(s.phase.type)).turns and int(s.phase.get("ap", 0)) < int(ability.get("ap", 1)):
		return "Pas assez de points d'action (%d nécessaires)." % int(ability.get("ap", 1))
	var cond: Dictionary = ability.get("conditions", {})
	if cond.has("self_hp_below") and hp_pct(actor) >= int(cond.self_hp_below):
		return "Utilisable seulement sous %d %% de PV." % int(cond.self_hp_below)
	return ""


func use_ability(actor: Dictionary, ability: Dictionary, target: Dictionary, cell: Vector2i = Vector2i(-1, -1)) -> String:
	var reason := ability_block_reason(actor, ability)
	if reason != "":
		return reason
	var kind := String(ability.get("target", "enemy"))
	var rng := int(ability.get("range", 1))
	var radius := int(ability.get("radius", 0))
	var targets: Array = []
	if kind == "self":
		targets = [actor]
	elif kind.begins_with("area"):
		var center := pos(actor)
		if rng > 0:
			if not target.is_empty():
				center = pos(target)
			elif cell.x >= 0:
				center = cell
			else:
				return "Choisissez une cible ou une case."
			if Rules.distance(pos(actor), center) > rng:
				return "Trop loin (portée %d)." % rng
		var want := "players" if (kind == "area_ally") == (side(actor) == "players") else "enemies"
		for t in map().get("tokens", []):
			if t.get("hidden", false) and side(actor) == "players":
				continue
			if t.kind == "object" or Rules.distance(pos(t), center) > radius or side(t) != want:
				continue
			if kind == "area_enemy" and (is_ko(t) or has_flag(t, "untargetable")):
				continue
			if kind == "area_ally" and is_ko(t) and not _has_heal(ability):
				continue
			targets.append(t)
		if targets.is_empty():
			return "Aucune cible dans la zone."
	else:
		if target.is_empty() and kind in ["ally", "any"]:
			target = actor
		var check := _check_target(actor, target, kind, rng, _has_heal(ability))
		if check != "":
			return check
		targets = [target]
	var err := _pay_ap(int(ability.get("ap", 1)))
	if err != "":
		return err
	var sheet := sheet_of(actor)
	if has_sheet(actor):
		sheet.res = maxi(0, int(sheet.get("res", 0)) - maxi(0, int(ability.get("cost", 0)) - (int(ability.get("rank", 1)) - 1)))
		if ability.get("ultimate", false):
			sheet.ult = 0
		if int(ability.get("cooldown", 0)) > 0 and in_combat():
			var cds: Dictionary = sheet.get("cooldowns", {})
			cds[String(ability.id)] = int(ability.cooldown) + 1
			sheet.cooldowns = cds
	if kind in ["enemy", "area_enemy"]:
		_break_invisibility(actor)
	var d := stats_of(actor)
	var stat_name := String(ability.get("stat", "Force"))
	var spec := {
		"name": String(ability.name), "roll": String(ability.get("roll", "none")),
		"to_hit": Rules.stat(sheet, stat_name, content(), d.mods) + int(d.to_hit) + (2 if String(ability.get("id", "")) in ["attaque_sournoise", "frappe_ombre", "tir_precis"] else 0),
		"crit": clampi(20 - int(d.crit_bonus), 2, 20), "element": String(ability.get("element", "physique")),
		"stat": stat_name, "rank": int(ability.get("rank", 1)), "effects": ability.get("effects", []), "ability": ability,
	}
	if ability.get("ultimate", false):
		_fxp(actor, "ultimate", 0, String(ability.name))
	_resolve(actor, spec, targets)
	var on := ""
	if targets.size() == 1 and targets[0] != actor:
		on = " → %s" % targets[0].name
	elif targets.size() > 1:
		on = " (%d cibles)" % targets.size()
	_post(actor, "%s utilise %s%s" % [actor.name, ability.name, on])
	return ""


func _has_heal(ability: Dictionary) -> bool:
	for e in ability.get("effects", []):
		if String(e.get("type", "")) == "heal":
			return true
	return false


func _check_target(actor: Dictionary, target: Dictionary, kind: String, rng: int, allow_ko: bool = false) -> String:
	if target.is_empty():
		return "Choisissez une cible."
	if target.get("hidden", false) and side(actor) == "players":
		return "Cible introuvable."
	if kind == "enemy":
		if target.id == actor.id:
			return "Choisissez un ennemi."
		if has_flag(target, "untargetable"):
			return "%s est impossible à cibler pour l'instant." % target.name
	if kind == "ally" and side(target) != side(actor):
		return "Choisissez un allié."
	if is_ko(target) and not allow_ko:
		return "%s est déjà hors de combat." % target.name
	var dd := dist(actor, target)
	if dd > rng:
		return "Cible hors de portée (%d case%s maximum, elle est à %d)." % [rng, "s" if rng > 1 else "", dd]
	return ""


func _break_invisibility(actor: Dictionary) -> void:
	var list := effects_of(actor)
	for i in range(list.size() - 1, -1, -1):
		var def := Content.get_entry(content(), "statuses", String(list[i].get("id", "")))
		if (def.get("flags", []) as Array).has("break_on_attack"):
			list.remove_at(i)


# ---------------------------------------------------------------------------
# Résolution : jet d'attaque puis effets, cible par cible
# ---------------------------------------------------------------------------

func _resolve(actor: Dictionary, spec: Dictionary, targets: Array) -> void:
	var killed: Array = []
	for target in targets:
		var crit := false
		if String(spec.roll) == "attack" and side(target) != side(actor):
			var p := _passive_mods(actor, target, String(spec.element))
			var defense := int(stats_of(target).defense) + int(_passive_defense(target))
			var d20 := _rng.randi_range(1, 20)
			var bonus := int(spec.to_hit) + int(p.to_hit)
			var total := d20 + bonus
			var hit := d20 == 20 or (d20 != 1 and total >= defense)
			crit = hit and d20 >= int(spec.crit)
			var detail := "d20 = %d %+d = %d contre Défense %d" % [d20, bonus, total, defense]
			spec["last_roll"] = {"expr": "d20%+d" % bonus, "detail": detail, "total": total, "difficulty": defense, "success": hit}
			# Le jet est montré à tous : dé, bonus, total, Défense visée, résultat.
			var outcome := "crit" if crit else ("hit" if hit else ("fumble" if d20 == 1 else "miss"))
			_fx.append({"token": String(actor.get("id", "")), "type": "roll", "target": String(target.get("id", "")), "target_name": String(target.get("name", "")),
				"label": String(spec.get("name", "")), "actor_name": String(actor.get("name", "")), "d20": d20, "bonus": bonus, "total": total, "vs": defense, "outcome": outcome})
			if not hit:
				_line("miss", "%s rate %s : %s." % [actor.name, target.name, detail if d20 != 1 else "d20 = 1, échec critique"])
				_fxp(target, "miss")
				continue
			if crit:
				_line("crit", "Coup critique sur %s ! (%s)" % [target.name, detail])
				_fxp(target, "crit")
			else:
				_line("hit", "%s touche %s : %s." % [actor.name, target.name, detail])
		var was_ko := is_ko(target)
		_apply_effects(actor, target, spec.effects, spec, crit, 0)
		if not was_ko and is_ko(target):
			killed.append(target)
	for t in killed:
		_trigger_passive(actor, "on_kill", t, spec)


func _apply_effects(actor: Dictionary, target: Dictionary, effects: Array, spec: Dictionary, crit: bool, depth: int) -> void:
	for e in effects:
		if not e is Dictionary:
			continue
		var on := String(e.get("on", "target"))
		var who: Array = [target]
		if on == "self":
			who = [actor]
		elif on == "allies":
			who = _allies_near(actor, int(e.get("radius", 2)))
		for w in who:
			_apply_effect(actor, w, e, spec, crit, depth)


func _apply_effect(actor: Dictionary, target: Dictionary, e: Dictionary, spec: Dictionary, crit: bool, depth: int) -> void:
	var sheet := sheet_of(actor)
	var d := stats_of(actor)
	var rank_bonus := (int(spec.get("rank", 1)) - 1) * 2
	match String(e.get("type", "")):
		"damage":
			var dice := String(e.get("dice", "1d6"))
			var r := Dice.roll(dice, _rng)
			var faces := _faces(r)
			var amount := int(r.get("total", 1))
			if crit:
				var r2 := Dice.roll(dice, _rng)
				faces.append_array(_faces(r2))
				amount += int(r2.get("total", 0))
			var mod := 0
			if e.get("flat_stat", false):
				mod += int(e.get("bonus", 0))
			else:
				var stat_name := String(e.get("stat", spec.get("stat", "Force")))
				mod += Rules.stat(sheet, stat_name, content(), d.mods) / 2 + int(d.damage) + int(e.get("bonus", 0)) + rank_bonus
			var p := _passive_mods(actor, target, String(e.get("element", spec.get("element", "physique"))))
			mod += int(p.damage)
			if String(p.get("damage_dice", "")) != "":
				var rp := Dice.roll(String(p.damage_dice), _rng)
				faces.append_array(_faces(rp))
				amount += int(rp.get("total", 0))
			amount += mod
			if spec.get("power", false):
				amount = int(round(amount * 1.5))
			var roll_info := {"faces": faces, "mod": mod, "power": bool(spec.get("power", false)), "crit": crit}
			var dealt := _apply_damage(target, amount, {"actor": actor, "element": String(e.get("element", spec.get("element", "physique"))), "roll": roll_info}, "")
			_last_damage = dealt
			if dealt > 0 and actor != target:
				_gain_ult(actor, int(Content.rule(content(), "ult_gain_deal")))
				_trigger_passive(actor, "on_hit", target, spec)
		"heal":
			var amount := int(e.get("amount", 0))
			if String(e.get("dice", "")) != "":
				var heal_stat := String(e.get("stat", spec.get("stat", "Esprit")))
				if heal_stat not in Content.stat_names(content()):
					heal_stat = "Esprit"
				var hr := Dice.roll(String(e.dice), _rng)
				var hfaces := _faces(hr)
				var hmod := Rules.stat(sheet, heal_stat, content(), d.mods) / 2 + int(e.get("bonus", 0)) + rank_bonus
				_fx.append({"token": String(actor.get("id", "")), "type": "heal_roll", "target": String(target.get("id", "")), "target_name": String(target.get("name", "")),
					"actor_name": String(actor.get("name", "")), "label": String(spec.get("name", "")), "faces": hfaces, "mod": hmod + int(e.get("amount", 0))})
				amount += int(hr.get("total", 0)) + Rules.stat(sheet, heal_stat, content(), d.mods) / 2
			amount += int(e.get("bonus", 0)) + rank_bonus
			amount = int(round(amount * (1.0 + float(int(d.heal_pct) + int(_passive_mods(actor, target, "soin").get("heal_pct", 0))) / 100.0)))
			_apply_heal(target, maxi(1, amount), "")
			_trigger_passive(actor, "on_heal", target, spec)
		"restore":
			_restore(target, String(e.get("resource", "res")), int(e.get("amount", 1)))
		"status":
			_add_status(actor, target, e)
		"stat":
			var st_name := String(e.get("stat", "Force"))
			var amount := int(e.get("amount", 1))
			_add_status(actor, target, {"status": "modifie", "turns": int(e.get("turns", 2)), "mods": {st_name: amount},
				"name": "%s %+d" % [st_name, amount], "kind": "buff" if amount > 0 else "debuff"})
		"cleanse":
			var n := int(e.get("count", 1))
			var list := effects_of(target)
			var removed: PackedStringArray = []
			for i in range(list.size() - 1, -1, -1):
				if n <= 0:
					break
				if String(list[i].get("kind", "")) == "debuff":
					removed.append(String(list[i].name))
					list.remove_at(i)
					n -= 1
			if not removed.is_empty():
				_line("heal", "%s est libéré de : %s." % [target.name, ", ".join(removed)])
				touch(target)
		"push", "pull":
			_shove(actor, target, int(e.get("cells", 1)) * (1 if e.type == "push" else -1))
		"ap":
			var amount := int(e.get("amount", 1))
			if String(target.get("id", "")) == s._current_token():
				s.phase.ap = maxi(0, int(s.phase.get("ap", 0)) + amount)
			else:
				target["ap_bonus"] = int(target.get("ap_bonus", 0)) + amount
			_line("status", "%s : %+d PA." % [target.name, amount])
		"drain":
			var amount := int(round(_last_damage * float(e.get("pct", 30)) / 100.0))
			if amount > 0:
				_apply_heal(actor, amount, "vol de vie")
		"summon":
			_summon(actor, e)
		"if":
			var ok := _cond_ok(e.get("cond", {}), actor, target, String(spec.get("element", "")))
			_apply_effects(actor, target, e.get("then", []) if ok else e.get("else", []), spec, crit, depth + 1)
		"narrate":
			if String(e.get("text", "")) != "":
				_line("info", String(e.text))


## Applique des dégâts (résistances, bouclier, protections). Renvoie les dégâts subis.
func _apply_damage(target: Dictionary, amount: int, ctx: Dictionary, source: String) -> int:
	var td := stats_of(target)
	var element := String(ctx.get("element", "physique"))
	var resist := 0
	if not ctx.is_empty():
		resist = int(td.resist_mag) if element == "magique" else int(td.resist_phys)
	amount = amount + int(td.damage_taken) - resist
	# Protection d'un allié (passif « ally_damaged », ex. Rempart du Gardien).
	var guard := _guardian_reduction(target)
	if guard.amount > 0 and amount > 0:
		amount -= int(guard.amount)
		_line("passive", "%s protège %s (−%d)." % [guard.name, target.name, guard.amount])
		_fxp(guard.token, "passive", 0, String(guard.passive))
	amount = maxi(1 if ctx.size() > 0 else 0, amount)
	# Bouclier.
	var absorbed := 0
	var list := effects_of(target)
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		if String(e.get("id", "")) == "bouclier" and amount > 0:
			var take := mini(int(e.get("value", 0)), amount)
			e.value = int(e.get("value", 0)) - take
			amount -= take
			absorbed += take
			if int(e.value) <= 0:
				list.remove_at(i)
	var before := int(target.get("hp", 0))
	if amount > 0:
		s._damage_token(target, amount)
	var dealt := before - int(target.get("hp", 0))
	var src := (" (%s)" % source) if source != "" else ""
	var abs_txt := (", %d absorbés par le bouclier" % absorbed) if absorbed > 0 else ""
	var roll: Dictionary = ctx.get("roll", {})
	if not roll.is_empty():
		# Détail du calcul : dés, bonus, ×1,5, résistance, bouclier.
		var parts: PackedStringArray = []
		var vals: PackedStringArray = []
		for f in roll.faces:
			vals.append(str(int(f.value)))
		parts.append("dés [%s]" % ", ".join(vals))
		if int(roll.mod) != 0:
			parts.append("%+d" % int(roll.mod))
		if roll.power:
			parts.append("×1,5")
		if resist > 0:
			parts.append("−%d résistance" % resist)
		src = " (%s)" % " ".join(parts)
		var actor: Dictionary = ctx.get("actor", {})
		_fx.append({"token": String(actor.get("id", "")), "type": "dmg_roll", "target": String(target.get("id", "")), "target_name": String(target.get("name", "")),
			"actor_name": String(actor.get("name", "")), "faces": roll.faces, "mod": int(roll.mod), "power": roll.power, "crit": roll.crit,
			"resist": resist, "absorbed": absorbed, "dealt": dealt})
	_line("dmg", "%s subit %d dégâts%s%s." % [target.name, dealt, src, abs_txt])
	_fxp(target, "dmg", dealt)
	if dealt > 0:
		_gain_ult(target, int(Content.rule(content(), "ult_gain_taken")))
		_trigger_passive(target, "on_damaged", ctx.get("actor", {}), {})
	if is_ko(target):
		_line("ko", "%s est hors de combat !" % target.name)
		_fxp(target, "ko")
		_on_defeated(target, ctx.get("actor", {}))
	touch(target)
	return dealt


## Un adversaire vient d'être vaincu : son XP est mise de côté pour la victoire,
## son butin est tiré tout de suite et donné à celui qui l'a vaincu (ou au coffre
## du groupe, selon les règles). Une seule fois par adversaire.
func _on_defeated(victim: Dictionary, killer: Dictionary) -> void:
	if victim.get("defeated", false):
		return
	if String(victim.get("summoned_by", "")) != "":
		victim["defeated"] = true
		return
	if side(victim) == "players":
		return
	victim["defeated"] = true
	var sh := sheet_of(victim) if has_sheet(victim) else {}
	s.phase["xp_pool"] = int(s.phase.get("xp_pool", 0)) + int(sh.get("xp_reward", 10 if sh.is_empty() else 0))
	s.phase["defeated"] = int(s.phase.get("defeated", 0)) + 1
	var table := String(sh.get("loot", ""))
	if table == "":
		return
	var drop := Inventory.roll_loot(content(), table, _rng)
	_lines.append_array(s.give_drop(_owner_player(killer), drop, String(victim.get("name", ""))))


## Joueur qui profite d'un coup : le propriétaire du pion, ou celui de l'invocation.
func _owner_player(t: Dictionary) -> String:
	if t.is_empty():
		return ""
	if String(t.get("summoned_by", "")) != "":
		return _owner_player(token(String(t.summoned_by)))
	return String(t.get("owner", "")) if String(t.get("kind", "")) == "pc" else ""


## Retire de la carte et de l'ordre des tours les adversaires vaincus et les
## invocations tombées (règle « remove_dead », active par défaut).
func remove_defeated() -> void:
	if not bool(Content.rule(content(), "remove_dead")):
		return
	var m := map()
	if m.is_empty():
		return
	var gone: Array = []
	for t in m.get("tokens", []):
		if t.get("defeated", false) and is_ko(t) and side(t) != "players" or (String(t.get("summoned_by", "")) != "" and is_ko(t)):
			gone.append(String(t.id))
	if gone.is_empty():
		return
	var current := s._current_token()
	m.tokens = (m.tokens as Array).filter(func(t): return not gone.has(String(t.id)))
	for id in gone:
		s.phase.order.erase(id)
	if s.phase.order.has(current):
		s.phase.turn = s.phase.order.find(current)
	else:
		s.phase.turn = clampi(int(s.phase.get("turn", 0)), 0, maxi(0, s.phase.order.size() - 1))
	s.map_changed(s.active_map, true)


## Faces tirées d'un lancer : [{sides, value}] (pour les montrer aux joueurs).
static func _faces(r: Dictionary) -> Array:
	var out: Array = []
	for g in r.get("rolls", []):
		for v in g.get("values", []):
			out.append({"sides": int(g.sides), "value": int(v)})
	return out


func _apply_heal(target: Dictionary, amount: int, source: String) -> void:
	var before := int(target.get("hp", 0))
	s._heal_token(target, amount)
	var healed := int(target.get("hp", 0)) - before
	var src := (" (%s)" % source) if source != "" else ""
	_line("heal", "%s récupère %d PV%s." % [target.name, healed, src])
	_fxp(target, "heal", healed)
	if before <= 0 and healed > 0:
		_line("heal", "%s se relève !" % target.name)


func _restore(target: Dictionary, resource: String, amount: int) -> void:
	if resource == "hp":
		_apply_heal(target, amount, "")
		return
	if not has_sheet(target):
		return
	var c := sheet_of(target)
	var before := int(c.get("res", 0))
	c.res = clampi(before + amount, 0, int(c.get("res_max", 0)))
	if int(c.res) != before:
		_line("res", "%s : %+d %s." % [target.name, int(c.res) - before, String(c.get("res_name", "ressource"))])
		_fxp(target, "res", int(c.res) - before)
	s._mark("characters")


func _add_status(actor: Dictionary, target: Dictionary, e: Dictionary) -> void:
	var id := String(e.get("status", ""))
	var chance := int(e.get("chance", 100))
	if chance < 100 and _rng.randi_range(1, 100) > chance:
		return
	var def := Content.get_entry(content(), "statuses", id)
	if def.is_empty():
		return
	var value := int(e.get("value", 0))
	if String(e.get("scale", "")) != "" and not actor.is_empty():
		value += Rules.stat(sheet_of(actor), String(e.scale), content())
	if value > 0 and String(def.get("id", "")) == "bouclier":
		value += Rules.stat(sheet_of(actor), "Charisme", content()) / 3 if not actor.is_empty() else 0
	var inst := {
		"id": id, "name": String(e.get("name", def.get("name", id))), "icon": String(def.get("icon", "sparkle")),
		"color": String(def.get("color", "#a07cc9")), "kind": String(e.get("kind", def.get("kind", "debuff"))),
		"turns": int(e.get("turns", 1)), "value": value, "description": String(def.get("description", "")),
	}
	if e.get("mods") is Dictionary:
		inst.mods = e.mods
		inst.description = inst.name
	var list := effects_of(target)
	var replaced := false
	for i in list.size():
		if String(list[i].get("id", "")) == id and String(list[i].get("name", "")) == inst.name:
			list[i].turns = maxi(int(list[i].get("turns", 0)), inst.turns)
			list[i].value = maxi(int(list[i].get("value", 0)), inst.value)
			replaced = true
	if not replaced:
		list.append(inst)
	var extra := (" (%d)" % value) if value > 0 else ""
	_line("status" if inst.kind == "debuff" else "buff", "%s : %s%s, %d tour%s." % [target.name, inst.name, extra, inst.turns, "s" if inst.turns > 1 else ""])
	_fxp(target, "status", 0, inst.name)
	touch(target)


func _shove(actor: Dictionary, target: Dictionary, cells: int) -> void:
	if target.id == actor.id:
		return
	var dir := pos(target) - pos(actor)
	dir = Vector2i(signi(dir.x), signi(dir.y))
	if cells < 0:
		dir = -dir
	if dir == Vector2i.ZERO:
		return
	var p := pos(target)
	for i in absi(cells):
		var nxt := p + dir
		if nxt == pos(actor) or not MapData.passable(map(), nxt.x, nxt.y) or not MapData.token_at(map(), nxt.x, nxt.y).is_empty():
			break
		p = nxt
	if p != pos(target):
		target.x = p.x
		target.y = p.y
		_line("info", "%s est %s." % [target.name, "repoussé" if cells > 0 else "attiré"])
		s.map_changed(s.active_map, true)


func _summon(actor: Dictionary, e: Dictionary) -> void:
	var p := MapData.free_cell_near(map(), int(actor.x), int(actor.y))
	var t := MapData.add_token(map(), {"kind": "npc", "name": String(e.get("name", "Invocation")), "x": p.x, "y": p.y,
		"color": String(e.get("color", "#9fc3d4")), "hp": int(e.get("hp", 10)), "hp_max": int(e.get("hp", 10)),
		"defense": int(e.get("defense", 10)), "attack": String(e.get("attack", "1d6")), "owner": String(actor.get("owner", ""))})
	if t.is_empty():
		return
	t.side = side(actor)
	t.summoned_by = String(actor.id)
	if in_combat():
		var i: int = s.phase.order.find(actor.id)
		s.phase.order.insert(i + 1, t.id)
	_line("buff", "%s invoque %s." % [actor.name, t.name])
	s.map_changed(s.active_map, true)


func _allies_near(actor: Dictionary, radius: int) -> Array:
	var out: Array = []
	for t in map().get("tokens", []):
		if t.kind != "object" and side(t) == side(actor) and not is_ko(t) and dist(actor, t) <= radius:
			out.append(t)
	return out


# ---------------------------------------------------------------------------
# Passifs
# ---------------------------------------------------------------------------

func _cond_ok(cond: Dictionary, actor: Dictionary, target: Dictionary, element: String) -> bool:
	if cond.is_empty():
		return true
	if cond.has("self_hp_below") and hp_pct(actor) >= int(cond.self_hp_below):
		return false
	if cond.has("target_hp_below") and (target.is_empty() or hp_pct(target) >= int(cond.target_hp_below)):
		return false
	if cond.get("target_weak", false) and (target.is_empty() or (hp_pct(target) >= 50 and not has_debuff(target))):
		return false
	if cond.get("target_debuffed", false) and (target.is_empty() or not has_debuff(target)):
		return false
	if cond.has("distance_min") and (target.is_empty() or dist(actor, target) < int(cond.distance_min)):
		return false
	if String(cond.get("target_has", "")) != "":
		if target.is_empty() or effects_of(target).filter(func(x): return x.get("id", "") == cond.target_has).is_empty():
			return false
	if String(cond.get("element", "")) != "" and element != String(cond.element):
		return false
	if cond.has("chance") and _rng.randi_range(1, 100) > int(cond.chance):
		return false
	return true


func _passive(t: Dictionary) -> Dictionary:
	return sheet_of(t).get("passive", {}) if has_sheet(t) else {}


## Bonus conditionnels du passif de l'attaquant (les bonus sans condition sont déjà dans Rules.derived).
func _passive_mods(actor: Dictionary, target: Dictionary, element: String) -> Dictionary:
	var p := _passive(actor)
	if String(p.get("trigger", "")) != "always" or (p.get("cond", {}) as Dictionary).is_empty():
		return {"to_hit": 0, "damage": 0}
	if not _cond_ok(p.cond, actor, target, element):
		return {"to_hit": 0, "damage": 0}
	var m: Dictionary = p.get("mods", {})
	if m.has("damage") or m.has("damage_dice") or m.has("to_hit"):
		_line("passive", "Passif : %s." % p.name)
		_fxp(actor, "passive", 0, String(p.name))
	return {"to_hit": int(m.get("to_hit", 0)), "damage": int(m.get("damage", 0)), "damage_dice": String(m.get("damage_dice", "")), "heal_pct": int(m.get("heal_pct", 0))}


func _passive_defense(target: Dictionary) -> int:
	var p := _passive(target)
	if String(p.get("trigger", "")) != "always" or (p.get("cond", {}) as Dictionary).is_empty():
		return 0
	if not _cond_ok(p.cond, target, {}, ""):
		return 0
	return int(p.get("mods", {}).get("defense", 0))


func _guardian_reduction(target: Dictionary) -> Dictionary:
	var best := {"amount": 0}
	for t in map().get("tokens", []):
		if t.id == target.id or is_ko(t) or side(t) != side(target):
			continue
		var p := _passive(t)
		if String(p.get("trigger", "")) == "ally_damaged" and dist(t, target) <= int(p.get("range", 1)) and int(p.get("reduce", 0)) > int(best.amount):
			best = {"amount": int(p.reduce), "name": String(t.name), "token": t, "passive": String(p.name)}
	return best


func _trigger_passive(t: Dictionary, trigger: String, other: Dictionary, spec: Dictionary) -> void:
	var p := _passive(t)
	if String(p.get("trigger", "")) != trigger or (p.get("effects", []) as Array).is_empty():
		return
	if not _cond_ok(p.get("cond", {}), t, other, String(spec.get("element", ""))):
		return
	_line("passive", "Passif de %s : %s." % [t.name, p.name])
	_fxp(t, "passive", 0, String(p.name))
	_apply_effects(t, t if other.is_empty() else other, p.effects, {"name": p.name, "stat": "Esprit"}, false, 1)


# ---------------------------------------------------------------------------
# Objets en combat
# ---------------------------------------------------------------------------

func use_item(actor: Dictionary, uid: String, target: Dictionary) -> String:
	if not has_sheet(actor):
		return "Ce pion n'a pas d'inventaire."
	var sheet := sheet_of(actor)
	var item := Inventory.find(sheet, uid)
	if item.is_empty():
		return "Objet introuvable."
	if (item.get("use", []) as Array).is_empty():
		return "%s ne s'utilise pas." % item.name
	var who := target if not target.is_empty() else actor
	if who.id != actor.id and dist(actor, who) > 1:
		return "Il faut être au contact pour utiliser un objet sur quelqu'un."
	var err := _pay_ap(_ap_rule("item_ap"))
	if err != "":
		return err
	_apply_effects(actor, who, item.use, {"name": item.name, "stat": "Esprit"}, false, 0)
	Inventory.consume(sheet, uid, 1)
	s._mark("characters")
	s.characters_changed.emit()
	_post(actor, "%s utilise %s%s" % [actor.name, item.name, (" sur " + String(who.name)) if who.id != actor.id else ""])
	return ""


# ---------------------------------------------------------------------------
# Jeu automatique des adversaires (aide au MJ)
# ---------------------------------------------------------------------------

## Avance vers l'adversaire le plus proche et l'attaque (capacité offensive si possible).
func auto_play(actor: Dictionary) -> String:
	var foes: Array = []
	for t in map().get("tokens", []):
		if t.kind != "object" and side(t) != side(actor) and not is_ko(t) and not t.get("hidden", false) and not has_flag(t, "untargetable"):
			foes.append(t)
	if foes.is_empty():
		return "Aucun adversaire visible."
	foes.sort_custom(func(a, b): return dist(actor, a) < dist(actor, b))
	var foe: Dictionary = foes[0]
	var sheet := sheet_of(actor)
	var best := {}
	for a in Rules.usable_abilities(sheet, content()):
		if String(a.get("target", "")) in ["enemy", "area_enemy"] and ability_block_reason(actor, a) == "" and _has_damage(a):
			if best.is_empty() or a.get("ultimate", false):
				best = a
	var rng := int(best.get("range", 1)) if not best.is_empty() else int(Rules.attack_profile(sheet, content(), Rules.weapons(sheet)[0]).range)
	if dist(actor, foe) > rng and not has_flag(actor, "root"):
		_step_toward(actor, foe, rng)
	if dist(actor, foe) > rng:
		return "%s ne peut pas atteindre sa cible ce tour-ci." % actor.name
	var err := ""
	if not best.is_empty():
		err = use_ability(actor, best, foe)
	if best.is_empty() or err != "":
		err = _weapon_attack(actor, foe, 0, int(s.phase.get("ap", 0)) >= _ap_rule("power_attack_ap") and _rng.randf() < 0.4)
	return err


func _has_damage(a: Dictionary) -> bool:
	for e in a.get("effects", []):
		if String(e.get("type", "")) == "damage":
			return true
	return false


func _step_toward(actor: Dictionary, foe: Dictionary, rng: int) -> void:
	var speed := int(stats_of(actor).speed)
	if Phases.def(String(s.phase.type)).turns:
		if int(s.phase.get("moves_left", 0)) <= 0:
			if _pay_ap(_ap_rule("move_ap")) != "":
				return
			s.phase.moves_left = speed
		speed = int(s.phase.moves_left)
	var best := pos(actor)
	var best_d := dist(actor, foe)
	for dy in range(-speed, speed + 1):
		for dx in range(-speed, speed + 1):
			var p := pos(actor) + Vector2i(dx, dy)
			if Rules.distance(pos(actor), p) > speed or not MapData.passable(map(), p.x, p.y) or not MapData.token_at(map(), p.x, p.y).is_empty():
				continue
			var dd := Rules.distance(p, pos(foe))
			if dd < best_d or (dd == best_d and Rules.distance(pos(actor), p) < Rules.distance(pos(actor), best)):
				if dd >= mini(rng, 1):
					best = p
					best_d = dd
	if best != pos(actor):
		if Phases.def(String(s.phase.type)).turns:
			s.phase.moves_left = int(s.phase.moves_left) - Rules.distance(pos(actor), best)
		actor.x = best.x
		actor.y = best.y
		s.map_changed(s.active_map, true)


# ---------------------------------------------------------------------------
# Fin du combat
# ---------------------------------------------------------------------------

## Victoire quand tous les adversaires visibles du tour par tour sont à terre ; défaite si tous les joueurs le sont.
func check_end() -> void:
	if not in_combat() or String(s.phase.get("result", "")) != "":
		return
	var foes := 0
	var foes_down := 0
	var heroes := 0
	var heroes_down := 0
	for id in s.phase.order:
		var t := token(String(id))
		if t.is_empty() or t.get("hidden", false):
			continue
		if side(t) == "players":
			if String(t.get("summoned_by", "")) != "":
				continue
			heroes += 1
			heroes_down += 1 if is_ko(t) else 0
		else:
			foes += 1
			foes_down += 1 if is_ko(t) else 0
	# Les adversaires vaincus ont pu être retirés de la carte : ils comptent quand même.
	if (foes > 0 or int(s.phase.get("defeated", 0)) > 0) and foes_down == foes:
		s.phase.result = "victory"
		_victory()
	elif heroes > 0 and heroes_down == heroes:
		s.phase.result = "defeat"
		s._add_message({"kind": Protocol.KIND_SYSTEM, "from": Protocol.MJ_ID, "from_name": "Combat", "to": Protocol.TO_ALL,
			"text": "Défaite… Tout le groupe est à terre. Le MJ décide de la suite.", "banner": "defeat"})
		s._phase_changed()


func _victory() -> void:
	# Adversaires mis à terre autrement (PV réglés par le MJ…) : comptés maintenant.
	for id in s.phase.order:
		var t := token(String(id))
		if not t.is_empty() and side(t) != "players" and not t.get("hidden", false) and is_ko(t):
			_on_defeated(t, {})
	var xp := int(s.phase.get("xp_pool", 0))
	var gold := 0
	var items: Array = []
	var heroes: Array = []
	for p in s.players.values():
		if s.characters.has(p.id) and p.status == Protocol.STATUS_ACCEPTED:
			heroes.append(p.id)
	var text := "Victoire !"
	var lines: Array = []
	if not heroes.is_empty() and xp > 0:
		var share := maxi(1, xp / heroes.size())
		lines.append({"t": "xp", "text": "+%d XP pour chacun" % share})
		for id in heroes:
			s.grant_xp(id, share, "", false)
	if gold > 0 and not heroes.is_empty():
		var share := gold / heroes.size()
		if share > 0:
			lines.append({"t": "gold", "text": "+%d or pour chacun" % share})
			for id in heroes:
				s.characters[id].gold = int(s.characters[id].get("gold", 0)) + share
	for it in items:
		s.add_loot(it, "Butin du combat")
		lines.append({"t": "loot", "text": "%s%s" % [it.name, (" ×%d" % int(it.qty)) if int(it.qty) > 1 else ""], "rarity": String(it.get("rarity", "commun"))})
	if not _lines.is_empty():
		# Butin des adversaires comptés à l'instant.
		lines.append_array(_lines)
		_lines = []
	var log: Array = s.phase.get("loot_log", [])
	if not log.is_empty():
		lines.append({"t": "info", "text": "Butin récupéré pendant le combat : " + ", ".join(PackedStringArray(log.slice(0, 12)))})
	if s.loot.size() > 0 and not items.is_empty():
		lines.append({"t": "info", "text": "Le butin attend dans le coffre du groupe : chacun peut se servir."})
	s._add_message({"kind": Protocol.KIND_COMBAT, "from": Protocol.MJ_ID, "from_name": "Combat", "to": Protocol.TO_ALL,
		"text": text, "lines": lines, "banner": "victory"})
	s._mark("characters")
	s.characters_changed.emit()
	s._phase_changed()


## Nettoyage quand le combat se termine (changement de phase).
func end_combat() -> void:
	for t in map().get("tokens", []):
		var list := effects_of(t)
		for i in range(list.size() - 1, -1, -1):
			if int(list[i].get("turns", 0)) > 0:
				list.remove_at(i)
		t.erase("ap_bonus")
		if has_sheet(t):
			sheet_of(t).cooldowns = {}
		touch(t)
	# Les invocations disparaissent.
	var m := map()
	if not m.is_empty():
		m.tokens = (m.tokens as Array).filter(func(t): return String(t.get("summoned_by", "")) == "")
		s.map_changed(s.active_map, true)


# ---------------------------------------------------------------------------
# Publication
# ---------------------------------------------------------------------------

func _post(actor: Dictionary, title: String) -> void:
	if _lines.is_empty() and _fx.is_empty():
		return
	var msg := {"kind": Protocol.KIND_COMBAT, "from": s._owner_or_mj(actor), "from_name": String(actor.get("name", "")),
		"to": Protocol.TO_ALL, "text": title, "lines": _lines.duplicate()}
	if actor.get("hidden", false):
		msg.to = Protocol.TO_MJ
	s._add_message(msg)
	if not _fx.is_empty():
		s.broadcast_fx(_fx.duplicate())
	_lines = []
	_fx = []
	remove_defeated()
	check_end()
	s._phase_changed()
