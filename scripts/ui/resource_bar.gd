class_name ResourceBar
extends Control
## Jauge de ressource (PV, mana, ultime, XP) : grande, lisible, animée quand la
## valeur change (la partie perdue reste visible un instant, chiffre qui pulse).

var caption := ""
var value := 0
var max_value := 1
var color := Palette.HP
var shown := 0.0
var ghost := 0.0
var flash := 0.0
var show_text := true
var _tween: Tween


func _init(bar_caption: String = "", bar_color: Color = Palette.HP, height: float = 22.0) -> void:
	caption = bar_caption
	color = bar_color
	custom_minimum_size = Vector2(60, height)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(v: int, m: int, animate: bool = true) -> void:
	m = maxi(1, m)
	var ratio := clampf(float(v) / m, 0.0, 1.0)
	var changed := v != value or m != max_value
	var before := shown
	value = v
	max_value = m
	if not animate or not is_inside_tree() or not changed:
		shown = ratio
		ghost = ratio
		queue_redraw()
		return
	if _tween:
		_tween.kill()
	ghost = maxf(before, ghost)
	flash = 1.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(_set_shown, before, ratio, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_ghost, maxf(before, ghost), ratio, 0.6).set_delay(0.3)
	_tween.tween_method(_set_flash, 1.0, 0.0, 0.5)


func _set_shown(x: float) -> void:
	shown = x
	queue_redraw()


func _set_ghost(x: float) -> void:
	ghost = x
	queue_redraw()


func _set_flash(x: float) -> void:
	flash = x
	queue_redraw()


func _draw() -> void:
	# Jauge pixel : contour noir, fond sombre, remplissage en deux tons avec un
	# reflet, graduations tous les 10 %, texte « HP  120 / 120 » avec contour.
	var r := Rect2(Vector2.ZERO, size).grow(-1)
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b0720"))
	draw_rect(r, color.darkened(0.82))
	var w := r.size.x
	if ghost > shown:
		draw_rect(Rect2(r.position, Vector2(w * ghost, r.size.y)), Color(1, 1, 1, 0.35))
	if shown > 0.0:
		var fill := Rect2(r.position, Vector2(maxf(2.0, w * shown), r.size.y))
		var c := color.lerp(Color.WHITE, flash * 0.35)
		draw_rect(fill, c.darkened(0.18))
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, ceilf(fill.size.y * 0.55))), c)
		draw_rect(Rect2(fill.position + Vector2(0, 1), Vector2(fill.size.x, maxf(1.0, floorf(fill.size.y * 0.18)))), c.lightened(0.35))
	if size.y >= 10:
		for k in range(1, 10):
			var x := r.position.x + roundf(w * k / 10.0)
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.18), 1.0)
	if show_text and size.y >= 12:
		var font := get_theme_font("font", "StrongLabel")
		var fs := int(clampf(size.y * 0.78, 11, 20))
		var y := size.y * 0.5 + fs * 0.36
		var value_text := "%d / %d" % [value, max_value]
		var vw := font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if caption != "":
			draw_string_outline(font, Vector2(6, y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
			draw_string(font, Vector2(6, y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.TEXT)
		var vx := size.x - vw - 6 if caption != "" else (size.x - vw) * 0.5
		draw_string_outline(font, Vector2(vx, y), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(vx, y), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.TEXT)
