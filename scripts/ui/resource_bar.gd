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
	var r := Rect2(Vector2.ZERO, size)
	var radius := minf(6.0, size.y * 0.4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = color.darkened(0.78)
	bg.set_corner_radius_all(int(radius))
	bg.border_color = Palette.BORDER
	bg.set_border_width_all(1)
	draw_style_box(bg, r)
	if ghost > shown:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(1, 1, 1, 0.35)
		g.set_corner_radius_all(int(radius))
		draw_style_box(g, Rect2(Vector2.ZERO, Vector2(size.x * ghost, size.y)))
	if shown > 0.0:
		var f := StyleBoxFlat.new()
		f.bg_color = color.lerp(Color.WHITE, flash * 0.35)
		f.set_corner_radius_all(int(radius))
		draw_style_box(f, Rect2(Vector2.ZERO, Vector2(maxf(size.x * shown, radius * 2), size.y)))
		var hl := StyleBoxFlat.new()
		hl.bg_color = Color(1, 1, 1, 0.12)
		hl.set_corner_radius_all(int(radius))
		draw_style_box(hl, Rect2(Vector2(0, 1), Vector2(maxf(size.x * shown, radius * 2), size.y * 0.42)))
	if show_text:
		var font := get_theme_font("font", "StrongLabel")
		var fs := int(clampf(size.y * 0.7, 11, 22))
		var text := "%d / %d" % [value, max_value]
		if caption != "":
			text = "%s  %s" % [caption, text]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2((size.x - tw) * 0.5, size.y * 0.5 + fs * 0.36)
		draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.TEXT)
