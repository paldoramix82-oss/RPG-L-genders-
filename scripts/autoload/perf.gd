extends CanvasLayer
## Compteur de performance (Réglages › « Afficher les performances ») :
## images par seconde, temps d'une image, mémoire, et les dernières mesures
## enregistrées par le jeu (génération de carte, dessin de la carte, données
## reçues). Sert à repérer ce qui rame sur un appareil précis.

var _label: Label
var _marks := {}   # nom -> [ms, heure]
var _counts := {}  # nom -> total
var _left := 0.0


func _ready() -> void:
	layer = 120
	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.75))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	set_enabled(bool(App.get_setting("debug", "perf", false)))


func enabled() -> bool:
	return visible


func set_enabled(on: bool) -> void:
	visible = on
	set_process(on)
	App.set_setting("debug", "perf", on)


## Mesure : Perf.record("Génération de carte", ms).
func record(what: String, ms: float) -> void:
	_marks[what] = [ms, Time.get_ticks_msec()]


## Compteur cumulé : Perf.count("Mises à jour de carte").
func count(what: String, n: int = 1) -> void:
	_counts[what] = int(_counts.get(what, 0)) + n


## Mesure le temps d'un appel : Perf.time("Dessin", func(): …).
func time(what: String, f: Callable) -> Variant:
	var t0 := Time.get_ticks_usec()
	var r: Variant = f.call()
	record(what, (Time.get_ticks_usec() - t0) / 1000.0)
	return r


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = 0.5
	var lines: Array = ["%d img/s · image %.1f ms · mémoire %.0f Mo" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]]
	lines.append("objets %d · dessins %d" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	for k in _marks:
		lines.append("%s : %.1f ms" % [k, float(_marks[k][0])])
	for k in _counts:
		lines.append("%s : %d" % [k, int(_counts[k])])
	_label.text = "\n".join(PackedStringArray(lines))
