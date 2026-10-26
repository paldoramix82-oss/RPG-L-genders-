class_name Backdrop
extends Control
## Fond d'écran commun : noir bleuté, halo violet discret, constellation dorée
## et vignette sombre sur les bords (attire l'œil vers le centre).

var _stars: Array[Vector3] = []
var _vignette: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 42:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.6, 1.8)))
	resized.connect(queue_redraw)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.62))
	g.add_point(0.55, Color(0, 0, 0, 0.08))
	_vignette = GradientTexture2D.new()
	_vignette.gradient = g
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.42)
	_vignette.fill_to = Vector2(1.05, 1.05)
	_vignette.width = 256
	_vignette.height = 256


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	var center := Vector2(size.x * 0.5, size.y * 0.18)
	var radius := maxf(size.x, size.y) * 0.9
	for i in 12:
		var t := float(i) / 12.0
		var c := Palette.VIOLET
		c.a = 0.018
		draw_circle(center, radius * (1.0 - t * 0.92), c)
	for s in _stars:
		var c := Palette.GOLD
		c.a = 0.25 + s.z * 0.12
		draw_circle(Vector2(s.x * size.x, s.y * size.y), s.z, c)
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false)
