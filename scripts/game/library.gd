class_name Library
extends RefCounted
## Bibliothèque du MJ : exporter ses créations (monstres, capacités, objets,
## effets, classes, peuples, butin, PNJ, cartes) dans un fichier, et les
## importer dans une autre campagne ou chez un autre MJ.
## Fichier : {"legenders_library": 1, "name", "content": {kind: {id: entrée}},
##   "characters": {id: fiche de PNJ}, "maps": [carte]}

const VERSION := 1
const EXT := ".legenders.json"

static var dir_path := "user://bibliotheque"


static func build(server: SessionServer, title: String, kinds: Array, map_ids: Array, with_npcs: bool) -> Dictionary:
	var out := {"legenders_library": VERSION, "name": Protocol.sanitize_name(title) if title.strip_edges() != "" else "Bibliothèque",
		"universe": String(server.session.get("universe", "")), "content": {}, "characters": {}, "maps": []}
	for kind in kinds:
		if server.content.has(kind) and server.content[kind] is Dictionary:
			out.content[kind] = (server.content[kind] as Dictionary).duplicate(true)
	var npc_ids := {}
	for mid in map_ids:
		var m: Dictionary = server.maps.get(String(mid), {})
		if m.is_empty():
			continue
		var copy: Dictionary = m.duplicate(true)
		copy.tokens = (copy.tokens as Array).filter(func(t): return String(t.get("kind", "")) != "pc")
		for k in ["explored"]:
			copy.erase(k)
		for t in copy.tokens:
			if String(t.get("char_id", "")) != "":
				npc_ids[String(t.char_id)] = true
		out.maps.append(copy)
	if with_npcs:
		for c in server.characters.values():
			if String(c.get("owner", "")) == "" and not server.players.has(String(c.id)):
				npc_ids[String(c.id)] = true
	for id in npc_ids:
		if server.characters.has(id):
			out.characters[id] = (server.characters[id] as Dictionary).duplicate(true)
	return out


## Fusionne une bibliothèque dans la campagne. Renvoie le résumé (ou l'erreur).
static func merge(server: SessionServer, data: Dictionary) -> Dictionary:
	if int(data.get("legenders_library", 0)) < 1:
		return {"error": "Ce fichier n'est pas une bibliothèque LEGENDERS."}
	var counts := {}
	var content_in: Dictionary = data.get("content", {}) if data.get("content") is Dictionary else {}
	# Ordre : effets et capacités d'abord (les objets, monstres et classes y font référence).
	for kind in ["statuses", "abilities", "items", "loot", "monsters", "species", "classes"]:
		if not content_in.get(kind) is Dictionary or kind not in Content.KINDS:
			continue
		for id in content_in[kind]:
			var e: Variant = content_in[kind][id]
			if not e is Dictionary:
				continue
			var entry: Dictionary = (e as Dictionary).duplicate(true)
			entry.id = String(id)
			if not server.mj_content_save(kind, entry).is_empty():
				counts[kind] = int(counts.get(kind, 0)) + 1
	# PNJ : nouveaux identifiants (pas de collision avec ceux de la campagne).
	var remap := {}
	var chars_in: Dictionary = data.get("characters", {}) if data.get("characters") is Dictionary else {}
	for old_id in chars_in:
		var raw: Variant = chars_in[old_id]
		if not raw is Dictionary:
			continue
		var new_id := "npc_" + Protocol.random_hex(4)
		var base := CharacterData.create(server.universe, new_id, "", String(raw.get("name", "PNJ")), server.content)
		var sheet := CharacterData.sanitize(raw, base)
		sheet.id = new_id
		sheet.owner = ""
		server.characters[new_id] = sheet
		remap[String(old_id)] = new_id
		counts["characters"] = int(counts.get("characters", 0)) + 1
	for m in data.get("maps", []):
		if not m is Dictionary or not m.get("cells") is String:
			continue
		var map: Dictionary = (m as Dictionary).duplicate(true)
		map.id = "map_" + Protocol.random_hex(4)
		map.w = clampi(int(map.get("w", 10)), 4, MapData.MAX_SIZE)
		map.h = clampi(int(map.get("h", 10)), 4, MapData.MAX_SIZE)
		if String(map.cells).length() != int(map.w) * int(map.h):
			continue
		if not map.get("decor") is Dictionary:
			map.decor = {}
		map.tokens = (map.get("tokens", []) as Array).filter(func(t): return t is Dictionary and String(t.get("kind", "")) != "pc")
		for t in map.tokens:
			for k in ["x", "y", "hp", "hp_max"]:
				t[k] = int(t.get(k, 0))
			if remap.has(String(t.get("char_id", ""))):
				t.char_id = remap[String(t.char_id)]
			elif String(t.get("char_id", "")) != "":
				t.char_id = ""
			# Liens vers des cartes d'une autre campagne : à refaire par le MJ.
			if String(t.get("link", "")) != "":
				t.erase("link")
		if not map.get("labels") is Array:
			map.labels = []
		if not map.get("spawn") is Dictionary:
			map.spawn = {"x": int(map.w) / 2, "y": int(map.h) / 2}
		server.maps[map.id] = map
		server.map_order.append(map.id)
		counts["maps"] = int(counts.get("maps", 0)) + 1
	server.maps_changed.emit()
	server.characters_changed.emit()
	return {"counts": counts}


static func summary(counts: Dictionary) -> String:
	var names := {"statuses": "effets", "abilities": "capacités", "items": "objets", "loot": "tables de butin", "monsters": "monstres",
		"species": "peuples", "classes": "classes", "characters": "PNJ", "maps": "cartes"}
	var parts: PackedStringArray = []
	for k in counts:
		parts.append("%d %s" % [int(counts[k]), names.get(k, k)])
	return ", ".join(parts) if not parts.is_empty() else "rien"


static func save_file(data: Dictionary, path: String = "") -> String:
	if path == "":
		DirAccess.make_dir_recursive_absolute(dir_path)
		path = "%s/%s%s" % [dir_path, String(data.get("name", "bibliotheque")).validate_filename().replace(" ", "_"), EXT]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Impossible d'écrire %s (%s)." % [path, error_string(FileAccess.get_open_error())]
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return ""


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func list_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if String(f).ends_with(EXT):
			out.append(dir_path + "/" + f)
	out.sort()
	return out
