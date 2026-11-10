class_name Backdrop
extends Control
## Fond d'écran commun : le ciel de l'écran titre (pixel art), assombri pour
## que les panneaux restent lisibles par-dessus.

var _tex: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex = load("res://assets/ui/title_bg.png")
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	if _tex:
		var k := maxf(size.x / _tex.get_width(), size.y / _tex.get_height())
		var sz := Vector2(_tex.get_width(), _tex.get_height()) * k
		var x := clampf(size.x * 0.5 - 300.0 * k, size.x - sz.x, 0.0)
		draw_texture_rect(_tex, Rect2(Vector2(x, (size.y - sz.y) * 0.5), sz), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.BG_DEEP, 0.62))
