class_name Universe
extends RefCounted
## Univers de jeu (lore, codex, suggestions pour la création de personnages).
## Fichiers : res://data/universes/*.json. Les entrées « mj_only » du codex
## ne sont jamais envoyées aux joueurs.

const DIR := "res://data/universes"
const DEFAULT_ID := "legenders"
const ORDER := ["legenders", "fantasy", "libre"]

static var _cache := {}


static func all() -> Array:
	if _cache.is_empty():
		for id in ORDER:
			var data := _read("%s/%s.json" % [DIR, id])
			if not data.is_empty():
				_cache[id] = data
	var list: Array = []
	for id in ORDER:
		if _cache.has(id):
			list.append(_cache[id])
	return list


static func get_by_id(id: String) -> Dictionary:
	all()
	return _cache.get(id, _cache.get(DEFAULT_ID, {}))


## Version envoyée à un joueur : sans les secrets du MJ.
static func for_player(universe: Dictionary) -> Dictionary:
	var copy := universe.duplicate(true)
	var codex: Array = []
	for entry in universe.get("codex", []):
		if not entry.get("mj_only", false):
			codex.append(entry)
	copy["codex"] = codex
	return copy


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
