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
