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
	_test_vision()
	_test_kills()
	_test_species()
	_test_adventures()
	_test_map_tools()
	_test_encounters()
	_test_checks()
	_test_town()
	_test_collisions()
	_test_monk_necro()
	_test_alliances()
	_test_keys()
	_test_npc_control()
	_test_nested_maps()
	_test_bricks()
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


func _test_vision() -> void:
	print("\n— Brouillard de guerre")
	var server := _server()
	var a := _add_player(server, "Vue")
	var b := _add_player(server, "Myope")
	server._cmd_char_create(a, {"class_id": "rodeur", "alloc": {"Force": 0, "Dextérité": 5, "Constitution": 4, "Intelligence": 0, "Esprit": 3, "Charisme": 3}, "choices": [0], "identity": {"name": "Vue"}})
	server._cmd_char_create(b, {"class_id": "guerrier", "alloc": {"Force": 5, "Dextérité": 0, "Constitution": 5, "Intelligence": 0, "Esprit": 2, "Charisme": 3}, "choices": [0], "identity": {"name": "Myope"}})
	var ra := Vision.radius(server.characters[a.id], server.content)
	var rb := Vision.radius(server.characters[b.id], server.content)
	_expect(ra > rb and ra == 3 + Rules.stat(server.characters[a.id], "Dextérité", server.content) / 2, "vision = 3 + Dextérité ÷ 2 (%d contre %d cases)" % [ra, rb])
	var m := server.mj_create_map("Plaine", 40, 20)
	server.mj_set_active_map(m.id)
	server.mj_start_game("exploration")
	var map: Dictionary = server.maps[server.active_map]
	var pa := MapData.token(map, "pawn_" + a.id)
	var pb := MapData.token(map, "pawn_" + b.id)
	pa.x = 5
	pa.y = 10
	pb.x = 34
	pb.y = 10
	var near := server.mj_spawn_monster("loup", 8, 10, false)
	var far := server.mj_spawn_monster("loup", 20, 10, false)
	var ids := func(view: Dictionary) -> Array: return (view.get("tokens", []) as Array).map(func(t): return String(t.id))
	var va := server._map_view(a.id)
	_expect(ids.call(va).has(near.id) and not ids.call(va).has(far.id), "un joueur voit le loup proche, pas le loup lointain")
	_expect(not ids.call(va).has(pb.id), "ni le pion d'un allié hors de vue (vision non partagée)")
	_expect(String(va.fog.visible).length() == 40 * 20 and Vision.is_set(va.fog.visible, map, 6, 10) and not Vision.is_set(va.fog.visible, map, 30, 10), "état du brouillard envoyé au téléphone")
	# Un mur coupe la vue.
	for y in range(8, 13):
		server.mj_paint(m.id, 7, y, "#")
	_expect(not ids.call(server._map_view(a.id)).has(near.id), "un mur cache le loup derrière lui")
	server.mj_add_label(m.id, 24, 4, "Ruines", false)
	_expect((server._map_view(a.id).labels as Array).is_empty(), "étiquette d'une zone inexplorée cachée")
	pa.x = 24
	pa.y = 6
	var v2 := server._map_view(a.id)
	_expect((v2.labels as Array).size() == 1, "étiquette révélée une fois la zone explorée")
	pa.x = 5
	pa.y = 10
	var v3 := server._map_view(a.id)
	_expect(Vision.is_set(v3.fog.explored, map, 24, 6) and not Vision.is_set(v3.fog.visible, map, 24, 6), "les zones déjà vues restent connues (exploration mémorisée)")
	server.mj_set_rules({"shared_vision": true})
	_expect(ids.call(server._map_view(a.id)).has(pb.id), "vision partagée : on voit tout le groupe et ce qu'il voit")
	server.mj_set_rules({"shared_vision": false})
	server.mj_update_map(m.id, {"fog": false})
	_expect(ids.call(server._map_view(a.id)).has(far.id), "brouillard désactivé : toute la carte est visible")
	server.mj_update_map(m.id, {"fog": true})
	server.mj_reset_fog(m.id)
	_expect(not Vision.is_set(server._map_view(a.id).fog.explored, map, 24, 6), "le MJ peut faire oublier l'exploration")
	_expect(not server.fog_preview(m.id).is_empty(), "aperçu du brouillard pour le MJ")


func _test_kills() -> void:
	print("\n— Monstres vaincus, butin et dés")
	var server := _server()
	var p := _add_player(server, "Kira")
	server._cmd_char_create(p, {"class_id": "guerrier", "alloc": {"Force": 5, "Dextérité": 3, "Constitution": 4, "Intelligence": 0, "Esprit": 0, "Charisme": 3}, "choices": [0], "identity": {"name": "Kira"}})
	var m := server.mj_create_map("Arène", 20, 12)
	server.mj_set_active_map(m.id)
	server.mj_start_game("exploration")
	var map: Dictionary = server.maps[server.active_map]
	var pawn := MapData.token(map, "pawn_" + p.id)
	pawn.x = 5
	pawn.y = 5
	var wolf := server.mj_spawn_monster("loup", 6, 5, false)
	wolf.x = 6
	wolf.y = 5
	var wsheet := server._sheet_for_token(wolf)
	wsheet.loot = "boss"
	var other := server.mj_spawn_monster("loup", 15, 5, false)
	server.mj_set_phase("combat")
	server.phase.order.erase(pawn.id)
	server.phase.order.push_front(pawn.id)
	server.phase.turn = 0
	server._start_turn_loop()
	wolf.hp = 1
	var gold_before := int(server.characters[p.id].gold)
	var inv_before: int = (server.characters[p.id].inventory as Array).size()
	var guard := 0
	_sent.clear()
	while not MapData.token(map, wolf.id).is_empty() and guard < 12:
		server.phase.turn = server.phase.order.find(pawn.id)
		server.phase.ap = 2
		server.turn_action(pawn.id, {"action": "quick", "target": wolf.id})
		guard += 1
	_expect(MapData.token(map, wolf.id).is_empty() and not server.phase.order.has(wolf.id), "le monstre vaincu disparaît de la carte et de l'ordre des tours")
	var c: Dictionary = server.characters[p.id]
	_expect((c.inventory as Array).size() > inv_before and int(c.gold) > gold_before, "le vainqueur reçoit le butin dans son sac (+%d or)" % (int(c.gold) - gold_before))
	var lines: Array = []
	for msg in server.messages:
		lines.append_array(msg.get("lines", []))
	_expect(lines.any(func(l): return String(l.get("t", "")) == "loot" and String(l.text).contains("récupère sur")), "le récit annonce ce qu'il a récupéré")
	_expect(lines.any(func(l): return String(l.get("t", "")) == "hit" or String(l.get("t", "")) == "miss" or String(l.get("t", "")) == "crit"), "le récit montre chaque jet (d20 + bonus contre Défense)")
	var fx: Array = []
	for s in _sent:
		if s[1] == Protocol.EVT_FX:
			fx.append_array(s[2].fx)
	var all_fx: Array = []
	server.fx.connect(func(l): all_fx.append_array(l))
	# Coup suivant sur l'autre loup, pour récupérer les retours visuels.
	other.x = 6
	other.y = 5
	server.phase.turn = server.phase.order.find(pawn.id)
	server.phase.ap = 2
	server.turn_action(pawn.id, {"action": "quick", "target": other.id})
	var roll: Array = all_fx.filter(func(f): return String(f.get("type", "")) == "roll")
	_expect(roll.size() == 1 and int(roll[0].d20) >= 1 and int(roll[0].d20) <= 20 and roll[0].has("vs") and roll[0].has("outcome"), "le jet de dé est envoyé aux écrans (d20 = %s)" % (str(roll[0].d20) if not roll.is_empty() else "?"))
	var hits: Array = all_fx.filter(func(f): return String(f.get("type", "")) == "dmg_roll")
	_expect(String(roll[0].outcome) in ["miss", "fumble"] or (hits.size() == 1 and not (hits[0].faces as Array).is_empty()), "dés de dégâts envoyés quand le coup porte")
	other.hp = 1
	guard = 0
	while server.phase.result == "" and guard < 12:
		server.phase.turn = server.phase.order.find(pawn.id)
		server.phase.ap = 2
		server.turn_action(pawn.id, {"action": "quick", "target": other.id})
		guard += 1
	_expect(server.phase.result == "victory" and int(server.characters[p.id].xp) > 0, "victoire après le dernier monstre retiré, XP distribuée")


func _test_species() -> void:
	print("\n— Peuples, synergies, équipement de départ")
	var c := Content.default_for("fantasy")
	_expect(Content.list(c, "species").size() >= 7 and not Rules.get_class_def(c, "druide").is_empty(), "7 peuples et la classe Druide")
	var alloc: Dictionary = Rules.get_class_def(c, "mage").recommended
	var elfe := Rules.build_sheet(CharacterData.create({}, "a", "a", "Lys", c), c, "mage", alloc, [0], "elfe")
	var orc := Rules.build_sheet(CharacterData.create({}, "b", "b", "Grok", c), c, "mage", alloc, [0], "demi_orc")
	_expect(int(elfe.res_max) >= int(orc.res_max) + 8, "un elfe mage a plus de mana qu'un demi-orc mage (%d contre %d)" % [int(elfe.res_max), int(orc.res_max)])
	_expect(Rules.base_stat(orc, "Force") == Rules.base_stat(elfe, "Force") + 2, "bonus de Force du demi-orc")
	_expect(int(Rules.derived(elfe, c).vision) > int(Rules.derived(orc, c).vision), "vision elfique")
	var druide := Rules.build_sheet(CharacterData.create({}, "d", "d", "Urg", c), c, "druide", Rules.get_class_def(c, "druide").recommended, [0], "demi_orc")
	var ids: Array = (druide.abilities as Array).map(func(a): return String(a.id))
	_expect(ids.has("appel_horde") and ids.has("rage_sang") and ids.has("appel_loup"), "un demi-orc druide appelle la horde (capacités de peuple et de synergie)")
	_expect(Rules.equipped_abilities(druide).size() == 6, "capacités de peuple équipées sans prendre d'emplacement")
	var inv: Array = (elfe.inventory as Array).map(func(i): return String(i.get("id", i.get("item_id", ""))))
	var names: Array = (elfe.inventory as Array).map(func(i): return String(i.name))
	_expect(names.has("Torche") and names.has("Corde (15 m)") and names.has("Trousse de soins"), "équipement de départ : torche, corde, trousse de soins")
	var server := _server()
	var p := _add_player(server, "Lys")
	_expect(server._cmd_char_create(p, {"class_id": "mage", "species_id": "elfe", "alloc": alloc, "choices": [0], "identity": {"name": "Lys"}}) == "", "création d'un elfe mage par l'hôte")
	_expect(server._cmd_char_create(_add_player(server, "X"), {"class_id": "mage", "species_id": "dragon_volant", "alloc": alloc, "choices": [0], "identity": {"name": "X"}}) != "", "peuple inconnu refusé")
	var sheet: Dictionary = server.characters[p.id]
	var torch: Dictionary = (sheet.inventory as Array).filter(func(i): return String(i.name) == "Torche")[0]
	var v0 := int(Rules.derived(sheet, server.content).vision)
	Inventory.equip(sheet, String(torch.uid))
	_expect(int(Rules.derived(sheet, server.content).vision) == v0 + 2, "équiper la torche : +2 cases de vision")


func _test_adventures() -> void:
	print("\n— Aventures prêtes à jouer")
	var advs := Adventures.all()
	_expect(advs.size() >= 6, "%d aventures disponibles" % advs.size())
	for adv in advs:
		var server := _server(String(adv.universe))
		var err := server.mj_load_adventure(String(adv.id))
		var map: Dictionary = server.maps.get(server.active_map, {})
		var drafts: Array = server.quests.filter(func(q): return String(q.status) == "draft")
		var npcs: Array = (map.get("tokens", []) as Array).filter(func(t): return String(t.kind) == "npc" and String(t.char_id) != "")
		var chests: Array = (map.get("tokens", []) as Array).filter(func(t): return String(t.get("loot", "")) != "")
		var ok: bool = err == "" and drafts.size() == (adv.quests as Array).size() and npcs.size() >= (adv.npcs as Array).size() and chests.size() == (adv.chests as Array).size()
		_expect(ok, "%s : carte, %d PNJ, %d quêtes en brouillon, %d coffres (%s)" % [adv.name, npcs.size(), drafts.size(), chests.size(), err])
	# Scènes et coffres, sur « Les cloches de Valombre ».
	var s := _server("fantasy")
	var p := _add_player(s, "Ana")
	s._cmd_char_create(p, {"class_id": "guerrier", "species_id": "nain", "alloc": Rules.get_class_def(s.content, "guerrier").recommended, "choices": [0], "identity": {"name": "Ana"}})
	s.mj_load_adventure("cloches_valombre")
	s.mj_start_game("exploration")
	s.mj_play_scene(1)
	_expect(s.quests.any(func(q): return String(q.title) == "Les cloches de minuit" and String(q.status) == "active"), "scène « Minuit » : la quête principale est donnée")
	_expect(s.messages.any(func(m): return String(m.get("kind", "")) == Protocol.KIND_NARRATION and String(m.text).contains("treizième")), "la narration de la scène est envoyée aux joueurs")
	var map: Dictionary = s.maps[s.active_map]
	var chest: Dictionary = (map.tokens as Array).filter(func(t): return String(t.get("loot", "")) != "" and not t.hidden)[0]
	var pawn := MapData.token(map, "pawn_" + p.id)
	_expect(s._cmd_open(p, {"token": chest.id}) != "", "trop loin : il faut s'approcher du coffre")
	var cell := MapData.free_cell_near(map, int(chest.x) + 1, int(chest.y))
	pawn.x = cell.x
	pawn.y = cell.y
	var c: Dictionary = s.characters[p.id]
	var before_items: int = (c.inventory as Array).size()
	var before_gold := int(c.gold)
	_expect(s._cmd_open(p, {"token": chest.id}) == "" and ((c.inventory as Array).size() > before_items or int(c.gold) > before_gold), "le coffre ouvert remplit le sac de celui qui l'ouvre")
	_expect(s._cmd_open(p, {"token": chest.id}) != "", "un coffre ne s'ouvre qu'une fois")
	s.mj_play_scene(3)
	_expect(s.phase.type != "combat" and not (map.tokens as Array).any(func(t): return String(t.kind) == "monster" and t.hidden), "scène « La crypte » : monstres révélés, ils attaqueront ceux qui approchent (pas de combat général)")


func _test_map_tools() -> void:
	print("\n— Création de cartes")
	var s := _server()
	var all_ok := true
	for kind in MapGen.KINDS:
		for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
			var m := s.mj_generate_map(kind, "moyenne", "", seed_value)
			var valid := String(m.cells).length() == int(m.w) * int(m.h)
			for ch in String(m.cells):
				if not MapData.TERRAINS.has(ch):
					valid = false
					break
			if not valid or not MapData.passable(m, int(m.spawn.x), int(m.spawn.y)):
				all_ok = false
				print("    carte « %s » invalide" % kind)
	_expect(all_ok, "6 types de cartes générés, terrains valides, départ praticable")
	var m := s.mj_create_map("Test", 10, 8)
	s.mj_fill(m.id, 0, 0, "s")
	_expect(String(m.cells) == "s".repeat(80), "Remplir : toute la zone d'un même terrain")
	s.mj_paint_rect(m.id, Vector2i(2, 2), Vector2i(6, 5), "d", true)
	_expect(MapData.cell(m, 2, 2) == "#" and MapData.cell(m, 4, 3) == "d", "Pièce : murs autour, sol à l'intérieur")
	s.mj_undo(m.id)
	_expect(MapData.cell(m, 2, 2) == "s" and String(m.cells) == "s".repeat(80), "Annuler : la pièce disparaît")


func _test_encounters() -> void:
	print("\n— Combats locaux, monstres agressifs, quêtes automatiques")
	var s := _server()
	var a := _add_player(s, "Aria")
	var b := _add_player(s, "Bram")
	s._cmd_char_create(a, {"class_id": "guerrier", "alloc": Rules.get_class_def(s.content, "guerrier").recommended, "choices": [0], "identity": {"name": "Aria"}})
	s._cmd_char_create(b, {"class_id": "mage", "alloc": Rules.get_class_def(s.content, "mage").recommended, "choices": [0], "identity": {"name": "Bram"}})
	var m := s.mj_create_map("Plaine", 44, 20)
	s.mj_set_active_map(m.id)
	s.mj_start_game("libre")
	var map: Dictionary = s.maps[s.active_map]
	var pa := MapData.token(map, "pawn_" + a.id)
	var pb := MapData.token(map, "pawn_" + b.id)
	pa.x = 5
	pa.y = 10
	pb.x = 34
	pb.y = 10
	var q := s.mj_quest_save({"title": "Chasse", "kind": "side", "assigned": [a.id], "objectives": [{"text": "Vaincre 2 loups", "kind": "kill", "target": "loup", "count": 2}],
		"rewards": {"xp": 50}, "give": true})
	_expect(q.auto, "quête avec objectif automatique : fin automatique activée")
	var w1 := s.mj_spawn_monster("loup", 12, 10, false)
	var w2 := s.mj_spawn_monster("loup", 13, 11, false)
	_expect(s.encounters.is_empty(), "rien ne se passe tant que personne n'entre dans le périmètre")
	_expect(s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 6, "y": 10}) == "" and s.encounters.is_empty(), "déplacement libre hors du périmètre (5 cases pour un loup)")
	_expect(s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 30, "y": 10}) != "", "déplacement libre limité (2 × vitesse)")
	s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 9, "y": 10})
	var enc := s.encounter_of(pa.id)
	_expect(not enc.is_empty() and (enc.order as Array).has(w1.id) and (enc.order as Array).has(w2.id), "entrer dans le périmètre : les loups attaquent (combat local)")
	_expect(s.encounter_of(pb.id).is_empty() and String(s.phase.type) == "libre", "l'autre joueur n'est pas concerné")
	_expect(String(s.phase_view_for_player(a.id).type) == "combat" and String(s.phase_view_for_player(b.id).type) == "libre", "chacun voit sa propre phase")
	_expect(s._cmd_pawn_move(b, {"map_id": m.id, "token_id": pb.id, "x": 36, "y": 10}) == "", "l'autre joueur continue d'explorer librement")
	_expect(s.combat.side(MapData.token(map, s._with(enc, s._current_token))) != "players", "embuscade : les monstres agissent en premier")
	var guard := 0
	while s._with(enc, s._current_token) != pa.id and guard < 20 and s.encounters.has(enc.id):
		s.tick(2.5)
		guard += 1
	_expect(s._with(enc, s._current_token) == pa.id, "les monstres jouent seuls, puis la main revient au joueur (%d étapes)" % guard)
	var xp_b := int(s.characters[b.id].xp)
	var spots := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var k := 0
	for w in [w1, w2]:
		w.hp = 1
		w.x = -50
		w.y = -50
	for w in [w1, w2]:
		while not MapData.token_at(map, int(pa.x) + spots[k].x, int(pa.y) + spots[k].y).is_empty():
			k += 1
		w.x = int(pa.x) + spots[k].x
		w.y = int(pa.y) + spots[k].y
		k += 1
	guard = 0
	while s.encounters.has(enc.id) and guard < 40:
		var cur: String = s._with(enc, s._current_token)
		if cur == pa.id:
			enc.ap = 2
			var foe := ""
			for id in enc.order:
				var t := MapData.token(map, String(id))
				if not t.is_empty() and String(t.kind) == "monster" and not s.combat.is_ko(t):
					foe = String(id)
			s._cmd_turn(a, {"action": "quick", "target": foe})
		s.tick(2.5)
		guard += 1
	_expect(not s.encounters.has(enc.id) and MapData.token(map, w1.id).is_empty() and MapData.token(map, w2.id).is_empty(), "victoire : combat terminé, loups retirés")
	_expect(int(s.characters[b.id].xp) == xp_b and int(s.characters[a.id].xp) > 0, "XP pour les participants seulement")
	_expect(String(s._quest(q.id).status) == "done", "quête « 2 loups » terminée toute seule")
	# Un joueur proche rejoint le combat d'un autre.
	var w3 := s.mj_spawn_monster("loup", 39, 10, true)
	s.mj_reveal_monsters()
	s.tick(0.6)
	var enc2 := s.encounter_of(pb.id)
	_expect(not enc2.is_empty() and s.encounter_of(pa.id).is_empty(), "un monstre révélé attaque le joueur à portée")
	pa.x = 35
	pa.y = 12
	s._check_join(pa)
	_expect(s.encounter_of(pa.id) == enc2, "un allié qui arrive rejoint le combat")
	# Fuite.
	guard = 0
	while not s.encounter_of(pb.id).is_empty() and guard < 25:
		enc2.turn = (enc2.order as Array).find(pb.id)
		enc2.ap = 2
		s._cmd_turn(b, {"action": "flee"})
		guard += 1
	_expect(s.encounter_of(pb.id).is_empty() and s.encounter_of(pa.id) == enc2, "fuir : on quitte le combat, l'allié reste")
	s.mj_encounter_end(enc2.id)
	# Engager un combat soi-même.
	var bear := s.mj_spawn_monster("ours", int(pa.x) - 3, int(pa.y), false)
	bear.calm_until = Time.get_unix_time_from_system() + 100.0
	_expect(s._cmd_turn(a, {"action": "engage", "target": bear.id}) == "", "attaquer un monstre : combat engagé")
	var enc3 := s.encounter_of(pa.id)
	_expect(not enc3.is_empty() and s._with(enc3, s._current_token) == pa.id, "celui qui engage agit en premier")
	s.mj_encounter_end(enc3.id)
	# PNJ : quête proposée, acceptée sur place, objectifs automatiques.
	var dorn := s.mj_add_token(s.active_map, {"kind": "npc", "name": "Dorn", "x": int(pb.x) + 1, "y": int(pb.y)})
	var q2 := s.mj_quest_save({"title": "Le minerai", "kind": "side", "giver": "Dorn", "objectives": [{"text": "Parler à Dorn", "kind": "talk", "target": "Dorn"},
		{"text": "Avoir une potion", "kind": "item", "target": "potion_soin", "count": 1}, {"text": "Aller au puits", "kind": "reach", "x": 20, "y": 3, "radius": 1}], "rewards": {"xp": 30}})
	_expect(s.quests_for(b.id).any(func(x): return x.id == q2.id and x.status == "offer"), "le PNJ propose sa quête au joueur")
	_expect(s._cmd_quest_accept(b, {"quest": q2.id}) == "" and s._quest(q2.id).assigned == [b.id], "quête secondaire acceptée : personnelle")
	var objs: Array = s._quest(q2.id).objectives
	_expect(objs[0].done and objs[1].done and not objs[2].done, "« parler » et « obtenir » cochés automatiquement")
	pb.x = 20
	pb.y = 4
	s._after_move(pb)
	_expect(String(s._quest(q2.id).status) == "done", "lieu atteint : quête terminée et récompensée seule")


func _test_checks() -> void:
	print("\n— Épreuves automatiques (action → jet → conséquences)")
	_expect(Checks.detect("J'escalade le mur du manoir") == "athletisme", "« J'escalade » → Athlétisme")
	_expect(Checks.detect("Je fouille le bureau du maire") == "fouille", "« Je fouille » → Fouille")
	_expect(Checks.detect("Je tente de convaincre le garde") == "persuasion", "« convaincre » → Persuasion")
	_expect(Checks.detect("Je chante une chanson") == "", "phrase sans compétence → le MJ décide")
	var s := _server()
	var a := _add_player(s, "Aria")
	var b := _add_player(s, "Bram")
	s._cmd_char_create(a, {"class_id": "guerrier", "alloc": Rules.get_class_def(s.content, "guerrier").recommended, "choices": [0], "identity": {"name": "Aria"}})
	s._cmd_char_create(b, {"class_id": "pretre" if not Rules.get_class_def(s.content, "pretre").is_empty() else "mage", "alloc": Rules.get_class_def(s.content, "mage").recommended, "choices": [0], "identity": {"name": "Bram"}})
	var m := s.mj_create_map("Plaine", 50, 24)
	s.mj_set_active_map(m.id)
	s.mj_start_game("libre")
	var map: Dictionary = s.maps[s.active_map]
	var pa := MapData.token(map, "pawn_" + a.id)
	var pb := MapData.token(map, "pawn_" + b.id)
	pa.x = 5
	pa.y = 10
	pb.x = 6
	pb.y = 10
	var ca: Dictionary = s.characters[a.id]
	# Fouille réussie : objets ou or dans le sac, résultat publié avec le jet.
	s.checks.forced_d20 = 18
	var gold0 := int(ca.gold)
	var bag0 := (ca.inventory as Array).size()
	_expect(s._cmd_action(a, {"to": Protocol.TO_ALL, "text": "Je fouille les buissons", "skill": "auto"}) == "", "action « Je fouille » : épreuve lancée")
	var last: Dictionary = s.messages[-1]
	_expect(last.get("check", {}).get("skill", "") == "fouille" and last.status == Protocol.ACTION_RESOLVED, "résultat immédiat (Fouille, résolue)")
	_expect(int(last.check.total) == 18 + int(last.check.bonus) and int(last.check.dc) > 0, "jet : d20 + caractéristique contre DD")
	_expect(int(ca.gold) > gold0 or (ca.inventory as Array).size() > bag0 or str(last.lines).contains("trouve") or str(last.lines).contains("Rien"), "conséquence appliquée : trouvaille dans le sac")
	_expect(s._cmd_check(a, {"skill": "fouille"}) != "", "même épreuve aussitôt : délai")
	s.checks._cooldown.clear()
	s._cmd_check(a, {"skill": "fouille"})
	_expect(str(s.messages[-1].lines).contains("déjà été fouillé"), "un endroit ne se fouille qu'une fois")
	# Chute : échec → dégâts.
	s.checks.forced_d20 = 1
	var hp0 := int(pa.hp)
	s._cmd_action(a, {"to": Protocol.TO_ALL, "text": "J'escalade la falaise", "skill": "auto"})
	_expect(int(pa.hp) < hp0 and String(s.messages[-1].check.outcome) == "fumble", "escalade ratée (1 naturel) : chute, PV perdus")
	# Perception : monstre caché repéré.
	s.checks.forced_d20 = 17
	var hidden := s.mj_spawn_monster("loup", 12, 10, true)
	s._cmd_check(a, {"skill": "perception"})
	_expect(not hidden.get("hidden", true), "Observer : le loup caché est repéré")
	_expect(s.encounters.is_empty(), "repéré à temps : le loup n'attaque pas tout de suite")
	map.tokens.erase(hidden)
	# Coffre verrouillé : crochetage.
	var chest := s.mj_add_token(m.id, {"kind": "object", "name": "Coffre", "x": 5, "y": 11})
	chest.loot = "coffre"
	chest.lock = 15
	s.checks.forced_d20 = 3
	s._cmd_check(a, {"skill": "crochetage", "target": chest.id})
	_expect(chest.has("loot"), "crochetage raté : le coffre reste fermé")
	s.checks._cooldown.clear()
	s.checks.forced_d20 = 19
	s._cmd_check(a, {"skill": "crochetage", "target": chest.id})
	_expect(not chest.has("loot"), "crochetage réussi : le coffre s'ouvre")
	# Intimider un monstre : réussi, il s'enfuit ; raté, il attaque.
	var w := s.mj_spawn_monster("loup", 9, 12, false)
	w.calm_until = SessionServer._clock() + 60.0
	s.checks.forced_d20 = 20
	s._cmd_check(a, {"skill": "intimidation", "target": w.id})
	_expect(MapData.token(map, w.id).is_empty(), "intimidation réussie : le loup s'enfuit")
	var w2 := s.mj_spawn_monster("loup", 9, 12, false)
	w2.calm_until = SessionServer._clock() + 60.0
	s.checks._cooldown.clear()
	s.checks.forced_d20 = 1
	s._cmd_check(a, {"skill": "intimidation", "target": w2.id})
	_expect(not s.encounter_of(pa.id).is_empty(), "intimidation ratée : le loup attaque (combat local)")
	var enc := s.encounter_of(pa.id)
	if not enc.is_empty() and s._with(enc, s._current_token) != pa.id:
		_expect(s._cmd_check(a, {"skill": "perception"}) != "", "en combat : pas d'épreuve hors de son tour")
	if not enc.is_empty():
		s.mj_encounter_end(String(enc.id))
	map.tokens.erase(w2)
	# Premiers soins sur un allié voisin, une fois par minute.
	s.checks.forced_d20 = 15
	s._damage_token(pa, 10)
	var hp1 := int(pa.hp)
	_expect(s._cmd_check(b, {"skill": "soins", "target": pa.id}) == "" and int(pa.hp) > hp1, "premiers soins : Aria récupère des PV")
	s.checks._cooldown.clear()
	hp1 = int(pa.hp)
	s._cmd_check(b, {"skill": "soins", "target": pa.id})
	_expect(int(pa.hp) == hp1, "pas deux soins de suite sur le même blessé")
	# Discrétion : invisible aux monstres un moment.
	s.checks.forced_d20 = 16
	s._cmd_check(a, {"skill": "discretion"})
	var w3 := s.mj_spawn_monster("loup", 9, 10, false)
	s._after_move(pa)
	_expect(s.encounter_of(pa.id).is_empty(), "caché : le loup ne voit pas Aria")
	map.tokens.erase(w3)
	# Action sans compétence : le MJ la tranche en un clic, puis ajoute une conséquence.
	s._cmd_action(a, {"to": Protocol.TO_ALL, "text": "Je chante une chanson paillarde", "skill": "auto"})
	var act: Dictionary = s.messages[-1]
	_expect(act.status == Protocol.ACTION_PENDING and not act.has("check"), "action libre sans compétence : en attente du MJ")
	s.checks.forced_d20 = 15
	_expect(s.mj_check_action(String(act.id), "persuasion", 10) == "" and act.status == Protocol.ACTION_RESOLVED and act.has("check"), "MJ : épreuve en un clic (Persuasion, DD 10)")
	var hp2 := int(pa.hp)
	_expect(s.mj_action_consequence(String(act.id), "dmg_small") == "" and int(pa.hp) < hp2, "MJ : conséquence en un clic (−1d4 PV)")
	# Jet demandé par le MJ avec une compétence : le joueur lance, tout se résout.
	s.mj_request_roll(a.id, "d20", "", 12, true, "endurance")
	var req: Dictionary = s.messages[-1]
	_expect(s._cmd_roll_answer(a, {"message_id": req.id}) == "" and req.status == "done" and req.has("check"), "jet demandé (Endurance) : résolu avec la caractéristique")
	s.checks.forced_d20 = 0


func _test_town() -> void:
	print("\n— Bâtiments prêts, habitants à rôle, quêtes secondaires prêtes")
	for id in Prefabs.LIST:
		var rows: Array = Prefabs.LIST[id].rows
		_expect(rows.all(func(r): return String(r).length() == String(rows[0]).length()), "plan régulier : %s" % id)
	for tid in QuestLibrary.TEMPLATES:
		var built := QuestLibrary.build(tid, "Berthe, aubergiste", "Gérald, garde")
		_expect(not built.is_empty() and not str(built).contains("{giver}") and not str(built).contains("{other}") and not str(built).contains("{place}"), "modèle de quête complet : %s" % tid)
	var s := _server()
	var a := _add_player(s, "Aria")
	s._cmd_char_create(a, {"class_id": "guerrier", "alloc": Rules.get_class_def(s.content, "guerrier").recommended, "choices": [0], "identity": {"name": "Aria"}})
	var m := s.mj_create_map("Bourg", 60, 40)
	s.mj_set_active_map(m.id)
	s.mj_start_game("libre")
	var map: Dictionary = s.maps[s.active_map]
	var corner := Prefabs.anchor(map, "auberge", 20, 12)
	var placed := s.mj_place_prefab(m.id, "auberge", 20, 12)
	var npc: Dictionary = placed.get("npc", {})
	_expect(MapData.cell(map, corner.x, corner.y) == "#" and not npc.is_empty() and String(npc.get("role", "")) == "aubergiste", "auberge posée : murs, et son aubergiste")
	_expect(map.labels.any(func(l): return l.text == "Auberge"), "nom du bâtiment sur la carte")
	_expect(s.quests.any(func(q): return q.giver == npc.name and q.status == "draft" and q.get("offer", false)), "l'aubergiste a déjà une quête à proposer")
	_expect(s.mj_undo(m.id) and MapData.cell(map, corner.x, corner.y) == ".", "bâtiment annulable")
	s.mj_place_prefab(m.id, "forge", 30, 20)
	var garde := s.mj_place_role_npc(m.id, "herboriste", 10, 30)
	_expect(String(garde.get("role", "")) == "herboriste", "habitant à rôle placé seul")
	# On parle au PNJ : quête prête, on l'accepte, les cibles apparaissent, la quête se termine en revenant.
	var pa := MapData.token(map, "pawn_" + a.id)
	pa.x = int(garde.x) + 1
	pa.y = int(garde.y)
	_expect(s._cmd_talk(a, {"token": garde.id}) == "", "parler à l'herboriste")
	var offers := s.quests_for(a.id).filter(func(q): return q.status == "offer" and q.giver == garde.name)
	_expect(not offers.is_empty(), "il propose une quête dès qu'on lui parle (%s)" % (offers[0].title if not offers.is_empty() else "-"))
	var qid := String(offers[0].id) if not offers.is_empty() else ""
	var tokens_before := (map.tokens as Array).size()
	_expect(s._cmd_quest_accept(a, {"quest": qid}) == "" and s._quest(qid).status == "active", "quête acceptée")
	var q := s._quest(qid)
	var tpl: Dictionary = QuestLibrary.TEMPLATES[q.template]
	_expect(not tpl.has("spawn") and not tpl.has("pickups") or (map.tokens as Array).size() > tokens_before, "à l'acceptation, les cibles apparaissent sur la carte")
	# Résoudre les objectifs comme le ferait le joueur.
	var guard := 0
	while q.status == "active" and guard < 30:
		guard += 1
		for o in q.objectives:
			if o.get("done", false):
				continue
			match String(o.kind):
				"kill":
					for t in (map.tokens as Array).duplicate():
						if String(t.get("quest", "")) == qid and String(t.kind) == "monster":
							s.combat._on_defeated(t, pa)
							(map.tokens as Array).erase(t)
				"item":
					var picked := false
					for t in (map.tokens as Array).duplicate():
						if t.get("pickup", false) and String(t.get("quest", "")) == qid:
							s.open_chest(String(t.id), a.id)
							picked = true
					if not picked:
						s.mj_give_item(a.id, String(o.target), int(o.count), false)
				"reach":
					pa.x = int(o.x)
					pa.y = int(o.y)
					s._after_move(pa)
				"talk":
					var who := String(o.target)
					for t in map.tokens:
						if String(t.name) == who:
							pa.x = int(t.x) + 1
							pa.y = int(t.y)
							s._cmd_talk(a, {"token": t.id})
			break
	_expect(q.status == "done", "quête prête menée au bout : terminée automatiquement (%s)" % q.title)
	var leftover := (s.characters[a.id].inventory as Array).filter(func(it): return QuestLibrary.ITEMS.has(String(it.get("item_id", ""))))
	_expect(leftover.is_empty() or not tpl.get("return", false), "objets de quête remis au PNJ")
	_expect(s._cmd_talk(a, {"token": garde.id}) == "" and s.quests.filter(func(x): return x.giver == garde.name).size() >= 2, "en lui reparlant, il propose une nouvelle quête")

	# Cartes générées : villages et villes avec leurs bâtiments et habitants, accessibles à pied.
	for kind in ["village", "ville", "foret"]:
		for size in ["grande", "immense"]:
			for seed_value in [3, 11]:
				var gm := s.mj_generate_map(kind, size, "", seed_value)
				var npcs := (gm.tokens as Array).filter(func(t): return String(t.get("role", "")) != "")
				var reach := _reachable(gm, Vector2i(int(gm.spawn.x), int(gm.spawn.y)))
				var stuck := npcs.filter(func(t): return not reach.has(Vector2i(int(t.x), int(t.y))))
				if kind != "foret":
					_expect(npcs.size() >= (4 if size == "grande" else 8), "%s %s (graine %d) : %d habitants" % [kind, size, seed_value, npcs.size()])
				_expect(stuck.is_empty(), "%s %s (graine %d) : chaque habitant est accessible à pied (%d coincés)" % [kind, size, seed_value, stuck.size()])
	_expect(MapGen.SIZES.immense.x >= 100, "taille immense disponible (100 × 68)")
	# Décor pixel art : posé par les bâtiments, effacé en repeignant, rétabli par « Annuler ».
	var dm := s.mj_create_map("Décor", 30, 20)
	var dmap: Dictionary = s.maps[dm.id]
	s.mj_place_prefab(dm.id, "auberge", 10, 8, false)
	var tables := (dmap.get("decor", {}) as Dictionary).values().filter(func(v): return v == "table")
	_expect(not tables.is_empty(), "auberge : tables posées dans le décor (%d)" % tables.size())
	var key: String = (dmap.decor as Dictionary).keys()[0]
	var kx := int(key.get_slice(",", 0))
	var ky := int(key.get_slice(",", 1))
	s.mj_snapshot(dm.id)
	MapData.set_cell(dmap, kx, ky, ".")
	_expect(MapData.decor_at(dmap, kx, ky) == "", "repeindre une case enlève son décor")
	s.mj_undo(dm.id)
	_expect(MapData.decor_at(dmap, kx, ky) != "", "« Annuler » rétablit le décor")
	_expect(MapData.view_for_player(dmap).get("decor", {}).size() == dmap.decor.size(), "le décor est envoyé aux joueurs")
	s._refresh_sprites(s.maps[s.active_map])
	var sprites := (s.maps[s.active_map].tokens as Array).map(func(t): return String(t.get("sprite", "")))
	_expect(sprites.has("units/guerrier") and sprites.any(func(x): return x.begins_with("units/") and x != "units/guerrier"), "pions : personnage de classe et habitants dessinés en pixel art")
	for sp in sprites:
		_expect(ResourceLoader.exists("res://assets/sprites/%s.png" % sp), "sprite présent : %s" % sp)


## Cases atteignables à pied depuis une case (8 directions, comme les déplacements).
func _reachable(map: Dictionary, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := p + Vector2i(dx, dy)
				if not seen.has(n) and MapData.in_bounds(map, n.x, n.y) and MapData.passable(map, n.x, n.y):
					seen[n] = true
					queue.append(n)
	return seen


func _test_collisions() -> void:
	print("\n— Collisions : murs, meubles, eau")
	var s := _server()
	var a := _add_player(s, "Aria")
	var alloc: Dictionary = Rules.get_class_def(s.content, "guerrier").recommended.duplicate()
	s._cmd_char_create(a, {"class_id": "guerrier", "alloc": alloc, "choices": [0], "identity": {"name": "Aria"}})
	var m := s.mj_create_map("Murs", 30, 20)
	s.mj_set_active_map(m.id)
	s.mj_start_game("libre")
	var map: Dictionary = s.maps[s.active_map]
	var pa := MapData.token(map, "pawn_" + a.id)
	pa.x = 5
	pa.y = 10
	# Mur vertical de y = 0 à 18 en x = 8 : une seule ouverture tout en bas.
	for y in 19:
		MapData.set_cell(map, 8, y, "#")
	_expect(s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 8, "y": 10}) != "", "on ne marche pas sur un mur")
	var err := s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 10, "y": 10})
	_expect(err != "" and int(pa.x) == 5, "le mur ne se traverse pas (chemin trop long) : %s" % err)
	MapData.set_cell(map, 8, 11, ".")
	_expect(s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 10, "y": 10}) == "" and int(pa.x) == 10, "par une ouverture, on passe")
	_expect(MapData.path(map, Vector2i(7, 10), Vector2i(9, 12), 10).all(func(p): return MapData.walkable(map, p.x, p.y)), "le chemin ne passe que par des cases praticables")
	# Coins de mur : pas de passage en diagonale entre deux murs.
	var corner := MapData.blank("Coin", 5, 5)
	MapData.set_cell(corner, 1, 0, "#")
	MapData.set_cell(corner, 0, 1, "#")
	_expect(not MapData.reach(corner, Vector2i(0, 0), 3).has(Vector2i(1, 1)), "on ne se glisse pas entre deux coins de mur")
	# Meubles et décors bloquants.
	MapData.set_cell(map, 12, 10, "t")
	_expect(s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 12, "y": 10}) != "", "on ne marche pas sur une table")
	MapData.set_decor(map, 13, 10, "barrel")
	_expect(not MapData.passable(map, 13, 10), "un tonneau bloque le passage")
	MapData.set_decor(map, 13, 10, "rug")
	_expect(MapData.passable(map, 13, 10), "un tapis se traverse")
	# Eau : peu profonde = nage selon la Dextérité ; profonde = jamais.
	for y in 20:
		MapData.set_cell(map, 15, y, "w")
	MapData.set_cell(map, 16, 10, "W")
	pa.x = 14
	pa.y = 10
	s.content.rules.swim_dex = 99
	_expect(not s.can_swim(pa) and s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 15, "y": 10}) != "", "sans savoir nager, l'eau bloque")
	_expect(s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 17, "y": 10}) != "" and int(pa.x) == 14, "pas de traversée de la rivière sans nager")
	s.content.rules.swim_dex = 1
	_expect(s.can_swim(pa) and s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 15, "y": 10}) == "", "avec assez de Dextérité, on nage dans l'eau peu profonde")
	_expect(s._cmd_pawn_move(a, {"map_id": m.id, "token_id": pa.id, "x": 16, "y": 10}) != "", "l'eau profonde reste infranchissable")
	s.content.rules.swim_dex = 6
	# Pinceau de décor.
	_expect(s.mj_set_decor(m.id, 20, 5, "tree_autumn") and not MapData.passable(map, 20, 5), "pinceau de décor : un arbre posé bloque le passage")
	_expect(s.mj_set_decor(m.id, 21, 5, "flowers_1") and MapData.passable(map, 21, 5), "des fleurs se traversent")
	_expect(s.mj_set_decor(m.id, 20, 5, "") and MapData.passable(map, 20, 5), "gomme de décor")
	_expect(not s.mj_set_decor(m.id, 22, 5, "n_existe_pas"), "un décor inconnu est refusé")
	_expect(Sprites.names("props").has("weapon_rack") and Sprites.names("nature").has("pine_snow"), "nouveaux décors disponibles dans la palette")


func _test_monk_necro() -> void:
	print("\n— Moine (insensible à la magie ciblée) et Nécromancien")
	var s := _server()
	_expect(not Rules.get_class_def(s.content, "moine").is_empty() and not Rules.get_class_def(s.content, "necromancien").is_empty(), "classes Moine et Nécromancien disponibles")
	var players: Array = []
	for spec in [["Mo", "moine"], ["Soi", "soigneur"], ["Ne", "necromancien"]]:
		var p := _add_player(s, spec[0])
		s._cmd_char_create(p, {"class_id": spec[1], "alloc": Rules.get_class_def(s.content, spec[1]).recommended, "choices": [0], "identity": {"name": spec[0]}})
		players.append(p)
	var m := s.mj_create_map("Arène", 20, 12)
	s.mj_set_active_map(m.id)
	s.mj_start_game("libre")
	var map: Dictionary = s.maps[s.active_map]
	var tok := func(p): return MapData.token(map, "pawn_" + p.id)
	var monk: Dictionary = tok.call(players[0])
	var healer: Dictionary = tok.call(players[1])
	var necro: Dictionary = tok.call(players[2])
	monk.x = 5
	monk.y = 5
	healer.x = 6
	healer.y = 5
	necro.x = 4
	necro.y = 5
	_expect(s.combat.has_trait(monk, "anti_magie"), "le passif du Moine porte la particularité « anti_magie »")
	s.mj_set_phase("combat")
	var heal: Dictionary = Content.get_entry(s.content, "abilities", "soin")
	s.phase.ap = 9
	s.characters[players[1].id].res = 50
	s._damage_token(monk, 8)
	s._damage_token(necro, 4)
	var hp0 := int(monk.hp)
	var err := s.combat.use_ability(healer, heal, monk)
	_expect(err != "" and int(monk.hp) == hp0, "un soin magique ne peut pas viser le Moine : %s" % err)
	_expect(s.combat.use_ability(healer, heal, necro) == "", "le même soin vise un autre allié sans problème")
	var bandage: Dictionary = Content.get_entry(s.content, "abilities", "premiers_soins")
	_expect(s.combat.use_ability(healer, bandage, monk) == "" and int(monk.hp) > hp0, "des premiers soins (non magiques) le soignent")
	var bolt := {"name": "Boule test", "target": "enemy", "range": 6, "ap": 1, "element": "magique", "roll": "none", "effects": [{"type": "damage", "dice": "1d6"}]}
	var wolf := s.mj_spawn_monster("loup", 9, 5, false)
	_expect(s.combat.use_ability(wolf, bolt, monk) != "", "un sort ennemi ciblé ne peut pas viser le Moine")
	var area := {"name": "Zone test", "target": "area_enemy", "range": 6, "radius": 1, "ap": 1, "element": "magique", "roll": "none", "effects": [{"type": "damage", "dice": "1d6", "bonus": 2}]}
	var hp1 := int(monk.hp)
	_expect(s.combat.use_ability(wolf, area, monk) == "" and int(monk.hp) < hp1, "une zone magique atteint le Moine")
	var punch := {"name": "Coup test", "target": "enemy", "range": 6, "ap": 1, "element": "physique", "roll": "none", "effects": [{"type": "damage", "dice": "1d4"}]}
	_expect(s.combat.use_ability(wolf, punch, monk) == "", "une attaque physique le vise normalement")
	var raise: Dictionary = Content.get_entry(s.content, "abilities", "lever_squelette")
	var before := (map.tokens as Array).size()
	s.characters[players[2].id].res = 20
	_expect(s.combat.use_ability(necro, raise, necro) == "" and (map.tokens as Array).size() == before + 1, "le Nécromancien relève un squelette")


func _test_alliances() -> void:
	print("\n— Alliances : monstres hostiles, neutres ou alliés")
	var s := _server()
	var a := _add_player(s, "Aria")
	s._cmd_char_create(a, {"class_id": "guerrier", "alloc": Rules.get_class_def(s.content, "guerrier").recommended, "choices": [0], "identity": {"name": "Aria"}})
	var m := s.mj_create_map("Plaine", 40, 20)
	s.mj_set_active_map(m.id)
	s.mj_start_game("libre")
	var map: Dictionary = s.maps[s.active_map]
	var pa := MapData.token(map, "pawn_" + a.id)
	pa.x = 5
	pa.y = 10
	var friend := s.mj_spawn_monster("loup", 7, 10, false)
	s.mj_update_token(m.id, friend.id, {"attitude": "allie"})
	var calm := s.mj_spawn_monster("ours", 5, 12, false)
	s.mj_update_token(m.id, calm.id, {"attitude": "neutre"})
	s._after_move(pa)
	s._scan_aggro()
	_expect(s.encounters.is_empty(), "un loup allié et un ours neutre n'attaquent pas")
	_expect(String(friend.disposition) == "players" and String(calm.disposition) == "neutral", "le camp est envoyé aux téléphones (socle vert / doré)")
	var foe := s.mj_spawn_monster("loup", 9, 10, false)
	s._after_move(pa)
	var enc := s.encounter_of(pa.id)
	_expect(not enc.is_empty() and (enc.order as Array).has(friend.id), "un monstre hostile attaque : le loup allié tout proche se bat aux côtés d'Aria")
	_expect(not (enc.order as Array).has(calm.id), "l'ours neutre reste en dehors du combat")
	if not enc.is_empty():
		s.mj_encounter_end(String(enc.id))
	map.tokens.erase(foe)
	calm.calm_until = 0.0
	_expect(s._cmd_turn(a, {"action": "engage", "target": calm.id}) == "" and s.combat.side(calm) == "enemies", "attaquer un neutre le rend hostile")
	var e2 := s.encounter_of(pa.id)
	if not e2.is_empty():
		s.mj_encounter_end(String(e2.id))
	_expect(s._cmd_turn(a, {"action": "engage", "target": friend.id}) != "", "on n'attaque pas un allié")
	var tame := s.mj_content_save("monsters", {"id": "loup_apprivoise", "name": "Loup apprivoisé", "attitude": "allie", "hp": 15})
	var t3 := s.mj_spawn_monster("loup_apprivoise", 20, 10, false)
	_expect(s.combat.side(t3) == "players", "l'attitude du modèle de monstre s'applique à tous ses pions")


func _test_keys() -> void:
	print("\n— Clés, portes et énigmes")
	var s := _server()
	var a := _add_player(s, "Aria")
	s._cmd_char_create(a, {"class_id": "guerrier", "alloc": Rules.get_class_def(s.content, "guerrier").recommended, "choices": [0], "identity": {"name": "Aria"}})
	var m := s.mj_create_map("Crypte", 30, 12)
	s.mj_set_active_map(m.id)
	s.mj_start_game("libre")
	var map: Dictionary = s.maps[s.active_map]
	var pa := MapData.token(map, "pawn_" + a.id)
	pa.x = 5
	pa.y = 5
	var key := s.mj_create_key("Clé de la crypte")
	_expect(not key.is_empty() and String(key.icon) == "key", "le MJ crée une clé")
	var chest := s.mj_add_token(m.id, {"kind": "object", "name": "Coffre scellé", "x": 6, "y": 5})
	chest.loot = "coffre"
	s.mj_update_token(m.id, chest.id, {"key": key.id, "consume_key": true})
	_expect(s._cmd_open(a, {"token": chest.id}).contains("Clé de la crypte") and chest.has("loot"), "sans la clé, le coffre reste fermé (et dit laquelle il faut)")
	# La clé est confiée à un monstre : on la récupère en le battant.
	var guard := s.mj_spawn_monster("squelette", 9, 5, false)
	s.mj_update_token(m.id, guard.id, {"carries": [key.id], "attitude": "neutre"})
	_expect(not MapData.view_for_player(map).tokens.any(func(t): return t.has("carries")), "les joueurs ne voient pas ce que garde un monstre")
	s.combat._on_defeated(guard, pa)
	var has_key := func(): return (s.characters[a.id].inventory as Array).any(func(it): return String(it.get("item_id", "")) == String(key.id))
	_expect(has_key.call(), "le monstre vaincu lâche la clé dans le sac du vainqueur")
	_expect(s._cmd_open(a, {"token": chest.id}) == "" and not chest.has("loot"), "avec la clé, le coffre s'ouvre")
	_expect(not has_key.call(), "la serrure a gardé la clé")
	# Porte à énigme.
	var door := s.mj_add_token(m.id, {"kind": "object", "name": "Porte du sphinx", "x": 4, "y": 5})
	s.mj_update_token(m.id, door.id, {"door": true, "riddle_q": "Qu'est-ce qui a des clés mais n'ouvre aucune porte ?", "riddle_a": "Le piano"})
	s._refresh_sprites(map)
	_expect(String(door.sprite) == "props/door" and not MapData.view_for_player(map).tokens.any(func(t): return t.has("riddle_a")), "porte dessinée ; la réponse reste secrète")
	_expect(not MapData.reach(map, Vector2i(5, 5), 1, true, s._move_blockers(map, pa)).has(Vector2i(4, 5)), "une porte fermée bloque le passage")
	_expect(s._cmd_open(a, {"token": door.id, "answer": "une harpe"}) != "", "mauvaise réponse : la porte reste fermée")
	_expect(s._cmd_open(a, {"token": door.id, "answer": "  PIANO "}) == "" and MapData.token(map, door.id).is_empty(), "bonne réponse (majuscules, article et espaces ignorés) : la porte s'ouvre")
	var hint := s.mj_place_item(m.id, String(key.id), 20, 5)
	_expect(not hint.is_empty() and hint.get("pickup", false), "le MJ peut aussi poser la clé par terre, à ramasser")


func _test_npc_control() -> void:
	print("\n— PNJ pilotés par le MJ")
	var s := _server()
	var a := _add_player(s, "Aria")
	var b := _add_player(s, "Bram")
	for p in [a, b]:
		s._cmd_char_create(p, {"class_id": "guerrier", "alloc": Rules.get_class_def(s.content, "guerrier").recommended, "choices": [0], "identity": {"name": p.name}})
	var m := s.mj_create_map("Taverne", 20, 12)
	s.mj_set_active_map(m.id)
	s.mj_start_game("libre")
	var map: Dictionary = s.maps[s.active_map]
	var npc := s.mj_add_token(m.id, {"kind": "npc", "name": "Gros Bill", "x": 6, "y": 5})
	_expect(s.mj_npc_say(npc.id, "Encore vous ? Payez d'abord.") and String(s.messages[-1].from_name) == "Gros Bill", "le MJ fait parler un PNJ (message à son nom)")
	_expect(s.mj_npc_say(npc.id, "Psst… la cave est piégée.", a.id) and String(s.messages[-1].to) == a.id, "aparté : un seul joueur l'entend")
	_expect(s.mj_npc_say(npc.id, "frappe du poing sur le comptoir.", Protocol.TO_ALL, true) and String(s.messages[-1].kind) == Protocol.KIND_NARRATION, "faire agir le PNJ (récit)")
	s.mj_set_npc_lines(m.id, npc.id, ["Bienvenue au Sanglier Rieur !", "", "On ne se bat pas ici."])
	_expect((npc.lines as Array).size() == 2, "répliques du PNJ enregistrées (lignes vides ignorées)")
	var q := s.mj_quest_save({"title": "La cave aux rats", "kind": "side", "objectives": [{"text": "Vider la cave"}], "rewards": {"xp": 20}})
	s.mj_quest_set_giver(String(q.id), "Gros Bill")
	var pa := MapData.token(map, "pawn_" + a.id)
	pa.x = 7
	pa.y = 5
	_expect(s._cmd_talk(a, {"token": npc.id}) == "" and s.quests_for(a.id).any(func(x): return x.id == q.id and x.status == "offer"), "la quête confiée au PNJ est proposée à qui lui parle")


func _test_nested_maps() -> void:
	print("\n— Cartes imbriquées : entrer dans une ville sans emmener tout le monde")
	var s := _server()
	var a := _add_player(s, "Aria")
	var b := _add_player(s, "Bram")
	for p in [a, b]:
		s._cmd_char_create(p, {"class_id": "guerrier", "alloc": Rules.get_class_def(s.content, "guerrier").recommended, "choices": [0], "identity": {"name": p.name}})
	var world := s.mj_create_map("Monde", 40, 20)
	var city := s.mj_generate_map("ville", "grande", "Valombre", 5)
	s.mj_set_active_map(world.id)
	s.mj_start_game("libre")
	var wmap: Dictionary = s.maps[world.id]
	var gate := s.mj_add_token(world.id, {"kind": "object", "name": "Pion", "x": 10, "y": 10})
	s.mj_link_maps(world.id, gate.id, city.id)
	_expect(String(gate.link) == city.id and String(gate.name).contains("Valombre"), "passage créé vers la ville")
	_expect((s.maps[city.id].tokens as Array).any(func(t): return String(t.get("link", "")) == world.id), "un passage de retour est créé dans la ville")
	var pa := MapData.token(wmap, "pawn_" + a.id)
	var pb := MapData.token(wmap, "pawn_" + b.id)
	pa.x = 11
	pa.y = 10
	pb.x = 30
	pb.y = 10
	_expect(s._dispatch(b, Protocol.CMD_ENTER, {"token": gate.id}) != "", "trop loin du passage : on ne peut pas entrer")
	_expect(s._on_map(s.map_of_player(a.id), func(): return s._dispatch(a, Protocol.CMD_ENTER, {"token": gate.id})) == "", "Aria entre dans la ville")
	_expect(s.map_of_player(a.id) == city.id and s.map_of_player(b.id) == world.id and s.active_map == world.id, "seule Aria change de carte ; Bram et la carte du groupe ne bougent pas")
	_expect(String(s._map_view(a.id).id) == city.id and String(s._map_view(b.id).id) == world.id, "chacun reçoit la carte où il se trouve")
	_expect(not (s._map_view(b.id).tokens as Array).any(func(t): return String(t.get("owner", "")) == a.id), "Bram ne voit plus le pion d'Aria sur la carte du monde")
	var ca := MapData.token(s.maps[city.id], "pawn_" + a.id)
	var dest := MapData.free_cell_near(s.maps[city.id], int(ca.x) + 2, int(ca.y))
	var err: String = s._on_map(city.id, func(): return s._cmd_pawn_move(a, {"map_id": city.id, "token_id": ca.id, "x": dest.x, "y": dest.y}))
	_expect(err == "" and int(ca.x) == dest.x, "Aria se déplace dans la ville (%s)" % err)
	_expect(s._cmd_pawn_move(b, {"map_id": world.id, "token_id": pb.id, "x": 31, "y": 10}) == "", "Bram continue d'explorer le monde")
	# Un monstre de la ville attaque Aria : le combat a lieu dans la ville.
	var wolf: Dictionary = s._on_map(city.id, func(): return s.mj_spawn_monster("loup", int(ca.x) + 2, int(ca.y), false))
	s._scan_aggro()
	var enc := s.encounter_of(String(ca.id))
	_expect(not enc.is_empty() and String(enc.map_id) == city.id, "un monstre de la ville attaque Aria : combat local dans la ville")
	var guard := 0
	while not enc.is_empty() and s.encounters.has(enc.id) and s._with(enc, s._current_token) != ca.id and guard < 10:
		s.tick(2.5)
		guard += 1
	_expect(s.encounters.has(enc.id), "le combat de la ville continue même si le groupe est sur une autre carte")
	s.mj_encounter_end(String(enc.id))
	(s.maps[city.id].tokens as Array).erase(wolf)
	var back: Dictionary = (s.maps[city.id].tokens as Array).filter(func(t): return String(t.get("link", "")) == world.id)[0]
	ca.x = int(back.x) + 1
	ca.y = int(back.y)
	if not MapData.passable(s.maps[city.id], int(ca.x), int(ca.y)):
		var c := MapData.free_cell_near(s.maps[city.id], int(back.x), int(back.y))
		ca.x = c.x
		ca.y = c.y
	_expect(s._on_map(city.id, func(): return s._dispatch(a, Protocol.CMD_ENTER, {"token": back.id})) == "" and s.map_of_player(a.id) == world.id, "Aria ressort par le passage de retour")
	_expect(not MapData.token(wmap, "pawn_" + a.id).is_empty(), "son pion réapparaît près de l'entrée du monde")
	s.mj_set_active_map(city.id)
	_expect(s.map_of_player(a.id) == city.id and s.map_of_player(b.id) == city.id, "« Montrer cette carte aux joueurs » ramène tout le monde au même endroit")


func _brick(group: Array, label: String) -> Dictionary:
	for b in group[2]:
		if String(b.label) == label:
			return b
	return {}


func _test_bricks() -> void:
	print("\n— Briques : capacités et passifs composés, capacités personnelles")
	var s := _server()
	# Composer une capacité : forme « zone à distance » + Feu + Étourdir.
	var a := {"name": "Pluie ardente", "effects": []}
	var fire := {}
	var stun := {}
	for g in BrickPalette.EFFECT_GROUPS:
		if fire.is_empty():
			fire = _brick(g, "Feu")
		if stun.is_empty():
			stun = _brick(g, "Étourdir")
	for b in [_brick(BrickPalette.SHAPES, "Zone à distance"), _brick(BrickPalette.COSTS, "Petit sort (3 mana)"), fire, stun]:
		_expect(not b.is_empty(), "brique trouvée : %s" % b.get("label", "?"))
		for k in b.get("fields", {}):
			a[k] = b.fields[k]
		a.effects.append_array((b.get("effects", []) as Array).duplicate(true))
	var clean := Content.sanitize_ability(a)
	_expect(clean.target == "area_enemy" and int(clean.radius) == 1 and int(clean.cost) == 3 and (clean.effects as Array).size() == 3, "les briques donnent une capacité valide (zone, coût, 3 effets)")
	# Chaque brique d'effet passe la validation sans rien perdre.
	var all_ok := true
	for g in BrickPalette.EFFECT_GROUPS:
		for b in g[2]:
			if Content.sanitize_effects(b.effects).size() != (b.effects as Array).size():
				all_ok = false
				print("    brique invalide : ", b.label)
	_expect(all_ok, "toutes les briques d'effet sont valides")
	for b in BrickPalette.EFFECT_GROUPS[0][2] + BrickPalette.EFFECT_GROUPS[2][2]:
		for e in b.effects:
			if String(e.get("type", "")) == "status":
				_expect(not Content.get_entry(s.content, "statuses", String(e.status)).is_empty(), "l'effet « %s » de la brique %s existe" % [e.status, b.label])
	# Capacité personnelle donnée à un seul personnage.
	var p := _add_player(s, "Kael")
	s._cmd_char_create(p, {"class_id": "guerrier", "alloc": Rules.get_class_def(s.content, "guerrier").recommended, "choices": [0], "identity": {"name": "Kael"}})
	var q := _add_player(s, "Lyra")
	s._cmd_char_create(q, {"class_id": "guerrier", "alloc": Rules.get_class_def(s.content, "guerrier").recommended, "choices": [0], "identity": {"name": "Lyra"}})
	var err := s.mj_personal_ability(p.id, clean)
	_expect(err == "", "capacité personnelle créée et apprise : %s" % err)
	var known: Array = (s.characters[p.id].abilities as Array).filter(func(x): return String(x.get("name", "")) == "Pluie ardente")
	_expect(known.size() == 1 and String(known[0].get("owner", "")) == "Kael", "Kael connaît « Pluie ardente » (marquée à son nom)")
	_expect((s.characters[q.id].abilities as Array).filter(func(x): return String(x.get("name", "")) == "Pluie ardente").is_empty(), "Lyra ne l'a pas")
	# Passif spécial : bonus permanent + particularité, en plus du passif de classe.
	var def0 := int(Rules.derived(s.characters[p.id], s.content).defense)
	err = s.mj_grant_passive(p.id, {"name": "Peau de pierre", "trigger": "always", "mods": {"defense": 2}, "traits": ["anti_magie"]})
	_expect(err == "", "passif spécial accordé : %s" % err)
	_expect(not (s.characters[p.id].passive as Dictionary).is_empty() and (s.characters[p.id].extra_passives as Array).size() == 1, "le passif de classe est conservé, le passif spécial s'ajoute")
	_expect(int(Rules.derived(s.characters[p.id], s.content).defense) == def0 + 2, "le bonus du passif spécial compte (+2 Défense)")
	var m := s.mj_create_map("Plaine", 16, 10)
	s.mj_set_active_map(m.id)
	s.mj_start_game("libre")
	var tk := MapData.token(s.maps[s.active_map], "pawn_" + p.id)
	_expect(s.combat.has_trait(tk, "anti_magie"), "la particularité du passif spécial est prise en compte en combat")
	_expect(s.mj_grant_passive(p.id, {"name": ""}) != "", "un passif sans nom est refusé")
	s.mj_remove_passive(p.id, 0)
	_expect((s.characters[p.id].extra_passives as Array).is_empty() and int(Rules.derived(s.characters[p.id], s.content).defense) == def0, "retirer le passif spécial annule son bonus")
	# Sauvegarde / relecture de la fiche : les passifs personnels survivent.
	s.mj_grant_passive(p.id, {"name": "Rage froide", "trigger": "on_damaged", "effects": [{"type": "stat", "stat": "Force", "amount": 2, "turns": 2, "on": "self"}]})
	var back := CharacterData.sanitize(s.characters[p.id].duplicate(true), s.characters[p.id])
	_expect((back.get("extra_passives", []) as Array).size() == 1 and String(back.extra_passives[0].trigger) == "on_damaged", "les passifs personnels sont gardés à la sauvegarde")
