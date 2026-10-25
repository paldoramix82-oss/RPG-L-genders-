class_name SessionServer
extends RefCounted
## État officiel de la session, côté PC du maître du jeu (serveur autoritaire).
##
## Cette classe ne connaît pas ENet : elle reçoit des identifiants de pairs et
## envoie des événements via les Callables fournies par Net. Elle décide seule
## de ce qui est valide et de ce que chaque client a le droit de recevoir.

signal players_changed
signal message_added(message: Dictionary)
signal log_added(entry: Dictionary)

var session := {}
## player_id -> fiche de connexion (contient le jeton secret : jamais envoyée telle quelle).
var players := {}
var messages: Array[Dictionary] = []
var connection_log: Array[Dictionary] = []

var _send: Callable  # func(peer_id: int, evt: String, payload: Dictionary)
var _kick: Callable  # func(peer_id: int, delay: float)
var _peer_to_player := {}
var _token_to_player := {}
var _seen_requests := {}  # player_id -> Array[String] (anti-doublons)
var _rate := {}  # peer_id -> Array[float]
var _auth_failures := {}  # ip -> {count, until}
var _next_message := 1


func _init(settings: Dictionary, send: Callable, kick: Callable) -> void:
	_send = send
	_kick = kick
	session = {
		"id": Protocol.random_hex(8),
		"code": Protocol.generate_code(),
		"name": Protocol.sanitize_name(settings.get("name", "")) if settings.get("name", "") != "" else "Partie sans nom",
		"mj_name": Protocol.sanitize_name(settings.get("mj_name", "")) if settings.get("mj_name", "") != "" else "Maître du jeu",
		"max_players": clampi(int(settings.get("max_players", Protocol.DEFAULT_MAX_PLAYERS)), 1, Protocol.MAX_PLAYERS_LIMIT),
		"auto_accept": bool(settings.get("auto_accept", false)),
		"port": int(settings.get("port", Protocol.DEFAULT_PORT)),
		"created": Protocol.now(),
	}
	if settings.has("code") and String(settings.code) != "":
		session.code = Protocol.normalize_code(settings.code)


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
		return _reject("Version du jeu différente de celle du MJ. Installez la même version (protocole v%d)." % Protocol.VERSION)

	if Protocol.normalize_code(String(request.get("code", ""))) != session.code:
		_register_auth_failure(ip)
		_log("Code invalide depuis %s." % ip, "warn")
		return _reject("Code de partie invalide.")

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
		_:
			error = "Commande inconnue."

	if error == "":
		seen.append(req_id)
		if seen.size() > 200:
			seen = seen.slice(seen.size() - 200)
		_seen_requests[player.id] = seen
	_ack(peer_id, req_id, error == "", error)


func _cmd_chat_send(player: Dictionary, payload: Dictionary) -> String:
	var to := String(payload.get("to", "")) if payload.get("to") is String else ""
	if to != Protocol.TO_ALL and to != Protocol.TO_MJ:
		return "Destinataire invalide."
	var text := Protocol.sanitize_text(payload.get("text", ""))
	if text == "":
		return "Message vide."
	_add_message(player.id, player.name, to, text)
	return ""


# ---------------------------------------------------------------------------
# Actions du maître du jeu (appelées directement par l'interface du PC)
# ---------------------------------------------------------------------------

## to : Protocol.TO_ALL ou l'identifiant d'un joueur (message privé).
func mj_send_message(to: String, text: String) -> bool:
	text = Protocol.sanitize_text(text)
	if text == "":
		return false
	if to != Protocol.TO_ALL and not players.has(to):
		return false
	_add_message(Protocol.MJ_ID, session.mj_name, to, text)
	return true


func accept_player(player_id: String) -> void:
	var player: Dictionary = players.get(player_id, {})
	if player.is_empty() or player.status == Protocol.STATUS_ACCEPTED:
		return
	player.status = Protocol.STATUS_ACCEPTED
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


## Oublie complètement un joueur (libère son nom et sa place).
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
	_log("%s a été retiré de la partie." % player.name)
	_broadcast_players()
	players_changed.emit()


func peer_id_of(player_id: String) -> int:
	return int(players.get(player_id, {}).get("peer_id", 0))


func count_online() -> int:
	var n := 0
	for p in players.values():
		if p.online and p.status == Protocol.STATUS_ACCEPTED:
			n += 1
	return n


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


# ---------------------------------------------------------------------------
# Diffusion filtrée
# ---------------------------------------------------------------------------

## Règle unique de visibilité des messages : public, ou adressé au joueur, ou écrit par lui.
static func can_see(player_id: String, message: Dictionary) -> bool:
	return message.to == Protocol.TO_ALL or message.to == player_id or message.from == player_id


func _add_message(from_id: String, from_name: String, to: String, text: String) -> void:
	var message := {
		"id": "m%d_%s" % [_next_message, session.id.substr(0, 4)],
		"ts": Protocol.now(),
		"from": from_id,
		"from_name": from_name,
		"to": to,
		"to_name": _recipient_name(to),
		"text": text,
	}
	_next_message += 1
	messages.append(message)
	for player in players.values():
		if player.online and player.status == Protocol.STATUS_ACCEPTED and can_see(player.id, message):
			_send.call(player.peer_id, Protocol.EVT_CHAT, {"message": message})
	message_added.emit(message)


func _send_welcome(player: Dictionary) -> void:
	var history: Array[Dictionary] = []
	for message in messages:
		if can_see(player.id, message):
			history.append(message)
	if history.size() > Protocol.MAX_HISTORY_SENT:
		history = history.slice(history.size() - Protocol.MAX_HISTORY_SENT)
	_send.call(player.peer_id, Protocol.EVT_WELCOME, {
		"session": {
			"id": session.id,
			"name": session.name,
			"mj_name": session.mj_name,
			"max_players": session.max_players,
		},
		"you": {"id": player.id, "name": player.name},
		"players": public_players(),
		"messages": history,
	})


func _broadcast_players() -> void:
	var list := public_players()
	for player in players.values():
		if player.online and player.status == Protocol.STATUS_ACCEPTED:
			_send.call(player.peer_id, Protocol.EVT_PLAYERS, {"players": list})


## Vue des joueurs destinée aux clients : ni jeton, ni adresse IP.
func public_players() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for player in players.values():
		if player.status == Protocol.STATUS_ACCEPTED:
			list.append({"id": player.id, "name": player.name, "online": player.online})
	return list


func _ack(peer_id: int, req_id: String, ok: bool, error: String = "") -> void:
	_send.call(peer_id, Protocol.EVT_ACK, {"req_id": req_id, "ok": ok, "error": error})


func _recipient_name(to: String) -> String:
	if to == Protocol.TO_ALL:
		return "Tout le groupe"
	if to == Protocol.TO_MJ:
		return session.mj_name
	return String(players.get(to, {}).get("name", "?"))


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
