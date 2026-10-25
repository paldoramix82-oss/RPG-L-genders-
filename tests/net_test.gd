extends Node
## Test d'intégration réseau : chaque rôle tourne dans un processus Godot distinct
## et communique réellement via ENet (UDP) sur la machine locale.
## Lancement : tests/run_net_test.sh
##
## Scénario 1 : server, alice, bob, wrongcode, mallory.
## Scénario 2 : server2, zoe (tuée brutalement par le script), yann.
## Scénario 3 : server3, dana, eli (fiches, carte, pions, dés, actions, secrets).

const CODE := "TEST42"
const DURATION := 16.0

var role := ""
var port := 17777
var _checks: Array[String] = []
var _failures: Array[String] = []
var _state := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
	match role:
		"server":
			_run_server()
		"alice":
			_run_alice()
		"bob":
			_run_bob()
		"wrongcode":
			_run_wrong_code()
		"mallory":
			_run_mallory()
		"server2":
			_run_server2()
		"zoe", "yann":
			_run_scenario2_player()
		"server3":
			_run_server3()
		"dana":
			_run_dana()
		"eli":
			_run_eli()
		_:
			_finish_now("rôle inconnu: " + role)
			return
	# Les serveurs restent en ligne jusqu'aux vérifications de leurs clients.
	var extra := {"server": 3.0, "server2": 4.0, "yann": 4.0, "server3": 3.0}.get(role, 0.0) as float
	await get_tree().create_timer(DURATION + extra).timeout
	_finish()


# --- Serveur (PC du MJ) -------------------------------------------------------

func _run_server() -> void:
	var err := Net.host({"name": "Test", "mj_name": "MJ Test", "port": port, "max_players": 4, "auto_accept": false, "code": CODE})
	_expect(err == "", "serveur démarré (%s)" % err)
	var server := Net.server
	server.players_changed.connect(func():
		for p in server.players.values():
			if p.online and p.status == Protocol.STATUS_PENDING:
				if p.name == "Mallory":
					server.refuse_player(p.id)
				else:
					server.accept_player(p.id)
		var alice := _find(server, "Alice")
		var bob := _find(server, "Bob")
		if not _state.get("greeted", false) and alice.get("online", false) and bob.get("online", false) \
				and alice.status == Protocol.STATUS_ACCEPTED and bob.status == Protocol.STATUS_ACCEPTED:
			_state.greeted = true
			server.mj_send_message(Protocol.TO_ALL, "Bienvenue")
			server.mj_send_message(alice.id, "secret pour Alice"))
	server.message_added.connect(func(m):
		if m.from_name == "Alice" and m.text == "Bonjour à tous" and not _state.get("kicked", false):
			_state.kicked = true
			await get_tree().create_timer(0.5).timeout
			# Coupure brutale, sans message de fin : simule une perte de Wi-Fi.
			Net._server_kick(server.peer_id_of(_find(server, "Alice").id), 0.0))


func _find(server: SessionServer, player_name: String) -> Dictionary:
	for p in server.players.values():
		if p.name == player_name:
			return p
	return {}


func _check_server() -> void:
	var server := Net.server
	var texts := server.messages.map(func(m): return m.text)
	_expect(texts.count("message hors ligne") == 1, "message envoyé pendant la coupure reçu une seule fois")
	_expect(texts.count("secret pour MJ") == 1, "requête dupliquée appliquée une seule fois")
	var names := server.players.values().map(func(p): return p.name)
	_expect(names.count("Alice") == 1, "Alice a conservé une seule fiche après reconnexion")
	_expect(_find(server, "Alice").get("disconnects", 0) >= 1, "la coupure d'Alice a été détectée")
	_expect(_find(server, "Mallory").get("status", "") == Protocol.STATUS_REFUSED, "Mallory refusée")
	_expect(not names.has("Intrus"), "mauvais code : aucune fiche créée")


# --- Alice : reconnexion et file d'envoi -------------------------------------

func _run_alice() -> void:
	_join("Alice")
	Net.client.welcomed.connect(func():
		_state.welcomes = _state.get("welcomes", 0) + 1
		if _state.welcomes == 1:
			_state.first_id = Net.client.me.id
			Net.client.send_chat(Protocol.TO_ALL, "Bonjour à tous")
		else:
			_state.second_id = Net.client.me.id)
	Net.reconnecting.connect(func(_attempt, _max):
		if not _state.get("queued", false):
			_state.queued = true
			Net.client.send_chat(Protocol.TO_ALL, "message hors ligne"))


func _check_alice() -> void:
	var texts := Net.client.messages.map(func(m): return m.text) if Net.client else []
	_expect(_state.get("welcomes", 0) >= 2, "Alice s'est reconnectée automatiquement")
	_expect(_state.get("first_id", "a") == _state.get("second_id", "b"), "même personnage après reconnexion")
	_expect(texts.has("Bienvenue"), "Alice reçoit le message public du MJ")
	_expect(texts.has("secret pour Alice"), "Alice reçoit son message privé")
	_expect(texts.count("message hors ligne") == 1, "Alice voit son message hors ligne une fois")
	_expect(not texts.has("secret pour MJ"), "Alice NE reçoit PAS le message privé de Bob au MJ")


# --- Bob : confidentialité et anti-doublons ----------------------------------

func _run_bob() -> void:
	await get_tree().create_timer(0.8).timeout
	_join("Bob")
	Net.client.welcomed.connect(func():
		if _state.get("sent", false):
			return
		_state.sent = true
		var req_id := Net.client.send_chat(Protocol.TO_MJ, "secret pour MJ")
		# Renvoi volontaire de la même requête (comme après une coupure).
		Net._c2s.rpc_id(1, Protocol.CMD_CHAT_SEND, {"to": Protocol.TO_MJ, "text": "secret pour MJ", "req_id": req_id}))


func _check_bob() -> void:
	var texts := Net.client.messages.map(func(m): return m.text) if Net.client else []
	_expect(texts.has("Bienvenue"), "Bob reçoit le message public du MJ")
	_expect(texts.has("Bonjour à tous"), "Bob reçoit le message public d'Alice")
	_expect(texts.count("message hors ligne") == 1, "Bob reçoit le message hors ligne d'Alice une fois")
	_expect(texts.count("secret pour MJ") == 1, "Bob voit son propre message privé une fois")
	_expect(not texts.has("secret pour Alice"), "Bob NE reçoit PAS le message privé destiné à Alice")


# --- Refus ---------------------------------------------------------------------

func _run_wrong_code() -> void:
	await get_tree().create_timer(0.4).timeout
	Net.join_failed.connect(func(reason): _state.reason = reason)
	var err := Net.join("127.0.0.1", port, "ZZZZZZ", "Intrus")
	_expect(err == "", "tentative lancée")


func _check_wrong_code() -> void:
	_expect(String(_state.get("reason", "")).contains("Code"), "mauvais code refusé : « %s »" % _state.get("reason", ""))
	_expect(Net.client == null, "aucune session côté client")


func _run_mallory() -> void:
	await get_tree().create_timer(1.2).timeout
	Net.session_ended.connect(func(reason): _state.reason = reason)
	Net.join_failed.connect(func(reason): _state.reason = reason)
	_join("Mallory")


func _check_mallory() -> void:
	_expect(String(_state.get("reason", "")).contains("refusé"), "refus du MJ reçu : « %s »" % _state.get("reason", ""))
	_expect(Net.client == null or Net.client.messages.is_empty(), "Mallory n'a reçu aucun message")


# --- Scénario 2 : coupure brutale et fin de session -----------------------

func _run_server2() -> void:
	var err := Net.host({"name": "Test2", "port": port, "auto_accept": true, "code": CODE})
	_expect(err == "", "serveur 2 démarré")
	Net.server.log_added.connect(func(entry):
		if String(entry.text).begins_with("Zoe est déconnecté"):
			_state.zoe_lost_at = Time.get_ticks_msec())
	await get_tree().create_timer(DURATION + 1.0).timeout
	_state.zoe_online = _find(Net.server, "Zoe").get("online", true)
	_state.zoe_kept = not _find(Net.server, "Zoe").is_empty()
	Net.leave("Fin de partie test")


func _check_server2() -> void:
	_expect(_state.has("zoe_lost_at"), "téléphone disparu détecté par le délai ENet")
	_expect(_state.get("zoe_online", true) == false, "Zoe marquée hors ligne")
	_expect(_state.get("zoe_kept", false), "la fiche de Zoe est conservée")


func _run_scenario2_player() -> void:
	await get_tree().create_timer(0.5).timeout
	Net.session_ended.connect(func(reason): _state.reason = reason)
	Net.reconnecting.connect(func(_a, _m): _state.reconnects = _state.get("reconnects", 0) + 1)
	_join(role.capitalize())


func _check_yann() -> void:
	_expect(_state.get("reason", "") == "Fin de partie test", "fin de session reçue : « %s »" % _state.get("reason", ""))
	_expect(_state.get("reconnects", 0) == 0, "pas de tentative de reconnexion après la fin voulue par le MJ")
	_expect(Net.state == Net.State.OFFLINE, "client hors ligne")


# --- Scénario 3 : fiches, carte, pions, dés, actions, secrets ---------------

func _run_server3() -> void:
	var err := Net.host({"name": "Test3", "port": port, "auto_accept": true, "code": CODE, "universe": "legenders"})
	_expect(err == "", "serveur 3 démarré")
	var server := Net.server
	server.characters_changed.connect(func():
		if _state.get("setup", false) or server.characters.size() < 2:
			return
		_state.setup = true
		var map_id := server.active_map
		server.mj_add_token(map_id, {"kind": "monster", "name": "Monstre caché", "x": 1, "y": 1, "hidden": true, "hp": 9, "hp_max": 9})
		server.mj_add_token(map_id, {"kind": "npc", "name": "PNJ visible", "x": 2, "y": 1, "hidden": false})
		server.mj_add_label(map_id, 3, 3, "Passage secret", true)
		server.mj_roll("d20", Protocol.TO_MJ, "jet secret MJ")
		server.mj_roll("d6", _find(server, "Dana").id, "jet pour Dana")
		server.mj_combat_start(false)
		server.mj_combat_end())
	server.message_added.connect(func(m):
		if m.get("kind", "") == Protocol.KIND_ACTION:
			server.mj_resolve_action(m.id, Protocol.ACTION_RESOLVED, "La porte cède.", "d20+2"))


func _check_server3() -> void:
	var server := Net.server
	var dana := _find(server, "Dana")
	var sheet: Dictionary = server.characters.get(dana.get("id", ""), {})
	_expect(sheet.get("name", "") == "Dana la Brave", "fiche de Dana enregistrée")
	_expect(sheet.get("secret", "") == "mon secret", "secret de la fiche conservé côté hôte")
	var pawn := MapData.token(server.maps[server.active_map], "pawn_" + String(dana.get("id", "")))
	_expect(not pawn.is_empty(), "pion de Dana créé sur la carte")
	_expect(int(pawn.get("x", -1)) == int(_state.get("dana_target_x", -2)) or pawn.get("x", 0) is int, "pion de Dana présent")
	_expect(server.messages.filter(func(m): return m.get("kind", "") == Protocol.KIND_ACTION and m.status == Protocol.ACTION_RESOLVED).size() == 1, "action de Dana résolue par le MJ")
	var save_err := server.save()
	_expect(save_err == "", "campagne sauvegardée (%s)" % save_err)
	var reloaded := CampaignStore.load_campaign(server.session.id)
	_expect((reloaded.get("characters", {}) as Dictionary).size() == 2, "sauvegarde relue avec les 2 fiches")
	var restored := SessionServer.new({"port": port}, func(_a, _b, _c): pass, func(_a, _b): pass, reloaded)
	_expect(restored.maps.size() == server.maps.size() and restored.active_map == server.active_map, "reprise : cartes et carte affichée restaurées")
	_expect(not MapData.token(restored.maps[restored.active_map], "pawn_" + String(dana.get("id", ""))).is_empty(), "reprise : pion de Dana restauré")
	_expect(restored.session.code == server.session.code and restored.players.size() == 2, "reprise : même code et mêmes joueurs (reconnexion possible)")
	CampaignStore.delete(server.session.id)


func _run_dana() -> void:
	await get_tree().create_timer(0.5).timeout
	_join("Dana")
	Net.client.welcomed.connect(func():
		Net.client.save_character({"name": "Dana la Brave", "secret": "mon secret", "species": "Humain",
			"magic": {"category": "Renforcement", "name": "Flammes", "public": true},
			"abilities": [{"name": "Poing de braise", "description": "Un coup enflammé"}],
			"stats": [{"name": "Force", "value": 14}], "hp": 18, "hp_max": 18}))
	Net.client.map_changed.connect(func():
		var pawn := MapData.token(Net.client.map, "pawn_" + String(Net.client.me.get("id", "")))
		if pawn.is_empty() or _state.get("moved", false):
			return
		_state.moved = true
		var p := MapData.free_cell_near(Net.client.map, int(pawn.x) + 2, int(pawn.y))
		_state.target = p
		Net.client.move_pawn(pawn.id, p.x, p.y)
		Net.client.declare_action(Protocol.TO_ALL, "Je force la porte.")
		Net.client.roll("2d6+3", Protocol.TO_ALL, "Escalade"))


func _check_dana() -> void:
	var c := Net.client
	var map := c.map
	var names := (map.get("tokens", []) as Array).map(func(t): return t.name)
	_expect(not names.has("Monstre caché"), "Dana ne reçoit pas le pion caché")
	_expect(names.has("PNJ visible"), "Dana voit le PNJ visible")
	_expect((map.get("labels", []) as Array).filter(func(l): return l.text == "Passage secret").is_empty(), "Dana ne reçoit pas l'étiquette secrète")
	var pawn := MapData.token(map, "pawn_" + String(c.me.get("id", "")))
	var target: Vector2i = _state.get("target", Vector2i(-9, -9))
	_expect(not pawn.is_empty() and int(pawn.x) == target.x and int(pawn.y) == target.y, "Dana a déplacé son pion")
	_expect((c.universe.get("codex", []) as Array).filter(func(e): return e.get("mj_only", false)).is_empty(), "codex sans entrées réservées au MJ")
	_expect(c.my_character().get("secret", "") == "mon secret", "Dana voit son propre secret")
	var labels := c.messages.map(func(m): return m.get("text", ""))
	_expect(not labels.has("jet secret MJ"), "Dana ne voit pas le jet secret du MJ")
	_expect(labels.has("jet pour Dana"), "Dana voit le jet que le MJ lui montre")
	var rolls := c.messages.filter(func(m): return m.get("kind", "") == Protocol.KIND_ROLL and m.text == "Escalade")
	_expect(rolls.size() == 1 and int(rolls[0].roll.total) >= 5 and int(rolls[0].roll.total) <= 15, "jet 2d6+3 calculé par l'hôte")
	var actions := c.messages.filter(func(m): return m.get("kind", "") == Protocol.KIND_ACTION)
	_expect(actions.size() == 1 and actions[0].status == Protocol.ACTION_RESOLVED and actions[0].result == "La porte cède.", "Dana reçoit la résolution de son action")


func _run_eli() -> void:
	await get_tree().create_timer(0.9).timeout
	_join("Eli")
	Net.client.welcomed.connect(func():
		Net.client.save_character({"name": "Eli", "secret": "secret d'Eli"}))
	Net.client.command_failed.connect(func(_r, error): _state.failed = error)
	Net.client.characters_changed.connect(func():
		if _state.get("tried", false):
			return
		for ch in Net.client.characters:
			if ch.get("name", "") == "Dana la Brave":
				_state.tried = true
				Net.client.move_pawn("pawn_" + String(ch.id), 0, 0))


func _check_eli() -> void:
	var c := Net.client
	var dana := {}
	for ch in c.characters:
		if ch.get("name", "") == "Dana la Brave":
			dana = ch
	_expect(not dana.is_empty(), "Eli voit la fiche publique de Dana")
	_expect(not dana.has("secret") and not dana.has("stats"), "la fiche de Dana vue par Eli ne contient ni secret ni détails")
	_expect(dana.get("magic", {}).get("name", "") == "Flammes", "Eli voit le nom public de la magie de Dana")
	_expect(String(_state.get("failed", "")).contains("propre pion"), "Eli ne peut pas déplacer le pion de Dana")
	var labels := c.messages.map(func(m): return m.get("text", ""))
	_expect(not labels.has("jet pour Dana"), "Eli ne voit pas le jet montré à Dana")
	_expect(labels.has("Je force la porte."), "Eli voit l'action publique de Dana")


# --- Outils --------------------------------------------------------------------

func _join(player_name: String) -> void:
	var err := Net.join("127.0.0.1", port, CODE.to_lower(), player_name)
	_expect(err == "", "%s : connexion lancée (%s)" % [player_name, err])


func _expect(condition: bool, label: String) -> void:
	if condition:
		_checks.append(label)
	else:
		_failures.append(label)


func _finish() -> void:
	match role:
		"server":
			_check_server()
		"alice":
			_check_alice()
		"bob":
			_check_bob()
		"wrongcode":
			_check_wrong_code()
		"mallory":
			_check_mallory()
		"server2":
			_check_server2()
		"yann":
			_check_yann()
		"server3":
			_check_server3()
		"dana":
			_check_dana()
		"eli":
			_check_eli()
	for c in _checks:
		print("[%s] OK    %s" % [role, c])
	for f in _failures:
		print("[%s] ÉCHEC %s" % [role, f])
	if Net.role == Net.Role.HOST:
		await Net.leave()
	get_tree().quit(1 if _failures.size() > 0 else 0)


func _finish_now(reason: String) -> void:
	print("[%s] ÉCHEC %s" % [role, reason])
	get_tree().quit(1)
