extends Node
## Pilote de captures : joue une petite scène réelle (hôte + joueur en réseau)
## puis photographie l'écran ou le panneau demandé.
## Arguments : --shot=menu|join|setup|host|player  --tab=<vue ou panneau>
##             --phase=none|exploration|combat  --map=<modèle>  --out=<png>
## Joueur : wizard1..wizard5, lobby, story, map, sheet, inventory, chest, journal, ability, help, levelup
## Hôte : table, story, combat, world, quests, create, chars, char, item_editor, quest_editor, ambush

const PORT := 17800

var shot := "menu"
var tab := ""
var map_template := "ile_test"
var out := "user://shot.png"
var phase := "combat"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.get_slice("=", 1)
		elif arg.begins_with("--tab="):
			tab = arg.get_slice("=", 1)
		elif arg.begins_with("--map="):
			map_template = arg.get_slice("=", 1)
		elif arg.begins_with("--phase="):
			phase = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
	match shot:
		"menu":
			App.goto(App.SCENE_MAIN_MENU)
		"join":
			App.goto(App.SCENE_JOIN)
		"setup":
			App.goto(App.SCENE_HOST)
		"host":
			await _host()
		"player":
			await _player()
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("capture : ", out)
	get_tree().quit()


func _host() -> void:
	Net.host({"name": "Légenders — Le test de la magie", "mj_name": "Le Conteur", "port": PORT, "max_players": 4, "universe": "legenders", "auto_accept": true})
	var server := Net.server
	for id in server.map_order:
		if server.maps[id].get("template", "") == map_template:
			server.mj_set_active_map(id)
	App.goto(App.SCENE_HOST)
	server.mj_narrate("Vous êtes téléportés au hasard sur l'île. Dix jours pour trouver le point de rendez-vous.", Protocol.TO_ALL, "Le test de survie")
	await get_tree().create_timer(4.0).timeout
	var map_id := server.active_map
	var player_ids: Array = server.players.keys()
	var pawn := MapData.token(server.maps[map_id], "pawn_" + String(player_ids[0])) if not player_ids.is_empty() else {}
	var px := int(pawn.get("x", 12))
	var py := int(pawn.get("y", 10))
	server.mj_spawn_monster("loup", px + 1, py, false)
	server.mj_spawn_monster("loup_alpha", px + 2, py + 1, false)
	server.mj_spawn_monster("bandit", px + 3, py - 1, true)
	server.mj_quest_save({"title": "Survivre dix jours", "kind": "main", "description": "Atteindre le point de rendez-vous avant la fin du test.",
		"objectives": [{"text": "Trouver de l'eau douce"}, {"text": "Rejoindre le pic central"}], "rewards": {"xp": 200, "gold": 50, "items": [{"item": "amulette_vie", "qty": 1}]}, "give": true})
	server.mj_quest_save({"title": "Le candidat disparu", "kind": "side", "objectives": [{"text": "Retrouver Mako"}], "rewards": {"xp": 80}, "give": true})
	server.add_loot(Content.item_instance(server.content, "lame_runique"), "Coffre ancien")
	server.add_loot(Content.item_instance(server.content, "potion_soin_sup", 2), "Coffre ancien")
	server.mj_music("poing_de_braise", true)
	for id in player_ids:
		server.mj_give_item(String(id), "bottes_vent", 1, false)
		server.mj_give_item(String(id), "livre_second_souffle", 1, false)
	if phase != "none":
		server.mj_start_game("exploration")
		if phase == "combat":
			server.mj_set_phase("combat")
			# Le joueur commence, pour montrer son panneau de tour.
			var pawns := player_ids.map(func(id): return "pawn_" + String(id))
			for i in server.phase.order.size():
				if pawns.has(server.phase.order[i]):
					server.phase.turn = i
					server._start_turn_loop()
					server._phase_changed()
					break
	if tab == "levelup":
		await get_tree().create_timer(2.0).timeout
		for id in server.players.keys():
			server.grant_xp(String(id), 120)
	await get_tree().create_timer(1.0).timeout
	var screen := get_tree().current_scene
	match tab:
		"story":
			screen._show("story")
		"combat", "world", "quests", "create", "chars", "net":
			screen._show(tab)
		"char":
			if not player_ids.is_empty():
				screen._open_char_tools(String(player_ids[0]))
		"item_editor":
			screen._open_content_editor("items", Content.get_entry(server.content, "items", "croc_vampirique"))
		"quest_editor":
			screen._open_quest_editor(server.quests[0])
		"ambush":
			screen._event_ambush()
	# Laisse le téléphone se photographier avant que l'hôte ne ferme.
	await get_tree().create_timer(4.0).timeout


## Débogage de mise en page : contrôles plus larges que l'écran.
func _report_wide(node: Node, limit: float) -> void:
	for child in node.get_children():
		if child is Control and child.get_combined_minimum_size().x > limit:
			print("LARGE ", child.get_path(), " ", child.get_class(), " ", child.get_combined_minimum_size())
		_report_wide(child, limit)


func _player() -> void:
	Net.joined.connect(func(): App.goto(App.SCENE_PLAYER))
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1", PORT, "Camille")
	await get_tree().create_timer(1.5).timeout
	var c := Net.client
	if c == null:
		return
	for i in 30:
		if c.is_accepted() and not c.content.is_empty():
			break
		await get_tree().create_timer(0.2).timeout
	var screen := get_tree().current_scene
	if tab.begins_with("wizard"):
		screen._open_wizard()
		var wizard: CreationWizard = screen._creation.get_child(0)
		wizard.class_id = "briseur"
		wizard.alloc = Rules.get_class_def(c.content, "briseur").recommended.duplicate()
		wizard.choices = [0]
		wizard.identity.name = "Shin"
		wizard.identity.portrait = {"face": 1, "skin": 2, "hair": 5, "hair_color": 4, "eyes": 1, "beard": 0, "mark": 1}
		wizard.step = int(tab.substr(6)) - 1
		wizard._show_step()
		await get_tree().create_timer(1.0).timeout
		if OS.get_cmdline_user_args().has("--debug-width"):
			_report_wide(get_tree().current_scene, get_viewport().get_visible_rect().size.x - 130)
		return
	c.create_character("briseur", Rules.get_class_def(c.content, "briseur").recommended, [0], {
		"name": "Shin", "species": "Humain", "appearance": "Cheveux en bataille, cicatrice de brûlure.",
		"portrait": {"face": 1, "skin": 2, "hair": 5, "hair_color": 4, "eyes": 1, "beard": 0, "mark": 1},
		"pawn": {"color": "#b0605a"}, "magic": {"name": "Renforcement des flammes", "category": "Renforcement", "public": true}})
	await get_tree().create_timer(1.0).timeout
	c.declare_action(Protocol.TO_ALL, "J'escalade le pic central pour repérer le point de rendez-vous.")
	c.roll("d20+2", Protocol.TO_ALL, "Escalade")
	c.send_chat(Protocol.TO_MJ, "Je garde une flamme allumée dans ma main, discrètement.")
	await get_tree().create_timer(4.5).timeout
	if OS.get_cmdline_user_args().has("--debug-fog"):
		var f: Variant = c.map.get("fog")
		print("FOG ", typeof(f), " ", (f as Dictionary).keys() if f is Dictionary else [], " ", String(f.get("visible", "")).count("1") if f is Dictionary else -1, " ", c.map.get("w"), "x", c.map.get("h"))
	match tab:
		"story":
			screen._show_view("story")
		"map", "":
			screen._show_view("map")
		"sheet", "levelup":
			screen._open_sheet()
		"inventory":
			screen._open_inventory("bag")
		"chest":
			screen._open_inventory("chest")
		"journal":
			screen._open_journal("quests")
		"help":
			screen._open_help()
		"ability":
			var abilities := Rules.usable_abilities(c.my_character(), c.content)
			if not abilities.is_empty():
				screen._open_ability(abilities[0])
	await get_tree().create_timer(1.0).timeout
