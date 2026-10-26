class_name NetUtils
extends RefCounted
## Fonctions utilitaires liées au réseau local.


## Renvoie les adresses IPv4 locales utilisables par les joueurs pour rejoindre.
## Les adresses privées (192.168.x.x, 10.x.x.x, 172.16-31.x.x) sont placées en premier.
static func get_lan_ipv4_addresses() -> PackedStringArray:
	var private_ips: PackedStringArray = []
	var other_ips: PackedStringArray = []
	for addr in IP.get_local_addresses():
		if not is_ipv4(addr):
			continue
		if addr.begins_with("127.") or addr.begins_with("169.254.") or addr == "0.0.0.0":
			continue
		if is_private_ipv4(addr):
			if not private_ips.has(addr):
				private_ips.append(addr)
		elif not other_ips.has(addr):
			other_ips.append(addr)
	private_ips.sort()
	return private_ips + other_ips


static func is_ipv4(addr: String) -> bool:
	var parts := addr.split(".")
	if parts.size() != 4:
		return false
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
			return false
	return true


static func is_private_ipv4(addr: String) -> bool:
	if addr.begins_with("192.168.") or addr.begins_with("10."):
		return true
	if addr.begins_with("172."):
		var second := int(addr.split(".")[1])
		return second >= 16 and second <= 31
	return false


## Adresse de diffusion en supposant un masque /24 (cas de la quasi-totalité
## des box et partages de connexion). Sert uniquement à la découverte automatique.
static func guess_broadcast(addr: String) -> String:
	var parts := addr.split(".")
	if parts.size() != 4:
		return "255.255.255.255"
	return "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
