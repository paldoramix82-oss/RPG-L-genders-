extends Node
## App — paramètres locaux, profil, navigation entre écrans et infos plateforme.
##
## Options de ligne de commande (après `--`) :
##   --profile=nom    sépare les données locales (plusieurs joueurs sur un même PC) ;
##   --force-mobile   affiche l'interface téléphone sur PC.

const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"
const SCENE_HOST := "res://scenes/host_screen.tscn"
const SCENE_JOIN := "res://scenes/join_screen.tscn"
const SCENE_PLAYER := "res://scenes/player_screen.tscn"

var profile := "default"
## Message à afficher sur l'écran suivant (ex. raison d'une fin de session).
var flash := ""
var settings := ConfigFile.new()
var _settings_path := ""


func _ready() -> void:
	randomize()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			profile = arg.get_slice("=", 1).validate_filename()
	var dir := "user://profiles/%s" % profile
	DirAccess.make_dir_recursive_absolute(dir)
	_settings_path = dir + "/settings.cfg"
	CampaignStore.dir_path = dir + "/campaigns"
	Library.dir_path = dir + "/bibliotheque"
	settings.load(_settings_path)
	if device_token() == "":
		settings.set_value("device", "token", Protocol.random_hex(16))
		save_settings()
	_autojoin.call_deferred()


## Fenêtre joueur d'essai ouverte par le MJ sur son PC :
## `-- --autojoin=127.0.0.1:17800 --name=Essai` rejoint la partie tout seul.
func _autojoin() -> void:
	var target := ""
	var who := "Essai"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autojoin="):
			target = arg.get_slice("=", 1)
		elif arg.begins_with("--name="):
			who = arg.get_slice("=", 1)
	if target == "" or not target.contains(":"):
		return
	await get_tree().process_frame
	Net.joined.connect(func(): goto(SCENE_PLAYER), CONNECT_ONE_SHOT)
	var err := Net.join(target.get_slice(":", 0), int(target.get_slice(":", 1)), who)
	if err != "":
		push_warning(err)


## Ouvre une fenêtre joueur d'essai (PC seulement) : un deuxième jeu, au format
## téléphone, qui rejoint la partie de cet ordinateur. Renvoie "" ou l'erreur.
func open_test_player(port: int, index: int) -> String:
	if is_mobile():
		return "Sur téléphone, utilisez un autre appareil pour tester."
	var args := PackedStringArray()
	if not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--resolution", "420x860", "--", "--profile=essai%d" % index, "--force-mobile",
		"--autojoin=127.0.0.1:%d" % port, "--name=Essai %d" % index])
	var pid := OS.create_process(OS.get_executable_path(), args)
	return "" if pid > 0 else "Impossible d'ouvrir la fenêtre d'essai."


## Identifiant secret de cet appareil : permet de retrouver son personnage après une coupure.
func device_token() -> String:
	return String(settings.get_value("device", "token", ""))


func get_setting(section: String, key: String, default: Variant = null) -> Variant:
	return settings.get_value(section, key, default)


func set_setting(section: String, key: String, value: Variant) -> void:
	settings.set_value(section, key, value)


func save_settings() -> void:
	# Écriture dans un fichier temporaire puis remplacement : pas de fichier à moitié écrit.
	var tmp := _settings_path + ".tmp"
	if settings.save(tmp) == OK:
		DirAccess.rename_absolute(tmp, _settings_path)


func is_mobile() -> bool:
	# `-- --force-mobile` : prévisualiser l'interface téléphone sur PC.
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.get_cmdline_user_args().has("--force-mobile")


## Tout appareil peut héberger : PC ou téléphone (le téléphone doit rester allumé,
## application au premier plan, pendant la partie).
func can_host() -> bool:
	return true


func goto(scene_path: String) -> void:
	get_tree().call_deferred("change_scene_to_file", scene_path)
