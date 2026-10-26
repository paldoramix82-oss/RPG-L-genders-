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
signal quests_changed
signal loot_changed
signal content_changed
## Retours visuels d'une action (le tableau de bord du MJ les anime aussi).
signal fx(list: Array)

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
var phase := {"type": "libre", "order": [], "turn": 0, "round": 1, "moves_left": 0, "ap": 0, "action_used": false, "initiative": {}, "result": ""}
## Catalogue de la campagne (règles, classes, capacités, objets, monstres…), modifiable par le MJ.
var content := {}
## Quêtes données par le MJ (brouillons compris).
var quests: Array = []
## Coffre commun du groupe : objets à se partager.
var loot: Array = []
var combat: Combat
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
	combat = Combat.new(self, _rng)
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
	content = Content.default_for(session.universe)
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
		Protocol.CMD_CHAR_CREATE:
			error = _cmd_char_create(player, payload)
		Protocol.CMD_ITEM:
			error = _cmd_item(player, payload)
		Protocol.CMD_LOOT_TAKE:
			error = _cmd_loot_take(player, payload)
		Protocol.CMD_LEVEL:
			error = _cmd_level(player, payload)
		Protocol.CMD_ABILITY_EQUIP:
			error = _cmd_ability_equip(player, payload)
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


## Le joueur modifie la partie « récit » de sa fiche (nom, histoire, apparence, portrait…).
## Les valeurs de jeu (caractéristiques, PV, objets…) ne sont jamais acceptées d'un téléphone.
func _cmd_char_save(player: Dictionary, payload: Dictionary) -> String:
	var existing: Dictionary = characters.get(player.id, {})
	if not existing.is_empty() and not session.players_edit_sheets:
		return "Le MJ a verrouillé les fiches : demandez-lui les modifications."
	var base := existing if not existing.is_empty() else CharacterData.create(universe, player.id, player.id, player.name, content)
	var input: Variant = payload.get("character")
	if not input is Dictionary:
		return "Fiche invalide."
	var sheet := CharacterData.sanitize_narrative(input, base)
	sheet.id = player.id
	sheet.owner = player.id
	sheet.kind = "pc"
	if String(sheet.name) == "":
		sheet.name = player.name
	var is_new := existing.is_empty()
	if is_new:
		sheet.gold = int(Content.rule(content, "start_gold"))
		sheet.side = "players"
	characters[player.id] = sheet
	_sync_pawns_for(player.id)
	_mark("characters")
	_unsaved = true
	characters_changed.emit()
	if is_new:
		_system_message("%s entre dans l'histoire sous les traits de %s." % [player.name, sheet.name])
	return ""


## Création avec l'assistant : l'hôte construit lui-même la fiche à partir de la classe,
## de la répartition (validée) et des choix d'équipement.
func _cmd_char_create(player: Dictionary, payload: Dictionary) -> String:
	var existing: Dictionary = characters.get(player.id, {})
	if not existing.is_empty() and session.get("started", false) and not session.players_edit_sheets:
		return "La partie a commencé : demandez au MJ pour refaire votre personnage."
	var class_id := String(payload.get("class_id", ""))
	if Rules.get_class_def(content, class_id).is_empty():
		return "Classe inconnue."
	var alloc: Dictionary = payload.get("alloc", {}) if payload.get("alloc") is Dictionary else {}
	var clean_alloc := {}
	for st in Content.stat_names(content):
		var v: Variant = alloc.get(st, 0)
		clean_alloc[st] = int(v) if (v is int or v is float) else 0
	if not Rules.valid_alloc(clean_alloc, content):
		return "Répartition des points invalide (%d points à répartir, entre %d et %d par caractéristique)." % [
			Content.rule(content, "stat_pool"), Content.rule(content, "stat_min"), Content.rule(content, "stat_max")]
	var choices: Array = []
	for c in (payload.get("choices", []) if payload.get("choices") is Array else []):
		choices.append(int(c) if (c is int or c is float) else 0)
	var base := CharacterData.create(universe, player.id, player.id, player.name, content)
	base = CharacterData.sanitize_narrative(payload.get("identity", {}), base)
	if String(base.name) == "":
		base.name = player.name
	var sheet := Rules.build_sheet(base, content, class_id, clean_alloc, choices)
	sheet.id = player.id
	sheet.owner = player.id
	sheet.kind = "pc"
	sheet.side = "players"
	if not existing.is_empty():
		# Refaire son personnage garde la progression et l'or.
		sheet.level = int(existing.get("level", 1))
		sheet.xp = int(existing.get("xp", 0))
		sheet.gold = int(existing.get("gold", sheet.gold))
		sheet = Rules.refresh(sheet, content, true)
	characters[player.id] = sheet
	_sync_pawns_for(player.id)
	_mark("characters")
	_unsaved = true
	characters_changed.emit()
	if existing.is_empty():
		_system_message("%s entre dans l'histoire : %s, %s." % [player.name, sheet.name, Rules.get_class_def(content, class_id).name])
	return ""


## Déplacement au tour par tour : dans les cases restantes ; en combat, un point
## d'action rachète un déplacement complet (vitesse).
func _spend_move(t: Dictionary, x: int, y: int) -> String:
	var rules := Phases.def(phase.type)
	if rules.move != "limit":
		return ""
	if combat.has_flag(t, "root"):
		return "Vous êtes immobilisé : impossible de bouger."
	var dist := Rules.distance(Vector2i(int(t.x), int(t.y)), Vector2i(x, y))
	var speed := int(combat.stats_of(t).speed)
	if int(t.get("speed", 0)) > 0 and not combat.has_sheet(t):
		speed = int(t.speed)
	if dist <= int(phase.moves_left):
		phase.moves_left = int(phase.moves_left) - dist
	elif phase.type == "combat":
		var cost := int(Content.rule(content, "move_ap"))
		if dist > int(phase.moves_left) + speed:
			return "Trop loin : %d case%s maximum (vitesse %d)." % [int(phase.moves_left) + speed, "s" if int(phase.moves_left) + speed > 1 else "", speed]
		if int(phase.get("ap", 0)) < cost:
			return "Plus de points d'action pour vous déplacer."
		phase.ap = int(phase.ap) - cost
		phase.moves_left = int(phase.moves_left) + speed - dist
	else:
		return "Trop loin : il vous reste %d case%s de déplacement." % [phase.moves_left, "s" if int(phase.moves_left) > 1 else ""]
	_mark("phase")
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
	var other := MapData.token_at(map, x, y)
	if not other.is_empty() and other.id != t.id:
		return "Case occupée."
	if rules.turns:
		if _current_token() != t.id:
			return "Ce n'est pas votre tour."
		var error := _spend_move(t, x, y)
		if error != "":
			return error
	elif combat.has_flag(t, "root"):
		return "Vous êtes immobilisé."
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
	sheet = Rules.refresh(sheet, content)
	_mj_log("Fiche de %s modifiée par le MJ." % sheet.name)
	characters[id] = sheet
	_sync_pawns_for(id)
	_mark("characters")
	_unsaved = true
	characters_changed.emit()
	return sheet


func mj_create_npc(npc_name: String = "") -> Dictionary:
	var id := "npc_" + Protocol.random_hex(4)
	var sheet := CharacterData.create(universe, id, "", _non_empty(Protocol.sanitize_name(npc_name), "Nouveau PNJ"), content)
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
		var raw: Dictionary = entry.duplicate(true)
		raw.id = id
		raw.owner = ""
		if Migrate.needs(raw):
			raw = Migrate.sheet(raw, content, universe)
		var sheet := CharacterData.sanitize(raw, CharacterData.create(universe, id, "", "", content))
		sheet.id = id
		sheet.owner = ""
		if String(sheet.get("kind", "")) == "monster":
			sheet.side = "enemies"
			sheet.xp_reward = maxi(int(sheet.get("xp_reward", 0)), int(sheet.hp_max))
			if String(sheet.get("loot", "")) == "":
				sheet.loot = "bete"
		for a in sheet.abilities:
			a.equipped = true
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
	if data.has("fog"):
		map.fog_of_war = bool(data.fog)
	if data.has("w") or data.has("h"):
		MapData.resize(map, int(data.get("w", map.w)), int(data.get("h", map.h)))
		map.erase("explored")
	if data.has("spawn_x"):
		map.spawn = {"x": clampi(int(data.spawn_x), 0, map.w - 1), "y": clampi(int(data.spawn_y), 0, map.h - 1)}
	map_changed(map_id)


## Le groupe oublie ce qu'il a exploré sur cette carte (brouillard complet).
func mj_reset_fog(map_id: String) -> void:
	var map: Dictionary = maps.get(map_id, {})
	if map.is_empty():
		return
	map.erase("explored")
	map_changed(map_id)


## Aperçu pour le MJ : réunion de ce que voient et ont exploré tous les joueurs.
func fog_preview(map_id: String) -> Dictionary:
	var map: Dictionary = maps.get(map_id, {})
	if map.is_empty() or not Vision.enabled(map):
		return {}
	var seen := {}
	var explored := "0".repeat(int(map.w) * int(map.h))
	for p in players.values():
		seen.merge(Vision.visible_for(map, String(p.id), characters, content))
		var e := String(map.get("explored", {}).get(String(p.id), ""))
		if e.length() == explored.length():
			var a := explored.to_ascii_buffer()
			var b := e.to_ascii_buffer()
			for i in a.size():
				if b[i] == 49:
					a[i] = 49
			explored = a.get_string_from_ascii()
	return {"explored": Vision.explore(map, explored, seen), "visible": Vision.mask(map, seen)}


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
	if previous == "combat" and type != "combat":
		combat.end_combat()
	var rules := Phases.def(type)
	phase = {"type": type, "order": [], "turn": 0, "round": 1, "moves_left": 0, "ap": 0, "action_used": false, "initiative": {}, "result": ""}
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
				phase.initiative[t.id] = _rng.randi_range(1, 20) + int(combat.stats_of(t).initiative)
				phase.order.append(t.id)
			phase.order.sort_custom(func(a, b): return phase.initiative[a] > phase.initiative[b])
		_skip_out_of_combat()
	var text := "Phase : %s. %s" % [rules.name, rules.rules]
	if type == "combat" and not phase.order.is_empty():
		var names: PackedStringArray = []
		for id in phase.order:
			names.append("%s (%d)" % [MapData.token(map, id).name, phase.initiative[id]])
		text += " Initiative : " + ", ".join(names) + "."
	_system_message(text)
	if rules.turns and not phase.order.is_empty():
		_start_turn_loop()
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
		if not t.is_empty() and not combat.is_ko(t):
			break
	_start_turn_loop()
	_phase_changed()


## Démarre le tour du pion courant ; un pion étourdi (ou mis à terre par un effet
## de début de tour) passe automatiquement au suivant.
func _start_turn_loop() -> void:
	var map: Dictionary = maps.get(active_map, {})
	for guard in phase.order.size() + 1:
		var t := MapData.token(map, _current_token())
		if t.is_empty():
			return
		if not t.hidden:
			_system_message("Au tour de %s." % t.name)
		if combat.begin_turn(t) or String(phase.get("result", "")) != "":
			return
		# Tour perdu : au suivant.
		for i in phase.order.size():
			phase.turn = int(phase.turn) + 1
			if phase.turn >= phase.order.size():
				phase.turn = 0
				phase.round = int(phase.round) + 1
			var nt := MapData.token(map, _current_token())
			if not nt.is_empty() and not combat.is_ko(nt):
				break


func _skip_out_of_combat() -> void:
	var map: Dictionary = maps.get(active_map, {})
	for i in phase.order.size():
		var t := MapData.token(map, _current_token())
		if t.is_empty() or not (int(t.get("hp_max", 0)) > 0 and int(t.get("hp", 1)) <= 0):
			return
		phase.turn = (int(phase.turn) + 1) % phase.order.size()


func _begin_turn() -> void:
	combat.begin_turn(MapData.token(maps.get(active_map, {}), _current_token()))


func _end_rest() -> void:
	for id in characters:
		var c: Dictionary = characters[id]
		if c.owner == "":
			continue
		c.hp = mini(int(c.hp_max), int(c.hp) + maxi(1, int(c.hp_max) * int(Content.rule(content, "rest_hp_pct")) / 100))
		c.res = int(c.res_max)
		_sync_pawns_for(id)
	_mark("characters")
	characters_changed.emit()
	_system_message("Fin du repos : chacun récupère %d %% de ses PV et toute sa ressource." % int(Content.rule(content, "rest_hp_pct")))


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
		"moves_left": phase.moves_left, "action_used": phase.action_used, "ap": int(phase.get("ap", 0)),
		"ap_max": int(Content.rule(content, "ap_per_turn")), "result": String(phase.get("result", "")),
		"initiative": _visible_initiative(order),
	}


func _visible_initiative(order: Array) -> Dictionary:
	var out := {}
	for id in order:
		if phase.initiative.has(id):
			out[id] = phase.initiative[id]
	return out


# --- Actions de tour (attaque, capacité, objet, fin de tour) ---

func _cmd_turn(player: Dictionary, payload: Dictionary) -> String:
	var map: Dictionary = maps.get(active_map, {})
	if not Phases.def(phase.type).turns:
		# Hors tour par tour : capacités et objets utilisables librement par son propre pion.
		var own := MapData.token(map, _pawn_id(player.id))
		if own.is_empty():
			return "Votre pion n'est pas sur la carte."
		if String(payload.get("action", "")) in ["ability", "item"]:
			var err := combat.action(own.id, payload)
			_phase_changed()
			return err
		return "Pas de tour en cours : décrivez votre action au MJ."
	var token := MapData.token(map, _current_token())
	if token.is_empty() or token.owner != player.id:
		return "Ce n'est pas votre tour."
	return turn_action(token.id, payload)


## Exécute une action pour le pion dont c'est le tour (joueur, ou MJ pour ses PNJ / monstres).
## payload : {action: end|quick|power|defend|ability|item|auto, target, index, id, uid, x, y}
func turn_action(token_id: String, payload: Dictionary) -> String:
	var rules := Phases.def(phase.type)
	if not rules.turns or _current_token() != token_id:
		return "Ce n'est pas le tour de ce pion."
	if String(payload.get("action", "")) == "end":
		_advance_turn()
		return ""
	var error := combat.action(token_id, payload)
	_phase_changed()
	return error


## Action du MJ hors tour (ex. faire agir un PNJ pendant le récit libre).
func mj_token_action(token_id: String, payload: Dictionary) -> String:
	if Phases.def(phase.type).turns and _current_token() == token_id:
		return turn_action(token_id, payload)
	var error := combat.action(token_id, payload)
	_phase_changed()
	return error


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
		"hp_max": int(t.get("hp_max", 0)), "effects": t.get("effects", []),
		"inventory": [{"name": "Attaque", "category": "arme", "slot": "arme", "equipped": true,
			"weapon": {"damage": String(t.get("attack", "1d6")) if String(t.get("attack", "")) != "" else "1d6", "stat": "Force", "crit": 20, "range": 1}}],
	}


func _owner_or_mj(t: Dictionary) -> String:
	return String(t.owner) if String(t.get("owner", "")) != "" else Protocol.MJ_ID


# ---------------------------------------------------------------------------
# Progression : expérience, niveaux, apprentissage
# ---------------------------------------------------------------------------

## Donne de l'XP à un personnage ; gère les montées de niveau (points et choix à faire).
func grant_xp(char_id: String, amount: int, reason: String = "", announce: bool = true) -> void:
	var c: Dictionary = characters.get(char_id, {})
	if c.is_empty() or amount == 0:
		return
	c.xp = maxi(0, int(c.get("xp", 0)) + amount)
	if announce:
		_reward_message(char_id, "%s gagne %d XP%s." % [c.name, amount, (" (%s)" % reason) if reason != "" else ""], [{"t": "xp", "text": "%+d XP" % amount}])
	var max_level := int(Content.rule(content, "level_max"))
	while int(c.level) < max_level and int(c.xp) >= Rules.xp_for_level(int(c.level) + 1, content):
		var before := Rules.derived(c, content)
		c.level = int(c.level) + 1
		var pending: Dictionary = c.get("pending", {"stat_points": 0, "picks": 0})
		pending.stat_points = int(pending.get("stat_points", 0)) + int(Content.rule(content, "stat_points_per_level"))
		if int(Content.rule(content, "pick_every_levels")) > 0 and int(c.level) % int(Content.rule(content, "pick_every_levels")) == 0:
			pending.picks = int(pending.get("picks", 0)) + 1
		c.pending = pending
		Rules.refresh(c, content)
		var after := Rules.derived(c, content)
		c.hp = mini(int(c.hp_max), int(c.hp) + maxi(0, int(after.hp_max) - int(before.hp_max)))
		c.res = mini(int(c.res_max), int(c.res) + maxi(0, int(after.res_max) - int(before.res_max)))
		_reward_message(char_id, "%s passe au niveau %d !" % [c.name, c.level],
			[{"t": "level", "text": "Niveau %d" % c.level}, {"t": "info", "text": "Ouvrez votre fiche pour choisir vos améliorations."}], "level")
	_sync_pawns_for(char_id)
	_mark("characters")
	_unsaved = true
	characters_changed.emit()


## Choix de montée de niveau : {stat: "Force"} | {learn: ability_id} | {upgrade: ability_id}
func _cmd_level(player: Dictionary, payload: Dictionary) -> String:
	return apply_level_choice(player.id, payload)


func apply_level_choice(char_id: String, payload: Dictionary) -> String:
	var c: Dictionary = characters.get(char_id, {})
	if c.is_empty():
		return "Fiche introuvable."
	var pending: Dictionary = c.get("pending", {})
	if payload.has("stat"):
		var st := String(payload.stat)
		if st not in Content.stat_names(content):
			return "Caractéristique inconnue."
		if int(pending.get("stat_points", 0)) <= 0:
			return "Aucun point de caractéristique à placer."
		pending.stat_points = int(pending.stat_points) - 1
		if c.get("auto", false):
			var trained: Dictionary = c.get("trained", {})
			trained[st] = int(trained.get(st, 0)) + 1
			c.trained = trained
		else:
			for s in c.stats:
				if s.name == st:
					s.value = int(s.value) + 1
		Rules.refresh(c, content)
		_reward_message(char_id, "%s améliore sa %s." % [c.name, st], [{"t": "level", "text": "%s +1" % st}])
	elif payload.has("learn"):
		if int(pending.get("picks", 0)) <= 0:
			return "Aucun apprentissage disponible."
		var id := String(payload.learn)
		var allowed := Rules.learnable_now(c, content).filter(func(a): return a.id == id)
		if allowed.is_empty():
			return "Cette capacité n'est pas encore accessible."
		pending.picks = int(pending.picks) - 1
		_learn(c, id)
	elif payload.has("upgrade"):
		if int(pending.get("picks", 0)) <= 0:
			return "Aucune amélioration disponible."
		var a := _known_ability(c, String(payload.upgrade))
		if a.is_empty():
			return "Capacité inconnue."
		if int(a.get("rank", 1)) >= int(Content.rule(content, "max_ability_rank")):
			return "%s est déjà au rang maximum." % a.name
		pending.picks = int(pending.picks) - 1
		a.rank = int(a.get("rank", 1)) + 1
		_reward_message(char_id, "%s maîtrise mieux %s (rang %d)." % [c.name, a.name, a.rank], [{"t": "level", "text": "%s rang %d" % [a.name, a.rank]}])
	else:
		return "Choix inconnu."
	c.pending = pending
	_sync_pawns_for(char_id)
	_mark("characters")
	_unsaved = true
	characters_changed.emit()
	return ""


func _known_ability(c: Dictionary, id: String) -> Dictionary:
	for a in c.get("abilities", []):
		if String(a.get("id", "")) == id:
			return a
	return {}


## Ajoute une capacité connue ; elle est équipée s'il reste un emplacement.
func _learn(c: Dictionary, ability_id: String) -> String:
	if not _known_ability(c, ability_id).is_empty():
		return "%s connaît déjà cette capacité." % c.name
	var a := Content.ability_copy(content, ability_id)
	if a.is_empty():
		return "Capacité introuvable."
	var slots := int(Content.rule(content, "slots_basic")) if not a.get("ultimate", false) else int(Content.rule(content, "slots_ultimate"))
	var used := (c.get("abilities", []) as Array).filter(func(x): return x.get("equipped", false) and bool(x.get("ultimate", false)) == bool(a.get("ultimate", false))).size()
	a.equipped = used < slots
	if not c.get("abilities") is Array:
		c.abilities = []
	c.abilities.append(a)
	_reward_message(String(c.id), "%s apprend %s !" % [c.name, a.name],
		[{"t": "level", "text": a.name}, {"t": "info", "text": "Équipée dans la barre rapide." if a.equipped else "Connue (à équiper depuis la fiche)."}])
	return ""


## Équiper / retirer une capacité de la barre rapide.
func _cmd_ability_equip(player: Dictionary, payload: Dictionary) -> String:
	if phase.type == "combat" and not Content.rule(content, "swap_in_combat"):
		return "Le MJ n'autorise pas à changer de capacités en combat."
	return set_ability_equipped(player.id, String(payload.get("id", "")), bool(payload.get("equipped", true)))


func set_ability_equipped(char_id: String, ability_id: String, equipped: bool) -> String:
	var c: Dictionary = characters.get(char_id, {})
	var a := _known_ability(c, ability_id)
	if a.is_empty():
		return "Capacité inconnue."
	if equipped and not a.get("equipped", false):
		var ult := bool(a.get("ultimate", false))
		var slots := int(Content.rule(content, "slots_ultimate" if ult else "slots_basic"))
		var used := (c.abilities as Array).filter(func(x): return x.get("equipped", false) and bool(x.get("ultimate", false)) == ult).size()
		if used >= slots:
			return "Plus d'emplacement libre (%d maximum) : retirez d'abord une capacité." % slots
	a.equipped = equipped
	_mark("characters")
	_unsaved = true
	characters_changed.emit()
	return ""


# ---------------------------------------------------------------------------
# Inventaire et coffre commun
# ---------------------------------------------------------------------------

## {action: equip|unequip|use|drop|give|read, uid, to}
func _cmd_item(player: Dictionary, payload: Dictionary) -> String:
	var c: Dictionary = characters.get(player.id, {})
	if c.is_empty():
		return "Créez d'abord votre personnage."
	var uid := String(payload.get("uid", ""))
	var item := Inventory.find(c, uid)
	if item.is_empty():
		return "Objet introuvable."
	var act := String(payload.get("action", ""))
	var error := ""
	match act:
		"equip", "unequip":
			if phase.type == "combat" and _current_token() != _pawn_id(player.id):
				return "En combat, on ne change d'équipement qu'à son tour."
			error = Inventory.equip(c, uid) if act == "equip" else Inventory.unequip(c, uid)
			if error == "":
				Rules.refresh(c, content)
		"use":
			if Phases.def(phase.type).turns and phase.type == "combat":
				return turn_action(_pawn_id(player.id), {"action": "item", "uid": uid}) if _current_token() == _pawn_id(player.id) else "Ce n'est pas votre tour."
			error = combat.action(_pawn_id(player.id), {"action": "item", "uid": uid, "target": payload.get("target", "")}) if not MapData.token(maps.get(active_map, {}), _pawn_id(player.id)).is_empty() else _use_item_offmap(c, item)
		"read":
			if String(item.get("teaches", "")) == "":
				return "Ce n'est pas un livre de compétence."
			error = _learn(c, String(item.teaches))
			if error == "":
				Inventory.consume(c, uid, 1)
		"drop":
			if String(item.get("category", "")) == "quete":
				return "Un objet de quête ne se jette pas."
			Inventory.consume(c, uid, int(item.get("qty", 1)))
			_system_message("%s se débarrasse de %s." % [c.name, item.name])
		"give":
			var to: Dictionary = characters.get(String(payload.get("to", "")), {})
			if to.is_empty() or to.get("owner", "") == "" or to.id == c.id:
				return "Destinataire introuvable."
			var copy := item.duplicate(true)
			copy.qty = 1 if not item.get("stackable", false) else int(payload.get("qty", item.get("qty", 1)))
			copy.qty = clampi(int(copy.qty), 1, int(item.get("qty", 1)))
			Inventory.consume(c, uid, int(copy.qty))
			copy.uid = "i_" + Protocol.random_hex(5)
			Inventory.add(to, copy)
			_system_message("%s donne %s à %s." % [c.name, copy.name, to.name])
		_:
			return "Action inconnue."
	if error == "":
		_sync_pawns_for(player.id)
		_mark("characters")
		_unsaved = true
		characters_changed.emit()
	return error


func _use_item_offmap(c: Dictionary, item: Dictionary) -> String:
	if (item.get("use", []) as Array).is_empty():
		return "%s ne s'utilise pas." % item.name
	for e in item.use:
		match String(e.get("type", "")):
			"heal":
				var amount := int(e.get("amount", 0)) + int(Dice.roll(String(e.get("dice", "0")), _rng).get("total", 0)) + int(e.get("bonus", 0))
				c.hp = mini(int(c.hp_max), int(c.hp) + maxi(1, amount))
			"restore":
				c.res = clampi(int(c.res) + int(e.get("amount", 0)), 0, int(c.res_max))
	Inventory.consume(c, String(item.uid), 1)
	_system_message("%s utilise %s." % [c.name, item.name])
	return ""


## Ajoute un objet au coffre commun (butin à se partager).
func add_loot(inst: Dictionary, source: String = "") -> void:
	if inst.is_empty():
		return
	var entry := inst.duplicate(true)
	entry.uid = "i_" + Protocol.random_hex(5)
	entry.equipped = false
	entry["from"] = source
	loot.append(entry)
	if loot.size() > 80:
		loot.pop_front()
	_mark("loot")
	_unsaved = true
	loot_changed.emit()


func _cmd_loot_take(player: Dictionary, payload: Dictionary) -> String:
	var c: Dictionary = characters.get(player.id, {})
	if c.is_empty():
		return "Créez d'abord votre personnage."
	return give_loot_to(String(payload.get("uid", "")), player.id)


func give_loot_to(uid: String, char_id: String) -> String:
	var c: Dictionary = characters.get(char_id, {})
	for i in loot.size():
		if String(loot[i].get("uid", "")) == uid:
			var entry: Dictionary = loot[i]
			entry.erase("from")
			if Inventory.add(c, entry).is_empty():
				return "Inventaire plein."
			loot.remove_at(i)
			_system_message("%s prend %s dans le coffre du groupe." % [c.name, entry.name])
			_mark("loot")
			_mark("characters")
			_unsaved = true
			loot_changed.emit()
			characters_changed.emit()
			return ""
	return "Quelqu'un l'a déjà pris."


func mj_loot_remove(uid: String) -> void:
	loot = loot.filter(func(x): return String(x.get("uid", "")) != uid)
	_mark("loot")
	_unsaved = true
	loot_changed.emit()


# ---------------------------------------------------------------------------
# Outils du MJ : récompenses, objets, effets, capacités, ressources
# ---------------------------------------------------------------------------

## Trace d'une intervention manuelle du MJ (visible seulement par lui).
func _mj_log(text: String) -> void:
	_add_message({"kind": Protocol.KIND_SYSTEM, "from": Protocol.MJ_ID, "from_name": "Journal du MJ", "to": Protocol.TO_MJ, "text": text, "mj_log": true})


func _reward_message(char_id: String, text: String, lines: Array = [], banner: String = "") -> void:
	var c: Dictionary = characters.get(char_id, {})
	var to := String(c.get("owner", "")) if String(c.get("owner", "")) != "" else Protocol.TO_MJ
	var msg := {"kind": Protocol.KIND_REWARD, "from": Protocol.MJ_ID, "from_name": "Récompense", "to": Protocol.TO_ALL if to != Protocol.TO_MJ else to,
		"text": text, "lines": lines, "char_id": char_id}
	if banner != "":
		msg.banner = banner
	_add_message(msg)


func mj_give_xp(char_id: String, amount: int, reason: String = "") -> void:
	grant_xp(char_id, amount, reason)
	_mj_log("XP %+d → %s" % [amount, characters.get(char_id, {}).get("name", "?")])


func mj_give_gold(char_id: String, amount: int, reason: String = "") -> void:
	var c: Dictionary = characters.get(char_id, {})
	if c.is_empty() or amount == 0:
		return
	c.gold = maxi(0, int(c.get("gold", 0)) + amount)
	_reward_message(char_id, "%s %s %d pièce%s d'or%s." % [c.name, "reçoit" if amount > 0 else "perd", absi(amount), "s" if absi(amount) > 1 else "",
		(" (%s)" % reason) if reason != "" else ""], [{"t": "gold", "text": "%+d or" % amount}])
	_mj_log("Or %+d → %s" % [amount, c.name])
	_mark("characters")
	_unsaved = true
	characters_changed.emit()


## Donne un objet (identifiant du catalogue ou définition complète créée à la volée).
func mj_give_item(char_id: String, source: Variant, qty: int = 1, announce: bool = true) -> String:
	var c: Dictionary = characters.get(char_id, {})
	if c.is_empty():
		return "Personnage introuvable."
	var def: Variant = source
	if source is Dictionary:
		def = Content.sanitize_item(source, content)
	var inst := Content.item_instance(content, def, qty)
	if inst.is_empty():
		return "Objet introuvable."
	if Inventory.add(c, inst).is_empty():
		return "Inventaire plein."
	if announce:
		_reward_message(char_id, "%s reçoit %s%s." % [c.name, inst.name, (" ×%d" % qty) if qty > 1 else ""],
			[{"t": "loot", "text": inst.name, "rarity": String(inst.get("rarity", "commun"))}])
	_mj_log("Objet donné : %s ×%d → %s" % [inst.name, qty, c.name])
	_sync_pawns_for(char_id)
	_mark("characters")
	_unsaved = true
	characters_changed.emit()
	return ""


func mj_remove_item(char_id: String, uid: String) -> void:
	var c: Dictionary = characters.get(char_id, {})
	var item := Inventory.find(c, uid)
	if item.is_empty():
		return
	Inventory.consume(c, uid, int(item.get("qty", 1)))
	Rules.refresh(c, content)
	_mj_log("Objet retiré : %s ← %s" % [item.name, c.name])
	_mark("characters")
	_unsaved = true
	characters_changed.emit()


func mj_teach(char_id: String, ability_id: String) -> String:
	var c: Dictionary = characters.get(char_id, {})
	if c.is_empty():
		return "Personnage introuvable."
	var err := _learn(c, ability_id)
	if err == "":
		_mj_log("Capacité apprise : %s → %s" % [Content.get_entry(content, "abilities", ability_id).get("name", ability_id), c.name])
		_mark("characters")
		_unsaved = true
		characters_changed.emit()
	return err


func mj_forget(char_id: String, ability_id: String) -> void:
	var c: Dictionary = characters.get(char_id, {})
	if c.is_empty():
		return
	c.abilities = (c.get("abilities", []) as Array).filter(func(a): return String(a.get("id", "")) != ability_id)
	_mj_log("Capacité retirée : %s ← %s" % [ability_id, c.name])
	_mark("characters")
	_unsaved = true
	characters_changed.emit()


## Ajuste PV / ressource / jauge d'ultime d'un personnage ou d'un pion (delta).
func mj_adjust(token_or_char: String, what: String, delta: int) -> void:
	var map: Dictionary = maps.get(active_map, {})
	var t := MapData.token(map, token_or_char)
	var c: Dictionary = characters.get(token_or_char, {})
	if t.is_empty() and not c.is_empty():
		for tk in map.get("tokens", []):
			if tk.char_id == token_or_char or tk.owner == token_or_char:
				t = tk
	if not t.is_empty() and c.is_empty():
		c = combat.sheet_of(t) if combat.has_sheet(t) else {}
	var name := String(c.get("name", t.get("name", "?")))
	match what:
		"hp":
			if not t.is_empty():
				_set_token_hp(t, clampi(int(t.get("hp", 0)) + delta, 0, maxi(int(t.get("hp_max", 1)), 1)))
			elif not c.is_empty():
				c.hp = clampi(int(c.hp) + delta, 0, int(c.hp_max))
			broadcast_fx([{"token": String(t.get("id", "")), "type": "dmg" if delta < 0 else "heal", "amount": absi(delta)}])
		"res":
			if not c.is_empty():
				c.res = clampi(int(c.get("res", 0)) + delta, 0, int(c.get("res_max", 0)))
		"ult":
			if not c.is_empty():
				c.ult = clampi(int(c.get("ult", 0)) + delta, 0, 100)
	_mj_log("%s %s %+d" % [name, {"hp": "PV", "res": "ressource", "ult": "jauge d'ultime"}.get(what, what), delta])
	_mark("characters")
	_unsaved = true
	characters_changed.emit()
	combat.check_end()
	_phase_changed()


## Modifie une caractéristique de base (fiche libre ou bonus d'entraînement d'une fiche auto).
func mj_set_stat(char_id: String, stat_name: String, delta: int) -> void:
	var c: Dictionary = characters.get(char_id, {})
	if c.is_empty():
		return
	if c.get("auto", false):
		var trained: Dictionary = c.get("trained", {})
		trained[stat_name] = int(trained.get(stat_name, 0)) + delta
		c.trained = trained
	else:
		for s in c.stats:
			if s.name == stat_name:
				s.value = maxi(0, int(s.value) + delta)
	Rules.refresh(c, content)
	_mj_log("%s : %s %+d" % [c.name, stat_name, delta])
	_sync_pawns_for(char_id)
	_mark("characters")
	_unsaved = true
	characters_changed.emit()


## Applique un effet de statut (du catalogue) à un pion de la carte affichée.
func mj_apply_status(token_id: String, status_id: String, turns: int, value: int = 0) -> String:
	var t := MapData.token(maps.get(active_map, {}), token_id)
	if t.is_empty():
		return "Pion introuvable."
	combat._lines = []
	combat._fx = []
	combat._add_status({}, t, {"status": status_id, "turns": turns, "value": value})
	combat._post({"name": "MJ", "owner": ""}, "Effet appliqué par le MJ")
	_mj_log("Effet %s (%d tours) → %s" % [status_id, turns, t.name])
	return ""


func mj_remove_status(token_id: String, index: int) -> void:
	var t := MapData.token(maps.get(active_map, {}), token_id)
	if t.is_empty():
		return
	var list := combat.effects_of(t)
	if index >= 0 and index < list.size():
		_mj_log("Effet retiré : %s ← %s" % [list[index].get("name", "?"), t.name])
		list.remove_at(index)
		combat.touch(t)


## Fiche complète d'un monstre du catalogue (PNJ « monstre » de la campagne).
func mj_create_monster(monster_id: String) -> Dictionary:
	var m := Content.get_entry(content, "monsters", monster_id)
	if m.is_empty():
		return {}
	var id := "npc_" + Protocol.random_hex(4)
	var sheet := CharacterData.create(universe, id, "", String(m.name), content)
	sheet.kind = "monster"
	sheet.side = "enemies"
	sheet.appearance = String(m.get("description", ""))
	var stats: Array = []
	for st in Content.stat_names(content):
		stats.append({"name": st, "value": int(m.get("stats", {}).get(st, 5))})
	sheet.stats = stats
	sheet.hp_max = int(m.get("hp", 20))
	sheet.hp = sheet.hp_max
	sheet.res_max = int(m.get("res", 10))
	sheet.res = sheet.res_max
	sheet.speed = int(m.get("speed", 5))
	sheet.defense_bonus = int(m.get("defense_bonus", 0))
	sheet.xp_reward = int(m.get("xp", 0))
	sheet.loot = String(m.get("loot", ""))
	sheet.concept = "Boss" if m.get("boss", false) else "Monstre"
	sheet.pawn = {"color": String(m.get("color", "#8a6a4a")), "symbol": ""}
	var abilities: Array = []
	for aid in m.get("abilities", []):
		var a := Content.ability_copy(content, String(aid), true)
		if not a.is_empty():
			abilities.append(a)
	sheet.abilities = abilities
	sheet.inventory = [{"uid": "i_" + Protocol.random_hex(5), "item_id": "", "name": "Attaque naturelle", "icon": "claw", "category": "arme",
		"rarity": "commun", "slot": "arme", "qty": 1, "equipped": true, "weapon": m.get("weapon", {"damage": "1d6", "stat": "Force", "crit": 20, "range": 1}),
		"mods": {"damage": int(m.get("power", 2)), "to_hit": int(m.get("power", 2)) / 2}, "description": ""}]
	characters[id] = sheet
	_unsaved = true
	characters_changed.emit()
	return sheet


## Place un monstre du catalogue sur la carte affichée (près de x, y ; caché si demandé).
func mj_spawn_monster(monster_id: String, x: int = -1, y: int = -1, hidden: bool = false) -> Dictionary:
	var sheet := mj_create_monster(monster_id)
	if sheet.is_empty():
		return {}
	var map: Dictionary = maps.get(active_map, {})
	var t := mj_place_character(sheet.id)
	if t.is_empty():
		return {}
	if x >= 0:
		var p := MapData.free_cell_near(map, x, y)
		t.x = p.x
		t.y = p.y
	t.hidden = hidden
	t.kind = "monster"
	if phase.type == "combat" and not hidden:
		phase.initiative[t.id] = _rng.randi_range(1, 20) + int(combat.stats_of(t).initiative)
		phase.order.append(t.id)
		_phase_changed()
	map_changed(active_map, true)
	return t


# ---------------------------------------------------------------------------
# Catalogue : créations du MJ à tout moment
# ---------------------------------------------------------------------------

## Crée ou remplace une entrée du catalogue (objet, capacité, statut, classe, monstre, butin).
func mj_content_save(kind: String, data: Dictionary) -> Dictionary:
	if kind not in Content.KINDS:
		return {}
	var clean := Content.sanitize(kind, data, content)
	if clean.is_empty():
		return {}
	if String(clean.get("id", "")) == "":
		clean.id = Content.make_id("", String(clean.get("name", kind)))
	content[kind][clean.id] = clean
	_unsaved = true
	if kind in Content.PLAYER_KINDS:
		_mark("content")
	content_changed.emit()
	_mj_log("Catalogue : « %s » enregistré (%s)." % [clean.get("name", clean.id), kind])
	return clean


func mj_content_delete(kind: String, id: String) -> void:
	if not content.get(kind, {}).has(id):
		return
	content[kind].erase(id)
	_unsaved = true
	if kind in Content.PLAYER_KINDS:
		_mark("content")
	content_changed.emit()


func mj_set_rules(values: Dictionary) -> void:
	for spec in Content.RULE_FIELDS:
		if values.has(spec[0]):
			content.rules[spec[0]] = clampi(int(values[spec[0]]), int(spec[2]), int(spec[3]))
	if values.has("swap_in_combat"):
		content.rules.swap_in_combat = bool(values.swap_in_combat)
	if values.has("shared_vision"):
		content.rules.shared_vision = bool(values.shared_vision)
		_mark("map")
	for id in characters:
		Rules.refresh(characters[id], content)
	_mark("content")
	_mark("characters")
	_unsaved = true
	content_changed.emit()
	characters_changed.emit()
	_mj_log("Règles de la campagne modifiées.")


## Met à jour les copies d'une capacité chez tous les personnages qui la connaissent.
func mj_push_ability_update(ability_id: String) -> int:
	var def := Content.get_entry(content, "abilities", ability_id)
	var n := 0
	for c in characters.values():
		for a in c.get("abilities", []):
			if String(a.get("id", "")) == ability_id:
				var rank := int(a.get("rank", 1))
				var eq := bool(a.get("equipped", false))
				a.merge(def.duplicate(true), true)
				a.rank = rank
				a.equipped = eq
				n += 1
	if n > 0:
		_mark("characters")
		characters_changed.emit()
	return n


# ---------------------------------------------------------------------------
# Quêtes
# ---------------------------------------------------------------------------

## Crée ou modifie une quête. data : {id?, title, kind: main|side, description,
## objectives: [{text, done}], assigned: [player_id] (vide = tout le groupe),
## rewards: {xp, gold, items: [{item | def, qty}]}, given}
func mj_quest_save(data: Dictionary) -> Dictionary:
	var id := String(data.get("id", ""))
	var quest := _quest(id)
	var is_new := quest.is_empty()
	if is_new:
		quest = {"id": "q_" + Protocol.random_hex(4), "status": "draft", "created": Protocol.now()}
		quests.append(quest)
	quest.title = Protocol.sanitize_text(data.get("title", quest.get("title", "Nouvelle quête")), 80)
	if String(quest.title).strip_edges() == "":
		quest.title = "Nouvelle quête"
	quest.kind = "main" if String(data.get("kind", quest.get("kind", "side"))) == "main" else "side"
	quest.description = Protocol.sanitize_text(data.get("description", quest.get("description", "")), 2000)
	quest.giver = Protocol.sanitize_text(data.get("giver", quest.get("giver", "")), 60)
	var objectives: Array = []
	for o in data.get("objectives", quest.get("objectives", [])):
		if o is Dictionary and String(o.get("text", "")).strip_edges() != "" and objectives.size() < 12:
			objectives.append({"text": Protocol.sanitize_text(o.text, 200), "done": bool(o.get("done", false))})
	quest.objectives = objectives
	var assigned: Array = []
	for p in data.get("assigned", quest.get("assigned", [])):
		if players.has(String(p)):
			assigned.append(String(p))
	quest.assigned = assigned
	var rw: Dictionary = data.get("rewards", quest.get("rewards", {})) if data.get("rewards", quest.get("rewards", {})) is Dictionary else {}
	var items: Array = []
	for it in rw.get("items", []):
		if it is Dictionary:
			if String(it.get("item", "")) != "" and not Content.get_entry(content, "items", String(it.item)).is_empty():
				items.append({"item": String(it.item), "qty": clampi(int(it.get("qty", 1)), 1, 99)})
			elif it.get("def") is Dictionary:
				items.append({"def": Content.sanitize_item(it.def, content), "qty": clampi(int(it.get("qty", 1)), 1, 99)})
	quest.rewards = {"xp": clampi(int(rw.get("xp", 0)), 0, 999999), "gold": clampi(int(rw.get("gold", 0)), 0, 999999), "items": items}
	if data.get("give", false) and quest.status == "draft":
		quest.status = "active"
		quest.given = Protocol.now()
		_announce_quest(quest, "Nouvelle quête")
	_quests_changed()
	return quest


func _quest(id: String) -> Dictionary:
	for q in quests:
		if q.id == id:
			return q
	return {}


func mj_quest_give(id: String) -> void:
	var q := _quest(id)
	if q.is_empty() or q.status != "draft":
		return
	q.status = "active"
	q.given = Protocol.now()
	_announce_quest(q, "Nouvelle quête")
	_quests_changed()


func mj_quest_objective(id: String, index: int, done: bool) -> void:
	var q := _quest(id)
	if q.is_empty() or index < 0 or index >= q.objectives.size():
		return
	q.objectives[index].done = done
	if done and q.status == "active":
		for to in _quest_recipients(q):
			_add_message({"kind": Protocol.KIND_REWARD, "from": Protocol.MJ_ID, "from_name": "Quête", "to": to,
				"text": "Objectif accompli : %s" % q.objectives[index].text, "lines": [{"t": "quest", "text": q.title}]})
	_quests_changed()


## Réussite : les récompenses sont distribuées une seule fois (la quête passe « réussie »).
func mj_quest_complete(id: String) -> void:
	var q := _quest(id)
	if q.is_empty() or q.status in ["done", "failed"]:
		return
	q.status = "done"
	q.finished = Protocol.now()
	for o in q.objectives:
		o.done = true
	var heroes: Array = _quest_heroes(q)
	var rw: Dictionary = q.get("rewards", {})
	var lines: Array = []
	if int(rw.get("xp", 0)) > 0:
		lines.append({"t": "xp", "text": "+%d XP" % int(rw.xp)})
	if int(rw.get("gold", 0)) > 0:
		lines.append({"t": "gold", "text": "+%d or" % int(rw.gold)})
	for it in rw.get("items", []):
		var def: Variant = it.get("def", it.get("item", ""))
		var inst := Content.item_instance(content, def, int(it.get("qty", 1)))
		if inst.is_empty():
			continue
		lines.append({"t": "loot", "text": inst.name + ((" ×%d" % int(inst.qty)) if int(inst.qty) > 1 else ""), "rarity": String(inst.get("rarity", "commun"))})
		if heroes.size() == 1:
			Inventory.add(characters[heroes[0]], inst)
		else:
			add_loot(inst, "Récompense : " + String(q.title))
	for to in _quest_recipients(q):
		_add_message({"kind": Protocol.KIND_REWARD, "from": Protocol.MJ_ID, "from_name": "Quête", "to": to,
			"text": "Quête accomplie : %s" % q.title, "lines": lines, "banner": "quest_done", "quest": q.id})
	for cid in heroes:
		if int(rw.get("gold", 0)) > 0:
			characters[cid].gold = int(characters[cid].get("gold", 0)) + int(rw.gold)
		if int(rw.get("xp", 0)) > 0:
			grant_xp(cid, int(rw.xp), "", false)
	_mark("characters")
	characters_changed.emit()
	_mj_log("Quête réussie : %s (récompenses distribuées)." % q.title)
	_quests_changed()


func mj_quest_fail(id: String) -> void:
	var q := _quest(id)
	if q.is_empty() or q.status in ["done", "failed"]:
		return
	q.status = "failed"
	q.finished = Protocol.now()
	for to in _quest_recipients(q):
		_add_message({"kind": Protocol.KIND_REWARD, "from": Protocol.MJ_ID, "from_name": "Quête", "to": to,
			"text": "Quête échouée : %s" % q.title, "lines": [], "banner": "quest_failed"})
	_quests_changed()


func mj_quest_delete(id: String) -> void:
	quests = quests.filter(func(q): return q.id != id)
	_quests_changed()


func _announce_quest(q: Dictionary, label: String) -> void:
	var lines: Array = [{"t": "quest", "text": "Quête principale" if q.kind == "main" else "Quête secondaire"}]
	for o in q.objectives:
		lines.append({"t": "info", "text": "• " + String(o.text)})
	for to in _quest_recipients(q):
		_add_message({"kind": Protocol.KIND_REWARD, "from": Protocol.MJ_ID, "from_name": "Quête", "to": to,
			"text": "%s : %s" % [label, q.title], "lines": lines, "banner": "quest_new", "quest": q.id})


## Destinataires des annonces : tout le groupe, ou chaque joueur concerné (messages privés).
func _quest_recipients(q: Dictionary) -> Array:
	return [Protocol.TO_ALL] if (q.get("assigned", []) as Array).is_empty() else q.assigned


## Personnages qui reçoivent les récompenses.
func _quest_heroes(q: Dictionary) -> Array:
	var out: Array = []
	var ids: Array = q.get("assigned", []) if not (q.get("assigned", []) as Array).is_empty() else players.keys()
	for id in ids:
		if characters.has(id) and players.has(id) and players[id].status == Protocol.STATUS_ACCEPTED:
			out.append(id)
	return out


func quests_for(player_id: String) -> Array:
	var out: Array = []
	for q in quests:
		if q.status == "draft":
			continue
		if (q.get("assigned", []) as Array).is_empty() or q.assigned.has(player_id):
			out.append(q)
	return out


func _quests_changed() -> void:
	_mark("quests")
	_unsaved = true
	quests_changed.emit()


# ---------------------------------------------------------------------------
# Événements rapides du MJ
# ---------------------------------------------------------------------------

## Narration du MJ (mise en forme « récit », distincte des messages).
func mj_narrate(text: String, to: String = Protocol.TO_ALL, title: String = "") -> bool:
	text = Protocol.sanitize_text(text)
	if text == "" or not _valid_mj_target(to):
		return false
	_add_message({"kind": Protocol.KIND_NARRATION, "from": Protocol.MJ_ID, "from_name": session.mj_name, "to": to, "text": text,
		"title": Protocol.sanitize_text(title, 80)})
	return true


## type : group_damage | group_heal | group_reward | group_check | ambush | trap
func mj_event(type: String, params: Dictionary) -> String:
	var heroes: Array = []
	for p in players.values():
		if characters.has(p.id) and p.status == Protocol.STATUS_ACCEPTED:
			heroes.append(p.id)
	var title := Protocol.sanitize_text(params.get("text", ""), 300)
	match type:
		"group_damage", "group_heal":
			var dice := String(params.get("dice", "1d6"))
			if not Dice.roll(dice, _rng).ok:
				return "Formule de dés invalide."
			var lines: Array = []
			var fxl: Array = []
			for id in heroes:
				var amount := int(Dice.roll(dice, _rng).total)
				var c: Dictionary = characters[id]
				if type == "group_damage":
					c.hp = maxi(0, int(c.hp) - amount)
					lines.append({"t": "dmg", "text": "%s : −%d PV" % [c.name, amount]})
				else:
					c.hp = mini(int(c.hp_max), int(c.hp) + amount)
					lines.append({"t": "heal", "text": "%s : +%d PV" % [c.name, amount]})
				_sync_pawns_for(id)
				fxl.append({"token": _pawn_id(id), "type": "dmg" if type == "group_damage" else "heal", "amount": amount})
			_add_message({"kind": Protocol.KIND_COMBAT, "from": Protocol.MJ_ID, "from_name": session.mj_name, "to": Protocol.TO_ALL,
				"text": title if title != "" else ("Le groupe est blessé !" if type == "group_damage" else "Le groupe reprend des forces."), "lines": lines})
			broadcast_fx(fxl)
		"group_reward":
			var xp := int(params.get("xp", 0))
			var gold := int(params.get("gold", 0))
			for id in heroes:
				if gold != 0:
					characters[id].gold = maxi(0, int(characters[id].get("gold", 0)) + gold)
				if xp > 0:
					grant_xp(id, xp, "", false)
			var lines: Array = []
			if xp > 0:
				lines.append({"t": "xp", "text": "+%d XP pour chacun" % xp})
			if gold != 0:
				lines.append({"t": "gold", "text": "%+d or pour chacun" % gold})
			var item_id := String(params.get("item", ""))
			if item_id != "":
				var inst := Content.item_instance(content, item_id, int(params.get("qty", 1)))
				if not inst.is_empty():
					add_loot(inst, title)
					lines.append({"t": "loot", "text": inst.name, "rarity": String(inst.get("rarity", "commun"))})
			_add_message({"kind": Protocol.KIND_REWARD, "from": Protocol.MJ_ID, "from_name": "Récompense", "to": Protocol.TO_ALL,
				"text": title if title != "" else "Récompense pour le groupe !", "lines": lines, "banner": "reward"})
		"group_check":
			var expr := String(params.get("expr", "d20"))
			for id in heroes:
				var st := String(params.get("stat", ""))
				var e := expr
				if st != "":
					e = "d20+%d" % Rules.stat(characters[id], st, content)
				mj_request_roll(id, e, title if title != "" else "Épreuve", int(params.get("difficulty", 12)), true)
		"ambush":
			var ids: Array = params.get("monsters", [])
			var map: Dictionary = maps.get(active_map, {})
			var center := Vector2i(int(params.get("x", map.get("spawn", {}).get("x", 0))), int(params.get("y", map.get("spawn", {}).get("y", 0))))
			var n := 0
			for mid in ids:
				var t := mj_spawn_monster(String(mid), center.x + _rng.randi_range(-3, 3), center.y + _rng.randi_range(-3, 3), false)
				if not t.is_empty():
					n += 1
			if n == 0:
				return "Aucun monstre placé."
			if title != "":
				mj_narrate(title)
			mj_set_phase("combat")
		_:
			return "Événement inconnu."
	_mark("characters")
	_unsaved = true
	characters_changed.emit()
	_mj_log("Événement : %s" % type)
	return ""


## Tire une table de butin (le MJ voit le résultat puis choisit où le mettre).
func mj_roll_loot(table_id: String) -> Dictionary:
	return Inventory.roll_loot(content, table_id, _rng)


## Retours visuels (chiffres flottants…) à tous les téléphones et au tableau du MJ.
func broadcast_fx(list: Array) -> void:
	var map: Dictionary = maps.get(active_map, {})
	var visible: Array = list.filter(func(f): return not MapData.token(map, String(f.get("token", ""))).get("hidden", false))
	for player in _accepted_online():
		var ids: Variant = _visible_tokens_for(player.id)
		var mine: Array = visible if ids == null else visible.filter(func(f): return (ids as Dictionary).has(String(f.get("token", ""))))
		if not mine.is_empty():
			_send.call(player.peer_id, Protocol.EVT_FX, {"fx": mine})
	fx.emit(list)


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
	if dirty.has("content"):
		var view := Content.for_player(content)
		for player in _accepted_online():
			_send.call(player.peer_id, Protocol.EVT_CONTENT, {"content": view})
	if dirty.has("quests"):
		for player in _accepted_online():
			_send.call(player.peer_id, Protocol.EVT_QUESTS, {"quests": quests_for(player.id)})
	if dirty.has("loot"):
		for player in _accepted_online():
			_send.call(player.peer_id, Protocol.EVT_LOOT, {"loot": loot})


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
		"map": _map_view(player.id),
		"phase": phase_view_for_player(),
		"music": music_view_for_player(),
		"content": Content.for_player(content),
		"quests": quests_for(player.id),
		"loot": loot,
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


## Carte active vue par un joueur : sans les pions cachés ni les notes du MJ et,
## avec le brouillard de guerre, seulement ce que son personnage voit (pions,
## étiquettes des zones explorées) + l'état du brouillard pour l'affichage.
func _map_view(player_id: String = "") -> Dictionary:
	var map: Dictionary = maps.get(active_map, {})
	if map.is_empty():
		return {}
	var view := MapData.view_for_player(map)
	if player_id == "" or not Vision.enabled(map):
		return view
	var seen := Vision.visible_for(map, player_id, characters, content)
	if not map.get("explored") is Dictionary:
		map["explored"] = {}
	var before := String(map.explored.get(player_id, ""))
	var explored := Vision.explore(map, before, seen)
	if explored != before:
		map.explored[player_id] = explored
		_unsaved = true
	var w := int(map.w)
	view["fog"] = {"explored": explored, "visible": Vision.mask(map, seen)}
	view["tokens"] = (view.tokens as Array).filter(func(t):
		return String(t.get("owner", "")) == player_id or seen.has(int(t.y) * w + int(t.x)))
	view["labels"] = (view.labels as Array).filter(func(l): return Vision.is_set(explored, map, int(l.x), int(l.y)))
	return view


## Pions qu'un joueur voit en ce moment (null : tous les pions non cachés).
func _visible_tokens_for(player_id: String) -> Variant:
	var map: Dictionary = maps.get(active_map, {})
	if map.is_empty() or not Vision.enabled(map):
		return null
	var ids := {}
	for t in _map_view(player_id).get("tokens", []):
		ids[String(t.id)] = true
	return ids


func _broadcast_players() -> void:
	var list := public_players()
	for player in _accepted_online():
		_send.call(player.peer_id, Protocol.EVT_PLAYERS, {"players": list})


func _broadcast_characters() -> void:
	for player in _accepted_online():
		_send.call(player.peer_id, Protocol.EVT_CHARACTERS, {"characters": characters_for(player.id)})


func _broadcast_map() -> void:
	for player in _accepted_online():
		_send.call(player.peer_id, Protocol.EVT_MAP, {"map": _map_view(player.id)})


## Mise à jour légère (déplacements) : pions, et brouillard s'il est actif.
func _broadcast_tokens() -> void:
	for player in _accepted_online():
		var view := _map_view(player.id)
		var payload := {"map_id": view.get("id", ""), "tokens": view.get("tokens", [])}
		if view.has("fog"):
			payload["fog"] = view.fog
			payload["labels"] = view.labels
		_send.call(player.peer_id, Protocol.EVT_TOKENS, payload)


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
				t.effects = sheet.get("effects", []).duplicate(true)
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
		"content": content, "quests": quests, "loot": loot, "phase": phase,
	})
	if error == "":
		_unsaved = false
	saved.emit(error)
	return error


func _load(data: Dictionary, settings: Dictionary) -> void:
	session = data.session
	_apply_runtime_settings(settings)
	universe = Universe.get_by_id(String(session.get("universe", Universe.DEFAULT_ID)))
	var format := int(data.get("format", 1))
	if format > CampaignStore.FORMAT:
		_log("Cette sauvegarde vient d'une version plus récente du jeu : certaines données peuvent manquer.", "warn")
	content = Content.normalize(data.content) if data.get("content") is Dictionary else Content.default_for(String(session.universe))
	if format < 2:
		CampaignStore.backup(String(session.get("id", "")), "v1")
		_log("Ancienne sauvegarde convertie au nouveau système de règles (copie de l'original : %s.json.v1)." % session.get("id", ""), "warn")
	for p in (data.get("players", {}) as Dictionary).values():
		var player := {
			"id": String(p.id), "name": String(p.name), "token": String(p.token), "status": String(p.status),
			"peer_id": 0, "ip": "", "online": false, "joined_at": float(p.get("joined_at", 0)),
			"last_seen": float(p.get("last_seen", 0)), "disconnects": 0,
		}
		players[player.id] = player
		_token_to_player[player.token] = player.id
	for c in (data.get("characters", {}) as Dictionary).values():
		var raw: Dictionary = c
		if Migrate.needs(raw):
			raw = Migrate.sheet(raw, content, universe)
		var sheet := CharacterData.sanitize(raw, CharacterData.create(universe, String(c.id), String(c.get("owner", "")), "", content))
		if players.has(sheet.id):
			sheet.kind = "pc"
			sheet.side = "players"
		characters[sheet.id] = sheet
	for m in (data.get("maps", {}) as Dictionary).values():
		m.w = int(m.w)
		m.h = int(m.h)
		m.spawn = {"x": int(m.spawn.x), "y": int(m.spawn.y)}
		for t in m.tokens:
			for key in ["x", "y", "hp", "hp_max"]:
				t[key] = int(t[key])
			for key in ["defense", "speed"]:
				if t.has(key):
					t[key] = int(t[key])
			if t.get("effects") is Array:
				t.effects = CharacterData.sanitize_effects_list(t.effects)
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
	quests = data.get("quests", []) if data.get("quests") is Array else []
	loot = data.get("loot", []) if data.get("loot") is Array else []
	if data.get("phase") is Dictionary and Phases.DEFS.has(String(data.phase.get("type", ""))):
		phase.merge(data.phase, true)
		for key in ["turn", "round", "moves_left", "ap"]:
			phase[key] = int(phase.get(key, 0))
	_log("Campagne « %s » chargée." % session.name, "ok")
