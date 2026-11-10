class_name OrnateStyle
extends StyleBox
## Habillage des panneaux et boutons : coins biseautés (pas d'arrondis « logiciel »),
## léger dégradé vertical, bordure fine, liseré intérieur et petites équerres
## dorées dans les coins. Dessiné en code : aucune image nécessaire.

var bg_top := Palette.PANEL
var bg_bottom := Palette.PANEL
var border := Palette.BORDER
var border_width := 1.0
## Couleur des équerres de coin et du liseré (transparent = aucun).
var accent := Color(0, 0, 0, 0)
## Taille du biseau des coins (px).
var cut := 6.0
## Liseré intérieur discret.
var inner_line := false
## Trait lumineux en haut (boutons, barres).
var top_glint := false


static func make(top: Color, bottom: Color, edge: Color, accent_color: Color = Color(0, 0, 0, 0), bevel: float = 6.0, margin: float = 12.0) -> OrnateStyle:
	var s := OrnateStyle.new()
	s.bg_top = top
	s.bg_bottom = bottom
	s.border = edge
	s.accent = accent_color
	s.cut = bevel
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.7
	s.content_margin_bottom = margin * 0.7
	return s


func _shape(r: Rect2, c: float) -> PackedVector2Array:
	c = minf(c, minf(r.size.x, r.size.y) * 0.3)
	var p := r.position
	var e := r.end
	return PackedVector2Array([
		Vector2(p.x + c, p.y), Vector2(e.x - c, p.y), Vector2(e.x, p.y + c), Vector2(e.x, e.y - c),
		Vector2(e.x - c, e.y), Vector2(p.x + c, e.y), Vector2(p.x, e.y - c), Vector2(p.x, p.y + c),
	])


func _draw(ci: RID, rect: Rect2) -> void:
	if rect.size.x < 2 or rect.size.y < 2:
		return
	var pts := _shape(rect, cut)
	var cols := PackedColorArray()
	for pt in pts:
		cols.append(bg_top.lerp(bg_bottom, clampf((pt.y - rect.position.y) / rect.size.y, 0.0, 1.0)))
	if bg_top.a > 0 or bg_bottom.a > 0:
		RenderingServer.canvas_item_add_polygon(ci, pts, cols)
	if top_glint:
		var g := rect.grow(-maxf(2.0, cut * 0.5))
		RenderingServer.canvas_item_add_line(ci, Vector2(g.position.x + cut, rect.position.y + 1.5), Vector2(g.end.x - cut, rect.position.y + 1.5), Color(1, 1, 1, 0.08), 1.0)
	if border.a > 0 and border_width > 0:
		var loop := pts.duplicate()
		loop.append(pts[0])
		RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([border]), border_width, true)
	if inner_line and accent.a > 0:
		var inner := _shape(rect.grow(-4), maxf(0.0, cut - 2))
		inner.append(inner[0])
		RenderingServer.canvas_item_add_polyline(ci, inner, PackedColorArray([Color(accent, accent.a * 0.25)]), 1.0, true)
	if accent.a > 0 and rect.size.x > 40 and rect.size.y > 30:
		_corners(ci, rect)


## Équerres dorées : un petit angle et un losange à chaque coin.
func _corners(ci: RID, r: Rect2) -> void:
	var l := clampf(minf(r.size.x, r.size.y) * 0.12, 7.0, 16.0)
	var o := 3.0
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var sx := 1.0 if corner.x == 0 else -1.0
		var sy := 1.0 if corner.y == 0 else -1.0
		var p := r.position + r.size * corner + Vector2(sx * o, sy * o)
		var a := p + Vector2(sx * (cut * 0.5 + l), 0)
		var b := p + Vector2(sx * cut * 0.5, 0)
		var c := p + Vector2(0, sy * cut * 0.5)
		var d := p + Vector2(0, sy * (cut * 0.5 + l))
		RenderingServer.canvas_item_add_polyline(ci, PackedVector2Array([a, b, c, d]), PackedColorArray([accent]), 1.5, true)
		var m := p + Vector2(sx * (cut * 0.5 + l + 4), 0)
		RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([m + Vector2(-2, 0), m + Vector2(0, -2), m + Vector2(2, 0), m + Vector2(0, 2)]), PackedColorArray([accent]))
