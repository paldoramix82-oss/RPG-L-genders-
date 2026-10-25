extends Node
## Test d'intégration réseau : chaque rôle tourne dans un processus Godot distinct
## et communique réellement via ENet (UDP) sur la machine locale.
## Lancement : tests/run_net_test.sh
##
## Scénario 1 : server, alice, bob, wrongcode, mallory.
## Scénario 2 : server2, zoe (tuée brutalement par le script), yann.

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
		_:
			_finish_now("rôle inconnu: " + role)
			return
	# Les serveurs restent en ligne jusqu'aux vérifications de leurs clients.
	var extra := {"server": 3.0, "server2": 4.0, "yann": 4.0}.get(role, 0.0) as float
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
	for c in _checks:
		print("[%s] OK    %s" % [role, c])
	for f in _failures:
		print("[%s] ÉCHEC %s" % [role, f])
	if role == "server":
		Net.leave()
	get_tree().quit(1 if _failures.size() > 0 else 0)


func _finish_now(reason: String) -> void:
	print("[%s] ÉCHEC %s" % [role, reason])
	get_tree().quit(1)
