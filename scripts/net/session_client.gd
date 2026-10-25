class_name SessionClient
extends RefCounted
## Vue locale de la session côté joueur (téléphone Android).
##
## Ne contient que ce que le serveur a accepté d'envoyer. Les commandes sont
## gardées dans une boîte d'envoi jusqu'à l'accusé de réception du serveur :
## après une coupure, elles sont renvoyées, et le serveur ignore les doublons.

signal status_changed(status: String)
signal welcomed
signal players_changed
signal message_received(message: Dictionary)
signal command_failed(req_id: String, error: String)
signal session_closed(reason: String)
signal notice(text: String)

var join_status := ""
var session := {}
var me := {}
var players: Array = []
var messages: Array = []

var _send: Callable  # func(cmd: String, payload: Dictionary)
var _outbox := {}  # req_id -> {cmd, payload}
var _req_prefix := Protocol.random_hex(3)
var _req_counter := 0
var _message_ids := {}


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
	return req_id


func send_chat(to: String, text: String) -> String:
	return send_command(Protocol.CMD_CHAT_SEND, {"to": to, "text": text})


func pending_count() -> int:
	return _outbox.size()


## Après une reconnexion : renvoie tout ce qui n'a pas été confirmé.
func resend_pending() -> void:
	for req_id in _outbox.keys():
		var entry: Dictionary = _outbox[req_id]
		_send.call(entry.cmd, entry.payload)


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
			me = payload.get("you", {})
			players = payload.get("players", [])
			messages.clear()
			_message_ids.clear()
			for m in payload.get("messages", []):
				if m is Dictionary:
					_message_ids[m.get("id", "")] = true
					messages.append(m)
			_set_status(Protocol.STATUS_ACCEPTED)
			welcomed.emit()
			players_changed.emit()
			resend_pending()
		Protocol.EVT_PLAYERS:
			players = payload.get("players", [])
			players_changed.emit()
		Protocol.EVT_CHAT:
			var m: Variant = payload.get("message")
			if m is Dictionary and not _message_ids.has(m.get("id", "")):
				_message_ids[m.get("id", "")] = true
				messages.append(m)
				message_received.emit(m)
		Protocol.EVT_ACK:
			var req_id := String(payload.get("req_id", ""))
			_outbox.erase(req_id)
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
