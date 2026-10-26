extends Node
## Test d'intégration réseau : chaque rôle tourne dans un processus Godot distinct
## et communique réellement via ENet (UDP) sur la machine locale.
## Lancement : tests/run_net_test.sh
##
## Scénario 1 : server, alice, bob, mallory.
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
	var err := Net.host({"name": "Test", "mj_name": "MJ Test", "port": port, "max_players": 4, "auto_accept": false})
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
	var err := Net.host({"name": "Test2", "port": port, "auto_accept": true})
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


# --- Scénario 3 : partie complète (création, phases, tours, combat, secrets) --

func _run_server3() -> void:
	var err := Net.host({"name": "Test3", "port": port, "auto_accept": true, "universe": "legenders"})
	_expect(err == "", "serveur 3 démarré")
	var server := Net.server
	server.characters_changed.connect(func():
		var ready := server.players.keys().filter(func(id): return server.characters.has(id))
		if _state.get("setup", false) or ready.size() < 2:
			return
		_state.setup = true
		var map_id := server.active_map
		server.mj_add_token(map_id, {"kind": "monster", "name": "Monstre caché", "x": 1, "y": 1, "hidden": true, "hp": 9, "hp_max": 9})
		_state.npc = server.mj_add_token(map_id, {"kind": "npc", "name": "PNJ visible", "x": 2, "y": 1, "hidden": false, "hp": 30, "hp_max": 30, "defense": 8, "attack": "1d4"}).id
		server.mj_add_label(map_id, 3, 3, "Passage secret", true)
		server.mj_roll("d20", Protocol.TO_MJ, "jet secret MJ")
		server.mj_roll("d6", _find(server, "Dana").id, "jet pour Dana")
		# Quête donnée au groupe et objet dans le coffre commun.
		_state.quest = server.mj_quest_save({"title": "Les loups de Valombre", "kind": "main", "objectives": [{"text": "Trouver la tanière"}],
			"rewards": {"xp": 120, "gold": 15}, "give": true}).id
		server.add_loot(Content.item_instance(server.content, "potion_soin"), "Test")
		server.mj_start_game("exploration"))
	server.phase_changed.connect(func():
		var phase: Dictionary = server.phase
		var map: Dictionary = server.maps[server.active_map]
		if phase.type == "exploration" and int(phase.round) >= 2 and not _state.get("combat", false):
			# Deuxième tour d'exploration : on passe au combat, Dana d'abord, le PNJ au contact.
			_state.combat = true
			var dana_pawn := MapData.token(map, "pawn_" + String(_find(server, "Dana").id))
			server.mj_update_token(server.active_map, _state.npc, {"x": int(dana_pawn.x) + 1, "y": int(dana_pawn.y)})
			server.mj_set_phase.call_deferred("combat")
		elif phase.type == "combat" and not _state.get("ordered", false):
			_state.ordered = true
			var dana_id := "pawn_" + String(_find(server, "Dana").id)
			phase.order.erase(dana_id)
			phase.order.push_front(dana_id)
			phase.turn = 0
			server._begin_turn()
			server._phase_changed()
		elif phase.type == "combat" and server._current_token() == _state.get("npc", "") and not _state.get("npc_attacked", false):
			_state.npc_attacked = true
			var dana_id := "pawn_" + String(_find(server, "Dana").id)
			_state.npc_attack_error = server.turn_action(_state.npc, {"action": "attack", "target": dana_id, "index": 0})
			server.turn_action.call_deferred(_state.npc, {"action": "end"}))
	server.message_added.connect(func(m):
		if m.get("kind", "") == Protocol.KIND_ACTION:
			# Le MJ demande à Dana de lancer elle-même son dé.
			server.mj_request_action_roll(m.id, "d20+2", 12))
	server.message_updated.connect(func(m):
		if m.get("kind", "") == Protocol.KIND_ACTION and m.status == Protocol.ACTION_ROLLED:
			server.mj_resolve_action(m.id, Protocol.ACTION_RESOLVED, "La porte cède.", ""))
	server.players_changed.connect(func():
		var eli := _find(server, "Eli")
		if not _state.get("asked_eli", false) and eli.get("online", false) and eli.status == Protocol.STATUS_ACCEPTED:
			_state.asked_eli = true
			server.mj_request_roll(eli.id, "d20", "Perception secrète", 10, false)
			server.mj_music("taverne", true)
			_state.imported = server.mj_import_npcs(NpcLibrary.packs("legenders")[0].npcs))


func _check_server3() -> void:
	var server := Net.server
	var dana := _find(server, "Dana")
	var sheet: Dictionary = server.characters.get(dana.get("id", ""), {})
	_expect(sheet.get("name", "") == "Dana la Brave", "fiche de Dana enregistrée")
	_expect(sheet.get("secret", "") == "mon secret", "secret de la fiche conservé côté hôte")
	_expect(sheet.get("auto", false) and sheet.get("class_id", "") == "ombre", "fiche de Dana créée avec l'assistant (classe Ombre)")
	var d := Rules.derived(sheet, server.content)
	_expect(int(sheet.get("hp_max", 0)) == int(d.hp_max) and int(d.hp_max) > 10 and int(sheet.defense) == int(d.defense), "PV et défense calculés automatiquement par l'hôte (%d PV, déf. %d)" % [d.hp_max, d.defense])
	_expect(sheet.get("inventory", []).any(func(i): return i.name == "Kunai jumeaux"), "équipement choisi dans l'assistant (Kunai jumeaux)")
	_expect(server.session.get("started", false), "la partie a été lancée par le MJ")
	var attacks := server.messages.filter(func(m): return m.get("kind", "") == Protocol.KIND_COMBAT and String(m.get("text", "")).contains("Attaque rapide"))
	_expect(attacks.any(func(m): return String(m.text).begins_with("Dana la Brave : Attaque rapide (Kunai jumeaux) → PNJ visible")), "Dana a attaqué le PNJ à son tour (jet automatique, 1 PA)")
	_expect(String(_state.get("npc_attack_error", "x")) == "" and attacks.any(func(m): return String(m.text).begins_with("PNJ visible : Attaque rapide")), "le MJ a fait attaquer son PNJ à son tour")
	var q := server._quest(String(_state.get("quest", "")))
	server.mj_quest_complete(q.id)
	_expect(q.status == "done" and int(server.characters[dana.id].gold) >= 20 + 15, "quête réussie : or distribué au groupe")
	_expect(server.loot.is_empty() and server.characters[dana.id].inventory.any(func(i): return i.name == "Potion de soin"), "Dana a pris la potion du coffre commun")
	_expect(server.messages.filter(func(m): return m.get("kind", "") == Protocol.KIND_ACTION and m.status == Protocol.ACTION_RESOLVED).size() == 1, "action de Dana résolue par le MJ")
	_expect(int(_state.get("imported", 0)) >= 10, "pack de PNJ importé (%d fiches)" % int(_state.get("imported", 0)))
	var eli_req := server.messages.filter(func(m): return m.get("kind", "") == Protocol.KIND_ROLL_REQUEST)
	_expect(eli_req.size() == 1 and eli_req[0].status == "done" and eli_req[0].roll.has("success"), "Eli a lancé lui-même le jet demandé")
	var save_err := server.save()
	_expect(save_err == "", "campagne sauvegardée (%s)" % save_err)
	var reloaded := CampaignStore.load_campaign(server.session.id)
	_expect((reloaded.get("characters", {}) as Dictionary).size() == server.characters.size(), "sauvegarde relue avec toutes les fiches (joueurs et PNJ)")
	var restored := SessionServer.new({"port": port}, Callable(), Callable(), reloaded)
	_expect(restored.maps.size() == server.maps.size() and restored.active_map == server.active_map, "reprise : cartes et carte affichée restaurées")
	_expect(not MapData.token(restored.maps[restored.active_map], "pawn_" + String(dana.get("id", ""))).is_empty(), "reprise : pion de Dana restauré")
	_expect(restored.players.size() == 2 and restored.session.get("started", false), "reprise : mêmes joueurs, partie déjà lancée")
	_expect(restored.music.track != "" and restored.music.track == server.music.track, "reprise : dernière musique mémorisée (%s)" % server.music.track)
	CampaignStore.delete(server.session.id)


func _run_dana() -> void:
	await get_tree().create_timer(0.5).timeout
	_join("Dana")
	Net.client.command_failed.connect(func(_r, error): _state.errors = _state.get("errors", []) + [error])
	Net.client.welcomed.connect(func():
		var c := Net.client
		var cls := Rules.get_class_def(c.content, "ombre")
		c.create_character("ombre", cls.recommended, [1], {"name": "Dana la Brave", "secret": "mon secret", "species": "Humain",
			"magic": {"name": "Flammes", "category": "Altération", "public": true}}))
	Net.client.quests_changed.connect(func(): _state.quests_seen = Net.client.quests.size())
	Net.client.loot_changed.connect(func():
		if not Net.client.loot.is_empty() and not _state.get("took", false):
			_state.took = true
			Net.client.take_loot(String(Net.client.loot[0].uid)))
	Net.client.phase_changed.connect(func():
		var c := Net.client
		if not c.is_my_turn():
			return
		var pawn := c.my_token()
		if c.phase.type == "exploration" and not _state.get("explored", false):
			_state.explored = true
			# Trop loin : refusé ; puis une case à côté : accepté.
			var far := int(c.phase.moves_left) + 2
			for f: Vector2i in [Vector2i(far, 0), Vector2i(-far, 0), Vector2i(0, far), Vector2i(0, -far), Vector2i(far, far), Vector2i(-far, -far)]:
				var q: Vector2i = Vector2i(int(pawn.x), int(pawn.y)) + f
				if MapData.passable(c.map, q.x, q.y) and MapData.token_at(c.map, q.x, q.y).is_empty():
					c.move_pawn(pawn.id, q.x, q.y)
					break
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
				var p: Vector2i = Vector2i(int(pawn.x), int(pawn.y)) + d
				if MapData.passable(c.map, p.x, p.y) and MapData.token_at(c.map, p.x, p.y).is_empty():
					_state.target = p
					break
			c.move_pawn(pawn.id, _state.target.x, _state.target.y)
			c.declare_action(Protocol.TO_ALL, "Je force la porte.")
			c.roll("2d6+3", Protocol.TO_ALL, "Escalade")
			c.turn_action("end")
		elif c.phase.type == "exploration" and int(c.phase.round) >= 2:
			c.turn_action("end")
		elif c.phase.type == "combat" and not _state.get("attacked", false):
			for t in c.map.tokens:
				if t.name == "PNJ visible":
					_state.attacked = true
					c.turn_action("attack", t.id, 0)
					c.turn_action("end")
		elif c.phase.type == "combat":
			c.turn_action("end"))
	Net.client.message_updated.connect(func(m):
		if m.get("kind", "") == Protocol.KIND_ACTION and m.status == Protocol.ACTION_ROLL and m.from == Net.client.me.id:
			Net.client.answer_roll(m.id))


func _check_dana() -> void:
	var c := Net.client
	var map := c.map
	var names := (map.get("tokens", []) as Array).map(func(t): return t.name)
	_expect(not names.has("Monstre caché"), "Dana ne reçoit pas le pion caché")
	_expect(names.has("PNJ visible"), "Dana voit le PNJ visible")
	_expect((map.get("labels", []) as Array).filter(func(l): return l.text == "Passage secret").is_empty(), "Dana ne reçoit pas l'étiquette secrète")
	var errors: Array = _state.get("errors", [])
	_expect(errors.any(func(e): return String(e).begins_with("Trop loin")), "déplacement au-delà de la vitesse refusé en exploration")
	var pawn := c.my_token()
	var target: Vector2i = _state.get("target", Vector2i(-9, -9))
	_expect(not pawn.is_empty() and int(pawn.x) == target.x and int(pawn.y) == target.y, "Dana a déplacé son pion pendant son tour")
	_expect((c.universe.get("codex", []) as Array).filter(func(e): return e.get("mj_only", false)).is_empty(), "codex sans entrées réservées au MJ")
	_expect(c.my_character().get("secret", "") == "mon secret", "Dana voit son propre secret")
	_expect(c.game_started() and c.phase.get("type", "") == "combat", "Dana est passée en combat (phase reçue)")
	var labels := c.messages.map(func(m): return m.get("text", ""))
	_expect(not labels.has("jet secret MJ"), "Dana ne voit pas le jet secret du MJ")
	_expect(labels.has("jet pour Dana"), "Dana voit le jet que le MJ lui montre")
	var rolls := c.messages.filter(func(m): return m.get("kind", "") == Protocol.KIND_ROLL and m.text == "Escalade")
	_expect(rolls.size() == 1 and int(rolls[0].roll.total) >= 5 and int(rolls[0].roll.total) <= 15, "jet 2d6+3 calculé par l'hôte")
	var actions := c.messages.filter(func(m): return m.get("kind", "") == Protocol.KIND_ACTION)
	_expect(actions.size() == 1 and actions[0].status == Protocol.ACTION_RESOLVED and actions[0].result == "La porte cède.", "Dana reçoit la résolution de son action")
	_expect(actions.size() == 1 and actions[0].roll.get("difficulty", 0) == 12 and actions[0].roll.has("success"), "Dana a lancé elle-même le dé demandé (difficulté 12)")
	_expect(not labels.has("Perception secrète"), "Dana ne voit pas le jet secret demandé à Eli")
	_expect(c.music.get("track", "") != "", "musique de l'hôte reçue")
	_expect(c.characters.size() == 2, "les fiches de PNJ du MJ ne sont pas envoyées aux joueurs")
	_expect(int(_state.get("quests_seen", 0)) == 1, "quête du MJ reçue par Dana")
	_expect(not c.content.get("classes", {}).is_empty() and c.content.get("monsters") == null, "catalogue reçu sans les monstres ni le butin du MJ")


func _run_eli() -> void:
	await get_tree().create_timer(0.9).timeout
	_join("Eli")
	Net.client.command_failed.connect(func(_r, error):
		_state.errors = _state.get("errors", []) + [error]
		if String(error).begins_with("Répartition"):
			Net.client.save_character({"name": "Eli", "secret": "secret d'Eli"}))
	Net.client.welcomed.connect(func():
		# Trop de points répartis : refusé par l'hôte.
		var c := Net.client
		c.create_character("briseur", {"Force": 6, "Dextérité": 6, "Constitution": 6}, [0], {"name": "Eli"}))
	Net.client.message_received.connect(func(m):
		if m.get("kind", "") == Protocol.KIND_ROLL_REQUEST:
			Net.client.answer_roll(m.id))
	Net.client.map_changed.connect(func():
		for t in Net.client.map.get("tokens", []):
			if String(t.name) == "Dana la Brave":
				_state.dana_pos = Vector2i(int(t.x), int(t.y)))
	Net.client.phase_changed.connect(func():
		var c := Net.client
		if not c.phase.get("turns", false) or c.my_token().is_empty():
			return
		if c.is_my_turn():
			c.turn_action("end")
		elif not _state.get("out_of_turn", false):
			_state.out_of_turn = true
			var me := c.my_token()
			c.move_pawn(me.id, int(me.x), int(me.y) + 1))
	Net.client.characters_changed.connect(func():
		if _state.get("tried", false):
			return
		for ch in Net.client.characters:
			if ch.get("name", "") == "Dana la Brave":
				_state.tried = true
				Net.client.move_pawn("pawn_" + String(ch.id), 0, 0))


func _check_eli() -> void:
	var c := Net.client
	var errors: Array = _state.get("errors", [])
	var dana := {}
	for ch in c.characters:
		if ch.get("name", "") == "Dana la Brave":
			dana = ch
	_expect(errors.any(func(e): return String(e).begins_with("Répartition des points invalide")), "trop de points répartis : refusé par l'hôte")
	_expect(not dana.is_empty(), "Eli voit la fiche publique de Dana")
	_expect(not dana.has("secret") and not dana.has("stats"), "la fiche de Dana vue par Eli ne contient ni secret ni détails")
	_expect(dana.get("magic", {}).get("name", "") == "Flammes", "Eli voit le nom public de la magie de Dana")
	_expect(errors.any(func(e): return String(e).contains("propre pion")), "Eli ne peut pas déplacer le pion de Dana")
	_expect(errors.any(func(e): return String(e) == "Ce n'est pas votre tour."), "Eli ne peut pas bouger pendant le tour de Dana")
	var labels := c.messages.map(func(m): return m.get("text", ""))
	_expect(not labels.has("jet pour Dana"), "Eli ne voit pas le jet montré à Dana")
	_expect(labels.has("Je force la porte."), "Eli voit l'action publique de Dana")
	var req := c.messages.filter(func(m): return m.get("kind", "") == Protocol.KIND_ROLL_REQUEST)
	_expect(req.size() == 1 and req[0].status == "done" and int(req[0].roll.total) >= 1, "Eli reçoit le résultat de son propre jet")
	var dana_pawn := {}
	for t in c.map.get("tokens", []):
		if String(t.name) == "Dana la Brave":
			dana_pawn = t
	_expect(not dana_pawn.is_empty() and _state.get("dana_pos", Vector2i(-1, -1)) == Vector2i(int(dana_pawn.x), int(dana_pawn.y)), "Eli voit le pion de Dana bouger (mise à jour légère des pions)")


# --- Outils --------------------------------------------------------------------

func _join(player_name: String) -> void:
	var err := Net.join("127.0.0.1", port, player_name)
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
