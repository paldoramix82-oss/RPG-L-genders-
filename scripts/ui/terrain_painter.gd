class_name TerrainPainter
extends Control
## Dessine tout le terrain d'une carte une seule fois, dans une texture (SubViewport) :
## dégradés entre terrains, rivages, arbres, montagnes, toits, murs, détails.
## MapView affiche ensuite cette texture : rapide même pour les grandes cartes.

## Taille de la texture limitée à 2048 px : garanti sur tous les téléphones (OpenGL ES 3).
const MAX_TEXTURE := 2048.0

var S := 24.0  # pixels par case dans la texture

var map := {}
var _cells := ""
var _w := 0
var _h := 0

const WATER := ["w", "W"]
const BUILDINGS := ["b", "R"]


func setup(new_map: Dictionary) -> void:
	map = new_map
	_cells = map.cells
	_w = int(map.w)
	_h = int(map.h)
	S = clampf(floorf(MAX_TEXTURE / maxi(_w, _h)), 12.0, 40.0)
	size = Vector2(_w, _h) * S
	queue_redraw()


func _code(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return ""
	return _cells[y * _w + x]


static func _n(x: int, y: int, k: int = 0) -> float:
	var h := (x * 374761393 + y * 668265263 + k * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10007.0


func _draw() -> void:
	if _w == 0:
		return
	# 1. Fond texturé
	for y in _h:
		for x in _w:
			_base(x, y, _code(x, y))
	# 2. Transitions douces entre terrains voisins
	for y in _h:
		for x in _w:
			_blend(x, y)
	# 3. Rivages
	for y in _h:
		for x in _w:
			_shore(x, y)
	# 4. Détails et reliefs, ligne par ligne (les éléments du bas recouvrent ceux du haut)
	for y in _h:
		for x in _w:
			_detail(x, y, _code(x, y))


func _base(x: int, y: int, code: String) -> void:
	var c := MapData.terrain_color(code)
	var p := Vector2(x, y) * S
	var half := S * 0.5
	for i in 4:
		var q := Vector2(i % 2, i / 2) * half
		draw_rect(Rect2(p + q, Vector2(half, half)), c.lightened((_n(x, y, i) - 0.5) * 0.09))


func _blend(x: int, y: int) -> void:
	var code := _code(x, y)
	var p := Vector2(x, y) * S
	var depth := S * 0.42
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var other := _code(x + d.x, y + d.y)
		if other == "" or other == code or other == "v" or code == "v":
			continue
		var oc := MapData.terrain_color(other)
		var a := Color(oc, 0.42)
		var z := Color(oc, 0.0)
		var pts: PackedVector2Array
		match d:
			Vector2i.LEFT:
				pts = [p, p + Vector2(depth, 0), p + Vector2(depth, S), p + Vector2(0, S)]
			Vector2i.RIGHT:
				pts = [p + Vector2(S, 0), p + Vector2(S, S), p + Vector2(S - depth, S), p + Vector2(S - depth, 0)]
			Vector2i.UP:
				pts = [p, p + Vector2(S, 0), p + Vector2(S, depth), p + Vector2(0, depth)]
			_:
				pts = [p + Vector2(0, S), p + Vector2(0, S - depth), p + Vector2(S, S - depth), p + Vector2(S, S)]
		var cols := PackedColorArray([a, z, z, a]) if d in [Vector2i.LEFT, Vector2i.UP] else PackedColorArray([a, a, z, z])
		draw_polygon(pts, cols)


func _shore(x: int, y: int) -> void:
	var code := _code(x, y)
	var water := code in WATER
	var p := Vector2(x, y) * S
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var other := _code(x + d.x, y + d.y)
		if other == "" or (other in WATER) == water:
			continue
		var a := p + Vector2(maxi(d.x, 0), maxi(d.y, 0)) * S
		var b := a + (Vector2(0, S) if d.x != 0 else Vector2(S, 0))
		var inward := -Vector2(d) * (2.0 if water else 1.5)
		if water:
			draw_line(a + inward, b + inward, Color(1, 1, 1, 0.28), 2.0)
			draw_line(a + inward * 2.5, b + inward * 2.5, Color(1, 1, 1, 0.1), 1.5)
		elif other in WATER:
			draw_line(a + inward, b + inward, Color(0, 0, 0, 0.18), 2.0)


func _detail(x: int, y: int, code: String) -> void:
	var p := Vector2(x, y) * S
	var c := p + Vector2(S, S) * 0.5
	var base := MapData.terrain_color(code)
	var n := _n(x, y, 7)
	match code:
		".":
			if n < 0.3:
				_tuft(p + Vector2(_n(x, y, 1), _n(x, y, 2)) * S * 0.8 + Vector2(2, 4), base)
			elif n > 0.93:
				draw_circle(p + Vector2(_n(x, y, 3), _n(x, y, 4)) * S, 1.6, [Color("e8d27a"), Color("d98ca8"), Color("f2f0e6")][int(n * 100) % 3])
		"y":
			for i in 5:
				var fp := p + Vector2(_n(x, y, 10 + i), _n(x, y, 20 + i)) * S
				draw_circle(fp, 1.7, [Color("f0d36a"), Color("e58fb0"), Color("f4f1e8"), Color("a99ae0")][i % 4])
			_tuft(p + Vector2(S * 0.3, S * 0.6), base)
		"z":
			for i in 4:
				var yy := p.y + S * (0.15 + i * 0.25)
				draw_line(Vector2(p.x, yy), Vector2(p.x + S, yy + S * 0.08), base.darkened(0.2), 1.0)
			if n > 0.7:
				draw_line(p + Vector2(S * 0.5, S * 0.2), p + Vector2(S * 0.5, S * 0.5), Color("c9b56a"), 1.0)
		"f", "F":
			var count := 2 if code == "f" else 3
			for i in count:
				var tp := p + Vector2(_n(x, y, 30 + i) * 0.6 + 0.2, _n(x, y, 40 + i) * 0.6 + 0.2) * S
				var r := S * (0.3 if code == "f" else 0.36) * (0.85 + _n(x, y, 50 + i) * 0.35)
				_tree(tp, r, base, code == "F")
		"m":
			_mountain(c + Vector2(0, S * 0.1), S * (0.62 + n * 0.2), base)
		"h":
			draw_circle(c + Vector2(0, S * 0.22), S * 0.42, Color(base.darkened(0.12), 0.6))
			draw_arc(c + Vector2(0, S * 0.3), S * 0.4, PI * 1.05, PI * 1.95, 12, base.lightened(0.18), 2.0, true)
		"q":
			for i in 3:
				var rp := p + Vector2(_n(x, y, 60 + i) * 0.6 + 0.2, _n(x, y, 70 + i) * 0.6 + 0.2) * S
				var rr := S * (0.12 + _n(x, y, 80 + i) * 0.1)
				draw_circle(rp + Vector2(1, 2), rr, Color(0, 0, 0, 0.3))
				draw_circle(rp, rr, base.lightened(0.05))
				draw_circle(rp - Vector2(rr, rr) * 0.3, rr * 0.45, base.lightened(0.25))
		"b", "R":
			_roof(x, y, p, base)
		"#":
			draw_rect(Rect2(p, Vector2(S, S)), base.lightened(0.12))
			if _code(x, y + 1) != "#":
				draw_rect(Rect2(p + Vector2(0, S * 0.55), Vector2(S, S * 0.45)), base.darkened(0.25))
				for i in 3:
					draw_line(p + Vector2(i * S / 3.0 + (S / 6.0 if i % 2 else 0.0), S * 0.55), p + Vector2(i * S / 3.0 + (S / 6.0 if i % 2 else 0.0), S), base.darkened(0.45), 1.0)
				draw_line(p + Vector2(0, S * 0.78), p + Vector2(S, S * 0.78), base.darkened(0.45), 1.0)
			draw_line(p, p + Vector2(S, 0), base.lightened(0.3), 1.0)
		"d":
			for i in range(1, 4):
				var yy := p.y + S * i / 4.0
				draw_line(Vector2(p.x, yy), Vector2(p.x + S, yy), base.darkened(0.25), 1.0)
			var xx := p.x + S * (0.3 + 0.4 * _n(x, y, 1))
			draw_line(Vector2(xx, p.y), Vector2(xx, p.y + S * 0.25), base.darkened(0.25), 1.0)
		"o":
			draw_rect(Rect2(p + Vector2(1, 1), Vector2(S - 2, S - 2)), base.darkened(0.18), false, 1.0)
			if n > 0.8:
				draw_line(p + Vector2(S * 0.2, S * 0.3), p + Vector2(S * 0.6, S * 0.7), base.darkened(0.3), 1.0)
		"p":
			for i in 4:
				var q := p + Vector2(i % 2, i / 2) * S * 0.5 + Vector2(S * 0.06, S * 0.06)
				draw_rect(Rect2(q, Vector2(S * 0.38, S * 0.38)), base.lightened(0.06 + (_n(x, y, i) - 0.5) * 0.12))
		"r":
			draw_rect(Rect2(p + Vector2(0, S * 0.25), Vector2(S, S * 0.5)), base.lightened(0.06))
			for i in 2:
				draw_circle(p + Vector2(_n(x, y, 90 + i), _n(x, y, 95 + i)) * S, 1.2, base.darkened(0.3))
		"B":
			for i in range(0, 5):
				var xx := p.x + S * i / 4.0
				draw_line(Vector2(xx, p.y + 2), Vector2(xx, p.y + S - 2), base.darkened(0.3), 1.0)
			draw_line(p + Vector2(0, 2), p + Vector2(S, 2), base.darkened(0.45), 2.0)
			draw_line(p + Vector2(0, S - 2), p + Vector2(S, S - 2), base.darkened(0.45), 2.0)
		"w", "W":
			var wc := Color(1, 1, 1, 0.12 if code == "w" else 0.07)
			var yy := p.y + S * (0.3 + n * 0.4)
			var xx := p.x + S * _n(x, y, 3) * 0.5
			draw_arc(Vector2(xx + S * 0.15, yy), S * 0.15, PI * 1.15, PI * 1.85, 6, wc, 1.2, true)
			if n > 0.85:
				draw_circle(p + Vector2(_n(x, y, 5), _n(x, y, 6)) * S, 1.0, Color(1, 1, 1, 0.35))
		"g":
			draw_line(p + Vector2(S * _n(x, y, 1), 0), p + Vector2(S * _n(x, y, 2), S), Color(1, 1, 1, 0.35), 1.0)
		"n":
			if n > 0.6:
				draw_circle(p + Vector2(_n(x, y, 1), _n(x, y, 2)) * S, S * 0.12, Color(0.75, 0.8, 0.88, 0.5))
		"s":
			draw_arc(c + Vector2(0, S * (n - 0.5) * 0.4), S * 0.35, PI * 1.2, PI * 1.8, 8, base.darkened(0.12), 1.0, true)
		"c":
			for i in 3:
				var e := p + Vector2(_n(x, y, 40 + i), _n(x, y, 50 + i)) * S
				draw_circle(e, 1.1, Color("e07a3a") if _n(x, y, 60 + i) > 0.8 else base.lightened(0.2))
		"l":
			draw_circle(p + Vector2(_n(x, y, 1), _n(x, y, 2)) * S, S * 0.22, Color("f2a43c", 0.8))
			draw_circle(p + Vector2(_n(x, y, 3), _n(x, y, 4)) * S, S * 0.12, Color("ffd76a", 0.9))
			draw_line(p + Vector2(0, S * n), p + Vector2(S, S * _n(x, y, 9)), Color("5a1e12", 0.6), 1.5)
		"k":
			draw_circle(p + Vector2(_n(x, y, 1) * 0.6 + 0.2, _n(x, y, 2) * 0.6 + 0.2) * S, S * 0.16, Color("2f4a52", 0.7))
			for i in 3:
				var rx := p.x + S * (0.2 + i * 0.28)
				draw_line(Vector2(rx, p.y + S * 0.85), Vector2(rx + S * 0.05, p.y + S * 0.45), Color("7a8a4e"), 1.0)
		"x", "u":
			for i in 3:
				var sp := p + Vector2(_n(x, y, 20 + i), _n(x, y, 30 + i)) * S
				draw_rect(Rect2(sp, Vector2(3, 2)), base.darkened(0.35) if i % 2 else base.lightened(0.15))
		"a":
			_crystal(c, base)
		"t":
			draw_rect(Rect2(p + Vector2(S * 0.15, S * 0.25), Vector2(S * 0.7, S * 0.55)), Color(0, 0, 0, 0.3))
			draw_rect(Rect2(p + Vector2(S * 0.12, S * 0.18), Vector2(S * 0.7, S * 0.5)), Color("7a5634"))
			draw_rect(Rect2(p + Vector2(S * 0.12, S * 0.18), Vector2(S * 0.7, S * 0.08)), Color("9a7044"))


func _tuft(at: Vector2, base: Color) -> void:
	var col := base.lightened(0.22)
	draw_line(at, at + Vector2(-2, -4), col, 1.0)
	draw_line(at, at + Vector2(0, -5), col, 1.0)
	draw_line(at, at + Vector2(2, -4), col, 1.0)


func _tree(at: Vector2, r: float, base: Color, dense: bool) -> void:
	draw_circle(at + Vector2(r * 0.25, r * 0.45), r, Color(0, 0, 0, 0.28))
	draw_rect(Rect2(at + Vector2(-r * 0.12, r * 0.4), Vector2(r * 0.24, r * 0.5)), Color("4a3524"))
	draw_circle(at, r, base.darkened(0.3 if dense else 0.2))
	draw_circle(at + Vector2(-r * 0.15, -r * 0.15), r * 0.75, base.lightened(0.05))
	draw_circle(at + Vector2(-r * 0.3, -r * 0.35), r * 0.38, base.lightened(0.22))


func _mountain(at: Vector2, w: float, base: Color) -> void:
	var top := at + Vector2(0, -w * 0.8)
	var left := at + Vector2(-w * 0.75, w * 0.35)
	var right := at + Vector2(w * 0.75, w * 0.35)
	draw_colored_polygon(PackedVector2Array([left + Vector2(4, 3), top + Vector2(4, 3), right + Vector2(4, 3)]), Color(0, 0, 0, 0.25))
	draw_colored_polygon(PackedVector2Array([left, top, at + Vector2(0, w * 0.35)]), base.lightened(0.12))
	draw_colored_polygon(PackedVector2Array([top, right, at + Vector2(0, w * 0.35)]), base.darkened(0.2))
	var snow := 0.32
	draw_colored_polygon(PackedVector2Array([top, top.lerp(left, snow), top.lerp(at + Vector2(0, w * 0.35), snow * 0.8), top.lerp(right, snow)]), Color("eceae4"))


func _roof(x: int, y: int, p: Vector2, base: Color) -> void:
	var same := func(dx: int, dy: int) -> bool: return _code(x + dx, y + dy) in BUILDINGS
	# Ombre portée sur le sol au sud et à l'est du bâtiment.
	if not same.call(0, 1):
		draw_rect(Rect2(p + Vector2(0, S), Vector2(S, S * 0.25)), Color(0, 0, 0, 0.25))
	if not same.call(1, 0):
		draw_rect(Rect2(p + Vector2(S, S * 0.2), Vector2(S * 0.2, S)), Color(0, 0, 0, 0.18))
	draw_rect(Rect2(p, Vector2(S, S)), base)
	# Toit à deux pans : moitié haute claire, moitié basse sombre, faîtage au milieu.
	draw_rect(Rect2(p, Vector2(S, S * 0.5)), base.lightened(0.12))
	draw_rect(Rect2(p + Vector2(0, S * 0.5), Vector2(S, S * 0.5)), base.darkened(0.12))
	draw_line(p + Vector2(0, S * 0.5), p + Vector2(S, S * 0.5), base.darkened(0.35), 1.5)
	for i in range(1, 3):
		draw_line(p + Vector2(0, S * i / 6.0), p + Vector2(S, S * i / 6.0), base.darkened(0.05), 1.0)
		draw_line(p + Vector2(0, S * 0.5 + S * i / 6.0), p + Vector2(S, S * 0.5 + S * i / 6.0), base.darkened(0.22), 1.0)
	if not same.call(-1, 0):
		draw_line(p, p + Vector2(0, S), base.darkened(0.4), 1.5)
	if not same.call(1, 0):
		draw_line(p + Vector2(S, 0), p + Vector2(S, S), base.darkened(0.4), 1.5)
	if not same.call(0, -1):
		draw_line(p, p + Vector2(S, 0), base.lightened(0.3), 1.5)
	if not same.call(0, 1):
		draw_line(p + Vector2(0, S), p + Vector2(S, S), base.darkened(0.45), 1.5)


func _crystal(at: Vector2, base: Color) -> void:
	draw_circle(at, S * 0.42, Color("b8a8f0", 0.18))
	for spec in [[-0.18, 0.5, 0.14], [0.05, 0.75, 0.16], [0.22, 0.45, 0.12]]:
		var bx: float = at.x + S * spec[0]
		var h: float = S * spec[1]
		var w: float = S * spec[2]
		var bottom := at.y + S * 0.3
		var pts := PackedVector2Array([Vector2(bx - w, bottom), Vector2(bx - w * 0.8, bottom - h * 0.7), Vector2(bx, bottom - h), Vector2(bx + w * 0.8, bottom - h * 0.7), Vector2(bx + w, bottom)])
		draw_colored_polygon(pts, Color("9d8cdc"))
		draw_colored_polygon(PackedVector2Array([Vector2(bx - w * 0.8, bottom - h * 0.7), Vector2(bx, bottom - h), Vector2(bx, bottom)]), Color("cfc4fa"))
