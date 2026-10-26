extends Node
## Tests des règles et du moteur de combat, sans réseau : création, formules,
## points d'action, capacités, statuts, passifs, ultime, victoire et butin,
## progression, inventaire, quêtes, sauvegarde et conversion des anciennes fiches.
## Usage : godot --headless --path . res://tests/rules_test.tscn

var _ok := 0
var _fail := 0
var _sent: Array = []


func _ready() -> void:
	CampaignStore.dir_path = "user://test_rules"
	_test_content()
	_test_creation()
	_test_combat()
	_test_progression_and_quests()
	_test_migration()
	print("\nRÉSULTAT : %d vérifications OK, %d en échec." % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _expect(cond: bool, label: String) -> void:
	if cond:
		_ok += 1
		print("  OK  ", label)
	else:
		_fail += 1
		print("  ÉCHEC  ", label)


func _server(universe: String = "fantasy") -> SessionServer:
	_sent.clear()
	return SessionServer.new({"name": "Test règles", "universe": universe, "auto_accept": true},
		func(peer, evt, payload): _sent.append([peer, evt, payload]), func(_p, _d): pass)


func _add_player(server: SessionServer, pname: String) -> Dictionary:
	var player := {"id": "p_" + pname.to_lower(), "name": pname, "token": Protocol.random_hex(16), "status": Protocol.STATUS_ACCEPTED,
		"peer_id": 0, "ip": "", "online": false, "joined_at": 0.0, "last_seen": 0.0, "disconnects": 0}
	server.players[player.id] = player
	return player


func _test_content() -> void:
	print("\n— Catalogue")
	for uid in ["fantasy", "legenders"]:
		var c := Content.default_for(uid)
		var classes := Rules.classes(c)
		_expect(classes.size() >= 7, "%s : %d classes" % [uid, classes.size()])
		var complete := true
		for cls in classes:
			if (cls.abilities as Array).size() != 3 or String(cls.ultimate) == "" or (cls.passive as Dictionary).is_empty():
				complete = false
			for id in cls.abilities + [cls.ultimate]:
				if Content.get_entry(c, "abilities", String(id)).is_empty():
					complete = false
		_expect(complete, "%s : chaque classe a 3 capacités, un ultime et un passif" % uid)
		_expect(Content.stat_names(c) == ["Force", "Dextérité", "Constitution", "Intelligence", "Esprit", "Charisme"], "%s : six caractéristiques" % uid)
	var c := Content.default_for("fantasy")
	_expect(not Content.get_entry(c, "classes", "gardien").is_empty() and not Content.get_entry(c, "classes", "soigneur").is_empty(), "classes Gardien et Soigneur présentes")
	var item := Content.sanitize_item({"name": "Épée test", "category": "arme", "rarity": "nimporte", "weapon": {"damage": "xx"}}, c)
	_expect(item.rarity == "commun" and item.weapon.damage == "1d6", "objet du MJ validé (rareté et dés corrigés)")


func _test_creation() -> void:
	print("\n— Création")
	var c := Content.default_for("fantasy")
	var good := {"Force": 4, "Dextérité": 2, "Constitution": 4, "Intelligence": 0, "Esprit": 2, "Charisme": 3}
	_expect(Rules.valid_alloc(good, c), "répartition de 15 points valide")
	var too_much := good.duplicate()
	too_much.Force = 5
	too_much.Charisme = 3
	too_much.Esprit = 3
	_expect(not Rules.valid_alloc(too_much, c), "plus de 15 points refusé")
	_expect(not Rules.valid_alloc({"Force": 6}, c), "au-delà de 10 refusé")
	_expect(not Rules.valid_alloc({"Force": -5}, c), "sous 1 refusé")
	var sheet := Rules.build_sheet(CharacterData.create({}, "x", "x", "Test", c), c, "guerrier", good, [2])
	_expect(Rules.base_stat(sheet, "Force") == 10 and Rules.base_stat(sheet, "Constitution") == 10, "5 + points + bonus de classe")
	_expect(int(sheet.hp_max) == 20 + 10 * 2, "PV = PV de classe + Constitution × 2 (%d)" % int(sheet.hp_max))
	_expect(Rules.equipped_abilities(sheet).size() == 4, "4 capacités équipées (3 + ultime)")
	_expect(not (sheet.passive as Dictionary).is_empty(), "passif de classe copié")
	var weapon: Array = sheet.inventory.filter(func(i): return i.get("equipped", false) and i.get("slot", "") == "arme")
	_expect(weapon.size() == 1 and weapon[0].name == "Marteau d'armes", "arme choisie équipée (Marteau d'armes)")
	var d := Rules.derived(sheet, c)
	_expect(int(d.defense) == 8 + Rules.stat(sheet, "Dextérité", c) + 1, "Défense = 8 + Dextérité + armure (%d)" % int(d.defense))
	var armor := Content.item_instance(c, "harnois")
	Inventory.add(sheet, armor)
	var inv_armor: Dictionary = sheet.inventory[-1]
	var preview := Inventory.preview(sheet, c, String(inv_armor.uid))
	var def_line: Array = preview.filter(func(p): return p.label == "Défense")
	_expect(def_line.size() == 1 and int(def_line[0].after) > int(def_line[0].before), "aperçu d'équipement : Défense %d → %d" % [def_line[0].before, def_line[0].after] if not def_line.is_empty() else "aperçu d'équipement")
	Inventory.equip(sheet, String(inv_armor.uid))
	_expect(Inventory.slot_items(sheet, "armure").size() == 1, "une seule armure équipée à la fois")


func _test_combat() -> void:
	print("\n— Combat")
	var server := _server()
	var p := _add_player(server, "Lina")
	var err := server._cmd_char_create(p, {"class_id": "assassin", "alloc": {"Force": 1, "Dextérité": 5, "Constitution": 3, "Intelligence": 1, "Esprit": 2, "Charisme": 3},
		"choices": [0], "identity": {"name": "Lina", "secret": "x"}})
	_expect(err == "", "création par l'hôte (%s)" % err)
	_expect(server._cmd_char_create(_add_player(server, "Triche"), {"class_id": "mage", "alloc": {"Force": 9}, "choices": []}) != "", "répartition truquée refusée par l'hôte")
	var sheet: Dictionary = server.characters[p.id]
	var cheat := server._cmd_char_save(p, {"character": {"name": "Lina", "hp_max": 999, "stats": [{"name": "Force", "value": 99}]}})
	_expect(cheat == "" and int(server.characters[p.id].hp_max) < 999 and Rules.base_stat(server.characters[p.id], "Force") < 99, "un téléphone ne peut pas changer ses PV ni ses caractéristiques")
	server.mj_start_game("exploration")
	var map: Dictionary = server.maps[server.active_map]
	var pawn := MapData.token(map, "pawn_" + p.id)
	_expect(not pawn.is_empty(), "pion du joueur posé")
	var wolf := server.mj_spawn_monster("loup", int(pawn.x) + 1, int(pawn.y), false)
	var wolf2 := server.mj_spawn_monster("loup", int(pawn.x) + 1, int(pawn.y) + 1, false)
	_expect(not wolf.is_empty() and not wolf2.is_empty(), "monstres du catalogue placés")
	# Le loup doit être adjacent pour le test.
	for w in [wolf, wolf2]:
		var cell := MapData.free_cell_near(map, int(pawn.x) + 1, int(pawn.y))
		w.x = cell.x
		w.y = cell.y
	server.mj_set_phase("combat")
	_expect(server.phase.type == "combat" and server.phase.order.size() == 3, "combat lancé, 3 combattants")
	# Lina joue en premier.
	server.phase.order.erase(pawn.id)
	server.phase.order.push_front(pawn.id)
	server.phase.turn = 0
	server._start_turn_loop()
	_expect(int(server.phase.ap) == 2, "2 points d'action au début du tour")
	var wolf_hp := int(wolf.hp)
	var e1 := server.turn_action(pawn.id, {"action": "quick", "target": wolf.id})
	_expect(e1 == "" and int(server.phase.ap) == 1, "attaque rapide : 1 PA dépensé")
	var e2 := server.turn_action(pawn.id, {"action": "power", "target": wolf.id})
	_expect(e2.begins_with("Pas assez de points d'action"), "attaque puissante refusée faute de PA (« %s »)" % e2)
	var last: Dictionary = server.messages[-1] if server.messages[-1].get("kind", "") == Protocol.KIND_COMBAT else {}
	for m in server.messages:
		if m.get("kind", "") == Protocol.KIND_COMBAT:
			last = m
	_expect(not last.is_empty() and (last.lines as Array).size() >= 1, "résultat publié en lignes colorées (%s)" % (last.get("text", "")))
	_expect(int(wolf.hp) <= wolf_hp, "le loup a perdu des PV ou l'attaque a raté (%d → %d)" % [wolf_hp, int(wolf.hp)])
	# Capacité avec poison.
	server.phase.ap = 2
	server.characters[p.id].res = 20
	var ab := server.turn_action(pawn.id, {"action": "ability", "id": "lame_empoisonnee", "target": wolf.id})
	_expect(ab == "" or ab.contains("hors de combat"), "capacité utilisée (%s)" % ab)
	_expect(int(server.characters[p.id].res) < 20, "coût en ressource payé")
	_expect(int(server.characters[p.id].cooldowns.get("lame_empoisonnee", 0)) > 0, "recharge démarrée")
	var again := server.turn_action(pawn.id, {"action": "ability", "id": "lame_empoisonnee", "target": wolf.id})
	_expect(again != "", "capacité en recharge refusée (« %s »)" % again)
	var ult := server.turn_action(pawn.id, {"action": "ability", "id": "danse_lames", "target": wolf.id})
	_expect(ult.begins_with("Ultime pas encore chargé"), "ultime bloqué tant que la jauge n'est pas pleine")
	# Défense et statuts.
	server.phase.ap = 1
	_expect(server.turn_action(pawn.id, {"action": "defend"}) == "", "se défendre")
	_expect(server.combat.effects_of(pawn).any(func(e): return e.id == "protege"), "effet « En garde » appliqué")
	server.mj_apply_status(wolf2.id, "etourdi", 1)
	_expect(server.combat.has_flag(wolf2, "stun"), "le MJ étourdit un loup")
	# Fin de tour : le loup 1 (ou le 2 étourdi, sauté) joue.
	server.turn_action(pawn.id, {"action": "end"})
	var current := server._current_token()
	_expect(current != wolf2.id, "le loup étourdi perd son tour")
	# Le MJ fait jouer automatiquement les loups jusqu'au retour de Lina.
	var guard := 0
	while server._current_token() != pawn.id and guard < 6 and server.phase.result == "":
		server.turn_action(server._current_token(), {"action": "auto"})
		server.turn_action(server._current_token(), {"action": "end"})
		guard += 1
	_expect(server._current_token() == pawn.id or server.phase.result != "", "les adversaires jouent puis la main revient au joueur")
	# Victoire : on met les loups à terre.
	server.characters[p.id].ult = 100
	var before_xp := int(server.characters[p.id].xp)
	server.mj_adjust(wolf.id, "hp", -999)
	server.mj_adjust(wolf2.id, "hp", -999)
	_expect(server.phase.result == "victory", "victoire détectée quand tous les ennemis sont à terre")
	_expect(int(server.characters[p.id].xp) > before_xp, "XP distribuée à la victoire (+%d)" % (int(server.characters[p.id].xp) - before_xp))
	var victory: Array = server.messages.filter(func(m): return m.get("banner", "") == "victory")
	_expect(victory.size() == 1, "un seul message de victoire")
	server.mj_adjust(wolf.id, "hp", -1)
	_expect(server.messages.filter(func(m): return m.get("banner", "") == "victory").size() == 1, "pas de double récompense")
	server.mj_set_phase("libre")
	_expect(server.combat.effects_of(pawn).filter(func(e): return int(e.get("turns", 0)) > 0).is_empty(), "effets temporaires retirés à la fin du combat")
	# Gardien : réduction des dégâts d'un allié adjacent.
	var g := Content.default_for("fantasy")
	_expect(String(Content.get_entry(g, "classes", "gardien").passive.trigger) == "ally_damaged", "passif du Gardien : protection des alliés")


func _test_progression_and_quests() -> void:
	print("\n— Progression, butin, quêtes")
	var server := _server()
	var p := _add_player(server, "Bo")
	server._cmd_char_create(p, {"class_id": "mage", "alloc": {"Force": 0, "Dextérité": 3, "Constitution": 3, "Intelligence": 5, "Esprit": 4, "Charisme": 0}, "choices": [1]})
	var c: Dictionary = server.characters[p.id]
	var hp_before := int(c.hp_max)
	server.grant_xp(p.id, 100)
	_expect(int(c.level) == 2, "100 XP : niveau 2")
	_expect(int(c.hp_max) > hp_before, "PV max augmentés au niveau 2")
	_expect(int(c.pending.stat_points) == 1 and int(c.pending.picks) == 1, "un point à placer et un apprentissage à choisir")
	_expect(server.apply_level_choice(p.id, {"stat": "Intelligence"}) == "", "point placé en Intelligence")
	_expect(Rules.base_stat(c, "Intelligence") == 13, "Intelligence 12 → 13")
	var learn := Rules.learnable_now(c, server.content)
	_expect(not learn.is_empty(), "capacité apprenable au niveau 2 (%s)" % (learn[0].name if not learn.is_empty() else "?"))
	_expect(server.apply_level_choice(p.id, {"learn": learn[0].id}) == "", "capacité apprise")
	_expect(c.abilities.any(func(a): return a.id == learn[0].id and not a.equipped), "connue mais pas équipée (emplacements pleins)")
	_expect(server.set_ability_equipped(p.id, learn[0].id, true) != "", "emplacements pleins : il faut en retirer une")
	server.set_ability_equipped(p.id, "gel", false)
	_expect(server.set_ability_equipped(p.id, learn[0].id, true) == "", "échange de capacité équipée")
	# Objet créé à la volée par le MJ.
	var err := server.mj_give_item(p.id, {"name": "Plume du phénix", "category": "unique", "rarity": "legendaire", "description": "Brille dans le noir."})
	_expect(err == "" and c.inventory.any(func(i): return i.name == "Plume du phénix" and i.rarity == "legendaire"), "objet créé en pleine partie et donné")
	server.mj_give_gold(p.id, 50)
	_expect(int(c.gold) == 20 + 50, "or : 20 de départ + 50")
	# Livre de compétence.
	server.mj_give_item(p.id, "livre_second_souffle")
	var book: Array = c.inventory.filter(func(i): return i.get("teaches", "") == "second_souffle")
	_expect(server._cmd_item(p, {"action": "read", "uid": book[0].uid}) == "", "lecture d'un livre de compétence")
	_expect(c.abilities.any(func(a): return a.id == "second_souffle"), "capacité apprise par le livre")
	# Coffre commun.
	var drop := server.mj_roll_loot("boss")
	_expect(not (drop.items as Array).is_empty() and int(drop.gold) >= 40, "table de butin « boss » : objets garantis et or")
	for it in drop.items:
		server.add_loot(it, "Test")
	var first: Dictionary = server.loot[0]
	_expect(server._cmd_loot_take(p, {"uid": first.uid}) == "", "objet pris dans le coffre")
	_expect(server._cmd_loot_take(p, {"uid": first.uid}) != "", "le même objet ne peut pas être pris deux fois")
	# Quêtes.
	var q := server.mj_quest_save({"title": "Les loups de Valombre", "kind": "main", "description": "Chassez les loups.",
		"objectives": [{"text": "Trouver la tanière"}, {"text": "Vaincre l'alpha"}], "rewards": {"xp": 150, "gold": 30, "items": [{"item": "amulette_vie", "qty": 1}]}})
	_expect(q.status == "draft" and server.quests_for(p.id).is_empty(), "quête en brouillon invisible des joueurs")
	server.mj_quest_give(q.id)
	_expect(server.quests_for(p.id).size() == 1, "quête donnée au groupe")
	server.mj_quest_objective(q.id, 0, true)
	var lvl := int(c.level)
	var gold := int(c.gold)
	server.mj_quest_complete(q.id)
	_expect(q.status == "done" and int(c.gold) == gold + 30, "quête réussie : or donné")
	_expect(int(c.level) >= lvl and c.inventory.any(func(i): return i.name == "Amulette de vie"), "XP et objet de récompense donnés (joueur seul : directement dans l'inventaire)")
	server.mj_quest_complete(q.id)
	_expect(int(c.gold) == gold + 30, "récompense jamais donnée deux fois")
	var zed := _add_player(server, "Zed")
	var side := server.mj_quest_save({"title": "Secret", "kind": "side", "assigned": [zed.id], "give": true})
	_expect(side.status == "active" and server.quests_for(p.id).size() == 1, "quête assignée à un autre joueur : invisible pour Bo")
	# Sauvegarde et reprise.
	var save_err := server.save()
	_expect(save_err == "", "sauvegarde (%s)" % save_err)
	var data := CampaignStore.load_campaign(server.session.id)
	_expect(int(data.get("format", 0)) == 2, "format de sauvegarde 2")
	var restored := SessionServer.new({"port": 7777}, func(_a, _b, _c): pass, func(_a, _b): pass, data)
	var rc: Dictionary = restored.characters.get(p.id, {})
	_expect(int(rc.get("level", 0)) == int(c.level) and int(rc.get("gold", 0)) == int(c.gold), "reprise : niveau et or")
	_expect((rc.get("inventory", []) as Array).size() == c.inventory.size() and (rc.get("abilities", []) as Array).size() == c.abilities.size(), "reprise : inventaire et capacités")
	_expect(restored.quests.size() == 2 and restored.content.items.size() == server.content.items.size(), "reprise : quêtes et catalogue")
	CampaignStore.delete(server.session.id)


func _test_migration() -> void:
	print("\n— Conversion des anciennes fiches")
	var c := Content.default_for("fantasy")
	var old := {"id": "p_old", "owner": "p_old", "name": "Ancien", "auto": false, "level": 2, "hp": 15, "hp_max": 20, "res": 5, "res_max": 10,
		"stats": [{"name": "Force", "value": 14}, {"name": "Agilité", "value": 12}, {"name": "Endurance", "value": 13}, {"name": "Perception", "value": 10}],
		"abilities": [{"name": "Coup puissant", "kind": "attack", "damage": "2d8", "stat": "Force", "res_cost": 3, "range": 1}],
		"inventory": [{"name": "Épée", "category": "arme", "damage": "1d8", "stat": "Agilité", "crit": 19, "range": 1, "equipped": true},
			{"name": "Potion", "category": "consommable", "heal": "2d4", "qty": 2}]}
	var conv := Migrate.sheet(old, c, {})
	_expect(Rules.base_stat(conv, "Force") == 7 and Rules.base_stat(conv, "Dextérité") == 6 and Rules.base_stat(conv, "Constitution") == 7, "caractéristiques converties (14 → 7, Agilité → Dextérité)")
	_expect(conv.abilities.size() == 1 and String(conv.abilities[0].effects[0].type) == "damage", "capacité convertie en effets")
	_expect(conv.inventory[0].weapon.stat == "Dextérité" and conv.inventory[1].use.size() == 1, "objets convertis (arme, potion)")
	_expect(int(conv.schema) == CharacterData.SCHEMA and int(conv.hp) == 15, "fiche marquée au nouveau format, PV conservés")
	var auto := {"id": "p_a", "owner": "p_a", "name": "Auto", "auto": true, "class_id": "pretre", "hp": 10, "hp_max": 20, "stats": []}
	var conv2 := Migrate.sheet(auto, c, {})
	_expect(conv2.class_id == "soigneur" and Rules.equipped_abilities(conv2).size() == 4, "ancien Prêtre devenu Soigneur, avec ses 4 capacités")
