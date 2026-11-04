class_name LanDiscovery
extends Node
## Découverte automatique des parties sur le réseau local (UDP broadcast).
##
## C'est un confort, pas une nécessité : la connexion manuelle par adresse IP
## fonctionne toujours. Certains réseaux (isolation des clients, partage de
## connexion de certains téléphones) ou certains Android bloquent le broadcast.
## L'annonce ne contient jamais le code de session.

signal server_found(info: Dictionary)

const ANNOUNCE_INTERVAL := 1.5
## Une partie non annoncée depuis ce délai disparaît de la liste.
const EXPIRY_SECONDS := 6.0

var _udp: PacketPeerUDP
var _mode := ""  # "announce" | "listen" | ""
var _announce_payload := {}
var _announce_timer := 0.0
var _targets: PackedStringArray = []
var servers := {}  # "ip:port" -> info


func start_announcing(payload: Dictionary) -> void:
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	# Bind sur un port éphémère : seul l'envoi nous intéresse.
	if _udp.bind(0) != OK:
		push_warning("Découverte LAN : impossible d'ouvrir un socket UDP.")
		_udp = null
		return
	_announce_payload = payload
	_targets = ["255.255.255.255"]
	for ip in NetUtils.get_lan_ipv4_addresses():
		var b := NetUtils.guess_broadcast(ip)
		if not _targets.has(b):
			_targets.append(b)
	_mode = "announce"
	_announce_timer = 0.0


func update_payload(payload: Dictionary) -> void:
	_announce_payload = payload


func start_listening() -> void:
	stop()
	_udp = PacketPeerUDP.new()
	if _udp.bind(Protocol.DISCOVERY_PORT) != OK:
		push_warning("Découverte LAN : port %d indisponible." % Protocol.DISCOVERY_PORT)
		_udp = null
		return
	servers.clear()
	_mode = "listen"


func stop() -> void:
	if _udp:
		_udp.close()
	_udp = null
	_mode = ""


func is_listening() -> bool:
	return _mode == "listen"


func _process(delta: float) -> void:
	if _udp == null:
		return
	if _mode == "announce":
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_timer = ANNOUNCE_INTERVAL
			var bytes := JSON.stringify(_announce_payload).to_utf8_buffer()
			for target in _targets:
				_udp.set_dest_address(target, Protocol.DISCOVERY_PORT)
				_udp.put_packet(bytes)
	elif _mode == "listen":
		while _udp.get_available_packet_count() > 0:
			var bytes := _udp.get_packet()
			var ip := _udp.get_packet_ip()
			_handle_packet(ip, bytes)
		var now := Protocol.now()
		for key in servers.keys():
			if now - float(servers[key].seen) > EXPIRY_SECONDS:
				servers.erase(key)


func _handle_packet(ip: String, bytes: PackedByteArray) -> void:
	if bytes.size() > 1024:
		return
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary or data.get("app", "") != Protocol.APP_ID:
		return
	var port := int(data.get("port", 0))
	if port <= 0 or port > 65535:
		return
	var info := {
		"ip": ip,
		"port": port,
		"name": Protocol.sanitize_name(data.get("name", "Partie")),
		"mj": Protocol.sanitize_name(data.get("mj", "")),
		"players": int(data.get("players", 0)),
		"max": int(data.get("max", 0)),
		"proto": int(data.get("proto", 0)),
		"seen": Protocol.now(),
	}
	var key := "%s:%d" % [ip, port]
	var is_new := not servers.has(key)
	servers[key] = info
	if is_new:
		server_found.emit(info)
