class_name CheckRunner
extends RefCounted
## Résolution des épreuves par l'hôte (voir Checks) : une action déclenche le
## jet, le résultat est calculé et les conséquences sont appliquées tout de
## suite (dégâts, objets trouvés, monstres repérés, coffre ouvert, fuite…).
## Le MJ peut ajouter des conséquences en un clic (consequence()).

var s: SessionServer
var _rng: RandomNumberGenerator
## Délai entre deux épreuves identiques ("joueur:compétence" → heure).
var _cooldown := {}
## Premiers soins : un blessé ne peut être soigné qu'une fois par minute.
var _aid := {}
## Tests : valeur imposée au d20 (0 = jet normal).
var forced_d20 := 0
## Combats déclenchés par l'épreuve (après la publication du résultat).
var _fights: Array = []

const OUTCOME_FX := {"crit": "crit", "success": "hit", "partial": "miss", "failure": "miss", "fumble": "fumble"}
## Conséquences rapides du MJ : [libellé, type].
const CONSEQUENCES := [
	["−1d4 PV", "dmg_small"], ["−1d8 PV", "dmg"], ["+1d6 PV", "heal"], ["+10 XP", "xp"], ["+1d10 or", "gold"],
	["Objet trouvé", "item"], ["Empoisonné", "poison"], ["Étourdi", "stun"],
]


func _init(server: SessionServer, rng: RandomNumberGenerator) -> void:
	s = server
	_rng = rng


func _map() -> Dictionary:
	return s.maps.get(s.active_map, {})


## Lance une épreuve pour un joueur. opts : {target, text, to, dc, message_id}.
## Renvoie "" ou un message d'erreur (rien n'est lancé).
func run(player_id: String, skill_id: String, opts: Dictionary = {}) -> String:
	var skill := Checks.get_skill(skill_id)
	if skill.is_empty():
		return "Compétence inconnue."
	var c: Dictionary = s.characters.get(player_id, {})
	if c.is_empty():
		return "Créez d'abord votre personnage."
	var map := _map()
	var pawn := MapData.token(map, "pawn_" + player_id)
	if pawn.is_empty():
		return "Votre pion n'est pas sur la carte."
	if s.combat.is_ko(pawn):
		return "Vous êtes à terre."
	var message_id := String(opts.get("message_id", ""))
	# Au tour par tour : seulement à son tour ; en combat, cela coûte des PA.
	var enc := s.encounter_of(String(pawn.id))
	var tp: Dictionary = enc if not enc.is_empty() else (s.phase if Phases.def(String(s.phase.type)).turns else {})
	var cost := 0
	if not tp.is_empty() and message_id == "":
		var cur: String = s._with(enc, s._current_token) if not enc.is_empty() else s._current_token()
		if cur != String(pawn.id):
			return "Ce n'est pas votre tour."
		if String(tp.type) == "combat":
			cost = int(Content.rule(s.content, "check_ap"))
			if int(tp.get("ap", 0)) < cost:
				return "Pas assez de points d'action."
	var now := SessionServer._clock()
	var key := player_id + ":" + skill_id
	if message_id == "" and float(_cooldown.get(key, 0.0)) > now:
		return "Patience : réessayez dans quelques secondes."
	# Cible : donnée par le joueur, sinon devinée selon la compétence.
	var target := {}
	var tid := String(opts.get("target", ""))
	if tid != "" and int(skill.range) > 0:
		target = MapData.token(map, tid)
		if target.is_empty() or target.get("hidden", false):
			return "Cible introuvable."
		if Rules.distance(_pos(pawn), _pos(target)) > int(skill.range):
			return "Trop loin : approchez-vous (%d case%s au plus)." % [int(skill.range), "s" if int(skill.range) > 1 else ""]
	else:
		target = _auto_target(skill_id, pawn, map)
	var dc := int(opts.get("dc", 0))
	if dc <= 0:
		dc = _context_dc(skill_id, skill, target)
	if dc >= 99:
		return "%s ne se laisse pas impressionner." % target.get("name", "Cette cible")

	var d20 := forced_d20 if forced_d20 > 0 else _rng.randi_range(1, 20)
	var b := Checks.bonus(c, s.content, skill_id)
	var total := d20 + b
	var o := Checks.outcome(d20, total, dc)
	var lines: Array = []
	var fx: Array = []
	_fights = []
	_effects(skill_id, o, c, pawn, target, map, lines, fx)
	if Checks.is_success(o):
		var xp := int(Content.rule(s.content, "check_xp")) * (2 if o == "crit" else 1)
		if xp > 0:
			s.grant_xp(String(c.id), xp, "", false)
			lines.append({"t": "xp", "text": "+%d XP" % xp})
	if cost > 0:
		tp.ap = int(tp.ap) - cost
		s._phase_changed()
	_cooldown[key] = now + float(Content.rule(s.content, "check_cooldown"))

	var check := {"skill": skill_id, "name": skill.name, "stat": skill.stat, "d20": d20, "bonus": b, "total": total, "dc": dc,
		"outcome": o, "target_name": String(target.get("name", "")), "label": Checks.OUTCOMES[o]}
	var text := Protocol.sanitize_text(String(opts.get("text", "")))
	if text == "":
		text = "%s%s" % [Checks.QUICK_LABELS.get(skill_id, skill.name), (" : " + String(target.name)) if not target.is_empty() and target.id != pawn.id else ""]
	var result := Checks.narrate(skill_id, o, String(c.name))
	if message_id != "":
		var m := s._message(message_id)
		if not m.is_empty():
			m.check = check
			m.result = result
			m.lines = lines
			m.status = Protocol.ACTION_RESOLVED if String(m.get("kind", "")) == Protocol.KIND_ACTION else "done"
			s._update_message(m)
	else:
		s._add_message({"kind": Protocol.KIND_ACTION, "from": player_id, "from_name": s._speaker_name(player_id),
			"to": String(opts.get("to", Protocol.TO_ALL)), "text": text, "status": Protocol.ACTION_RESOLVED,
			"result": result, "roll": {}, "check": check, "lines": lines})
	var roll_fx := {"type": "roll", "token": String(pawn.id), "target": String(target.get("id", "")), "actor_name": String(c.name),
		"target_name": String(target.get("name", "")) if target.get("id", "") != pawn.id else "", "label": String(skill.name),
		"d20": d20, "bonus": b, "total": total, "vs": dc, "vs_label": "DD", "outcome": OUTCOME_FX[o], "tag": String(Checks.OUTCOMES[o]).to_upper()}
	s.broadcast_fx([roll_fx] + fx)
	for f in _fights:
		s.start_encounter(f[0], f[1], true)
	_fights = []
	s._mark("characters")
	s.characters_changed.emit()
	return ""


static func _pos(t: Dictionary) -> Vector2i:
	return Vector2i(int(t.get("x", 0)), int(t.get("y", 0)))


## Cible logique quand le joueur n'en donne pas.
func _auto_target(skill_id: String, pawn: Dictionary, map: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 999
	var rng := int(Checks.get_skill(skill_id).get("range", 0))
	for t in map.get("tokens", []):
		if t.get("hidden", false) or t.id == pawn.id:
			continue
		var d := Rules.distance(_pos(pawn), _pos(t))
		if d > rng or d >= best_d:
			continue
		var kind := String(t.get("kind", ""))
		var ok := false
		match skill_id:
			"crochetage":
				ok = (kind == "object" and String(t.get("loot", "")) != "") or kind == "npc"
			"athletisme":
				ok = kind == "object" and int(t.get("lock", 0)) > 0
			"soins":
				ok = kind == "pc" and not s.combat.is_ko(t) and int(t.get("hp", 0)) < int(t.get("hp_max", 0))
			"persuasion":
				ok = kind == "npc"
			"intimidation":
				ok = kind in ["npc", "monster"] and not s.combat.is_ko(t)
			"savoir":
				ok = kind == "monster" and not s.combat.is_ko(t)
		if ok:
			best = t
			best_d = d
	if skill_id == "soins" and (best.is_empty() or int(pawn.get("hp", 0)) < int(pawn.get("hp_max", 0)) and int(best.get("hp", 0)) * int(pawn.get("hp_max", 1)) >= int(pawn.get("hp", 0)) * int(best.get("hp_max", 1))):
		best = pawn
	return best


## Difficulté selon le contexte (coffre verrouillé, monstre coriace…).
func _context_dc(skill_id: String, skill: Dictionary, target: Dictionary) -> int:
	var dc := int(skill.dc)
	if target.is_empty():
		return dc
	if String(target.get("kind", "")) == "object" and int(target.get("lock", 0)) > 0:
		return int(target.lock) + (2 if skill_id == "athletisme" else 0)
	if String(target.get("kind", "")) == "monster" and skill_id == "intimidation":
		var sh := s.combat.sheet_of(target)
		if sh.get("boss", false) or String(sh.get("rank", "")) == "boss":
			return 99
		return clampi(10 + int(target.get("hp_max", 10)) / 6, 10, 24)
	return dc


func _hurt(t: Dictionary, amount: int, why: String, lines: Array, fx: Array) -> void:
	amount = maxi(1, amount)
	s._damage_token(t, amount)
	lines.append({"t": "dmg", "text": "%s perd %d PV (%s)" % [t.name, amount, why]})
	fx.append({"token": String(t.id), "type": "dmg", "amount": amount})


func _dice(expr: String) -> int:
	return int(Dice.roll(expr, _rng).get("total", 1))


## Objets d'une table (catalogue de la campagne, sinon table de secours) dans le sac.
func _find(c: Dictionary, table_id: String, rolls: int, source: String, lines: Array) -> void:
	var table := Content.get_entry(s.content, "loot", table_id)
	var found := 0
	for i in rolls:
		var drop: Dictionary
		if not table.is_empty():
			drop = Inventory.roll_loot(s.content, table_id, _rng)
		else:
			drop = Inventory.roll_loot({"loot": {table_id: Checks.TABLES.get(table_id, {})}, "items": s.content.get("items", {})}, table_id, _rng)
		for it in drop.items:
			if not Inventory.add(c, it).is_empty():
				lines.append({"t": "loot", "text": "%s trouve : %s%s" % [c.name, it.name, (" ×%d" % int(it.qty)) if int(it.get("qty", 1)) > 1 else ""], "rarity": String(it.get("rarity", "commun"))})
				found += 1
		if int(drop.gold) > 0:
			c.gold = int(c.get("gold", 0)) + int(drop.gold)
			lines.append({"t": "gold", "text": "%s trouve %d pièces d'or" % [c.name, int(drop.gold)]})
			found += 1
	if found == 0:
		lines.append({"t": "info", "text": "Rien d'utile %s." % source})
	else:
		s.quest_event("item", {}, [String(c.get("owner", c.id))])


## Un endroit ne se fouille qu'une fois (rayon de 4 cases).
func _spot_used(map: Dictionary, p: Vector2i, kind: String) -> bool:
	for sp in map.get("searched", []):
		if String(sp.get("k", "")) == kind and Rules.distance(p, Vector2i(int(sp.x), int(sp.y))) <= 4:
			return true
	return false


func _use_spot(map: Dictionary, p: Vector2i, kind: String) -> void:
	if not map.get("searched") is Array:
		map.searched = []
	map.searched.append({"x": p.x, "y": p.y, "k": kind})
	if map.searched.size() > 300:
		map.searched = map.searched.slice(map.searched.size() - 300)


## Dévoile ce qui est caché autour (monstres, objets, étiquettes secrètes).
func _reveal_around(map: Dictionary, p: Vector2i, radius: int, kinds: Array, lines: Array, prefix: String) -> int:
	var names: PackedStringArray = []
	for t in map.get("tokens", []):
		if t.get("hidden", false) and String(t.get("kind", "")) in kinds and Rules.distance(p, _pos(t)) <= radius:
			t.hidden = false
			if String(t.kind) == "monster":
				t.calm_until = SessionServer._clock() + 5.0
			names.append(String(t.name))
	for l in map.get("labels", []):
		if l.get("hidden", false) and Rules.distance(p, Vector2i(int(l.x), int(l.y))) <= radius:
			l.hidden = false
			names.append("« %s »" % l.text)
	if not names.is_empty():
		lines.append({"t": "info", "text": "%s : %s" % [prefix, ", ".join(names)]})
		s.map_changed(s.active_map, true)
	return names.size()


## Une rumeur : l'étiquette secrète la plus proche devient visible.
func _rumor(map: Dictionary, p: Vector2i, lines: Array) -> bool:
	var best := {}
	var best_d := 9999
	for l in map.get("labels", []):
		var d := Rules.distance(p, Vector2i(int(l.x), int(l.y)))
		if l.get("hidden", false) and d < best_d:
			best = l
			best_d = d
	if best.is_empty():
		return false
	best.hidden = false
	lines.append({"t": "quest", "text": "Rumeur : « %s » (indiqué sur la carte)" % best.text})
	s.map_changed(s.active_map, true)
	return true


func _effects(skill_id: String, o: String, c: Dictionary, pawn: Dictionary, target: Dictionary, map: Dictionary, lines: Array, fx: Array) -> void:
	var ok := Checks.is_success(o)
	var crit := o == "crit"
	var bad := o in ["failure", "fumble"]
	var p := _pos(pawn)
	var now := SessionServer._clock()
	var tkind := String(target.get("kind", ""))
	match skill_id:
		"athletisme":
			if tkind == "object" and String(target.get("loot", "")) != "":
				if ok:
					lines.append({"t": "info", "text": "%s force %s." % [c.name, target.name]})
					target.erase("lock")
					s.open_chest(String(target.id), String(c.get("owner", c.id)))
				elif bad:
					_hurt(pawn, _dice("1d4"), "effort", lines, fx)
			elif o == "failure":
				_hurt(pawn, _dice("1d4"), "chute", lines, fx)
			elif o == "fumble":
				_hurt(pawn, _dice("1d6") + 1, "lourde chute", lines, fx)
		"discretion":
			if ok:
				var secs := 45.0 if crit else 25.0
				pawn.safe_until = now + secs
				lines.append({"t": "info", "text": "%s se fond dans le décor : les monstres ne le voient plus pendant %d s." % [c.name, int(secs)]})
			elif bad:
				var seen: Array = []
				var radius := int(Content.rule(s.content, "aggro_radius")) * 2
				for m in map.get("tokens", []):
					if s._can_aggro(m) and Rules.distance(p, _pos(m)) <= radius and Vision._line_clear(String(map.cells), int(map.w), _pos(m), p):
						seen.append(m)
				pawn.safe_until = 0.0
				if not seen.is_empty() and bool(Content.rule(s.content, "auto_aggro")) and not Phases.def(String(s.phase.type)).turns and s.encounter_of(String(pawn.id)).is_empty():
					lines.append({"t": "dmg", "text": "Repéré ! %s attaque." % seen[0].name})
					_fights.append([seen, [String(c.get("owner", ""))]])
				else:
					lines.append({"t": "info", "text": "Un bruit maladroit… mais personne n'est là pour l'entendre."})
		"crochetage":
			if tkind == "object" and String(target.get("loot", "")) != "":
				if ok:
					target.erase("lock")
					s.open_chest(String(target.id), String(c.get("owner", c.id)))
				elif o == "fumble":
					_hurt(pawn, _dice("1d6"), "piège", lines, fx)
				else:
					lines.append({"t": "info", "text": "La serrure résiste."})
			elif tkind == "npc":
				if ok:
					var g := _dice("1d10") + (5 if crit else 0)
					c.gold = int(c.get("gold", 0)) + g
					lines.append({"t": "gold", "text": "%s subtilise %d pièces d'or à %s" % [c.name, g, target.name]})
				elif o == "fumble":
					target.talk_block_until = now + 60.0
					lines.append({"t": "dmg", "text": "%s vous prend la main dans le sac et refuse de vous parler un moment !" % target.name})
			else:
				lines.append({"t": "info", "text": "Rien à crocheter ici (approchez-vous d'un coffre)."})
		"endurance":
			if ok:
				var effects := s.combat.effects_of(pawn)
				for i in effects.size():
					if String(effects[i].get("kind", "")) == "debuff" or String(Content.get_entry(s.content, "statuses", String(effects[i].get("id", ""))).get("kind", "")) == "debuff":
						lines.append({"t": "heal", "text": "%s se débarrasse de : %s" % [c.name, effects[i].get("name", effects[i].get("id", "?"))]})
						effects.remove_at(i)
						s.combat.touch(pawn)
						break
				if crit:
					s._heal_token(pawn, _dice("1d4"))
			elif o == "failure":
				_hurt(pawn, _dice("1d4"), "épuisement", lines, fx)
			elif o == "fumble":
				_hurt(pawn, _dice("1d6"), "épuisement", lines, fx)
		"fouille", "survie":
			var kind := "fouille" if skill_id == "fouille" else "cueillette"
			if ok:
				if _spot_used(map, p, kind):
					lines.append({"t": "info", "text": "Cet endroit a déjà été %s : allez voir plus loin." % ("fouillé" if kind == "fouille" else "exploité")})
				else:
					_use_spot(map, p, kind)
					_find(c, kind, 2 if crit else 1, "ici", lines)
					if skill_id == "fouille":
						_reveal_around(map, p, 4, ["object"], lines, "Vous découvrez")
			elif o == "fumble":
				_hurt(pawn, 1, "coupure" if skill_id == "fouille" else "ronces", lines, fx)
		"savoir":
			if ok and tkind == "monster":
				var sh := s.combat.sheet_of(target)
				var st := s.combat.stats_of(target)
				if String(sh.get("description", "")) != "":
					lines.append({"t": "info", "text": String(sh.description)})
				lines.append({"t": "info", "text": "%s : %d/%d PV, Défense %d, résistance physique %d, magique %d" % [target.name, int(target.get("hp", 0)), int(target.get("hp_max", 0)), int(st.defense), int(st.resist_phys), int(st.resist_mag)]})
				if int(st.resist_mag) < int(st.resist_phys):
					lines.append({"t": "quest", "text": "Point faible : la magie."})
				elif int(st.resist_phys) < int(st.resist_mag):
					lines.append({"t": "quest", "text": "Point faible : les armes."})
			elif ok:
				if not _rumor(map, p, lines):
					lines.append({"t": "info", "text": "Rien ici ne vous rappelle quoi que ce soit."})
		"perception":
			if ok:
				if _reveal_around(map, p, 12 if crit else 8, ["monster", "object", "npc"], lines, "Vous repérez") == 0:
					lines.append({"t": "info", "text": "Rien d'anormal alentour."})
				pawn.safe_until = maxf(float(pawn.get("safe_until", 0.0)), now + 4.0)
		"soins":
			var who := target if not target.is_empty() else pawn
			var cid := String(who.get("owner", who.id))
			if ok:
				if float(_aid.get(cid, 0.0)) > now:
					lines.append({"t": "info", "text": "%s a déjà été soigné il y a peu (une fois par minute)." % who.name})
				else:
					var esp := Rules.stat(c, "Esprit", s.content)
					var amount := (6 if crit else _dice("1d6")) + esp / 2
					s._heal_token(who, amount)
					_aid[cid] = now + 60.0
					lines.append({"t": "heal", "text": "%s rend %d PV à %s" % [c.name, amount, who.name]})
					fx.append({"token": String(who.id), "type": "heal", "amount": amount})
			elif o == "fumble":
				_hurt(who, 1, "maladresse", lines, fx)
		"persuasion", "intimidation":
			if tkind == "monster":
				if skill_id == "persuasion":
					if ok:
						target.calm_until = now + 60.0
						lines.append({"t": "info", "text": "%s se calme et vous laisse passer (1 minute)." % target.name})
					elif bad:
						lines.append({"t": "info", "text": "%s ne comprend pas un mot…" % target.name})
				elif ok:
					if not s.encounter_of(String(target.id)).is_empty():
						s.combat._add_status({}, target, {"status": "effraye", "turns": 2, "value": 0})
						s.combat.touch(target)
						lines.append({"t": "info", "text": "%s est effrayé !" % target.name})
					else:
						(map.tokens as Array).erase(target)
						lines.append({"t": "info", "text": "%s s'enfuit sans demander son reste !" % target.name})
						s.map_changed(s.active_map, true)
				elif bad and s.encounter_of(String(target.id)).is_empty() and not Phases.def(String(s.phase.type)).turns:
					target.calm_until = 0.0
					lines.append({"t": "dmg", "text": "%s n'apprécie pas et attaque !" % target.name})
					_fights.append([[target], [String(c.get("owner", ""))]])
			elif tkind == "npc":
				if ok:
					var offered := s.npc_offer(target, String(c.get("owner", "")))
					if offered != "":
						lines.append({"t": "quest", "text": "%s vous confie quelque chose : « %s » (touchez-le pour accepter)." % [target.name, offered]})
					if not _rumor(map, p, lines) and offered == "":
						lines.append({"t": "info", "text": "%s se montre bien disposé envers vous." % target.name})
					if crit and skill_id == "persuasion":
						var g := _dice("1d6")
						c.gold = int(c.get("gold", 0)) + g
						lines.append({"t": "gold", "text": "%s vous offre %d pièces d'or pour la route" % [target.name, g]})
				elif o == "fumble":
					target.talk_block_until = now + 30.0
					lines.append({"t": "dmg", "text": "%s se vexe et refuse de vous parler un moment." % target.name})
				else:
					lines.append({"t": "info", "text": "%s ne se laisse pas %s." % [target.name, "convaincre" if skill_id == "persuasion" else "impressionner"]})
			else:
				lines.append({"t": "info", "text": "Personne à qui parler ici."})
		"magie":
			if ok:
				if _reveal_around(map, p, 10, ["object"], lines, "Une aura magique révèle") == 0:
					lines.append({"t": "info", "text": "Aucune magie cachée alentour."})
				var gain := _dice("1d4") + (2 if crit else 0)
				c.res = mini(int(c.get("res_max", 0)), int(c.get("res", 0)) + gain)
				s._sync_pawns_for(String(c.id))
			elif o == "fumble":
				_hurt(pawn, _dice("1d4"), "retour de magie", lines, fx)


## Conséquence ajoutée par le MJ (un clic) à une action : appliquée à son auteur.
func consequence(message_id: String, kind: String) -> String:
	var m := s._message(message_id)
	if m.is_empty() or String(m.get("kind", "")) != Protocol.KIND_ACTION:
		return "Action introuvable."
	var pid := String(m.get("from", ""))
	var c: Dictionary = s.characters.get(pid, {})
	var pawn := MapData.token(_map(), "pawn_" + pid)
	if c.is_empty():
		return "Ce joueur n'a pas de personnage."
	var lines: Array = m.get("lines", [])
	var fx: Array = []
	match kind:
		"dmg_small", "dmg":
			if pawn.is_empty():
				return "Pion introuvable."
			_hurt(pawn, _dice("1d4" if kind == "dmg_small" else "1d8"), "conséquence", lines, fx)
		"heal":
			if pawn.is_empty():
				return "Pion introuvable."
			var n := _dice("1d6")
			s._heal_token(pawn, n)
			lines.append({"t": "heal", "text": "%s récupère %d PV" % [c.name, n]})
			fx.append({"token": String(pawn.id), "type": "heal", "amount": n})
		"xp":
			s.grant_xp(String(c.id), 10, "", false)
			lines.append({"t": "xp", "text": "+10 XP"})
		"gold":
			var g := _dice("1d10")
			c.gold = int(c.get("gold", 0)) + g
			lines.append({"t": "gold", "text": "%s gagne %d pièces d'or" % [c.name, g]})
		"item":
			_find(c, "fouille", 1, "cette fois", lines)
		"poison", "stun":
			if pawn.is_empty():
				return "Pion introuvable."
			s.combat._add_status({}, pawn, {"status": "poison" if kind == "poison" else "etourdi", "turns": 3 if kind == "poison" else 1, "value": 0})
			s.combat.touch(pawn)
			lines.append({"t": "dmg", "text": "%s est %s" % [c.name, "empoisonné" if kind == "poison" else "étourdi"]})
		_:
			return "Conséquence inconnue."
	m.lines = lines
	if String(m.status) in [Protocol.ACTION_PENDING, Protocol.ACTION_ROLLED]:
		m.status = Protocol.ACTION_RESOLVED
	s._update_message(m)
	if not fx.is_empty():
		s.broadcast_fx(fx)
	s._mark("characters")
	s.characters_changed.emit()
	return ""
