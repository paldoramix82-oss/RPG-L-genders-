class_name Adventures
extends RefCounted
## Aventures prêtes à jouer (data/adventures/*.json, générées par
## tools/make_adventures.py) : carte, PNJ, monstres, coffres, quêtes en
## brouillon et scènes à raconter avec des conseils pour le MJ.

const DIR := "res://data/adventures"

static var _all: Array = []


static func all(universe_id: String = "") -> Array:
	if _all.is_empty():
		var dir := DirAccess.open(DIR)
		if dir:
			var files := Array(dir.get_files()).filter(func(f): return f.ends_with(".json"))
			files.sort()
			for file in files:
				var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + file))
				if parsed is Dictionary and parsed.has("id"):
					_all.append(parsed)
	if universe_id == "":
		return _all
	return _all.filter(func(a): return String(a.get("universe", "*")) in ["*", universe_id])


static func get_by_id(id: String) -> Dictionary:
	for a in all():
		if String(a.id) == id:
			return a
	return {}
