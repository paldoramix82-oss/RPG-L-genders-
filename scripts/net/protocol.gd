class_name Protocol
extends RefCounted
## Constantes et utilitaires partagés par le serveur (MJ) et les clients (joueurs).
##
## Toute la communication applicative passe par deux RPC de l'autoload Net :
##   - client -> serveur : commande (cmd: String, payload: Dictionary)
##   - serveur -> client : événement (evt: String, payload: Dictionary)
## Le serveur est la seule source de vérité : il valide chaque commande et
## décide quelles données envoyer à quel client.

## À incrémenter dès que le format des messages change de façon incompatible.
const VERSION := 2
const APP_ID := "legenders-rpg"

const DEFAULT_PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS_LIMIT := 12
const DEFAULT_MAX_PLAYERS := 6

## Durée maximale de la phase d'authentification ENet (secondes).
const AUTH_TIMEOUT := 10.0
## Détection d'une connexion coupée (millisecondes) : voir ENetPacketPeer.set_timeout().
const PEER_TIMEOUT_MIN_MS := 4000
const PEER_TIMEOUT_MAX_MS := 12000

const RECONNECT_DELAY := 3.0
const RECONNECT_MAX_ATTEMPTS := 40

## Anti-abus : nombre de commandes acceptées par fenêtre glissante.
const RATE_LIMIT_COUNT := 25
const RATE_LIMIT_WINDOW := 5.0
## Anti-force brute sur le code de session.
const AUTH_MAX_FAILURES := 5
const AUTH_LOCKOUT_SECONDS := 30.0

const MAX_NAME_LENGTH := 32
const MAX_MESSAGE_LENGTH := 2000
const MAX_HISTORY_SENT := 200

const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6

## Destinataire spécial : le maître du jeu.
const TO_MJ := "mj"
## Destinataire spécial : tout le groupe.
const TO_ALL := "all"
## Identifiant d'auteur réservé au maître du jeu.
const MJ_ID := "mj"

# --- Commandes client -> serveur ---
const CMD_CHAT_SEND := "chat_send"
const CMD_ACTION := "action_declare"
const CMD_ROLL := "dice_roll"
const CMD_CHAR_SAVE := "char_save"
const CMD_PAWN_MOVE := "pawn_move"

# --- Événements serveur -> client ---
const EVT_JOIN_STATUS := "join_status"
const EVT_WELCOME := "welcome"
const EVT_PLAYERS := "players"
const EVT_CHAT := "chat"
const EVT_ACK := "ack"
const EVT_NOTICE := "notice"
const EVT_SESSION_CLOSED := "session_closed"
const EVT_MSG_UPDATE := "msg_update"
const EVT_CHARACTERS := "characters"
const EVT_MAP := "map"
const EVT_COMBAT := "combat"
const EVT_SETTINGS := "settings"

# --- Types de messages du fil ---
const KIND_CHAT := "chat"
const KIND_ACTION := "action"
const KIND_ROLL := "roll"
const KIND_SYSTEM := "system"

# --- Statut d'une action déclarée ---
const ACTION_PENDING := "pending"
const ACTION_RESOLVED := "resolved"
const ACTION_REFUSED := "refused"

# --- Statuts d'un joueur dans la session ---
const STATUS_PENDING := "pending"
const STATUS_ACCEPTED := "accepted"
const STATUS_REFUSED := "refused"


## Encode un dictionnaire pour la phase d'authentification (JSON -> octets).
## Le JSON évite tout décodage d'objets arbitraires venant du réseau.
static func encode_auth(data: Dictionary) -> PackedByteArray:
	return JSON.stringify(data).to_utf8_buffer()


static func decode_auth(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() == 0 or bytes.size() > 4096:
		return {}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	return {}


static func generate_code() -> String:
	var code := ""
	for i in CODE_LENGTH:
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code


## Normalise un code saisi par un joueur : majuscules, sans espaces ni tirets.
static func normalize_code(raw: String) -> String:
	return raw.strip_edges().to_upper().replace(" ", "").replace("-", "")


static func random_hex(byte_count: int) -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(byte_count).hex_encode()


## Nettoie un nom de joueur : retire les caractères de contrôle et limite la longueur.
static func sanitize_name(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var out := ""
	for ch in (raw as String).strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.substr(0, MAX_NAME_LENGTH).strip_edges()


## Nettoie un texte libre : conserve les retours à la ligne, limite la longueur.
static func sanitize_text(raw: Variant, max_length: int = MAX_MESSAGE_LENGTH) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var out := ""
	for ch in (raw as String).strip_edges():
		var c := ch.unicode_at(0)
		if c >= 32 or c == 10:
			out += ch
	return out.substr(0, max_length)


static func now() -> float:
	return Time.get_unix_time_from_system()


static func format_time(unix: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix + _utc_offset_seconds()))
	return "%02d:%02d" % [d.hour, d.minute]


static func _utc_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
