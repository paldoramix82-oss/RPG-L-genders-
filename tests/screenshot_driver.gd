extends Node

var shot := "menu"
var out := "user://shot.png"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
	match shot:
		"menu":
			App.goto(App.SCENE_MAIN_MENU)
		"join":
			App.goto(App.SCENE_JOIN)
		"host":
			Net.host({"name": "Les Cendres de Valombre", "mj_name": "Le Conteur", "port": 17800, "max_players": 4, "code": "VAL0MB"})
			App.goto(App.SCENE_HOST)
			Net.server.mj_send_message(Protocol.TO_ALL, "La pluie de cendres tombe sur Valombre depuis trois jours. Les cloches du temple se sont tues.")
			await get_tree().create_timer(2.5).timeout
			for p in Net.server.players.values():
				Net.server.accept_player(p.id)
			await get_tree().create_timer(1.0).timeout
			for p in Net.server.players.values():
				if p.name == "Camille":
					Net.server.mj_send_message(p.id, "Tu remarques une marque de brûlure en forme de spirale sur la main du tavernier.")
		"player":
			Net.joined.connect(func(): App.goto(App.SCENE_PLAYER))
			Net.join("127.0.0.1", 17800, "VAL0MB", "Camille")
			await get_tree().create_timer(2.0).timeout
			if Net.client:
				Net.client.send_chat(Protocol.TO_ALL, "J'entre dans la taverne et j'observe les clients.")
				Net.client.send_chat(Protocol.TO_MJ, "Discrètement, je garde la main sur ma dague.")
	await get_tree().create_timer(5.0 if shot == "host" else 3.0).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("capture : ", out)
	get_tree().quit()
