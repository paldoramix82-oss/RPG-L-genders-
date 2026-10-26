extends Node
## Net — transport réseau (ENet sur UDP) et authentification des appareils.
##
## Le PC du MJ héberge (rôle HOST) ; chaque téléphone se connecte (rôle CLIENT).
## Toute la logique de jeu passe par deux RPC seulement :
##   _c2s(cmd, payload) : un joueur demande quelque chose au serveur ;
##   _s2c(evt, payload) : le serveur informe UN client précis (jamais de diffusion
##                        aveugle : chaque envoi est filtré par SessionServer).
## Les pairs non authentifiés (mauvais code, mauvaise version) ne reçoivent rien.

signal state_changed(state: State)
signal join_failed(reason: String)
signal joined
signal session_ended(reason: String)
signal reconnecting(attempt: int, max_attempts: int)

enum Role { NONE, HOST, CLIENT }
enum State { OFFLINE, HOSTING, CONNECTING, CONNECTED, RECONNECTING }

const CONNECT_TIMEOUT := 8.0
const AUTOSAVE_INTERVAL := 60.0

var role := Role.NONE
var state := State.OFFLINE
var server: SessionServer
var client: SessionClient
var discovery: LanDiscovery
var last_error := ""

var _peer: ENetMultiplayerPeer
var _known_peers := {}  # peer_id -> true (côté serveur, y compris en cours d'authentification)
var _join := {}  # paramètres de connexion côté client
var _ever_connected := false
var _closing := false
var _ending := false
var _reject_reason := ""
var _reconnect_attempt := 0
var _attempt_serial := 0
var _autosave_left := AUTOSAVE_INTERVAL


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	discovery = LanDiscovery.new()
	discovery.name = "LanDiscovery"
	add_child(discovery)
	var smp := multiplayer as SceneMultiplayer
	smp.peer_authenticating.connect(_on_peer_authenticating)
	smp.peer_authentication_failed.connect(_on_peer_authentication_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if role != Role.HOST or server == null:
		return
	server.flush()
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_INTERVAL
		if server.has_unsaved_changes() and not _ending:
			server.save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Fermeture de la fenêtre : prévenir les joueurs avant de quitter.
		await leave("Le MJ a fermé la partie.")
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		# Retour au premier plan sur Android : on retente tout de suite si besoin.
		if role == Role.CLIENT and state == State.RECONNECTING:
			_attempt_connection()


# ---------------------------------------------------------------------------
# Hébergement (PC du MJ)
# ---------------------------------------------------------------------------

## settings : name, mj_name, universe, port, max_players, auto_accept.
## saved_data : campagne chargée par CampaignStore (vide = nouvelle campagne).
## Renvoie "" ou un message d'erreur.
func host(settings: Dictionary, saved_data: Dictionary = {}) -> String:
	if _ending:
		return "Fermeture de la session précédente en cours, réessayez."
	leave()
	var port := int(settings.get("port", Protocol.DEFAULT_PORT))
	if port < 1024 or port > 65535:
		return "Port invalide (1024 à 65535)."
	_peer = ENetMultiplayerPeer.new()
	var max_players := clampi(int(settings.get("max_players", Protocol.DEFAULT_MAX_PLAYERS)), 1, Protocol.MAX_PLAYERS_LIMIT)
	# Marge pour les demandes refusées et les reconnexions qui se chevauchent.
	var err := _peer.create_server(port, max_players + 4)
	if err != OK:
		_peer = null
		return "Impossible d'ouvrir le port %d (déjà utilisé ?). Code Godot : %s" % [port, error_string(err)]
	role = Role.HOST
	server = SessionServer.new(settings, _server_send, _server_kick, saved_data)
	_autosave_left = AUTOSAVE_INTERVAL
	server.players_changed.connect(func(): discovery.update_payload(server.discovery_payload()))
	server.music_changed.connect(Music.apply_state)
	_setup_multiplayer()
	discovery.start_announcing(server.discovery_payload())
	_set_state(State.HOSTING)
	return ""


func _server_send(peer_id: int, evt: String, payload: Dictionary) -> void:
	if role != Role.HOST or not _known_peers.has(peer_id) or not multiplayer.get_peers().has(peer_id):
		return
	# Un appareil qui vient de se couper peut encore figurer dans la liste : on
	# n'écrit que vers les connexions réellement établies.
	var packet_peer := _peer.get_peer(peer_id)
	if packet_peer and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
		_s2c.rpc_id(peer_id, evt, payload)


func _server_kick(peer_id: int, delay: float) -> void:
	if delay > 0.0:
		_flush()
		await get_tree().create_timer(delay).timeout
	if role == Role.HOST and _known_peers.has(peer_id):
		(multiplayer as SceneMultiplayer).disconnect_peer(peer_id)
		# disconnect_peer() n'émet pas peer_disconnected côté serveur :
		# on met l'état de la session à jour nous-mêmes.
		_on_peer_disconnected(peer_id)


## Délai aller-retour en millisecondes vers un appareil (-1 si inconnu).
func get_peer_rtt(peer_id: int) -> int:
	if _peer == null or peer_id == 0:
		return -1
	if role == Role.HOST and not _known_peers.has(peer_id):
		return -1
	if role == Role.CLIENT and state != State.CONNECTED:
		return -1
	var packet_peer := _peer.get_peer(peer_id)
	if packet_peer == null:
		return -1
	return int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func get_peer_ip(peer_id: int) -> String:
	if _peer == null or not _known_peers.has(peer_id):
		return ""
	var packet_peer := _peer.get_peer(peer_id)
	return packet_peer.get_remote_address() if packet_peer else ""


# ---------------------------------------------------------------------------
# Connexion (téléphone d'un joueur)
# ---------------------------------------------------------------------------

## Rejoint l'hôte à cette adresse : plus besoin de code de partie.
func join(ip: String, port: int, player_name: String) -> String:
	if _ending:
		return "Fermeture de la session précédente en cours, réessayez."
	leave()
	ip = ip.strip_edges()
	if not NetUtils.is_ipv4(ip) and not ip.is_valid_ip_address():
		return "Adresse IP invalide (exemple : 192.168.1.20)."
	if port < 1024 or port > 65535:
		return "Port invalide."
	if Protocol.sanitize_name(player_name) == "":
		return "Indiquez votre nom."
	_join = {
		"ip": ip,
		"port": port,
		"name": Protocol.sanitize_name(player_name),
	}
	role = Role.CLIENT
	client = SessionClient.new(_client_send)
	client.session_closed.connect(_on_session_closed_by_server)
	client.music_changed.connect(func(): Music.apply_state(client.music))
	_ever_connected = false
	_reconnect_attempt = 0
	return _attempt_connection()


func _client_send(cmd: String, payload: Dictionary) -> void:
	if role == Role.CLIENT and state == State.CONNECTED:
		_c2s.rpc_id(1, cmd, payload)


func _attempt_connection() -> String:
	_close_peer()
	_reject_reason = ""
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(_join.ip, _join.port)
	if err != OK:
		_peer = null
		return "Impossible de créer la connexion : %s" % error_string(err)
	_setup_multiplayer()
	_set_state(State.RECONNECTING if _ever_connected else State.CONNECTING)
	_attempt_serial += 1
	_watch_connect_timeout(_attempt_serial)
	return ""


func _watch_connect_timeout(serial: int) -> void:
	await get_tree().create_timer(CONNECT_TIMEOUT).timeout
	if serial == _attempt_serial and role == Role.CLIENT and state in [State.CONNECTING, State.RECONNECTING]:
		_on_connection_failed()


func _on_connected_to_server() -> void:
	if role != Role.CLIENT:
		return
	_ever_connected = true
	_reconnect_attempt = 0
	_attempt_serial += 1
	var server_peer := _peer.get_peer(1)
	if server_peer:
		server_peer.set_timeout(0, Protocol.PEER_TIMEOUT_MIN_MS, Protocol.PEER_TIMEOUT_MAX_MS)
	_set_state(State.CONNECTED)
	joined.emit()


func _on_connection_failed() -> void:
	if role != Role.CLIENT or _closing:
		return
	_attempt_serial += 1
	if _reject_reason != "":
		_fail(_reject_reason)
	elif _ever_connected:
		_schedule_reconnect()
	else:
		_fail("L'appareil du MJ ne répond pas à %s:%d.\nVérifiez l'adresse, le Wi-Fi commun et le pare-feu." % [_join.ip, _join.port])


func _on_server_disconnected() -> void:
	if role != Role.CLIENT or _closing:
		return
	if _reject_reason != "":
		_fail(_reject_reason)
	else:
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	_close_peer()
	_reconnect_attempt += 1
	if _reconnect_attempt > Protocol.RECONNECT_MAX_ATTEMPTS:
		_fail("Connexion perdue avec le MJ. La partie n'est plus joignable.")
		return
	_set_state(State.RECONNECTING)
	reconnecting.emit(_reconnect_attempt, Protocol.RECONNECT_MAX_ATTEMPTS)
	var serial := _attempt_serial
	await get_tree().create_timer(Protocol.RECONNECT_DELAY).timeout
	if serial == _attempt_serial and role == Role.CLIENT and state == State.RECONNECTING:
		_attempt_connection()


func _on_session_closed_by_server(reason: String) -> void:
	_end_session(reason)


func _fail(reason: String) -> void:
	last_error = reason
	var was_connected := _ever_connected
	_reset()
	if was_connected:
		session_ended.emit(reason)
	else:
		join_failed.emit(reason)


func _end_session(reason: String) -> void:
	last_error = reason
	_reset()
	session_ended.emit(reason)


# ---------------------------------------------------------------------------
# Authentification (phase ENet avant tout échange de jeu)
# ---------------------------------------------------------------------------

func _setup_multiplayer() -> void:
	var smp := multiplayer as SceneMultiplayer
	smp.auth_callback = _on_auth_data
	smp.auth_timeout = Protocol.AUTH_TIMEOUT
	# Les clients ne peuvent pas se parler directement : tout passe par le serveur.
	smp.server_relay = false
	smp.allow_object_decoding = false
	multiplayer.multiplayer_peer = _peer


func _on_peer_authenticating(peer_id: int) -> void:
	if role == Role.HOST:
		_known_peers[peer_id] = true
		var packet_peer := _peer.get_peer(peer_id)
		if packet_peer:
			packet_peer.set_timeout(0, Protocol.PEER_TIMEOUT_MIN_MS, Protocol.PEER_TIMEOUT_MAX_MS)
	elif role == Role.CLIENT and peer_id == 1:
		(multiplayer as SceneMultiplayer).send_auth(1, Protocol.encode_auth({
			"proto": Protocol.VERSION,
			"name": _join.name,
			"token": App.device_token(),
		}))


func _on_auth_data(peer_id: int, data: PackedByteArray) -> void:
	var smp := multiplayer as SceneMultiplayer
	if role == Role.HOST:
		var request := Protocol.decode_auth(data)
		var result := server.authenticate(peer_id, get_peer_ip(peer_id), request)
		smp.send_auth(peer_id, Protocol.encode_auth(result))
		if result.ok:
			smp.complete_auth(peer_id)
		# En cas de refus, le client ferme lui-même la connexion après avoir lu le
		# motif ; sinon le délai d'authentification (AUTH_TIMEOUT) la coupe.
	elif role == Role.CLIENT and peer_id == 1:
		var response := Protocol.decode_auth(data)
		if response.get("ok", false):
			smp.complete_auth(1)
		else:
			_reject_reason = String(response.get("reason", "Connexion refusée par le serveur."))
			_fail.call_deferred(_reject_reason)


func _on_peer_authentication_failed(peer_id: int) -> void:
	if role == Role.HOST:
		_known_peers.erase(peer_id)
		server.on_peer_disconnected(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	if role == Role.HOST:
		server.on_peer_connected(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if role == Role.HOST:
		_known_peers.erase(peer_id)
		server.on_peer_disconnected(peer_id)


# ---------------------------------------------------------------------------
# RPC : les deux seuls points d'entrée réseau du jeu
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _c2s(cmd: Variant, payload: Variant) -> void:
	if role != Role.HOST:
		return
	server.handle_command(multiplayer.get_remote_sender_id(), cmd, payload)


@rpc("authority", "call_remote", "reliable")
func _s2c(evt: Variant, payload: Variant) -> void:
	if role != Role.CLIENT or multiplayer.get_remote_sender_id() != 1:
		return
	client.handle_event(evt, payload)


# ---------------------------------------------------------------------------
# Fermeture
# ---------------------------------------------------------------------------

## Quitte la partie (joueur) ou la termine (MJ). Peut être attendue avec `await`.
func leave(reason: String = "Le MJ a terminé la partie.") -> void:
	if role == Role.HOST and server and _peer and not _ending:
		_ending = true
		server.flush()
		server.save()
		server.close(reason)
		_flush()
		# On continue à faire tourner ENet un court instant pour que l'annonce de fin
		# parvienne aux téléphones ; sinon ils tenteraient de se reconnecter.
		discovery.stop()
		await get_tree().create_timer(0.5).timeout
		_ending = false
	_reset()


func _reset() -> void:
	Music.apply_state({})
	_closing = true
	_attempt_serial += 1
	discovery.stop()
	_close_peer()
	_known_peers.clear()
	role = Role.NONE
	server = null
	client = null
	_closing = false
	_set_state(State.OFFLINE)


func _close_peer() -> void:
	if _peer:
		_closing = true
		_flush()
		_peer.close()
		_peer = null
		multiplayer.multiplayer_peer = null
		_closing = false
		_known_peers.clear()


func _flush() -> void:
	if _peer and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		_peer.host.flush()


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(new_state)


func state_label() -> String:
	match state:
		State.HOSTING:
			return "Serveur actif"
		State.CONNECTING:
			return "Connexion…"
		State.CONNECTED:
			return "Connecté"
		State.RECONNECTING:
			return "Reconnexion (%d/%d)…" % [_reconnect_attempt, Protocol.RECONNECT_MAX_ATTEMPTS]
	return "Hors ligne"


func join_params() -> Dictionary:
	return _join.duplicate()
