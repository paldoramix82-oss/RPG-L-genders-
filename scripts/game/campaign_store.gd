class_name CampaignStore
extends RefCounted
## Sauvegarde locale des campagnes sur l'appareil qui héberge (JSON).
## Écriture sûre : fichier temporaire, puis l'ancienne sauvegarde devient .bak,
## puis le temporaire prend sa place. En cas de fichier abîmé, le .bak est relu.

## 2 : catalogue de campagne, quêtes, coffre, fiches au nouveau système de règles.
const FORMAT := 2

## Dossier des sauvegardes (App le place dans le profil local).
static var dir_path := "user://campaigns"


static func save(data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(dir_path)
	var id := String(data.get("session", {}).get("id", ""))
	if id == "" or not id.is_valid_hex_number():
		return "Identifiant de campagne invalide."
	data["format"] = FORMAT
	data["saved_at"] = Protocol.now()
	var path := "%s/%s.json" % [dir_path, id]
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Impossible d'écrire la sauvegarde (%s)." % error_string(FileAccess.get_open_error())
	f.store_string(JSON.stringify(data))
	f.close()
	# Vérifie que le fichier écrit se relit correctement avant de remplacer l'ancien.
	if not JSON.parse_string(FileAccess.get_file_as_string(tmp)) is Dictionary:
		return "La sauvegarde écrite est illisible ; l'ancienne est conservée."
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	var err := DirAccess.rename_absolute(tmp, path)
	return "" if err == OK else "Échec du remplacement de la sauvegarde (%s)." % error_string(err)


static func load_campaign(id: String) -> Dictionary:
	var path := "%s/%s.json" % [dir_path, id]
	for candidate in [path, path + ".bak"]:
		if FileAccess.file_exists(candidate):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
			if parsed is Dictionary and parsed.has("session"):
				return parsed
	return {}


## [{id, name, universe, saved_at, players}] du plus récent au plus ancien.
static func list() -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var data := load_campaign(file.get_basename())
		if data.is_empty():
			continue
		out.append({
			"id": file.get_basename(),
			"name": String(data.session.get("name", "?")),
			"universe": String(data.session.get("universe", "")),
			"saved_at": float(data.get("saved_at", 0)),
			"players": (data.get("players", {}) as Dictionary).size(),
		})
	out.sort_custom(func(a, b): return a.saved_at > b.saved_at)
	return out


## Copie de sécurité d'une sauvegarde avant sa conversion (ex. « <id>.json.v1 »).
static func backup(id: String, suffix: String) -> void:
	var path := "%s/%s.json" % [dir_path, id]
	if FileAccess.file_exists(path) and not FileAccess.file_exists(path + "." + suffix):
		DirAccess.copy_absolute(path, path + "." + suffix)


static func delete(id: String) -> void:
	for suffix in [".json", ".json.bak", ".json.tmp", ".json.v1"]:
		DirAccess.remove_absolute("%s/%s%s" % [dir_path, id, suffix])
