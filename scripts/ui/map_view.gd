class_name MapView
extends Control
## Carte interactive : terrain en cases, étiquettes et pions façon jeu de plateau.
##
## Souris : molette = zoom, clic droit/milieu ou glisser dans le vide = déplacer la vue.
## Tactile : un doigt = toucher / glisser, deux doigts = zoom et déplacement.
## Outil « move » : toucher un pion le sélectionne ; toucher une case l'y envoie
## (ou glisser le pion). Les autres outils émettent cell_tapped / paint_requested.

signal token_selected(token_id: String)
signal move_requested(token_id: String, x: int, y: int)
signal cell_tapped(x: int, y: int)
signal paint_requested(x: int, y: int)
signal paint_finished

const CELL := 32.0
const TAP_SLOP := 10.0

var map := {}
var is_mj := false
var my_id := ""
var tool := "move"
var selected := ""
var current_turn := ""
var combat_ids: Array = []
var show_grid := true
## Pion sur lequel « Recentrer » se place (joueur : son propre pion).
var focus_id := ""

var zoom := 1.0
var offset := Vector2.ZERO
var _display := {}  # token_id -> Vector2 (position affichée, animée)
var _map_key := ""
var _press_pos := Vector2.ZERO
var _pressing := false
var _moved := false
var _drag_candidate := ""
var _dragging := ""
var _drag_pos := Vector2.ZERO
var _painting := false
var _last_paint := Vector2i(-1, -1)
var _touches := {}
var _pinch_dist := 0.0
var _pinch_center := Vector2.ZERO
var _pan_button := false
var _hover := Vector2i(-1, -1)
var _time := 0.0
var _font: Font


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_font = get_theme_font("font", "StrongLabel")
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(bar)
	for spec in [["−", func(): zoom_at(size * 0.5, 1.0 / 1.25)], ["+", func(): zoom_at(size * 0.5, 1.25)], ["Recentrer", recenter]]:
		var b := UIKit.button(spec[0], "", spec[1])
		b.custom_minimum_size = Vector2(44, 40)
		b.add_theme_font_size_override("font_size", 16)
		b.focus_mode = Control.FOCUS_NONE
		bar.add_child(b)
	resized.connect(func():
		if _map_key == "":
			return
		queue_redraw())


## Affiche une carte. La vue (zoom, position) est conservée tant que c'est la même carte.
func set_map(new_map: Dictionary) -> void:
	map = new_map
	var key := "%s:%s:%s" % [map.get("id", ""), map.get("w", 0), map.get("h", 0)]
	if key != _map_key:
		_map_key = key
		_display.clear()
		recenter.call_deferred()
	if selected != "" and MapData.token(map, selected).is_empty():
		selected = ""
	queue_redraw()


func fit() -> void:
	if map.is_empty() or size.x <= 0 or size.y <= 0:
		return
	var w := float(map.w) * CELL
	var h := float(map.h) * CELL
	zoom = clampf(minf((size.x - 16) / w, (size.y - 16) / h), 0.2, 4.0)
	offset = (size - Vector2(w, h) * zoom) * 0.5
	queue_redraw()


## Vue d'ensemble, ou zoom confortable sur le pion suivi s'il existe.
func recenter() -> void:
	fit()
	var t := MapData.token(map, focus_id)
	if t.is_empty() or size.x <= 0:
		return
	var target_zoom := maxf(zoom, 34.0 / CELL)
	if is_equal_approx(target_zoom, zoom):
		return
	zoom = target_zoom
	offset = size * 0.5 - (Vector2(float(t.x), float(t.y)) + Vector2(0.5, 0.5)) * CELL * zoom
	queue_redraw()


func zoom_at(pos: Vector2, factor: float) -> void:
	var old := zoom
	zoom = clampf(zoom * factor, 0.2, 4.0)
	offset = pos - (pos - offset) * (zoom / old)
	queue_redraw()


func cell_at(pos: Vector2) -> Vector2i:
	var p := (pos - offset) / (CELL * zoom)
	return Vector2i(floori(p.x), floori(p.y))


func cell_center(c: Vector2) -> Vector2:
	return offset + (c + Vector2(0.5, 0.5)) * CELL * zoom


func can_move(t: Dictionary) -> bool:
	if t.is_empty():
		return false
	return is_mj or (t.get("owner", "") == my_id and my_id != "" and map.get("players_can_move", true))


func select(token_id: String) -> void:
	selected = token_id
	token_selected.emit(token_id)
	queue_redraw()


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if map.is_empty():
		return
	_time += delta
	var moving := false
	var seen := {}
	for t in map.get("tokens", []):
		var target := Vector2(float(t.x), float(t.y))
		seen[t.id] = true
		if not _display.has(t.id):
			_display[t.id] = target
		var cur: Vector2 = _display[t.id]
		if cur.distance_to(target) > 0.01:
			_display[t.id] = cur.lerp(target, minf(1.0, delta * 10.0))
			moving = true
		else:
			_display[t.id] = target
	for id in _display.keys():
		if not seen.has(id):
			_display.erase(id)
	if moving or current_turn != "" or _dragging != "":
		queue_redraw()


# ---------------------------------------------------------------------------
# Dessin
# ---------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG_DEEP)
	if map.is_empty():
		var msg := "Aucune carte affichée pour l'instant."
		draw_string(_font, Vector2(16, size.y * 0.5), msg, HORIZONTAL_ALIGNMENT_CENTER, size.x - 32, 18, Palette.MUTED)
		return
	var cs := CELL * zoom
	var w := int(map.w)
	var h := int(map.h)
	var x0 := clampi(floori(-offset.x / cs), 0, w)
	var y0 := clampi(floori(-offset.y / cs), 0, h)
	var x1 := clampi(ceili((size.x - offset.x) / cs), 0, w)
	var y1 := clampi(ceili((size.y - offset.y) / cs), 0, h)
	var cells: String = map.cells
	# Ombre portée du plateau.
	draw_rect(Rect2(offset + Vector2(4, 6), Vector2(w, h) * cs), Color(0, 0, 0, 0.35))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var code := cells[y * w + x]
			_draw_cell(Rect2(offset + Vector2(x, y) * cs, Vector2(cs, cs)), code, x, y)
	if show_grid and cs >= 14:
		var gc := Color(0, 0, 0, 0.18)
		for x in range(x0, x1 + 1):
			draw_line(offset + Vector2(x * cs, y0 * cs), offset + Vector2(x * cs, y1 * cs), gc, 1.0)
		for y in range(y0, y1 + 1):
			draw_line(offset + Vector2(x0 * cs, y * cs), offset + Vector2(x1 * cs, y * cs), gc, 1.0)
	draw_rect(Rect2(offset, Vector2(w, h) * cs), Palette.GOLD_DIM, false, 2.0)
	if is_mj and map.has("spawn"):
		var sp := cell_center(Vector2(float(map.spawn.x), float(map.spawn.y)))
		draw_arc(sp, cs * 0.42, 0, TAU, 24, Palette.OK, 2.0, true)
		_text(sp + Vector2(0, cs * 0.12), "départ", maxi(9, int(cs * 0.26)), Palette.OK)
	if _hover.x >= 0 and tool != "move" and MapData.in_bounds(map, _hover.x, _hover.y):
		draw_rect(Rect2(offset + Vector2(_hover) * cs, Vector2(cs, cs)), Color(1, 1, 1, 0.25), false, 2.0)
	for l in map.get("labels", []):
		_draw_label(l, cs)
	var tokens: Array = map.get("tokens", [])
	for t in tokens:
		if t.id != _dragging:
			_draw_token(t, _display.get(t.id, Vector2(float(t.x), float(t.y))), cs, 1.0)
	if _dragging != "":
		var t := MapData.token(map, _dragging)
		if not t.is_empty():
			var c := cell_at(_drag_pos)
			if MapData.in_bounds(map, c.x, c.y):
				draw_rect(Rect2(offset + Vector2(c) * cs, Vector2(cs, cs)), Color(Palette.GOLD, 0.35))
			_draw_token(t, (_drag_pos - offset) / cs - Vector2(0.5, 0.5), cs, 0.85)


func _draw_cell(r: Rect2, code: String, x: int, y: int) -> void:
	var base := MapData.terrain_color(code)
	var n := _noise(x, y)
	draw_rect(r, base.lightened((n - 0.5) * 0.08))
	var s := r.size.x
	if s < 10:
		return
	var c := r.get_center()
	match code:
		"f", "F":
			var count := 2 if code == "f" else 3
			for i in count:
				var p := r.position + Vector2(_noise(x + i * 7, y) * 0.6 + 0.2, _noise(x, y + i * 5) * 0.6 + 0.2) * s
				draw_circle(p + Vector2(0, s * 0.05), s * 0.2, base.darkened(0.35))
				draw_circle(p, s * 0.19, base.lightened(0.12))
		"w", "W":
			var wc := base.lightened(0.18)
			var yy := r.position.y + s * (0.35 + n * 0.3)
			draw_line(Vector2(r.position.x + s * 0.2, yy), Vector2(r.position.x + s * 0.45, yy - s * 0.06), wc, 1.0, true)
			draw_line(Vector2(r.position.x + s * 0.45, yy - s * 0.06), Vector2(r.position.x + s * 0.7, yy), wc, 1.0, true)
		"m":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.38, s * 0.3), c + Vector2(0, -s * 0.35), c + Vector2(s * 0.38, s * 0.3)]), base.darkened(0.2))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.1, -s * 0.12), c + Vector2(0, -s * 0.35), c + Vector2(s * 0.1, -s * 0.12)]), Color("e6e2da"))
		"h":
			draw_arc(c + Vector2(0, s * 0.25), s * 0.32, PI, TAU, 10, base.lightened(0.15), 2.0, true)
		"b":
			draw_rect(r.grow(-s * 0.08), base.lightened(0.1))
			draw_line(Vector2(r.position.x + s * 0.08, c.y), Vector2(r.end.x - s * 0.08, c.y), base.darkened(0.3), 1.0)
		"#":
			draw_rect(Rect2(r.position, Vector2(s, s * 0.22)), base.lightened(0.18))
		"t":
			draw_rect(r.grow(-s * 0.18), Color("7a5a3a"))
		"a":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.32), c + Vector2(s * 0.2, 0), c + Vector2(0, s * 0.32), c + Vector2(-s * 0.2, 0)]), Color("b8a8f0"))
		"l":
			draw_circle(r.position + Vector2(n, _noise(y, x)) * s, s * 0.12, Color("f0a040"))
		"c", "s", "x":
			for i in 3:
				var p := r.position + Vector2(_noise(x * 3 + i, y), _noise(x, y * 3 + i)) * s
				draw_circle(p, s * 0.04, base.lightened(0.25) if code != "x" else base.darkened(0.3))
		"p", "o":
			draw_line(Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), base.darkened(0.15), 1.0)
			var xx := r.position.x + s * (0.5 if y % 2 == 0 else 0.25)
			draw_line(Vector2(xx, r.position.y), Vector2(xx, c.y), base.darkened(0.15), 1.0)
		"B", "d":
			for i in range(1, 3):
				var yy := r.position.y + s * i / 3.0
				draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), base.darkened(0.2), 1.0)
		"n", "g":
			draw_circle(r.position + Vector2(n, _noise(y, x)) * s, s * 0.05, Color(1, 1, 1, 0.8))
		"k":
			draw_line(c + Vector2(-s * 0.2, s * 0.1), c + Vector2(-s * 0.2, -s * 0.2), Color("6b7d52"), 1.0)
			draw_line(c + Vector2(s * 0.1, s * 0.15), c + Vector2(s * 0.12, -s * 0.15), Color("6b7d52"), 1.0)


func _draw_label(l: Dictionary, cs: float) -> void:
	var hidden: bool = l.get("hidden", false)
	var font_size := clampi(int(cs * 0.36), 10, 20)
	var text := ("◇ " if hidden else "") + String(l.text)
	var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var center := cell_center(Vector2(float(l.x), float(l.y))) - Vector2(0, cs * 0.55)
	var rect := Rect2(center - Vector2(ts.x * 0.5 + 6, ts.y * 0.5 + 2), Vector2(ts.x + 12, ts.y + 4))
	var bg := Color(0.08, 0.07, 0.1, 0.78)
	draw_rect(rect, bg)
	draw_rect(rect, Palette.PRIVATE if hidden else Palette.GOLD_DIM, false, 1.0)
	draw_string(_font, Vector2(rect.position.x + 6, rect.position.y + 2 + _font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.PRIVATE if hidden else Palette.TEXT)


func _draw_token(t: Dictionary, cell_pos: Vector2, cs: float, alpha: float) -> void:
	var center := offset + (cell_pos + Vector2(0.5, 0.5)) * cs
	var r := cs * 0.4
	var hidden: bool = t.get("hidden", false)
	if hidden:
		alpha *= 0.5
	var color := Color(String(t.get("color", "#999999")))
	color.a = alpha
	var kind := String(t.get("kind", "npc"))
	var ring := Color("e8e2d6")
	if kind == "monster":
		ring = Palette.DANGER
	elif kind == "npc":
		ring = Palette.VIOLET.lightened(0.2)
	elif kind == "object":
		ring = Palette.GOLD_DIM
	if t.get("owner", "") == my_id and my_id != "":
		ring = Palette.GOLD
	ring.a = alpha
	if t.id == current_turn:
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		draw_circle(center, r * (1.35 + pulse * 0.15), Color(Palette.GOLD, 0.25 * alpha))
	# Socle et pion.
	draw_circle(center + Vector2(0, r * 0.18), r, Color(0, 0, 0, 0.45 * alpha))
	if kind == "object":
		var sq := Rect2(center - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6)
		draw_rect(sq, color)
		draw_rect(sq, ring, false, maxf(1.5, cs * 0.06))
	else:
		draw_circle(center, r, color)
		draw_arc(center, r, 0, TAU, 32, ring, maxf(1.5, cs * 0.07), true)
		draw_circle(center - Vector2(r * 0.3, r * 0.35), r * 0.25, Color(1, 1, 1, 0.12 * alpha))
	if t.id == selected:
		draw_arc(center, r * 1.22, 0, TAU, 32, Color(Palette.GOLD, alpha), 2.0, true)
	var initials := CharacterData.initials_of(String(t.get("name", "?")))
	var fs := maxi(8, int(r * 0.85))
	var text_color := Color("15141a") if color.get_luminance() > 0.55 else Color("f4efe6")
	text_color.a = alpha
	_text(center + Vector2(0, fs * 0.35), initials, fs, text_color)
	var hp_max := int(t.get("hp_max", 0))
	if hp_max > 0 and cs >= 18:
		var ratio := clampf(float(t.get("hp", 0)) / hp_max, 0.0, 1.0)
		var bar := Rect2(center + Vector2(-r, -r - cs * 0.16), Vector2(r * 2, maxf(3, cs * 0.08)))
		draw_rect(bar, Color(0, 0, 0, 0.6 * alpha))
		var hc := Palette.OK if ratio > 0.5 else (Palette.WARN if ratio > 0.25 else Palette.DANGER)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(hc, alpha))
	if cs >= 26:
		var name_text := String(t.get("name", ""))
		var nfs := clampi(int(cs * 0.3), 9, 16)
		var ts := _font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs)
		var pos := center + Vector2(-ts.x * 0.5, r + nfs + 1)
		draw_rect(Rect2(pos - Vector2(3, nfs), Vector2(ts.x + 6, nfs + 4)), Color(0, 0, 0, 0.55 * alpha))
		draw_string(_font, pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(Palette.TEXT, alpha))


func _text(center_baseline: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, center_baseline - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func _noise(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 1000) / 1000.0


# ---------------------------------------------------------------------------
# Entrées
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if map.is_empty():
		return
	# Sur téléphone, les gestes arrivent en événements tactiles : on ignore leur
	# émulation souris pour ne pas les traiter deux fois.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mb.position, 1.12)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mb.position, 1.0 / 1.12)
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_pan_button = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin(mb.position)
			else:
				_end(mb.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hover = cell_at(mm.position)
		if _pan_button:
			offset += mm.relative
			queue_redraw()
		elif _pressing:
			_drag(mm.position, mm.relative)
		elif tool != "move":
			queue_redraw()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() == 2:
			_cancel_gesture()
			var pts: Array = _touches.values()
			_pinch_dist = (pts[0] as Vector2).distance_to(pts[1])
			_pinch_center = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
		elif _touches.size() == 1 and st.pressed:
			_begin(st.position)
		elif _touches.is_empty() and not st.pressed:
			_end(st.position)
		accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d := (pts[0] as Vector2).distance_to(pts[1])
			var center := ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
			if _pinch_dist > 0:
				zoom_at(center, d / _pinch_dist)
			offset += center - _pinch_center
			_pinch_dist = d
			_pinch_center = center
			queue_redraw()
		else:
			_drag(sd.position, sd.relative)
		accept_event()


func _begin(pos: Vector2) -> void:
	_pressing = true
	_moved = false
	_press_pos = pos
	_drag_candidate = ""
	var c := cell_at(pos)
	if tool == "move":
		var t := MapData.token_at(map, c.x, c.y)
		if can_move(t):
			_drag_candidate = t.id
	elif tool == "paint" and MapData.in_bounds(map, c.x, c.y):
		_painting = true
		_last_paint = c
		paint_requested.emit(c.x, c.y)


func _drag(pos: Vector2, relative: Vector2) -> void:
	if not _pressing:
		return
	if pos.distance_to(_press_pos) > TAP_SLOP:
		_moved = true
	var c := cell_at(pos)
	if _painting:
		if c != _last_paint and MapData.in_bounds(map, c.x, c.y):
			_last_paint = c
			paint_requested.emit(c.x, c.y)
		return
	if _drag_candidate != "" and _moved:
		_dragging = _drag_candidate
		_drag_pos = pos
		queue_redraw()
	elif _moved:
		offset += relative
		queue_redraw()


func _end(pos: Vector2) -> void:
	if not _pressing:
		return
	_pressing = false
	var c := cell_at(pos)
	if _painting:
		_painting = false
		paint_finished.emit()
	elif _dragging != "":
		var id := _dragging
		_dragging = ""
		var t := MapData.token(map, id)
		if MapData.in_bounds(map, c.x, c.y) and (int(t.x) != c.x or int(t.y) != c.y):
			move_requested.emit(id, c.x, c.y)
		queue_redraw()
	elif not _moved:
		_tap(c)


func _cancel_gesture() -> void:
	_pressing = false
	_dragging = ""
	_drag_candidate = ""
	if _painting:
		_painting = false
		paint_finished.emit()


func _tap(c: Vector2i) -> void:
	if not MapData.in_bounds(map, c.x, c.y):
		return
	if tool != "move":
		cell_tapped.emit(c.x, c.y)
		return
	var t := MapData.token_at(map, c.x, c.y)
	if not t.is_empty():
		select("" if t.id == selected else t.id)
		return
	var sel := MapData.token(map, selected)
	if can_move(sel):
		move_requested.emit(selected, c.x, c.y)
	else:
		select("")
