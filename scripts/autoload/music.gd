extends Node
## Music — lecture de la bande originale avec fondu enchaîné.
## Sur l'hôte, suit les choix du MJ ; sur un téléphone, suit l'hôte si le joueur
## a laissé la musique activée (réglage local « audio/enabled »).
## Avant la partie (menus, création, salon), le thème principal joue en fond
## tant que le MJ n'a pas lancé de morceau.

signal changed

const FADE := 1.5
const MENU_TRACK := "kurtzuma"

var current := ""
var playing := false
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _state := {}
var _menu := false


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	set_volume(volume())


func _exit_tree() -> void:
	for p in _players:
		p.stop()
		p.stream = null


func enabled() -> bool:
	return bool(App.get_setting("audio", "enabled", true))


func volume() -> float:
	return float(App.get_setting("audio", "volume", 0.7))


func set_enabled(on: bool) -> void:
	App.set_setting("audio", "enabled", on)
	App.save_settings()
	apply_state(_state)


func set_volume(v: float) -> void:
	App.set_setting("audio", "volume", clampf(v, 0.0, 1.0))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, clampf(v, 0.0, 1.0))))


## Musique des menus (avant le début de la partie) : active ou non.
func set_menu(on: bool) -> void:
	if on == _menu and (playing or not on or not enabled()):
		return
	_menu = on
	apply_state(_state)


## state : {track, playing, started_at} (heure de départ de l'hôte, pour se caler).
func apply_state(state: Dictionary) -> void:
	_state = state
	var track := String(state.get("track", ""))
	var want := bool(state.get("playing", false)) and track != "" and enabled()
	if not want:
		if _menu and enabled():
			play(MENU_TRACK)
		else:
			stop()
		return
	var offset := maxf(0.0, Protocol.now() - float(state.get("started_at", Protocol.now())))
	play(track, offset)


func play(track_id: String, offset: float = 0.0) -> void:
	var info := MusicLibrary.track(track_id)
	if info.is_empty():
		return
	if track_id == current and playing:
		return
	var stream := load(String(info.file)) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var length := stream.get_length()
	if length > 0.0:
		offset = fmod(offset, length)
	var old := _players[_active]
	_active = 1 - _active
	var p := _players[_active]
	p.stream = stream
	p.volume_db = -40.0
	p.play(offset)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(p, "volume_db", 0.0, FADE)
	if old.playing:
		tween.tween_property(old, "volume_db", -60.0, FADE)
		tween.chain().tween_callback(old.stop)
	current = track_id
	playing = true
	changed.emit()


func stop() -> void:
	if not playing:
		return
	playing = false
	for p in _players:
		if p.playing:
			var tween := create_tween()
			tween.tween_property(p, "volume_db", -60.0, FADE)
			tween.tween_callback(p.stop)
	changed.emit()


func title() -> String:
	return String(MusicLibrary.track(current).get("title", "")) if playing else ""
