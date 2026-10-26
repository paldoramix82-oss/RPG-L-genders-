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
	settings.load(_settings_path)
	if device_token() == "":
		settings.set_value("device", "token", Protocol.random_hex(16))
		save_settings()


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
