extends Node
## Pilote de captures : joue une petite scène réelle (hôte + joueur en réseau)
## puis photographie l'onglet demandé.
## Arguments : --shot=menu|join|host|player  --tab=<onglet>  --phase=none|exploration|combat  --out=<png>

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
	server.mj_send_message(Protocol.TO_ALL, "Vous êtes téléportés au hasard sur l'île. Dix jours pour trouver le point de rendez-vous.")
	await get_tree().create_timer(4.0).timeout
	var map_id := server.active_map
	server.mj_add_token(map_id, {"kind": "monster", "name": "Croc blanc", "x": 13, "y": 12, "color": "#d9dee4", "hp": 22, "hp_max": 22})
	server.mj_add_token(map_id, {"kind": "npc", "name": "Candidat rival", "x": 16, "y": 9, "color": "#6f9fc9", "hp": 15, "hp_max": 15})
	for p in server.players.values():
		server.mj_request_roll(p.id, "d20", "Perception", 12, true)
	var packs := NpcLibrary.packs("legenders")
	server.mj_import_npcs(packs[0].npcs.slice(0, 3))
	for id in server.characters.keys():
		if not server.players.has(id):
			var t := server.mj_place_character(id)
			server.mj_update_token(map_id, t.id, {"hidden": false})
	server.mj_music("poing_de_braise", true)
	if phase != "none":
		server.mj_start_game("exploration")
		if phase == "combat":
			server.mj_set_phase("combat")
			# Le joueur commence, pour montrer son panneau de tour.
			var pawns := server.players.keys().map(func(id): return "pawn_" + String(id))
			for i in server.phase.order.size():
				if pawns.has(server.phase.order[i]):
					server.phase.turn = i
					server._begin_turn()
					server._phase_changed()
					break
	await get_tree().create_timer(1.0).timeout
	var screen := get_tree().current_scene
	if tab != "" and screen.get("_tabs"):
		screen._tabs.show_page(tab)
	# Laisse le téléphone se photographier avant que l'hôte ne ferme.
	await get_tree().create_timer(4.0).timeout


func _player() -> void:
	Net.joined.connect(func(): App.goto(App.SCENE_PLAYER))
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1", PORT, "Camille")
	await get_tree().create_timer(1.5).timeout
	var c := Net.client
	if c == null:
		return
	var screen := get_tree().current_scene
	if tab.begins_with("wizard"):
		# Assistant de création : wizard1..wizard4.
		screen._open_wizard()
		var wizard: CreationWizard = screen._creation.get_child(0)
		wizard.class_id = "briseur"
		wizard.alloc = Rules.get_class_def("legenders", "briseur").recommended.duplicate()
		wizard.step = int(tab.substr(6)) - 1
		wizard.identity.name = "Shin"
		wizard._show_step()
		await get_tree().create_timer(1.0).timeout
		return
	var base := CharacterData.create(c.universe, c.me.id, c.me.id, "Shin")
	var sheet := Rules.build_sheet(base, "legenders", "briseur", Rules.get_class_def("legenders", "briseur").recommended, [0])
	sheet.concept = "Gardien du Dragon (débutant)"
	sheet.species = "Humain"
	sheet.pawn.color = "#b0605a"
	sheet.magic.name = "Renforcement des flammes"
	sheet.goals = "Devenir mage d'État et réveiller Sol'fyr pour de bon."
	c.save_character(sheet)
	await get_tree().create_timer(1.0).timeout
	c.declare_action(Protocol.TO_ALL, "J'escalade le pic central pour repérer le point de rendez-vous.")
	c.roll("d20+2", Protocol.TO_ALL, "Escalade")
	c.send_chat(Protocol.TO_MJ, "Je garde une flamme allumée dans ma main, discrètement.")
	await get_tree().create_timer(2.5).timeout
	if tab == "dice":
		screen._roll(Protocol.TO_ALL, "2d6+3", "Escalade")
		await get_tree().create_timer(0.5).timeout
		return
	if tab == "request":
		screen._tabs.show_page("adventure")
		await get_tree().create_timer(1.0).timeout
		return
	if tab == "editor":
		screen._tabs.show_page("sheet")
		screen._open_editor(screen._sheet_box)
	elif tab != "" and screen.get("_tabs"):
		screen._tabs.show_page(tab)
	await get_tree().create_timer(1.0).timeout
