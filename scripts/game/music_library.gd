class_name MusicLibrary
extends RefCounted
## Bande originale du jeu (data/music.json, fichiers dans assets/music).
## Les morceaux sont composés par tools/compose_music.py.

const MANIFEST := "res://data/music.json"

static var _tracks: Array = []


static func tracks() -> Array:
	if _tracks.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Array:
			_tracks = parsed
	return _tracks


static func track(id: String) -> Dictionary:
	for t in tracks():
		if t.id == id:
			return t
	return {}


## Morceaux dont l'ambiance commence par `mood` (« Combat » -> « Combat (rock) »).
static func by_mood(mood: String) -> Array:
	return tracks().filter(func(t): return String(t.mood).begins_with(mood))


static func moods() -> PackedStringArray:
	var out: PackedStringArray = []
	for t in tracks():
		if not out.has(t.mood):
			out.append(t.mood)
	return out
