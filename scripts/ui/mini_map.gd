class_name MiniMap
extends PanelContainer
## Mini-carte (coin de l'écran joueur) : nom du lieu, carte en petit avec le
## brouillard, les héros (or pour soi, cyan pour le groupe), les monstres
## visibles (rouge) et les PNJ (blanc). Toucher : recentrer la carte sur soi.

signal tapped

var map := {}
var my_id := ""
var _title: Label
var _canvas: Control
var _img_tex: ImageTexture
var _baked_cells := ""
var _baked_fog := ""


func _init() -> void:
	theme_type_variation = "CardPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	_title = UIKit.label("", "StrongLabel")
	_title.add_theme_font_size_override("font_size", 13)
	_title.clip_text = true
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_title)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(112, 80)
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	col.add_child(_canvas)
	gui_input.connect(func(ev):
		if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
			tapped.emit())


func set_map(m: Dictionary, me: String) -> void:
	map = m
	my_id = me
	_title.text = String(m.get("name", ""))
	var cells := String(m.get("cells", ""))
	var fog: Dictionary = m.get("fog", {}) if m.get("fog") is Dictionary else {}
	var explored := String(fog.get("explored", ""))
	if cells != _baked_cells or explored != _baked_fog:
		_bake(cells, explored)
	_canvas.queue_redraw()


## Une image d'un pixel par case (couleur du terrain, sombre hors exploration).
func _bake(cells: String, explored: String) -> void:
	_baked_cells = cells
	_baked_fog = explored
	var w := int(map.get("w", 0))
	var h := int(map.get("h", 0))
	if w <= 0 or h <= 0 or cells.length() != w * h:
		_img_tex = null
		return
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var fogged := explored.length() == w * h
	for y in h:
		for x in w:
			var i := y * w + x
			var c := MapData.terrain_color(cells[i])
			if fogged and explored[i] != "1":
				c = Palette.BG_DEEP
			img.set_pixel(x, y, c)
	_img_tex = ImageTexture.create_from_image(img)


func _draw_map() -> void:
	var r := Rect2(Vector2.ZERO, _canvas.size)
	_canvas.draw_rect(r, Palette.BG_DEEP)
	if _img_tex == null:
		return
	var w := float(map.get("w", 1))
	var h := float(map.get("h", 1))
	var k := minf(r.size.x / w, r.size.y / h)
	var off := (r.size - Vector2(w, h) * k) * 0.5
	_canvas.draw_texture_rect(_img_tex, Rect2(off, Vector2(w, h) * k), false)
	for t in map.get("tokens", []):
		var p := off + (Vector2(float(t.x), float(t.y)) + Vector2(0.5, 0.5)) * k
		var col := Color.WHITE
		match String(t.get("kind", "")):
			"pc":
				col = Palette.GOLD if String(t.get("owner", "")) == my_id else Color("6fe6ff")
			"monster":
				col = Palette.HP if String(t.get("disposition", "enemies")) == "enemies" else Palette.OK
			"object":
				col = Color("c9a0ff") if t.get("passage", false) or String(t.get("link", "")) != "" else Color("d8b060")
		var s := maxf(2.0, k * 0.9)
		if String(t.get("owner", "")) == my_id and String(t.get("kind", "")) == "pc":
			s += 2.0
			_canvas.draw_rect(Rect2(p - Vector2(s, s) * 0.5 - Vector2(1, 1), Vector2(s, s) + Vector2(2, 2)), Color.BLACK)
		_canvas.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), col)
