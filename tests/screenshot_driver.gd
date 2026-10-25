extends Node
## Pilote de captures : joue une petite scène réelle (hôte + joueur en réseau)
## puis photographie l'onglet demandé.
## Arguments : --shot=menu|join|host|player  --tab=<onglet>  --out=<png>

const PORT := 17800
const CODE := "VALMBR"

var shot := "menu"
var tab := ""
var out := "user://shot.png"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.get_slice("=", 1)
		elif arg.begins_with("--tab="):
			tab = arg.get_slice("=", 1)
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
	Net.host({"name": "Légenders — Le test de la magie", "mj_name": "Le Conteur", "port": PORT, "max_players": 4, "code": CODE, "universe": "legenders", "auto_accept": true})
	var server := Net.server
	for id in server.map_order:
		if server.maps[id].get("template", "") == "ile_test":
			server.mj_set_active_map(id)
	App.goto(App.SCENE_HOST)
	server.mj_send_message(Protocol.TO_ALL, "Vous êtes téléportés au hasard sur l'île. Dix jours pour trouver le point de rendez-vous.")
	await get_tree().create_timer(4.0).timeout
	var map_id := server.active_map
	server.mj_add_token(map_id, {"kind": "monster", "name": "Croc blanc", "x": 13, "y": 12, "color": "#d9dee4", "hp": 22, "hp_max": 22})
	server.mj_add_token(map_id, {"kind": "npc", "name": "Candidat rival", "x": 16, "y": 9, "color": "#6f9fc9", "hp": 15, "hp_max": 15})
	server.mj_combat_start(false)
	await get_tree().create_timer(1.0).timeout
	var screen := get_tree().current_scene
	if tab != "" and screen.get("_tabs"):
		screen._tabs.show_page(tab)
	await get_tree().create_timer(1.0).timeout


func _player() -> void:
	Net.joined.connect(func(): App.goto(App.SCENE_PLAYER))
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1", PORT, CODE, "Camille")
	await get_tree().create_timer(1.5).timeout
	var c := Net.client
	if c == null:
		return
	c.save_character({
		"name": "Shin", "concept": "Gardien du Dragon (débutant)", "species": "Humain", "origin": "RAC (Mako)", "age": "17",
		"appearance": "Cheveux en bataille, cicatrice de brûlure sur l'avant-bras.", "rank": "B",
		"magic": {"category": "Renforcement", "name": "Renforcement des flammes", "origin": "Imposition par un Légender (Gardien)",
			"description": "Se recouvre de flammes pour gagner en résistance, en vitesse et en dégâts.", "limits": "S'emballe vite ; épuisant au-delà de quelques minutes.", "public": true},
		"abilities": [{"name": "Poing de Sol'fyr", "description": "Un coup chargé de flammes.", "cost": "3 AEC", "range": "Contact"}],
		"stats": [{"name": "Force", "value": 14}, {"name": "Agilité", "value": 12}, {"name": "Endurance", "value": 13}, {"name": "Intelligence", "value": 8}, {"name": "Perception", "value": 10}, {"name": "Charisme", "value": 11}],
		"skills": [{"name": "Combat", "value": 3}, {"name": "Survie", "value": 1}],
		"inventory": [{"name": "Ration de survie", "qty": 3, "description": "Volée par des ombrés ?"}],
		"hp": 17, "hp_max": 20, "res": 8, "res_max": 10, "goals": "Devenir mage d'État et réveiller Sol'fyr pour de bon.",
		"pawn": {"color": "#b0605a", "symbol": "SH"},
	})
	await get_tree().create_timer(1.0).timeout
	c.declare_action(Protocol.TO_ALL, "J'escalade le pic central pour repérer le point de rendez-vous.")
	c.roll("d20+2", Protocol.TO_ALL, "Escalade")
	c.send_chat(Protocol.TO_MJ, "Je garde une flamme allumée dans ma main, discrètement.")
	await get_tree().create_timer(2.5).timeout
	var screen := get_tree().current_scene
	if tab == "editor":
		screen._tabs.show_page("sheet")
		screen._open_editor()
	elif tab != "" and screen.get("_tabs"):
		screen._tabs.show_page(tab)
	await get_tree().create_timer(1.0).timeout
