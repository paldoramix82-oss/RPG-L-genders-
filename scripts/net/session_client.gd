class_name SessionClient
extends RefCounted
## Vue locale de la session côté joueur.
##
## Ne contient que ce que le serveur a accepté d'envoyer. Les commandes sont
## gardées dans une boîte d'envoi jusqu'à l'accusé de réception du serveur :
## après une coupure, elles sont renvoyées, et le serveur ignore les doublons.

signal status_changed(status: String)
signal welcomed
signal players_changed
signal message_received(message: Dictionary)
signal message_updated(message: Dictionary)
signal characters_changed
signal map_changed
signal phase_changed
signal settings_changed
signal music_changed
signal command_failed(req_id: String, error: String)
signal session_closed(reason: String)
signal notice(text: String)
signal content_changed
signal quests_changed
signal loot_changed
## Retours visuels d'une action (dégâts, soins, effets) : [{token, type, amount, text}].
signal fx(list: Array)
## Une commande vient d'être envoyée ou confirmée par l'hôte (indicateur « envoi… »).
signal outbox_changed

var join_status := ""
var session := {}
var universe := {}
var me := {}
var players: Array = []
var messages: Array = []
var characters: Array = []
var map := {}
var phase := {}
var music := {}
## Catalogue visible des joueurs : règles, caractéristiques, classes, capacités, statuts.
var content := {}
var quests: Array = []
## Coffre commun du groupe.
var loot: Array = []

var _send: Callable  # func(cmd: String, payload: Dictionary)
var _outbox := {}  # req_id -> {cmd, payload}
var _req_prefix := Protocol.random_hex(3)
var _req_counter := 0
var _message_index := {}  # id -> index dans messages


func _init(send: Callable) -> void:
	_send = send


func is_accepted() -> bool:
	return join_status == Protocol.STATUS_ACCEPTED


## Envoie une commande au serveur. Le résultat arrive plus tard (ack + événements).
func send_command(cmd: String, payload: Dictionary) -> String:
	_req_counter += 1
	var req_id := "%s-%d" % [_req_prefix, _req_counter]
	payload["req_id"] = req_id
	_outbox[req_id] = {"cmd": cmd, "payload": payload}
	if is_accepted():
		_send.call(cmd, payload)
	outbox_changed.emit()
	return req_id


func send_chat(to: String, text: String) -> String:
	return send_command(Protocol.CMD_CHAT_SEND, {"to": to, "text": text})


func declare_action(to: String, text: String) -> String:
	return send_command(Protocol.CMD_ACTION, {"to": to, "text": text})


func roll(expr: String, to: String, label: String = "") -> String:
	return send_command(Protocol.CMD_ROLL, {"expr": expr, "to": to, "label": label})


func save_character(sheet: Dictionary) -> String:
	return send_command(Protocol.CMD_CHAR_SAVE, {"character": sheet})


## Lance soi-même le dé demandé par le MJ (pour une action ou une demande de jet).
func answer_roll(message_id: String) -> String:
	return send_command(Protocol.CMD_ROLL_ANSWER, {"message_id": message_id})


## Action pendant son tour : end, quick, power, defend, ability (extra.id), item (extra.uid).
func turn_action(action: String, target: String = "", index: int = 0, extra: Dictionary = {}) -> String:
	var payload := {"action": action, "target": target, "index": index}
	payload.merge(extra, true)
	return send_command(Protocol.CMD_TURN, payload)


## Création avec l'assistant : l'hôte construit la fiche (classe, points, équipement, identité).
func create_character(class_id: String, alloc: Dictionary, choices: Array, identity: Dictionary) -> String:
	return send_command(Protocol.CMD_CHAR_CREATE, {"class_id": class_id, "alloc": alloc, "choices": choices, "identity": identity})


## Inventaire : equip, unequip, use, drop, give (extra.to), read.
func item_action(action: String, uid: String, extra: Dictionary = {}) -> String:
	var payload := {"action": action, "uid": uid}
	payload.merge(extra, true)
	return send_command(Protocol.CMD_ITEM, payload)


func take_loot(uid: String) -> String:
	return send_command(Protocol.CMD_LOOT_TAKE, {"uid": uid})


## Montée de niveau : {"stat": nom} | {"learn": id} | {"upgrade": id}.
func level_choice(choice: Dictionary) -> String:
	return send_command(Protocol.CMD_LEVEL, choice)


func equip_ability(ability_id: String, equipped: bool) -> String:
	return send_command(Protocol.CMD_ABILITY_EQUIP, {"id": ability_id, "equipped": equipped})


## Quêtes en cours (principales d'abord).
func active_quests() -> Array:
	var list := quests.filter(func(q): return q.get("status", "") == "active")
	list.sort_custom(func(a, b): return (a.get("kind", "") == "main") and b.get("kind", "") != "main")
	return list


func my_token() -> Dictionary:
	return MapData.token(map, "pawn_" + String(me.get("id", "")))


func is_my_turn() -> bool:
	return phase.get("turns", false) and String(phase.get("current", "")) != "" and phase.current == my_token().get("id", "-")


func game_started() -> bool:
	return bool(session.get("started", false))


func move_pawn(token_id: String, x: int, y: int) -> String:
	return send_command(Protocol.CMD_PAWN_MOVE, {"map_id": String(map.get("id", "")), "token_id": token_id, "x": x, "y": y})


func pending_count() -> int:
	return _outbox.size()


## Après une reconnexion : renvoie tout ce qui n'a pas été confirmé.
func resend_pending() -> void:
	for req_id in _outbox.keys():
		var entry: Dictionary = _outbox[req_id]
		_send.call(entry.cmd, entry.payload)


func my_character() -> Dictionary:
	for c in characters:
		if c.get("id", "") == me.get("id", ""):
			return c
	return {}


func character(char_id: String) -> Dictionary:
	for c in characters:
		if c.get("id", "") == char_id:
			return c
	return {}


func can_edit_sheet() -> bool:
	return my_character().is_empty() or bool(session.get("players_edit_sheets", true))


func player_name(player_id: String) -> String:
	if player_id == Protocol.MJ_ID:
		return String(session.get("mj_name", "MJ"))
	for p in players:
		if p.id == player_id:
			return p.name
	return "?"


func handle_event(evt: Variant, payload: Variant) -> void:
	if typeof(evt) != TYPE_STRING or not payload is Dictionary:
		return
	match evt:
		Protocol.EVT_JOIN_STATUS:
			_set_status(String(payload.get("status", "")))
		Protocol.EVT_WELCOME:
			session = payload.get("session", {})
			universe = payload.get("universe", {})
			me = payload.get("you", {})
			players = payload.get("players", [])
			characters = payload.get("characters", [])
			map = payload.get("map", {})
			phase = payload.get("phase", {})
			music = payload.get("music", {})
			content = payload.get("content", {})
			quests = payload.get("quests", [])
			loot = payload.get("loot", [])
			messages.clear()
			_message_index.clear()
			for m in payload.get("messages", []):
				if m is Dictionary:
					_message_index[m.get("id", "")] = messages.size()
					messages.append(m)
			_set_status(Protocol.STATUS_ACCEPTED)
			welcomed.emit()
			players_changed.emit()
			characters_changed.emit()
			map_changed.emit()
			phase_changed.emit()
			music_changed.emit()
			content_changed.emit()
			quests_changed.emit()
			loot_changed.emit()
			resend_pending()
		Protocol.EVT_PLAYERS:
			players = payload.get("players", [])
			players_changed.emit()
		Protocol.EVT_CHAT:
			var m: Variant = payload.get("message")
			if m is Dictionary and not _message_index.has(m.get("id", "")):
				_message_index[m.get("id", "")] = messages.size()
				messages.append(m)
				message_received.emit(m)
		Protocol.EVT_MSG_UPDATE:
			var m: Variant = payload.get("message")
			if m is Dictionary and _message_index.has(m.get("id", "")):
				messages[_message_index[m.id]] = m
				message_updated.emit(m)
		Protocol.EVT_CHARACTERS:
			characters = payload.get("characters", [])
			characters_changed.emit()
		Protocol.EVT_MAP:
			map = payload.get("map", {})
			map_changed.emit()
		Protocol.EVT_TOKENS:
			if String(payload.get("map_id", "")) == String(map.get("id", "")) and payload.get("tokens") is Array:
				map["tokens"] = payload.tokens
				if payload.get("fog") is Dictionary:
					map["fog"] = payload.fog
				if payload.get("labels") is Array:
					map["labels"] = payload.labels
				map_changed.emit()
		Protocol.EVT_MUSIC:
			music = payload.get("music", {})
			music_changed.emit()
		Protocol.EVT_PHASE:
			phase = payload.get("phase", {})
			phase_changed.emit()
		Protocol.EVT_CONTENT:
			content = payload.get("content", content)
			content_changed.emit()
			characters_changed.emit()
		Protocol.EVT_QUESTS:
			quests = payload.get("quests", [])
			quests_changed.emit()
		Protocol.EVT_LOOT:
			loot = payload.get("loot", [])
			loot_changed.emit()
		Protocol.EVT_FX:
			if payload.get("fx") is Array:
				fx.emit(payload.fx)
		Protocol.EVT_SETTINGS:
			session = payload.get("session", session)
			settings_changed.emit()
		Protocol.EVT_ACK:
			var req_id := String(payload.get("req_id", ""))
			_outbox.erase(req_id)
			outbox_changed.emit()
			if not payload.get("ok", false):
				command_failed.emit(req_id, String(payload.get("error", "Erreur inconnue.")))
		Protocol.EVT_NOTICE:
			notice.emit(String(payload.get("text", "")))
		Protocol.EVT_SESSION_CLOSED:
			session_closed.emit(String(payload.get("reason", "La partie est terminée.")))


func _set_status(status: String) -> void:
	if status == join_status:
		return
	join_status = status
	status_changed.emit(status)
