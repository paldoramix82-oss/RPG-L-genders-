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
## Mode « choisir une cible » : le pion touché est renvoyé ici.
signal target_picked(token_id: String)

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
## Cases accessibles ce tour (surlignées) : {Vector2i: true}.
var reachable := {}
## Mode ciblage pour une attaque, une capacité ou un objet.
var target_mode := false
## Pions ciblables pendant le choix d'une cible (entourés en rouge).
var target_ids: Array = []
## Chiffres et textes flottants (dégâts, soins, effets) : {token, text, color, t}.
var _floaters: Array = []

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
var _terrain_vp: SubViewport
var _painter: TerrainPainter
var _baked_cells := ""
var _baked_size := Vector2i.ZERO


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_font = get_theme_font("font", "StrongLabel")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_terrain_vp = SubViewport.new()
	_terrain_vp.transparent_bg = true
	_terrain_vp.disable_3d = true
	_terrain_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_painter = TerrainPainter.new()
	_terrain_vp.add_child(_painter)
	add_child(_terrain_vp)
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
	zoom = clampf(minf((size.x - 32) / w, (size.y - 32) / h), 0.04, 4.0)
	offset = (size - Vector2(w, h) * zoom) * 0.5
	queue_redraw()


## Vue d'ensemble, ou zoom confortable sur le pion suivi s'il existe.
func recenter() -> void:
	fit()
	var t := MapData.token(map, focus_id)
	if t.is_empty() or size.x <= 0:
		return
	# Environ 9 cases de large sur téléphone : pions lisibles.
	var target_zoom := maxf(zoom, clampf(size.x / 9.0, 34.0, 56.0) / CELL)
	if is_equal_approx(target_zoom, zoom):
		return
	zoom = target_zoom
	offset = size * 0.5 - (Vector2(float(t.x), float(t.y)) + Vector2(0.5, 0.5)) * CELL * zoom
	queue_redraw()


func zoom_at(pos: Vector2, factor: float) -> void:
	var old := zoom
	zoom = clampf(zoom * factor, 0.04, 4.0)
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


## Cases à portée de déplacement (même règle que l'hôte : distance en cases,
## diagonales comprises, case libre et franchissable).
func compute_reachable(from: Vector2i, moves: int) -> Dictionary:
	var out := {}
	if moves <= 0:
		return out
	var occupied := {}
	for t in map.get("tokens", []):
		occupied[Vector2i(int(t.x), int(t.y))] = true
	for y in range(from.y - moves, from.y + moves + 1):
		for x in range(from.x - moves, from.x + moves + 1):
			var c := Vector2i(x, y)
			if c != from and MapData.passable(map, x, y) and not occupied.has(c):
				out[c] = true
	return out


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
	for f in _floaters:
		f.t = float(f.t) + delta
	_floaters = _floaters.filter(func(f): return float(f.t) < 1.8)
	if moving or current_turn != "" or _dragging != "" or not reachable.is_empty() or not _floaters.is_empty() or target_mode:
		queue_redraw()


## Retours visuels d'une action : chiffres de dégâts / soins, « Raté », « Critique ! »…
func show_fx(list: Array) -> void:
	var stagger := {}
	for f in list:
		var id := String(f.get("token", ""))
		var amount := int(f.get("amount", 0))
		var text := ""
		var col := Palette.TEXT
		match String(f.get("type", "")):
			"dmg":
				text = "−%d" % amount
				col = Palette.HP.lightened(0.15)
			"heal":
				text = "+%d" % amount
				col = Palette.HEAL
			"res":
				text = "%+d" % amount
				col = Palette.MANA.lightened(0.2)
			"miss":
				text = "Raté"
				col = Palette.MUTED
			"crit":
				text = "Critique !"
				col = Palette.ULT
			"ko":
				text = "Hors de combat"
				col = Palette.DANGER
			"status":
				text = String(f.get("text", ""))
				col = Palette.PRIVATE
			"passive":
				text = "Passif : " + String(f.get("text", ""))
				col = Palette.VIOLET.lightened(0.5)
			"ultimate":
				text = String(f.get("text", "Ultime")) + " !"
				col = Palette.ULT
			"ult":
				text = "Ultime prêt"
				col = Palette.ULT
		if text == "" or (text.begins_with("−") and amount == 0):
			continue
		var n := int(stagger.get(id, 0))
		stagger[id] = n + 1
		_floaters.append({"token": id, "text": text, "color": col, "t": -0.25 * n, "big": f.get("type", "") in ["dmg", "heal", "crit"]})
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
	if String(map.cells) != _baked_cells or int(map.w) != _baked_size.x or int(map.h) != _baked_size.y:
		_bake()
	var cs := CELL * zoom
	var w := int(map.w)
	var h := int(map.h)
	var board := Rect2(offset, Vector2(w, h) * cs)
	# Cadre du plateau : ombre, bordure en bois sombre et liseré doré.
	draw_rect(board.grow(10).grow_individual(0, 0, 4, 6), Color(0, 0, 0, 0.45))
	draw_rect(board.grow(9), Color("2a2118"))
	draw_rect(board.grow(9), Palette.GOLD_DIM, false, 2.0)
	draw_rect(board.grow(3), Palette.GOLD_DEEP, false, 2.0)
	draw_texture_rect(_terrain_vp.get_texture(), board, false)
	var x0 := clampi(floori(-offset.x / cs), 0, w)
	var y0 := clampi(floori(-offset.y / cs), 0, h)
	var x1 := clampi(ceili((size.x - offset.x) / cs), 0, w)
	var y1 := clampi(ceili((size.y - offset.y) / cs), 0, h)
	if show_grid and cs >= 18:
		var gc := Color(0, 0, 0, 0.12)
		for x in range(x0, x1 + 1):
			draw_line(offset + Vector2(x * cs, y0 * cs), offset + Vector2(x * cs, y1 * cs), gc, 1.0)
		for y in range(y0, y1 + 1):
			draw_line(offset + Vector2(x0 * cs, y * cs), offset + Vector2(x1 * cs, y * cs), gc, 1.0)
	if is_mj and map.has("spawn"):
		var sp := cell_center(Vector2(float(map.spawn.x), float(map.spawn.y)))
		draw_arc(sp, cs * 0.42, 0, TAU, 24, Palette.OK, 2.0, true)
		_text(sp + Vector2(0, cs * 0.12), "départ", maxi(9, int(cs * 0.26)), Palette.OK)
	if not reachable.is_empty():
		var pulse := 0.16 + 0.06 * sin(_time * 3.0)
		for c in reachable:
			var r := Rect2(offset + Vector2(c) * cs, Vector2(cs, cs)).grow(-1)
			draw_rect(r, Color(Palette.GOLD, pulse))
			draw_rect(r, Color(Palette.GOLD, 0.45), false, 1.0)
	if target_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.1, 0.1, 0.12))
		draw_string(_font, Vector2(12, size.y - 14), "Touchez la cible", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.DANGER.lightened(0.3))
	if _hover.x >= 0 and tool != "move" and MapData.in_bounds(map, _hover.x, _hover.y):
		draw_rect(Rect2(offset + Vector2(_hover) * cs, Vector2(cs, cs)), Color(1, 1, 1, 0.3), false, 2.0)
	for l in map.get("labels", []):
		_draw_label(l, cs)
	var tokens: Array = map.get("tokens", []).duplicate()
	tokens.sort_custom(func(a, b): return float(_display.get(a.id, Vector2(0, a.y)).y) < float(_display.get(b.id, Vector2(0, b.y)).y))
	for t in tokens:
		if t.id != _dragging:
			_draw_token(t, _display.get(t.id, Vector2(float(t.x), float(t.y))), cs, 1.0)
	if target_mode:
		for id in target_ids:
			var tt := MapData.token(map, String(id))
			if not tt.is_empty():
				var pc := cell_center(_display.get(tt.id, Vector2(float(tt.x), float(tt.y))))
				draw_arc(pc, cs * (0.55 + 0.05 * sin(_time * 5.0)), 0, TAU, 28, Palette.DANGER.lightened(0.2), maxf(2.0, cs * 0.06), true)
	for f in _floaters:
		if float(f.t) < 0:
			continue
		var ft := MapData.token(map, String(f.token))
		if ft.is_empty():
			continue
		var p := cell_center(_display.get(ft.id, Vector2(float(ft.x), float(ft.y))))
		var k := float(f.t) / 1.8
		var fsz := clampi(int(cs * (0.62 if f.big else 0.4)), 13, 34)
		var txt := String(f.text)
		var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		var pos := p + Vector2(-tw * 0.5, -cs * 0.7 - k * cs * 1.1)
		var a := clampf(1.6 - k * 1.6, 0.0, 1.0)
		var sc := 1.0 + maxf(0.0, 0.25 - float(f.t)) * 1.6
		var fs2 := int(fsz * sc)
		for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 2)]:
			draw_string(_font, pos + o, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0, 0, 0, a * 0.85))
		draw_string(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(f.color, a))
	if _dragging != "":
		var t := MapData.token(map, _dragging)
		if not t.is_empty():
			var c := cell_at(_drag_pos)
			if MapData.in_bounds(map, c.x, c.y):
				draw_rect(Rect2(offset + Vector2(c) * cs, Vector2(cs, cs)), Color(Palette.GOLD, 0.35))
			_draw_token(t, (_drag_pos - offset) / cs - Vector2(0.5, 0.5), cs, 0.85)


## Recalcule la texture du terrain (au chargement et quand le MJ peint).
func _bake() -> void:
	_baked_cells = String(map.cells)
	_baked_size = Vector2i(int(map.w), int(map.h))
	_painter.setup(map)
	_terrain_vp.size = Vector2i(_painter.size)
	_terrain_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	queue_redraw()


func _draw_label(l: Dictionary, cs: float) -> void:
	var hidden: bool = l.get("hidden", false)
	var font_size := clampi(int(cs * 0.36), 10, 20)
	var text := ("◇ " if hidden else "") + String(l.text)
	var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var center := cell_center(Vector2(float(l.x), float(l.y))) - Vector2(0, cs * 0.55)
	var rect := Rect2(center - Vector2(ts.x * 0.5 + 8, ts.y * 0.5 + 3), Vector2(ts.x + 16, ts.y + 6))
	# Petit parchemin : fond clair, bord doré.
	draw_rect(rect.grow(1), Color(0, 0, 0, 0.35))
	draw_rect(rect, Color("2a2330", 0.88) if hidden else Color("e9dfc6", 0.92))
	draw_rect(rect, Palette.PRIVATE if hidden else Palette.GOLD_DIM, false, 1.0)
	var col := Palette.PRIVATE if hidden else Color("2a2118")
	draw_string(_font, Vector2(rect.position.x + 8, rect.position.y + 3 + _font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


## Pions façon jeu de plateau : silhouette de pion (personnages, PNJ), créature
## à cornes (monstres) ou coffre (objets), avec ombre, reflet et jauge de PV.
func _draw_token(t: Dictionary, cell_pos: Vector2, cs: float, alpha: float) -> void:
	var center := offset + (cell_pos + Vector2(0.5, 0.5)) * cs
	var r := cs * 0.42
	var hidden: bool = t.get("hidden", false)
	if hidden:
		alpha *= 0.5
	var knocked_out := int(t.get("hp_max", 0)) > 0 and int(t.get("hp", 1)) <= 0
	if knocked_out:
		alpha *= 0.45
	var color := Color(String(t.get("color", "#999999")))
	color.a = alpha
	var kind := String(t.get("kind", "npc"))
	var ring := Color("1c1a20")
	if kind == "monster":
		ring = Palette.DANGER.darkened(0.2)
	if t.get("owner", "") == my_id and my_id != "":
		ring = Palette.GOLD
	ring.a = alpha
	var base := center + Vector2(0, r * 0.62)
	if t.id == current_turn:
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		_ellipse(base, Vector2(r * (1.25 + pulse * 0.2), r * 0.5), Color(Palette.GOLD, 0.35 * alpha))
	if t.id == selected:
		_ellipse(base, Vector2(r * 1.15, r * 0.45), Color(Palette.GOLD, 0.55 * alpha), false)
	_ellipse(base + Vector2(r * 0.12, r * 0.08), Vector2(r * 0.85, r * 0.3), Color(0, 0, 0, 0.45 * alpha))
	var light := color.lightened(0.35)
	var dark := color.darkened(0.35)
	match kind:
		"object":
			var box := Rect2(center - Vector2(r * 0.75, r * 0.35), Vector2(r * 1.5, r * 0.95))
			draw_rect(box, color)
			draw_rect(Rect2(box.position, Vector2(box.size.x, box.size.y * 0.35)), light)
			draw_rect(box, ring, false, maxf(1.0, cs * 0.04))
			draw_rect(Rect2(box.get_center() - Vector2(r * 0.12, r * 0.05), Vector2(r * 0.24, r * 0.26)), Palette.GOLD)
		"monster":
			var body := center + Vector2(0, r * 0.05)
			for side in [-1, 1]:
				var horn := PackedVector2Array([body + Vector2(side * r * 0.35, -r * 0.45), body + Vector2(side * r * 0.75, -r * 1.05), body + Vector2(side * r * 0.08, -r * 0.6)])
				draw_colored_polygon(horn, Color("e8e0cc", alpha))
			draw_circle(body, r * 0.72, ring)
			draw_circle(body, r * 0.64, color)
			draw_circle(body + Vector2(-r * 0.22, -r * 0.25), r * 0.28, Color(light, 0.5 * alpha))
			for side in [-1, 1]:
				draw_circle(body + Vector2(side * r * 0.24, -r * 0.05), r * 0.11, Color("ffdf6a", alpha))
				draw_circle(body + Vector2(side * r * 0.24, -r * 0.05), r * 0.05, Color("1c1a20", alpha))
		_:
			# Pion : socle, corps évasé, tête ronde.
			_ellipse(base, Vector2(r * 0.72, r * 0.26), dark)
			_ellipse(base - Vector2(0, r * 0.06), Vector2(r * 0.68, r * 0.23), color)
			var body := PackedVector2Array([
				base + Vector2(-r * 0.55, -r * 0.08), base + Vector2(r * 0.55, -r * 0.08),
				center + Vector2(r * 0.2, -r * 0.18), center + Vector2(-r * 0.2, -r * 0.18)])
			draw_colored_polygon(body, color)
			draw_colored_polygon(PackedVector2Array([body[0], body[3], center + Vector2(-r * 0.05, -r * 0.18), base + Vector2(-r * 0.2, -r * 0.08)]), Color(light, 0.55 * alpha))
			draw_colored_polygon(PackedVector2Array([body[1], body[2], center + Vector2(r * 0.1, -r * 0.18), base + Vector2(r * 0.25, -r * 0.08)]), Color(dark, 0.5 * alpha))
			var head := center + Vector2(0, -r * 0.48)
			draw_circle(head, r * 0.36, ring)
			draw_circle(head, r * 0.31, color)
			draw_circle(head + Vector2(-r * 0.1, -r * 0.1), r * 0.12, Color(1, 1, 1, 0.35 * alpha))
			draw_polyline(PackedVector2Array([body[0], body[3], body[2], body[1]]), ring, maxf(1.0, cs * 0.035), true)
	# Initiales sur une petite plaque
	var initials := CharacterData.initials_of(String(t.get("name", "?")))
	var fs := maxi(7, int(r * 0.5))
	if cs >= 16:
		var tw := _font.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var plate := Rect2(base + Vector2(-tw * 0.5 - 3, -fs * 0.55), Vector2(tw + 6, fs + 2))
		draw_rect(plate, Color(0.08, 0.07, 0.1, 0.75 * alpha))
		draw_string(_font, Vector2(plate.position.x + 3, plate.position.y + _font.get_ascent(fs)), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Palette.TEXT, alpha))
	if knocked_out:
		draw_line(center + Vector2(-r, -r) * 0.7, center + Vector2(r, r) * 0.7, Palette.DANGER, maxf(2.0, cs * 0.08))
		draw_line(center + Vector2(r, -r) * 0.7, center + Vector2(-r, r) * 0.7, Palette.DANGER, maxf(2.0, cs * 0.08))
	var hp_max := int(t.get("hp_max", 0))
	if hp_max > 0 and cs >= 18:
		var ratio := clampf(float(t.get("hp", 0)) / hp_max, 0.0, 1.0)
		var bar := Rect2(center + Vector2(-r * 0.8, -r * 1.1), Vector2(r * 1.6, maxf(3, cs * 0.08)))
		draw_rect(bar.grow(1), Color(0, 0, 0, 0.65 * alpha))
		var hc := Palette.OK if ratio > 0.5 else (Palette.WARN if ratio > 0.25 else Palette.DANGER)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(hc, alpha))
	var effects: Array = t.get("effects", [])
	if not effects.is_empty() and cs >= 22:
		var isz := clampf(cs * 0.3, 9, 18)
		var n := mini(effects.size(), 4)
		var start := center + Vector2(-isz * n * 0.5, -r * 1.1 - isz - 3)
		for i in n:
			var e: Dictionary = effects[i]
			var ec := Color(String(e.get("color", "#a07cc9")))
			var rect := Rect2(start + Vector2(i * isz, 0), Vector2(isz, isz))
			draw_circle(rect.get_center(), isz * 0.5, Color(ec.darkened(0.7), 0.9 * alpha))
			Icons.paint(self, String(e.get("icon", "sparkle")), rect.grow(-isz * 0.12), Color(ec.lightened(0.2), alpha))
	if cs >= 30:
		var name_text := String(t.get("name", ""))
		var nfs := clampi(int(cs * 0.28), 9, 15)
		var ts := _font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs)
		var pos := base + Vector2(-ts.x * 0.5, r * 0.3 + nfs)
		draw_rect(Rect2(pos - Vector2(4, nfs), Vector2(ts.x + 8, nfs + 4)), Color(0, 0, 0, 0.6 * alpha))
		draw_string(_font, pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(Palette.TEXT, alpha))


func _ellipse(center: Vector2, radii: Vector2, color: Color, filled: bool = true) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		draw_polyline(pts, color, 2.0, true)


func _text(center_baseline: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, center_baseline - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


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
	if tool == "move" and not target_mode:
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
	if target_mode:
		var target := MapData.token_at(map, c.x, c.y)
		if not target.is_empty():
			target_picked.emit(target.id)
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
