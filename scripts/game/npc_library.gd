class_name NpcLibrary
extends RefCounted
## Packs de PNJ prêts à l'emploi (data/npcs/*.json) : fiches complètes que le MJ
## importe dans sa campagne puis modifie librement.

const DIR := "res://data/npcs"

static var _packs: Array = []


static func packs(universe_id: String = "") -> Array:
	if _packs.is_empty():
		var dir := DirAccess.open(DIR)
		if dir:
			var files := Array(dir.get_files()).filter(func(f): return f.ends_with(".json"))
			files.sort()
			for file in files:
				var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + file))
				if parsed is Dictionary and parsed.get("npcs") is Array:
					_packs.append(parsed)
	if universe_id == "":
		return _packs
	return _packs.filter(func(p): return p.get("universe", "*") in ["*", universe_id])
