extends Node
## Vérifie que tous les scripts du projet se compilent (les erreurs sont affichées par Godot).
## Usage : godot --headless --path . res://tests/check_scripts.tscn


func _ready() -> void:
	var failed := 0
	var files: Array = []
	_collect("res://scripts", files)
	_collect("res://tests", files)
	for path in files:
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			print("ÉCHEC : ", path)
	print("%d scripts vérifiés, %d en erreur." % [files.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)


func _collect(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".gd") and f != "check_scripts.gd":
			out.append(dir_path + "/" + f)
	for d in dir.get_directories():
		_collect(dir_path + "/" + d, out)
