class_name SessionServer
extends RefCounted
## État officiel de la campagne, sur l'appareil qui héberge (serveur autoritaire).
##
## Cette classe ne connaît pas ENet : elle reçoit des identifiants de pairs et
## envoie des événements via les Callables fournies par Net. Elle décide seule
## de ce qui est valide et de ce que chaque joueur a le droit de recevoir.

signal players_changed
signal message_added(message: Dictionary)
signal message_updated(message: Dictionary)
signal log_added(entry: Dictionary)
signal characters_changed
signal maps_changed
signal phase_changed
signal saved(error: String)
signal music_changed(state: Dictionary)

var session := {}
var universe := {}
## player_id -> fiche de connexion (contient le jeton secret : jamais envoyée telle quelle).
var players := {}
var messages: Array = []
var connection_log: Array[Dictionary] = []
## char_id -> fiche (joueurs : char_id == player_id ; PNJ : « npc_… »).
var characters := {}
var maps := {}
var map_order: Array = []
var active_map := ""
## Phase de jeu en cours (voir Phases) et tour par tour.
var phase := {"type": "libre", "order": [], "turn": 0, "round": 1, "moves_left": 0, "action_used": false, "initiative": {}}
var music := {"track": "", "playing": false, "started_at": 0.0, "broadcast": true, "auto_combat": true}
var _music_before_combat := {}

var _send: Callable  # func(peer_id: int, evt: String, payload: Dictionary)
var _kick: Callable  # func(peer_id: int, delay: float)
var _peer_to_player := {}
var _token_to_player := {}
var _seen_requests := {}  # player_id -> Array[String] (anti-doublons)
var _rate := {}  # peer_id -> Array[float]
var _auth_failures := {}  # ip -> {count, until}
var _next_message := 1
var _rng := RandomNumberGenerator.new()
var _dirty := {}  # "map" / "tokens" / "characters" / "phase" / "music" -> true : diffusion groupée
var _unsaved := false


func _init(settings: Dictionary, send: Callable, kick: Callable, saved_data: Dictionary = {}) -> void:
	_send = send
	_kick = kick
	_rng.randomize()
	if not saved_data.is_empty():
		_load(saved_data, settings)
		return
	session = {
		"id": Protocol.random_hex(8),
		"code": Protocol.generate_code(),
		"name": _non_empty(Protocol.sanitize_name(settings.get("name", "")), "Partie sans nom"),
		"mj_name": _non_empty(Protocol.sanitize_name(settings.get("mj_name", "")), "Maître du jeu"),
		"universe": String(settings.get("universe", Universe.DEFAULT_ID)),
		"description": Protocol.sanitize_text(settings.get("description", "")),
		"created": Protocol.now(),
		"started": false,
	}
	_apply_runtime_settings(settings)
	universe = Universe.get_by_id(session.universe)
	session.universe = String(universe.get("id", Universe.DEFAULT_ID))
	if settings.has("code") and String(settings.code) != "":
		session.code = Protocol.normalize_code(settings.code)
	# Cartes de départ : les modèles de l'univers choisi.
	for t in MapData.templates(session.universe):
		var map := MapData.from_template(t)
		maps[map.id] = map
		map_order.append(map.id)
	if not map_order.is_empty():
		active_map = map_order[0]
	_unsaved = true


func _apply_runtime_settings(settings: Dictionary) -> void:
	session.max_players = clampi(int(settings.get("max_players", session.get("max_players", Protocol.DEFAULT_MAX_PLAYERS))), 1, Protocol.MAX_PLAYERS_LIMIT)
	session.auto_accept = bool(settings.get("auto_accept", session.get("auto_accept", true)))
	session.port = int(settings.get("port", Protocol.DEFAULT_PORT))
	session.players_edit_sheets = bool(settings.get("players_edit_sheets", session.get("players_edit_sheets", true)))


# ---------------------------------------------------------------------------
# Cycle de vie des connexions
# ---------------------------------------------------------------------------

## Appelée pendant la phase d'authentification ENet. Renvoie la réponse envoyée au client.
func authenticate(peer_id: int, ip: String, request: Dictionary) -> Dictionary:
	var lock: Dictionary = _auth_failures.get(ip, {})
	if lock.get("until", 0.0) > Protocol.now():
		_log("Tentative bloquée depuis %s (trop d'essais)." % ip, "warn")
		return _reject("Trop de tentatives. Réessayez dans quelques secondes.")

	if int(request.get("proto", -1)) != Protocol.VERSION:
		_log("Version incompatible depuis %s." % ip, "warn")
		return _reject("Version du jeu différente de celle de l'hôte. Installez la même version (protocole v%d)." % Protocol.VERSION)

	# Plus de code de partie : l'adresse IP suffit pour rejoindre. Le MJ peut
	# toujours choisir de valider chaque nouveau joueur.

	var token := String(request.get("token", ""))
	if token.length() < 16 or token.length() > 64 or not token.is_valid_hex_number():
		return _reject("Identifiant d'appareil invalide.")

	var player_name := Protocol.sanitize_name(request.get("name", ""))
	if player_name == "":
		return _reject("Indiquez un nom de joueur.")

	_auth_failures.erase(ip)
	var player: Dictionary
	if _token_to_player.has(token):
		player = players[_token_to_player[token]]
		if player.status == Protocol.STATUS_REFUSED:
			return _reject("Le MJ a refusé votre participation à cette partie.")
		if player.peer_id != 0 and player.peer_id != peer_id:
			# Même appareil qui revient (changement de Wi-Fi, appli relancée) :
			# l'ancienne connexion fantôme est fermée.
			_peer_to_player.erase(player.peer_id)
			_kick.call(player.peer_id, 0.0)
			_log("%s se reconnecte : ancienne connexion fermée." % player.name)
	else:
		for other in players.values():
			if String(other.name).to_lower() == player_name.to_lower():
				return _reject("Le nom « %s » est déjà utilisé dans cette partie." % player_name)
		if _count_seats() >= int(session.max_players):
			return _reject("La partie est complète (%d joueurs maximum)." % session.max_players)
		player = {
			"id": "p_" + Protocol.random_hex(4),
			"name": player_name,
			"token": token,
			"status": Protocol.STATUS_ACCEPTED if session.auto_accept else Protocol.STATUS_PENDING,
			"peer_id": 0,
			"ip": ip,
			"online": false,
			"joined_at": Protocol.now(),
			"last_seen": Protocol.now(),
			"disconnects": 0,
		}
		players[player.id] = player
		_token_to_player[token] = player.id
		_unsaved = true
		_log("Nouvelle demande de %s (%s)." % [player_name, ip])

	player.peer_id = peer_id
	player.ip = ip
	_peer_to_player[peer_id] = player.id
	return {"ok": true, "player_id": player.id, "status": player.status, "session_id": session.id}


## Appelée quand l'authentification est terminée des deux côtés.
func on_peer_connected(peer_id: int) -> void:
	var player := _player_for_peer(peer_id)
	if player.is_empty():
		_kick.call(peer_id, 0.0)
		return
	player.online = true
	player.last_seen = Protocol.now()
	_rate.erase(peer_id)
	if player.status == Protocol.STATUS_ACCEPTED:
		_log("%s est connecté." % player.name, "ok")
		_send_welcome(player)
	else:
		_log("%s attend votre validation." % player.name, "ask")
		_send.call(peer_id, Protocol.EVT_JOIN_STATUS, {"status": player.status})
	_broadcast_players()
	players_changed.emit()


func on_peer_disconnected(peer_id: int) -> void:
	_rate.erase(peer_id)
	var player := _player_for_peer(peer_id)
	_peer_to_player.erase(peer_id)
	if player.is_empty() or player.peer_id != peer_id:
		return
	player.peer_id = 0
	if player.online:
		player.online = false
		player.disconnects += 1
		player.last_seen = Protocol.now()
		_log("%s est déconnecté (personnage conservé)." % player.name, "warn")
	_broadcast_players()
	players_changed.emit()


## Prévient tous les appareils que la partie se termine (pas de reconnexion automatique).
func close(reason: String) -> void:
	for peer_id in _peer_to_player.keys():
		_send.call(peer_id, Protocol.EVT_SESSION_CLOSED, {"reason": reason})


# ---------------------------------------------------------------------------
# Commandes reçues des joueurs
# ---------------------------------------------------------------------------

func handle_command(peer_id: int, cmd: Variant, payload: Variant) -> void:
	var player := _player_for_peer(peer_id)
	if player.is_empty() or typeof(cmd) != TYPE_STRING or not payload is Dictionary:
		return
	var req_id := String(payload.get("req_id", "")) if payload.get("req_id") is String else ""
	if req_id == "" or req_id.length() > 64:
		return
	if not _check_rate(peer_id):
		_ack(peer_id, req_id, false, "Trop de requêtes, patientez un instant.")
		return
	# Une commande renvoyée après une reconnexion n'est jamais appliquée deux fois.
	var seen: Array = _seen_requests.get(player.id, [])
	if seen.has(req_id):
		_ack(peer_id, req_id, true)
		return
	if player.status != Protocol.STATUS_ACCEPTED:
		_ack(peer_id, req_id, false, "Le MJ n'a pas encore validé votre participation.")
		return

	var error := ""
	match cmd:
		Protocol.CMD_CHAT_SEND:
			error = _cmd_chat_send(player, payload)
		Protocol.CMD_ACTION:
			error = _cmd_action(player, payload)
		Protocol.CMD_ROLL:
			error = _cmd_roll(player, payload)
		Protocol.CMD_CHAR_SAVE:
			error = _cmd_char_save(player, payload)
		Protocol.CMD_PAWN_MOVE:
			error = _cmd_pawn_move(player, payload)
		Protocol.CMD_ROLL_ANSWER:
			error = _cmd_roll_answer(player, payload)
		Protocol.CMD_TURN:
			error = _cmd_turn(player, payload)
		_:
			error = "Commande inconnue."

	if error == "":
		seen.append(req_id)
		if seen.size() > 200:
			seen = seen.slice(seen.size() - 200)
		_seen_requests[player.id] = seen
	_ack(peer_id, req_id, error == "", error)


func _target_from(payload: Dictionary) -> String:
	var to := String(payload.get("to", "")) if payload.get("to") is String else ""
	return to if to == Protocol.TO_ALL or to == Protocol.TO_MJ else ""


func _cmd_chat_send(player: Dictionary, payload: Dictionary) -> String:
	var to := _target_from(payload)
	if to == "":
		return "Destinataire invalide."
	var text := Protocol.sanitize_text(payload.get("text", ""))
	if text == "":
		return "Message vide."
	_add_message({"from": player.id, "from_name": _speaker_name(player.id), "to": to, "text": text})
	return ""


## Action libre : le serveur l'enregistre « en attente » ; seul le MJ décide du résultat.
func _cmd_action(player: Dictionary, payload: Dictionary) -> String:
	var to := _target_from(payload)
	if to == "":
		return "Visibilité invalide."
	var text := Protocol.sanitize_text(payload.get("text", ""))
	if text == "":
		return "Décrivez votre action."
	_add_message({
		"kind": Protocol.KIND_ACTION, "from": player.id, "from_name": _speaker_name(player.id),
		"to": to, "text": text, "status": Protocol.ACTION_PENDING, "result": "", "roll": {},
	})
	_log("Nouvelle action de %s." % player.name, "ask")
	return ""


func _cmd_roll(player: Dictionary, payload: Dictionary) -> String:
	var to := _target_from(payload)
	if to == "":
		return "Visibilité invalide."
	var result := Dice.roll(String(payload.get("expr", "")), _rng)
	if not result.ok:
		return result.error
	_add_roll_message(player.id, _speaker_name(player.id), to, result, Protocol.sanitize_text(payload.get("label", ""), 80))
	return ""


func _cmd_char_save(player: Dictionary, payload: Dictionary) -> String:
	var existing: Dictionary = characters.get(player.id, {})
	if not existing.is_empty() and not session.players_edit_sheets:
		return "Le MJ a verrouillé les fiches : demandez-lui les modifications."
	var base := existing if not existing.is_empty() else CharacterData.create(universe, player.id, player.id, player.name)
	var input: Variant = payload.get("character")
	if not input is Dictionary:
		return "Fiche invalide."
	# Le joueur ne peut pas changer l'identifiant ni le propriétaire de sa fiche.
	var sheet := CharacterData.sanitize(input, base)
	sheet.id = player.id
	sheet.owner = player.id
	if String(sheet.name) == "":
		sheet.name = player.name
	var is_new := existing.is_empty()
	if sheet.get("auto", false):
		if not Rules.valid_alloc(sheet.get("alloc", {})):
			return "Répartition des points invalide (%d points maximum)." % Rules.POINT_POOL
		sheet = Rules.refresh(sheet, session.universe, is_new)
	characters[player.id] = sheet
	_sync_pawns_for(player.id)
	_mark("characters")
	_unsaved = true
	characters_changed.emit()
	if is_new:
		_system_message("%s entre dans l'histoire sous les traits de %s." % [player.name, sheet.name])
	return ""


func _cmd_pawn_move(player: Dictionary, payload: Dictionary) -> String:
	var map: Dictionary = maps.get(active_map, {})
	if map.is_empty() or String(payload.get("map_id", "")) != active_map:
		return "Cette carte n'est plus affichée."
	if not map.get("players_can_move", true):
		return "Le MJ a bloqué les déplacements sur cette carte."
	var t := MapData.token(map, String(payload.get("token_id", "")))
	if t.is_empty() or t.owner != player.id or t.hidden:
		return "Vous ne pouvez déplacer que votre propre pion."
	var x := int(payload.get("x", -1))
	var y := int(payload.get("y", -1))
	if not MapData.passable(map, x, y):
		return "Case infranchissable."
	var rules := Phases.def(phase.type)
	if rules.move == "none":
		return "Pas de déplacement pendant la phase « %s »." % rules.name
	if rules.turns:
		if _current_token() != t.id:
			return "Ce n'est pas votre tour."
		if rules.move == "limit":
			var dist := Rules.distance(Vector2i(int(t.x), int(t.y)), Vector2i(x, y))
			if dist > int(phase.moves_left):
				return "Trop loin : il vous reste %d case%s de déplacement." % [phase.moves_left, "s" if int(phase.moves_left) > 1 else ""]
			phase.moves_left = int(phase.moves_left) - dist
			_mark("phase")
	t.x = x
	t.y = y
	_mark("tokens")
	_unsaved = true
	maps_changed.emit()
	return ""


# ---------------------------------------------------------------------------
# Actions du maître du jeu (appelées directement par l'interface de l'hôte)
# ---------------------------------------------------------------------------

## to : Protocol.TO_ALL ou l'identifiant d'un joueur (message privé).
func mj_send_message(to: String, text: String) -> bool:
	text = Protocol.sanitize_text(text)
	if text == "" or not _valid_mj_target(to):
		return false
	_add_message({"from": Protocol.MJ_ID, "from_name": session.mj_name, "to": to, "text": text})
	return true


## to : TO_ALL (public), TO_MJ (secret : MJ seul) ou un joueur.
func mj_roll(expr: String, to: String, label: String = "") -> String:
	if not _valid_mj_target(to) and to != Protocol.TO_MJ:
		return "Destinataire invalide."
	var result := Dice.roll(expr, _rng)
	if not result.ok:
		return result.error
	_add_roll_message(Protocol.MJ_ID, session.mj_name, to, result, Protocol.sanitize_text(label, 80))
	return ""


## Résout ou refuse une action déclarée. Le résultat suit la visibilité de l'action.
## Le joueur lance lui-même le dé que le MJ lui a demandé (le tirage reste fait par l'hôte).
func _cmd_roll_answer(player: Dictionary, payload: Dictionary) -> String:
	var message := _message(String(payload.get("message_id", "")))
	if message.is_empty():
		return "Demande de jet introuvable."
	var kind := String(message.get("kind", ""))
	var request: Dictionary = message.get("request", {})
	if kind == Protocol.KIND_ACTION:
		if message.from != player.id or message.status != Protocol.ACTION_ROLL:
			return "Aucun jet n'est attendu pour cette action."
	elif kind == Protocol.KIND_ROLL_REQUEST:
		if message.to != player.id or message.status != "open":
			return "Ce jet a déjà été lancé."
	else:
		return "Ce message n'attend pas de jet."
	var result := Dice.roll(String(request.get("expr", "d20")), _rng)
	if not result.ok:
		return result.error
	message.roll = _roll_view(result, int(request.get("difficulty", 0)))
	message.status = Protocol.ACTION_ROLLED if kind == Protocol.KIND_ACTION else "done"
	_update_message(message)
	if kind == Protocol.KIND_ROLL_REQUEST and request.get("public", true):
		var label := String(request.get("label", ""))
		_add_message({
			"kind": Protocol.KIND_ROLL, "from": player.id, "from_name": _speaker_name(player.id), "to": Protocol.TO_ALL,
			"text": label if label != "" else "Jet demandé par le MJ", "roll": message.roll,
		})
	return ""


func _roll_view(result: Dictionary, difficulty: int) -> Dictionary:
	var view := {"expr": result.expr, "detail": Dice.describe(result), "total": result.total}
	if difficulty > 0:
		view.difficulty = difficulty
		view.success = int(result.total) >= difficulty
	return view


## Demande au joueur auteur d'une action de lancer lui-même son dé.
func mj_request_action_roll(message_id: String, expr: String, difficulty: int = 0) -> String:
	var message := _message(message_id)
	if message.is_empty() or message.get("kind", "") != Protocol.KIND_ACTION:
		return "Action introuvable."
	var check := Dice.roll(expr, RandomNumberGenerator.new())
	if not check.ok:
		return check.error
	message.status = Protocol.ACTION_ROLL
	message.request = {"expr": check.expr, "difficulty": maxi(0, difficulty)}
	message.roll = {}
	_update_message(message)
	return ""


## Demande un jet à un joueur, hors action (ex. « Perception, difficulté 12 »).
func mj_request_roll(player_id: String, expr: String, label: String, difficulty: int = 0, public: bool = true) -> String:
	if not players.has(player_id):
		return "Joueur introuvable."
	var check := Dice.roll(expr, RandomNumberGenerator.new())
	if not check.ok:
		return check.error
	_add_message({
		"kind": Protocol.KIND_ROLL_REQUEST, "from": Protocol.MJ_ID, "from_name": session.mj_name, "to": player_id,
		"text": Protocol.sanitize_text(label, 80), "status": "open", "roll": {},
		"request": {"expr": check.expr, "difficulty": maxi(0, difficulty), "label": Protocol.sanitize_text(label, 80), "public": public},
	})
	return ""


func mj_resolve_action(message_id: String, status: String, result_text: String, roll_expr: String = "") -> String:
	var message := _message(message_id)
	if message.is_empty() or message.get("kind", "") != Protocol.KIND_ACTION:
		return "Action introuvable."
	if status not in [Protocol.ACTION_RESOLVED, Protocol.ACTION_REFUSED, Protocol.ACTION_PENDING]:
		return "Statut invalide."
	if roll_expr.strip_edges() != "":
		var result := Dice.roll(roll_expr, _rng)
		if not result.ok:
			return result.error
		message.roll = _roll_view(result, int(message.get("request", {}).get("difficulty", 0)))
	message.status = status
	message.result = Protocol.sanitize_text(result_text)
	_update_message(message)
	return ""


func accept_player(player_id: String) -> void:
	var player: Dictionary = players.get(player_id, {})
	if player.is_empty() or player.status == Protocol.STATUS_ACCEPTED:
		return
	player.status = Protocol.STATUS_ACCEPTED
	_unsaved = true
	_log("%s a été accepté." % player.name, "ok")
	if player.online:
		_send_welcome(player)
	_broadcast_players()
	players_changed.emit()


func refuse_player(player_id: String) -> void:
	var player: Dictionary = players.get(player_id, {})
	if player.is_empty():
		return
	player.status = Protocol.STATUS_REFUSED
	_unsaved = true
	_log("%s a été refusé." % player.name, "warn")
	if player.peer_id != 0:
		_send.call(player.peer_id, Protocol.EVT_JOIN_STATUS, {"status": Protocol.STATUS_REFUSED})
		_kick.call(player.peer_id, 0.5)
	_broadcast_players()
	players_changed.emit()


## Déconnecte un joueur sans supprimer sa fiche : il pourra revenir.
func kick_player(player_id: String) -> void:
	var player: Dictionary = players.get(player_id, {})
	if player.is_empty() or player.peer_id == 0:
		return
	_send.call(player.peer_id, Protocol.EVT_SESSION_CLOSED, {"reason": "Le MJ vous a déconnecté. Vous pouvez rejoindre à nouveau."})
	_kick.call(player.peer_id, 0.5)
	_log("%s a été déconnecté par le MJ." % player.name)


## Oublie complètement un joueur (libère son nom et sa place ; sa fiche devient un PNJ).
func remove_player(player_id: String) -> void:
	var player: Dictionary = players.get(player_id, {})
	if player.is_empty():
		return
	if player.peer_id != 0:
		_send.call(player.peer_id, Protocol.EVT_SESSION_CLOSED, {"reason": "Le MJ vous a retiré de la partie."})
		_peer_to_player.erase(player.peer_id)
		_kick.call(player.peer_id, 0.5)
	_token_to_player.erase(player.token)
	_seen_requests.erase(player_id)
	players.erase(player_id)
	if characters.has(player_id):
		var sheet: Dictionary = characters[player_id]
		characters.erase(player_id)
		sheet.id = "npc_" + Protocol.random_hex(4)
		sheet.owner = ""
		characters[sheet.id] = sheet
		for map in maps.values():
			for t in map.tokens:
				if t.owner == player_id:
					t.owner = ""
					t.kind = "npc"
					t.char_id = sheet.id
		_mark("characters")
		_mark("map")
		characters_changed.emit()
	_unsaved = true
	_log("%s a été retiré de la partie." % player.name)
	_broadcast_players()
	players_changed.emit()


func set_players_edit_sheets(enabled: bool) -> void:
	session.players_edit_sheets = enabled
	_unsaved = true
	_broadcast_settings()


# --- Fiches ---

func mj_save_character(sheet_input: Dictionary) -> Dictionary:
	var id := String(sheet_input.get("id", ""))
	var base: Dictionary = characters.get(id, {})
	if base.is_empty():
		return {}
	var sheet := CharacterData.sanitize(sheet_input, base)
	sheet.id = base.id
	sheet.owner = base.owner
	sheet = Rules.refresh(sheet, session.universe)
	characters[id] = sheet
	_sync_pawns_for(id)
	_mark("characters")
	_unsaved = true
	characters_changed.emit()
	return sheet


func mj_create_npc(npc_name: String = "") -> Dictionary:
	var id := "npc_" + Protocol.random_hex(4)
	var sheet := CharacterData.create(universe, id, "", _non_empty(Protocol.sanitize_name(npc_name), "Nouveau PNJ"))
	characters[id] = sheet
	_unsaved = true
	characters_changed.emit()
	return sheet


## Ajoute des PNJ d'un pack (fiches modèles) à la campagne.
func mj_import_npcs(entries: Array) -> int:
	var count := 0
	for entry in entries:
		if not entry is Dictionary:
			continue
		var id := "npc_" + Protocol.random_hex(4)
		var sheet := CharacterData.sanitize(entry, CharacterData.create(universe, id, ""))
		sheet.id = id
		sheet.owner = ""
		characters[id] = sheet
		count += 1
	if count > 0:
		_unsaved = true
		characters_changed.emit()
	return count


func mj_delete_character(id: String) -> void:
	if not characters.has(id) or players.has(id):
		return
	characters.erase(id)
	for map in maps.values():
		for t in map.tokens:
			if t.char_id == id:
				t.char_id = ""
	_unsaved = true
	characters_changed.emit()


## Place le pion d'un PNJ sur la carte affichée.
func mj_place_character(id: String) -> Dictionary:
	var sheet: Dictionary = characters.get(id, {})
	var map: Dictionary = maps.get(active_map, {})
	if sheet.is_empty() or map.is_empty():
		return {}
	for t in map.tokens:
		if t.char_id == id:
			return t
	var p := MapData.free_cell_near(map, int(map.spawn.x), int(map.spawn.y))
	var t := MapData.add_token(map, {
		"kind": "monster" if sheet.get("kind", "") == "monster" else "npc", "name": sheet.name, "x": p.x, "y": p.y,
		"color": sheet.pawn.color, "char_id": id, "hp": sheet.hp, "hp_max": sheet.hp_max, "hidden": true,
	})
	map_changed(map.id, true)
	return t


# --- Cartes ---

func mj_create_map(map_name: String, w: int, h: int, template_id: String = "") -> Dictionary:
	var map: Dictionary
	if template_id != "":
		for t in MapData.templates():
			if t.get("id", "") == template_id:
				map = MapData.from_template(t)
		if map.is_empty():
			return {}
		if map_name.strip_edges() != "":
			map.name = Protocol.sanitize_name(map_name)
	else:
		map = MapData.blank(map_name, w, h)
	maps[map.id] = map
	map_order.append(map.id)
	_unsaved = true
	maps_changed.emit()
	return map


func mj_duplicate_map(map_id: String) -> Dictionary:
	var source: Dictionary = maps.get(map_id, {})
	if source.is_empty():
		return {}
	var map: Dictionary = source.duplicate(true)
	map.id = "map_" + Protocol.random_hex(4)
	map.name = Protocol.sanitize_name(source.name + " (copie)")
	map.tokens = map.tokens.filter(func(t): return t.owner == "")
	maps[map.id] = map
	map_order.append(map.id)
	_unsaved = true
	maps_changed.emit()
	return map


func mj_delete_map(map_id: String) -> void:
	if not maps.has(map_id) or maps.size() <= 1:
		return
	maps.erase(map_id)
	map_order.erase(map_id)
	if active_map == map_id:
		mj_set_active_map(map_order[0])
	_unsaved = true
	maps_changed.emit()


func mj_set_active_map(map_id: String) -> void:
	if not maps.has(map_id):
		return
	active_map = map_id
	_ensure_player_pawns(maps[map_id])
	if Phases.def(phase.type).turns:
		mj_set_phase(phase.type)
	_mark("map")
	_unsaved = true
	maps_changed.emit()
	_system_message("Le groupe se trouve maintenant : %s." % maps[map_id].name)


func mj_update_map(map_id: String, data: Dictionary) -> void:
	var map: Dictionary = maps.get(map_id, {})
	if map.is_empty():
		return
	if data.has("name"):
		map.name = _non_empty(Protocol.sanitize_name(data.name), map.name)
	if data.has("description"):
		map.description = Protocol.sanitize_text(data.description, 500)
	if data.has("players_can_move"):
		map.players_can_move = bool(data.players_can_move)
	if data.has("w") or data.has("h"):
		MapData.resize(map, int(data.get("w", map.w)), int(data.get("h", map.h)))
	if data.has("spawn_x"):
		map.spawn = {"x": clampi(int(data.spawn_x), 0, map.w - 1), "y": clampi(int(data.spawn_y), 0, map.h - 1)}
	map_changed(map_id)


## Peint un disque de terrain. Renvoie true si quelque chose a changé.
func mj_paint(map_id: String, x: int, y: int, code: String, radius: int = 0) -> bool:
	var map: Dictionary = maps.get(map_id, {})
	if map.is_empty():
		return false
	var changed := false
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius + radius:
				changed = MapData.set_cell(map, x + dx, y + dy, code) or changed
	if changed:
		map_changed(map_id)
	return changed


func mj_add_token(map_id: String, data: Dictionary) -> Dictionary:
	var map: Dictionary = maps.get(map_id, {})
	if map.is_empty():
		return {}
	var t := MapData.add_token(map, data)
	map_changed(map_id, true)
	return t


func mj_update_token(map_id: String, token_id: String, data: Dictionary) -> void:
	var map: Dictionary = maps.get(map_id, {})
	var t := MapData.token(map, token_id) if not map.is_empty() else {}
	if t.is_empty():
		return
	data.erase("owner")
	MapData.update_token(t, data, map)
	# Les PV d'un pion de personnage restent synchronisés avec sa fiche.
	var cid: String = t.char_id if t.char_id != "" else t.owner
	if characters.has(cid) and (data.has("hp") or data.has("hp_max")):
		characters[cid].hp = t.hp
		characters[cid].hp_max = t.hp_max
		_mark("characters")
		characters_changed.emit()
	map_changed(map_id, true)


func mj_remove_token(map_id: String, token_id: String) -> void:
	var map: Dictionary = maps.get(map_id, {})
	if map.is_empty():
		return
	map.tokens = map.tokens.filter(func(t): return t.id != token_id)
	phase.order.erase(token_id)
	map_changed(map_id, true)


func mj_add_label(map_id: String, x: int, y: int, text: String, hidden: bool) -> void:
	var map: Dictionary = maps.get(map_id, {})
	if not map.is_empty() and not MapData.add_label(map, x, y, text, hidden).is_empty():
		map_changed(map_id)


func mj_remove_label_at(map_id: String, x: int, y: int) -> bool:
	var map: Dictionary = maps.get(map_id, {})
	if map.is_empty():
		return false
	var before: int = map.labels.size()
	map.labels = map.labels.filter(func(l): return int(l.x) != x or int(l.y) != y)
	if map.labels.size() != before:
		map_changed(map_id)
		return true
	return false


func mj_toggle_label_hidden_at(map_id: String, x: int, y: int) -> void:
	var map: Dictionary = maps.get(map_id, {})
	for l in map.get("labels", []):
		if int(l.x) == x and int(l.y) == y:
			l.hidden = not l.hidden
	map_changed(map_id)


## À appeler après toute modification d'une carte par le MJ. tokens_only : seuls
## les pions ont changé (envoi plus léger que la carte complète).
func map_changed(map_id: String, tokens_only: bool = false) -> void:
	_unsaved = true
	if map_id == active_map:
		_mark("tokens" if tokens_only else "map")
	maps_changed.emit()


# --- Lancement de la partie et phases ---

## « La partie commence ! » : tout le monde passe de la création à la partie.
func mj_start_game(first_phase: String = "exploration") -> void:
	session.started = true
	_ensure_player_pawns(maps.get(active_map, {}))
	_system_message("La partie commence ! Bonne aventure à tous.")
	_broadcast_settings()
	mj_set_phase(first_phase)
	_unsaved = true


## Change de phase. Les phases au tour par tour construisent l'ordre de jeu :
## les joueurs (exploration, dialogue) ou tous les pions visibles par initiative (combat).
func mj_set_phase(type: String, include_hidden: bool = false) -> void:
	if not Phases.DEFS.has(type):
		return
	var previous := String(phase.type)
	if previous == "repos" and type != "repos":
		_end_rest()
	var rules := Phases.def(type)
	phase = {"type": type, "order": [], "turn": 0, "round": 1, "moves_left": 0, "action_used": false, "initiative": {}}
	var map: Dictionary = maps.get(active_map, {})
	if rules.turns and not map.is_empty():
		if rules.who == "players":
			for t in map.tokens:
				if t.kind == "pc" and players.has(String(t.owner)) and int(t.get("hp", 1)) > 0:
					phase.order.append(t.id)
		else:
			for t in map.tokens:
				if t.kind == "object" or (t.hidden and not include_hidden):
					continue
				phase.initiative[t.id] = _rng.randi_range(1, 20) + int(Rules.derived(_sheet_for_token(t), session.universe).initiative)
				phase.order.append(t.id)
			phase.order.sort_custom(func(a, b): return phase.initiative[a] > phase.initiative[b])
		_skip_out_of_combat()
		_begin_turn()
	var text := "Phase : %s. %s" % [rules.name, rules.rules]
	if type == "combat" and not phase.order.is_empty():
		var names: PackedStringArray = []
		for id in phase.order:
			names.append("%s (%d)" % [MapData.token(map, id).name, phase.initiative[id]])
		text += " Initiative : " + ", ".join(names) + "."
	_system_message(text)
	_phase_changed()
	if type == "combat" and previous != "combat" and music.auto_combat:
		var fights := MusicLibrary.by_mood("Combat")
		if not fights.is_empty():
			_music_before_combat = {"track": music.track, "playing": music.playing}
			mj_music(String(fights[_rng.randi_range(0, fights.size() - 1)].id), true)
	elif previous == "combat" and type != "combat" and not _music_before_combat.is_empty():
		mj_music(String(_music_before_combat.track), bool(_music_before_combat.playing))
		_music_before_combat = {}


## Passe au joueur suivant (fin de tour ou décision du MJ).
func mj_next_turn() -> void:
	if not Phases.def(phase.type).turns or phase.order.is_empty():
		return
	_advance_turn()


func mj_turn_move(token_id: String, delta: int) -> void:
	var i: int = phase.order.find(token_id)
	if i < 0:
		return
	var current := _current_token()
	var j := clampi(i + delta, 0, phase.order.size() - 1)
	phase.order.remove_at(i)
	phase.order.insert(j, token_id)
	phase.turn = maxi(0, phase.order.find(current))
	_phase_changed()


func mj_turn_toggle(token_id: String) -> void:
	if not Phases.def(phase.type).turns:
		return
	var current := _current_token()
	if phase.order.has(token_id):
		phase.order.erase(token_id)
	else:
		phase.order.append(token_id)
	if phase.order.has(current):
		phase.turn = phase.order.find(current)
	else:
		phase.turn = clampi(int(phase.turn), 0, maxi(0, phase.order.size() - 1))
		_begin_turn()
	_phase_changed()


func _advance_turn() -> void:
	var map: Dictionary = maps.get(active_map, {})
	for i in phase.order.size():
		phase.turn = int(phase.turn) + 1
		if phase.turn >= phase.order.size():
			phase.turn = 0
			phase.round = int(phase.round) + 1
		var t := MapData.token(map, _current_token())
		if not t.is_empty() and not (int(t.get("hp_max", 0)) > 0 and int(t.get("hp", 1)) <= 0):
			break
	_begin_turn()
	var t := MapData.token(map, _current_token())
	if not t.is_empty() and not t.hidden:
		_system_message("Au tour de %s." % t.name)
	_phase_changed()


func _skip_out_of_combat() -> void:
	var map: Dictionary = maps.get(active_map, {})
	for i in phase.order.size():
		var t := MapData.token(map, _current_token())
		if t.is_empty() or not (int(t.get("hp_max", 0)) > 0 and int(t.get("hp", 1)) <= 0):
			return
		phase.turn = (int(phase.turn) + 1) % phase.order.size()


func _begin_turn() -> void:
	var t := MapData.token(maps.get(active_map, {}), _current_token())
	phase.action_used = false
	phase.moves_left = int(Rules.derived(_sheet_for_token(t), session.universe).speed) if not t.is_empty() else 0
	if int(t.get("speed", 0)) > 0:
		phase.moves_left = int(t.speed)


func _end_rest() -> void:
	for id in characters:
		var c: Dictionary = characters[id]
		if c.owner == "":
			continue
		c.hp = mini(int(c.hp_max), int(c.hp) + maxi(1, int(c.hp_max) / 2))
		c.res = int(c.res_max)
		_sync_pawns_for(id)
	_mark("characters")
	characters_changed.emit()
	_system_message("Fin du repos : chacun récupère la moitié de ses PV et toute son énergie.")


func _current_token() -> String:
	if not Phases.def(phase.type).turns or phase.order.is_empty():
		return ""
	return String(phase.order[clampi(int(phase.turn), 0, phase.order.size() - 1)])


func _phase_changed() -> void:
	_mark("phase")
	_unsaved = true
	phase_changed.emit()


## Vue de la phase pour les joueurs : ordre limité aux pions visibles.
func phase_view_for_player() -> Dictionary:
	var map: Dictionary = maps.get(active_map, {})
	var rules := Phases.def(phase.type)
	var order: Array = []
	for id in phase.order:
		var t := MapData.token(map, id)
		if not t.is_empty() and not t.hidden:
			order.append(id)
	var current := _current_token()
	return {
		"type": phase.type, "name": rules.name, "rules": rules.rules, "turns": rules.turns, "move": rules.move,
		"order": order, "current": current if order.has(current) else "", "round": phase.round,
		"moves_left": phase.moves_left, "action_used": phase.action_used,
	}


# --- Actions de tour (attaque, capacité, objet, fin de tour) ---

func _cmd_turn(player: Dictionary, payload: Dictionary) -> String:
	var map: Dictionary = maps.get(active_map, {})
	var token := MapData.token(map, _current_token())
	if token.is_empty() or token.owner != player.id:
		return "Ce n'est pas votre tour."
	return turn_action(token.id, payload)


## Exécute une action pour le pion dont c'est le tour (joueur, ou MJ pour ses PNJ/monstres).
## payload : {action: "end"|"attack"|"ability"|"item", target, index}
func turn_action(token_id: String, payload: Dictionary) -> String:
	var rules := Phases.def(phase.type)
	if not rules.turns or _current_token() != token_id:
		return "Ce n'est pas le tour de ce pion."
	var action := String(payload.get("action", ""))
	if action == "end":
		_advance_turn()
		return ""
	if phase.action_used:
		return "Vous avez déjà fait votre action ce tour-ci : terminez votre tour."
	var map: Dictionary = maps.get(active_map, {})
	var actor := MapData.token(map, token_id)
	var sheet := _sheet_for_token(actor)
	var target := MapData.token(map, String(payload.get("target", "")))
	var index := int(payload.get("index", 0))
	var error := ""
	match action:
		"attack":
			var list := Rules.weapons(sheet)
			error = _attack(actor, target, Rules.attack_profile(sheet, session.universe, list[clampi(index, 0, list.size() - 1)]), "")
		"ability":
			var abilities: Array = sheet.get("abilities", [])
			if index < 0 or index >= abilities.size():
				return "Capacité introuvable."
			error = _use_ability(actor, sheet, abilities[index], target)
		"item":
			error = _use_item(actor, sheet, index, target)
		_:
			return "Action inconnue."
	if error == "":
		phase.action_used = true
		_phase_changed()
	return error


func _attack(actor: Dictionary, target: Dictionary, profile: Dictionary, ability_name: String) -> String:
	if target.is_empty() or target.id == actor.id:
		return "Choisissez une cible."
	var dist := Rules.distance(Vector2i(int(actor.x), int(actor.y)), Vector2i(int(target.x), int(target.y)))
	if dist > int(profile.range):
		return "Cible hors de portée (%d case%s maximum)." % [profile.range, "s" if int(profile.range) > 1 else ""]
	var defense := int(Rules.derived(_sheet_for_token(target), session.universe).defense)
	if int(target.get("defense", 0)) > 0 and _sheet_for_token(target).get("id", "") == "":
		defense = int(target.defense)
	defense -= int(profile.get("ignore_defense", 0))
	var d20 := _rng.randi_range(1, 20)
	var total := d20 + int(profile.to_hit)
	var hit := d20 == 20 or (d20 != 1 and total >= defense)
	var crit := hit and d20 >= int(profile.crit)
	var damage := 0
	var detail := "d20 = %d %+d = %d contre Défense %d" % [d20, profile.to_hit, total, defense]
	if hit:
		var r := Dice.roll(String(profile.damage), _rng)
		damage = int(r.get("total", 1))
		if crit:
			damage += int(Dice.roll(String(profile.damage), _rng).get("total", 0))
		damage = maxi(1, damage + int(profile.damage_mod))
		_damage_token(target, damage)
	var label := "%s attaque %s avec %s" % [actor.name, target.name, ability_name if ability_name != "" else profile.name]
	var outcome := ("CRITIQUE ! " if crit else "Touché ! ") + "%d dégâts" % damage if hit else ("Échec critique !" if d20 == 1 else "Raté.")
	_add_message({
		"kind": Protocol.KIND_ROLL, "from": _owner_or_mj(actor), "from_name": String(actor.name), "to": Protocol.TO_ALL,
		"text": "%s — %s" % [label, outcome],
		"roll": {"expr": "d20%+d" % int(profile.to_hit), "detail": detail, "total": total, "difficulty": defense, "success": hit},
	})
	if hit and int(target.get("hp", 1)) <= 0:
		_system_message("%s est hors de combat !" % target.name)
	return ""


func _use_ability(actor: Dictionary, sheet: Dictionary, ability: Dictionary, target: Dictionary) -> String:
	var cost := int(ability.get("res_cost", 0))
	var res := int(sheet.get("res", 0))
	if cost > res and sheet.get("id", "") != "":
		return "Pas assez d'énergie (%d nécessaires, %d restants)." % [cost, res]
	var kind := String(ability.get("kind", "effect"))
	var stat_mod := Rules.mod(Rules.stat(sheet, String(ability.get("stat", ""))))
	var error := ""
	match kind:
		"attack":
			var profile := {
				"name": ability.name, "to_hit": stat_mod + int(Rules.derived(sheet, session.universe).attack_bonus),
				"damage": String(ability.get("damage", "1d6")), "damage_mod": stat_mod,
				"crit": 20, "range": maxi(1, int(ability.get("range", 1))),
			}
			error = _attack(actor, target, profile, String(ability.name))
		"heal":
			var who := target if not target.is_empty() else actor
			var dist := Rules.distance(Vector2i(int(actor.x), int(actor.y)), Vector2i(int(who.x), int(who.y)))
			if dist > maxi(0, int(ability.get("range", 0))):
				return "Cible trop loin pour %s." % ability.name
			var amount := maxi(1, int(Dice.roll(String(ability.get("heal", "1d6")), _rng).get("total", 1)) + stat_mod)
			_heal_token(who, amount)
			_system_message("%s utilise %s : %s récupère %d PV." % [actor.name, ability.name, who.name, amount])
		_:
			var on := (" sur " + String(target.name)) if not target.is_empty() else ""
			_system_message("%s utilise %s%s : %s" % [actor.name, ability.name, on, ability.get("description", "")])
	if error == "" and sheet.get("id", "") != "" and characters.has(sheet.id):
		characters[sheet.id].res = maxi(0, res - cost)
		_mark("characters")
		characters_changed.emit()
	return error


func _use_item(actor: Dictionary, sheet: Dictionary, index: int, target: Dictionary) -> String:
	var inv: Array = sheet.get("inventory", [])
	if index < 0 or index >= inv.size() or not characters.has(String(sheet.get("id", ""))):
		return "Objet introuvable."
	var item: Dictionary = inv[index]
	if String(item.get("category", "")) != "consommable" or int(item.get("qty", 1)) <= 0:
		return "Cet objet ne s'utilise pas en action."
	var who := target if not target.is_empty() else actor
	if Rules.distance(Vector2i(int(actor.x), int(actor.y)), Vector2i(int(who.x), int(who.y))) > 1:
		return "Il faut être au contact pour donner un objet."
	var heal_dice := String(item.get("heal", ""))
	if heal_dice != "" and heal_dice != "0":
		var amount := maxi(1, int(Dice.roll(heal_dice, _rng).get("total", 1)))
		_heal_token(who, amount)
		_system_message("%s utilise %s : %s récupère %d PV." % [actor.name, item.name, who.name, amount])
	else:
		_system_message("%s utilise %s. %s" % [actor.name, item.name, item.get("description", "")])
	item.qty = int(item.get("qty", 1)) - 1
	if item.qty <= 0:
		inv.remove_at(index)
	_mark("characters")
	characters_changed.emit()
	return ""


func _damage_token(t: Dictionary, amount: int) -> void:
	_set_token_hp(t, maxi(0, int(t.get("hp", 0)) - amount))


func _heal_token(t: Dictionary, amount: int) -> void:
	_set_token_hp(t, mini(int(t.get("hp_max", 0)) if int(t.get("hp_max", 0)) > 0 else 9999, int(t.get("hp", 0)) + amount))


func _set_token_hp(t: Dictionary, value: int) -> void:
	t.hp = value
	var cid: String = t.char_id if t.char_id != "" else t.owner
	if characters.has(cid):
		characters[cid].hp = value
		_mark("characters")
		characters_changed.emit()
	map_changed(active_map, true)


## Fiche associée à un pion ; pour un pion sans fiche, une fiche minimale tirée du pion.
func _sheet_for_token(t: Dictionary) -> Dictionary:
	if t.is_empty():
		return {}
	var cid: String = t.char_id if t.char_id != "" else t.owner
	if characters.has(cid):
		return characters[cid]
	return {
		"stats": [], "abilities": [], "speed": int(t.get("speed", 0)), "defense": int(t.get("defense", 0)),
		"inventory": [{"name": "Attaque", "category": "arme", "damage": String(t.get("attack", "1d6")) if String(t.get("attack", "")) != "" else "1d6",
			"stat": "", "crit": 20, "range": 1, "equipped": true}],
	}


func _owner_or_mj(t: Dictionary) -> String:
	return String(t.owner) if String(t.get("owner", "")) != "" else Protocol.MJ_ID


# --- Musique ---

## Lance (ou arrête) un morceau. Il est joué chez l'hôte et, si la diffusion est
## active, sur les téléphones (synchronisés sur l'heure de départ).
func mj_music(track: String, playing: bool) -> void:
	if track != "" and MusicLibrary.track(track).is_empty():
		return
	music.track = track
	music.playing = playing and track != ""
	music.started_at = Protocol.now()
	music_changed.emit(music.duplicate())
	_mark("music")


func mj_music_settings(broadcast: bool, auto_combat: bool) -> void:
	music.broadcast = broadcast
	music.auto_combat = auto_combat
	_mark("music")


func music_view_for_player() -> Dictionary:
	if not music.broadcast:
		return {"track": "", "playing": false, "started_at": 0.0}
	return {"track": music.track, "playing": music.playing, "started_at": music.started_at}


# ---------------------------------------------------------------------------
# Diffusion filtrée
# ---------------------------------------------------------------------------

## Règle unique de visibilité des messages : public, ou adressé au joueur, ou écrit par lui.
static func can_see(player_id: String, message: Dictionary) -> bool:
	return message.to == Protocol.TO_ALL or message.to == player_id or message.from == player_id


## Diffusion groupée des changements (appelée chaque image par Net).
func flush() -> void:
	if _dirty.is_empty():
		return
	var dirty := _dirty
	_dirty = {}
	if dirty.has("characters"):
		_broadcast_characters()
	if dirty.has("map"):
		_broadcast_map()
	elif dirty.has("tokens"):
		_broadcast_tokens()
	if dirty.has("phase"):
		var view := phase_view_for_player()
		for player in _accepted_online():
			_send.call(player.peer_id, Protocol.EVT_PHASE, {"phase": view})
	if dirty.has("music"):
		var view := music_view_for_player()
		for player in _accepted_online():
			_send.call(player.peer_id, Protocol.EVT_MUSIC, {"music": view})


func _mark(what: String) -> void:
	_dirty[what] = true


func _accepted_online() -> Array:
	return players.values().filter(func(p): return p.online and p.status == Protocol.STATUS_ACCEPTED)


func _add_message(fields: Dictionary) -> Dictionary:
	var message := {
		"id": "m%d_%s" % [_next_message, session.id.substr(0, 4)],
		"kind": Protocol.KIND_CHAT,
		"ts": Protocol.now(),
	}
	message.merge(fields, true)
	message["to_name"] = _recipient_name(message.to)
	_next_message += 1
	messages.append(message)
	if messages.size() > 2000:
		messages = messages.slice(messages.size() - 2000)
	for player in _accepted_online():
		if can_see(player.id, message):
			_send.call(player.peer_id, Protocol.EVT_CHAT, {"message": message})
	_unsaved = true
	message_added.emit(message)
	return message


func _update_message(message: Dictionary) -> void:
	for player in _accepted_online():
		if can_see(player.id, message):
			_send.call(player.peer_id, Protocol.EVT_MSG_UPDATE, {"message": message})
	_unsaved = true
	message_updated.emit(message)


func _add_roll_message(from_id: String, from_name: String, to: String, result: Dictionary, label: String) -> void:
	_add_message({
		"kind": Protocol.KIND_ROLL, "from": from_id, "from_name": from_name, "to": to,
		"text": label, "roll": {"expr": result.expr, "detail": Dice.describe(result), "total": result.total},
	})


func _system_message(text: String) -> void:
	_add_message({"kind": Protocol.KIND_SYSTEM, "from": Protocol.MJ_ID, "from_name": "Récit", "to": Protocol.TO_ALL, "text": text})


func _send_welcome(player: Dictionary) -> void:
	_ensure_player_pawns(maps.get(active_map, {}))
	var history: Array = []
	for message in messages:
		if can_see(player.id, message):
			history.append(message)
	if history.size() > Protocol.MAX_HISTORY_SENT:
		history = history.slice(history.size() - Protocol.MAX_HISTORY_SENT)
	_send.call(player.peer_id, Protocol.EVT_WELCOME, {
		"session": public_session(),
		"universe": Universe.for_player(universe),
		"you": {"id": player.id, "name": player.name},
		"players": public_players(),
		"messages": history,
		"characters": characters_for(player.id),
		"map": _map_view(),
		"phase": phase_view_for_player(),
		"music": music_view_for_player(),
	})


func public_session() -> Dictionary:
	return {
		"id": session.id, "name": session.name, "mj_name": session.mj_name, "max_players": session.max_players,
		"universe": session.universe, "description": session.get("description", ""),
		"players_edit_sheets": session.players_edit_sheets, "started": session.get("started", false),
	}


func characters_for(player_id: String) -> Array:
	var list: Array = []
	for c in characters.values():
		if c.owner == player_id:
			list.append(c)
		elif c.owner != "":
			list.append(CharacterData.public_view(c))
	return list


func _map_view() -> Dictionary:
	var map: Dictionary = maps.get(active_map, {})
	return MapData.view_for_player(map) if not map.is_empty() else {}


func _broadcast_players() -> void:
	var list := public_players()
	for player in _accepted_online():
		_send.call(player.peer_id, Protocol.EVT_PLAYERS, {"players": list})


func _broadcast_characters() -> void:
	for player in _accepted_online():
		_send.call(player.peer_id, Protocol.EVT_CHARACTERS, {"characters": characters_for(player.id)})


func _broadcast_map() -> void:
	var view := _map_view()
	for player in _accepted_online():
		_send.call(player.peer_id, Protocol.EVT_MAP, {"map": view})


func _broadcast_tokens() -> void:
	var view := _map_view()
	for player in _accepted_online():
		_send.call(player.peer_id, Protocol.EVT_TOKENS, {"map_id": view.get("id", ""), "tokens": view.get("tokens", [])})


func _broadcast_settings() -> void:
	var s := public_session()
	for player in _accepted_online():
		_send.call(player.peer_id, Protocol.EVT_SETTINGS, {"session": s})


## Vue des joueurs destinée aux clients : ni jeton, ni adresse IP.
func public_players() -> Array:
	var list: Array = []
	for player in players.values():
		if player.status == Protocol.STATUS_ACCEPTED:
			list.append({"id": player.id, "name": player.name, "online": player.online})
	return list


## Crée sur la carte les pions des joueurs qui ont une fiche et n'y sont pas encore.
func _ensure_player_pawns(map: Dictionary) -> void:
	if map.is_empty():
		return
	for player in players.values():
		if player.status != Protocol.STATUS_ACCEPTED or not characters.has(player.id):
			continue
		if not MapData.token(map, _pawn_id(player.id)).is_empty():
			continue
		var sheet: Dictionary = characters[player.id]
		var p := MapData.free_cell_near(map, int(map.spawn.x), int(map.spawn.y))
		var t := MapData.add_token(map, {
			"kind": "pc", "name": sheet.name, "x": p.x, "y": p.y, "color": sheet.pawn.color,
			"owner": player.id, "char_id": player.id, "hp": sheet.hp, "hp_max": sheet.hp_max,
		})
		if not t.is_empty():
			t.id = _pawn_id(player.id)
			if map.id == active_map:
				_mark("map")


static func _pawn_id(player_id: String) -> String:
	return "pawn_" + player_id


## Répercute nom, couleur et PV d'une fiche sur ses pions.
func _sync_pawns_for(char_id: String) -> void:
	var sheet: Dictionary = characters.get(char_id, {})
	if sheet.is_empty():
		return
	for map in maps.values():
		for t in map.tokens:
			if t.char_id == char_id or t.owner == char_id:
				t.name = sheet.name
				t.color = sheet.pawn.color
				t.hp = sheet.hp
				t.hp_max = sheet.hp_max
	_ensure_player_pawns(maps.get(active_map, {}))
	_mark("map")
	maps_changed.emit()


func _ack(peer_id: int, req_id: String, ok: bool, error: String = "") -> void:
	_send.call(peer_id, Protocol.EVT_ACK, {"req_id": req_id, "ok": ok, "error": error})


func _valid_mj_target(to: String) -> bool:
	return to == Protocol.TO_ALL or players.has(to)


func _speaker_name(player_id: String) -> String:
	var player: Dictionary = players.get(player_id, {})
	var sheet: Dictionary = characters.get(player_id, {})
	if not sheet.is_empty() and String(sheet.name) != "" and sheet.name != player.get("name", ""):
		return "%s (%s)" % [sheet.name, player.get("name", "?")]
	return String(player.get("name", "?"))


func _recipient_name(to: String) -> String:
	if to == Protocol.TO_ALL:
		return "Tout le groupe"
	if to == Protocol.TO_MJ:
		return session.mj_name
	return String(players.get(to, {}).get("name", "?"))


func _message(message_id: String) -> Dictionary:
	for i in range(messages.size() - 1, -1, -1):
		if messages[i].id == message_id:
			return messages[i]
	return {}


func pending_actions() -> Array:
	return messages.filter(func(m): return m.get("kind", "") == Protocol.KIND_ACTION and m.get("status", "") in [Protocol.ACTION_PENDING, Protocol.ACTION_ROLL, Protocol.ACTION_ROLLED])


func peer_id_of(player_id: String) -> int:
	return int(players.get(player_id, {}).get("peer_id", 0))


func count_online() -> int:
	return _accepted_online().size()


func count_status(status: String) -> int:
	var n := 0
	for p in players.values():
		if p.status == status:
			n += 1
	return n


func discovery_payload() -> Dictionary:
	return {
		"app": Protocol.APP_ID,
		"proto": Protocol.VERSION,
		"name": session.name,
		"mj": session.mj_name,
		"port": session.port,
		"players": count_online(),
		"max": session.max_players,
	}


func _player_for_peer(peer_id: int) -> Dictionary:
	var player_id: String = _peer_to_player.get(peer_id, "")
	return players.get(player_id, {})


func _count_seats() -> int:
	var n := 0
	for p in players.values():
		if p.status != Protocol.STATUS_REFUSED:
			n += 1
	return n


func _check_rate(peer_id: int) -> bool:
	var now := Protocol.now()
	var stamps: Array = _rate.get(peer_id, [])
	while not stamps.is_empty() and now - float(stamps[0]) > Protocol.RATE_LIMIT_WINDOW:
		stamps.pop_front()
	if stamps.size() >= Protocol.RATE_LIMIT_COUNT:
		_rate[peer_id] = stamps
		return false
	stamps.append(now)
	_rate[peer_id] = stamps
	return true


func _register_auth_failure(ip: String) -> void:
	var entry: Dictionary = _auth_failures.get(ip, {"count": 0, "until": 0.0})
	entry.count += 1
	if entry.count >= Protocol.AUTH_MAX_FAILURES:
		entry.count = 0
		entry.until = Protocol.now() + Protocol.AUTH_LOCKOUT_SECONDS
	_auth_failures[ip] = entry


func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _log(text: String, kind: String = "info") -> void:
	var entry := {"ts": Protocol.now(), "text": text, "kind": kind}
	connection_log.append(entry)
	if connection_log.size() > 300:
		connection_log.pop_front()
	log_added.emit(entry)


static func _non_empty(value: String, fallback: String) -> String:
	return value if value.strip_edges() != "" else fallback


# ---------------------------------------------------------------------------
# Sauvegarde
# ---------------------------------------------------------------------------

func has_unsaved_changes() -> bool:
	return _unsaved


func save() -> String:
	var players_out := {}
	for p in players.values():
		players_out[p.id] = {"id": p.id, "name": p.name, "token": p.token, "status": p.status, "joined_at": p.joined_at, "last_seen": p.last_seen}
	var error := CampaignStore.save({
		"session": session, "players": players_out, "characters": characters, "maps": maps,
		"map_order": map_order, "active_map": active_map, "messages": messages, "next_message": _next_message, "music": music,
	})
	if error == "":
		_unsaved = false
	saved.emit(error)
	return error


func _load(data: Dictionary, settings: Dictionary) -> void:
	session = data.session
	_apply_runtime_settings(settings)
	universe = Universe.get_by_id(String(session.get("universe", Universe.DEFAULT_ID)))
	for p in (data.get("players", {}) as Dictionary).values():
		var player := {
			"id": String(p.id), "name": String(p.name), "token": String(p.token), "status": String(p.status),
			"peer_id": 0, "ip": "", "online": false, "joined_at": float(p.get("joined_at", 0)),
			"last_seen": float(p.get("last_seen", 0)), "disconnects": 0,
		}
		players[player.id] = player
		_token_to_player[player.token] = player.id
	for c in (data.get("characters", {}) as Dictionary).values():
		var sheet := CharacterData.sanitize(c, CharacterData.create(universe, String(c.id), String(c.get("owner", ""))))
		characters[sheet.id] = sheet
	for m in (data.get("maps", {}) as Dictionary).values():
		m.w = int(m.w)
		m.h = int(m.h)
		m.spawn = {"x": int(m.spawn.x), "y": int(m.spawn.y)}
		for t in m.tokens:
			for key in ["x", "y", "hp", "hp_max"]:
				t[key] = int(t[key])
		for l in m.labels:
			l.x = int(l.x)
			l.y = int(l.y)
		maps[m.id] = m
	map_order = (data.get("map_order", maps.keys()) as Array).filter(func(id): return maps.has(id))
	active_map = String(data.get("active_map", ""))
	if not maps.has(active_map):
		active_map = map_order[0] if not map_order.is_empty() else ""
	messages = data.get("messages", [])
	_next_message = int(data.get("next_message", messages.size() + 1))
	if data.get("music") is Dictionary:
		music.merge(data.music, true)
		music.playing = false
	_log("Campagne « %s » chargée." % session.name, "ok")
