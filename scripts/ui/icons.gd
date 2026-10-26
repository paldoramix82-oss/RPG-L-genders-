class_name Icons
extends Control
## Icônes vectorielles du jeu (objets, capacités, effets), dessinées en code :
## aucune image externe, nettes à toutes les tailles. Les coordonnées sont dans
## un carré unité centré (−0,5 … 0,5).
##
## Utilisation : Icons.new("sword", couleur, 40) comme contrôle, ou
## Icons.paint(canvas, "sword", rect, couleur) dans un _draw().

var icon := "star"
var color := Palette.GOLD
## Fond (pastille) : transparent par défaut.
var backing := Color(0, 0, 0, 0)
var frame := Color(0, 0, 0, 0)


func _init(icon_name: String = "star", icon_color: Color = Palette.GOLD, px: float = 32.0) -> void:
	icon = icon_name
	color = icon_color
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_icon(icon_name: String, icon_color: Color = color) -> void:
	icon = icon_name
	color = icon_color
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var r := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
	if backing.a > 0:
		draw_circle(r.get_center(), s * 0.5, backing)
	if frame.a > 0:
		draw_arc(r.get_center(), s * 0.5 - 1, 0, TAU, 32, frame, 1.5, true)
	paint(self, icon, r.grow(-s * 0.12) if backing.a > 0 else r, color)


static func paint(ci: CanvasItem, name: String, rect: Rect2, col: Color) -> void:
	var c := rect.get_center()
	var s := minf(rect.size.x, rect.size.y)
	var w := maxf(1.5, s * 0.08)
	var dark := col.darkened(0.55)
	var light := col.lightened(0.3)
	var P := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * s
	var line := func(a: Vector2, b: Vector2, width: float = 1.0, k: Color = col) -> void: ci.draw_line(P.call(a.x, a.y), P.call(b.x, b.y), k, w * width, true)
	var poly := func(pts: Array, k: Color = col) -> void:
		var arr := PackedVector2Array()
		for p in pts:
			arr.append(P.call(p.x, p.y))
		ci.draw_colored_polygon(arr, k)
	var circ := func(x: float, y: float, rad: float, k: Color = col) -> void: ci.draw_circle(P.call(x, y), rad * s, k)
	var ring := func(x: float, y: float, rad: float, width: float = 1.0, k: Color = col) -> void: ci.draw_arc(P.call(x, y), rad * s, 0, TAU, 28, k, w * width, true)
	var arc := func(x: float, y: float, rad: float, a0: float, a1: float, width: float = 1.0, k: Color = col) -> void: ci.draw_arc(P.call(x, y), rad * s, a0, a1, 20, k, w * width, true)
	match name:
		"sword":
			poly.call([Vector2(-0.04, 0.12), Vector2(0.04, 0.12), Vector2(0.04, -0.36), Vector2(0, -0.45), Vector2(-0.04, -0.36)], light)
			line.call(Vector2(-0.18, 0.13), Vector2(0.18, 0.13), 1.2)
			line.call(Vector2(0, 0.13), Vector2(0, 0.36), 1.3, dark.lightened(0.3))
			circ.call(0, 0.4, 0.05)
		"axe":
			line.call(Vector2(-0.05, 0.45), Vector2(0.05, -0.4), 1.2, Color("9a7044"))
			poly.call([Vector2(0.02, -0.32), Vector2(0.32, -0.42), Vector2(0.36, -0.05), Vector2(0.06, -0.12)], light)
		"hammer":
			line.call(Vector2(0, 0.45), Vector2(0, -0.2), 1.2, Color("9a7044"))
			poly.call([Vector2(-0.3, -0.42), Vector2(0.3, -0.42), Vector2(0.3, -0.14), Vector2(-0.3, -0.14)], light)
		"spear":
			line.call(Vector2(-0.3, 0.42), Vector2(0.2, -0.28), 1.0, Color("9a7044"))
			poly.call([Vector2(0.14, -0.2), Vector2(0.38, -0.42), Vector2(0.24, -0.14)], light)
		"dagger":
			poly.call([Vector2(-0.04, 0.05), Vector2(0.04, 0.05), Vector2(0, -0.42)], light)
			line.call(Vector2(-0.14, 0.06), Vector2(0.14, 0.06), 1.1)
			line.call(Vector2(0, 0.06), Vector2(0, 0.3), 1.2, dark.lightened(0.3))
		"bow":
			arc.call(-0.15, 0, 0.42, -PI * 0.42, PI * 0.42, 1.0, Color("b08a5a"))
			line.call(Vector2(-0.15 + 0.42 * cos(PI * 0.42), -0.42 * sin(PI * 0.42)), Vector2(-0.15 + 0.42 * cos(PI * 0.42), 0.42 * sin(PI * 0.42)), 0.4, Palette.TEXT)
			line.call(Vector2(-0.3, 0), Vector2(0.38, 0), 0.7, light)
			poly.call([Vector2(0.42, 0), Vector2(0.32, -0.06), Vector2(0.32, 0.06)], light)
		"crossbow":
			line.call(Vector2(0, -0.35), Vector2(0, 0.4), 1.2, Color("9a7044"))
			arc.call(0, -0.05, 0.35, PI * 1.1, PI * 1.9, 1.0, light)
			line.call(Vector2(-0.33, -0.15), Vector2(0.33, -0.15), 0.4, Palette.TEXT)
		"gun":
			poly.call([Vector2(-0.38, -0.12), Vector2(0.38, -0.12), Vector2(0.38, 0.02), Vector2(-0.38, 0.02)], light)
			poly.call([Vector2(-0.3, 0.0), Vector2(-0.12, 0.0), Vector2(-0.18, 0.32), Vector2(-0.34, 0.3)], dark.lightened(0.3))
		"staff":
			line.call(Vector2(-0.22, 0.42), Vector2(0.12, -0.25), 1.1, Color("9a7044"))
			circ.call(0.16, -0.32, 0.12, Color("9fc3d4"))
			circ.call(0.13, -0.35, 0.04, Color.WHITE)
		"wand":
			line.call(Vector2(-0.3, 0.35), Vector2(0.15, -0.15), 0.9, Color("6b4a2a"))
			poly.call([Vector2(0.24, -0.38), Vector2(0.29, -0.26), Vector2(0.4, -0.24), Vector2(0.3, -0.17), Vector2(0.33, -0.05), Vector2(0.24, -0.12), Vector2(0.15, -0.05), Vector2(0.17, -0.17), Vector2(0.08, -0.24), Vector2(0.19, -0.26)], Color("ffd76a"))
		"lute", "music":
			if name == "lute":
				circ.call(-0.08, 0.14, 0.2, Color("9a7044"))
				line.call(Vector2(0.04, 0.02), Vector2(0.3, -0.36), 1.0, Color("6b4a2a"))
				circ.call(-0.08, 0.14, 0.06, dark)
			else:
				circ.call(-0.18, 0.28, 0.1)
				circ.call(0.2, 0.2, 0.1)
				line.call(Vector2(-0.1, 0.28), Vector2(-0.1, -0.32))
				line.call(Vector2(0.28, 0.2), Vector2(0.28, -0.4))
				line.call(Vector2(-0.1, -0.32), Vector2(0.28, -0.4), 1.6)
		"claw":
			for i in 3:
				var x := -0.2 + i * 0.2
				arc.call(x - 0.15, 0.1, 0.3, -PI * 0.45, PI * 0.05, 0.9, light)
		"fist":
			poly.call([Vector2(-0.26, -0.12), Vector2(0.26, -0.12), Vector2(0.26, 0.3), Vector2(-0.26, 0.3)], col)
			for i in 4:
				circ.call(-0.2 + i * 0.133, -0.14, 0.075, light)
		"armor":
			poly.call([Vector2(-0.34, -0.3), Vector2(-0.12, -0.38), Vector2(0, -0.28), Vector2(0.12, -0.38), Vector2(0.34, -0.3), Vector2(0.26, 0.0), Vector2(0.22, 0.4), Vector2(-0.22, 0.4), Vector2(-0.26, 0.0)], col)
			line.call(Vector2(0, -0.26), Vector2(0, 0.38), 0.6, dark)
		"robe":
			poly.call([Vector2(-0.14, -0.4), Vector2(0.14, -0.4), Vector2(0.36, 0.4), Vector2(-0.36, 0.4)], col)
			line.call(Vector2(-0.2, 0.0), Vector2(0.2, 0.0), 0.8, Palette.GOLD)
		"cloak":
			poly.call([Vector2(0, -0.42), Vector2(0.36, 0.4), Vector2(0, 0.28), Vector2(-0.36, 0.4)], col)
			circ.call(0, -0.3, 0.06, Palette.GOLD)
		"shield":
			poly.call([Vector2(-0.32, -0.38), Vector2(0.32, -0.38), Vector2(0.32, 0.02), Vector2(0, 0.42), Vector2(-0.32, 0.02)], col)
			line.call(Vector2(0, -0.32), Vector2(0, 0.32), 0.7, light)
			line.call(Vector2(-0.26, -0.08), Vector2(0.26, -0.08), 0.7, light)
		"ward":
			arc.call(0, 0.05, 0.36, PI, TAU, 1.2, col)
			arc.call(0, 0.05, 0.22, PI, TAU, 0.8, light)
			line.call(Vector2(-0.36, 0.05), Vector2(0.36, 0.05), 0.8, col)
		"castle":
			poly.call([Vector2(-0.36, 0.38), Vector2(-0.36, -0.2), Vector2(-0.2, -0.2), Vector2(-0.2, -0.34), Vector2(-0.08, -0.34), Vector2(-0.08, -0.2), Vector2(0.08, -0.2), Vector2(0.08, -0.34), Vector2(0.2, -0.34), Vector2(0.2, -0.2), Vector2(0.36, -0.2), Vector2(0.36, 0.38)], col)
			poly.call([Vector2(-0.08, 0.38), Vector2(-0.08, 0.12), Vector2(0.08, 0.12), Vector2(0.08, 0.38)], dark)
		"ring":
			ring.call(0, 0.08, 0.26, 1.2)
			poly.call([Vector2(0, -0.42), Vector2(0.12, -0.26), Vector2(0, -0.16), Vector2(-0.12, -0.26)], Color("9fd4f0"))
		"amulet":
			arc.call(0, -0.2, 0.28, PI * 0.05, PI * 0.95, 0.6, Palette.GOLD)
			poly.call([Vector2(0, -0.02), Vector2(0.18, 0.2), Vector2(0, 0.42), Vector2(-0.18, 0.2)], col)
			circ.call(0, 0.2, 0.06, light)
		"crown":
			poly.call([Vector2(-0.36, 0.25), Vector2(-0.36, -0.25), Vector2(-0.18, 0.0), Vector2(0, -0.35), Vector2(0.18, 0.0), Vector2(0.36, -0.25), Vector2(0.36, 0.25)], col)
		"boots":
			poly.call([Vector2(-0.22, -0.4), Vector2(0.06, -0.4), Vector2(0.06, 0.12), Vector2(0.38, 0.22), Vector2(0.38, 0.38), Vector2(-0.22, 0.38)], col)
		"eye":
			poly.call([Vector2(-0.42, 0), Vector2(-0.2, -0.2), Vector2(0, -0.24), Vector2(0.2, -0.2), Vector2(0.42, 0), Vector2(0.2, 0.2), Vector2(0, 0.24), Vector2(-0.2, 0.2)], col)
			circ.call(0, 0, 0.13, dark)
			circ.call(-0.04, -0.04, 0.04, Color.WHITE)
		"book":
			poly.call([Vector2(-0.34, -0.36), Vector2(0.3, -0.36), Vector2(0.3, 0.36), Vector2(-0.34, 0.36)], col)
			poly.call([Vector2(-0.26, -0.3), Vector2(0.24, -0.3), Vector2(0.24, 0.3), Vector2(-0.26, 0.3)], Color("ece6da"))
			line.call(Vector2(-0.16, -0.14), Vector2(0.14, -0.14), 0.5, dark)
			line.call(Vector2(-0.16, 0.0), Vector2(0.14, 0.0), 0.5, dark)
			line.call(Vector2(-0.16, 0.14), Vector2(0.06, 0.14), 0.5, dark)
		"scroll", "map":
			poly.call([Vector2(-0.32, -0.3), Vector2(0.32, -0.3), Vector2(0.32, 0.3), Vector2(-0.32, 0.3)], Color("e3d3a8"))
			circ.call(-0.32, -0.3, 0.07, Color("b89c68"))
			circ.call(0.32, 0.3, 0.07, Color("b89c68"))
			if name == "map":
				line.call(Vector2(-0.2, 0.15), Vector2(0.05, -0.1), 0.5, Color("8a5a3a"))
				line.call(Vector2(0.1, -0.15), Vector2(0.2, -0.05), 0.6, Color("c25050"))
				line.call(Vector2(0.2, -0.15), Vector2(0.1, -0.05), 0.6, Color("c25050"))
			else:
				for i in 3:
					line.call(Vector2(-0.2, -0.14 + i * 0.12), Vector2(0.2, -0.14 + i * 0.12), 0.4, Color("8a7550"))
		"potion", "flask":
			var liquid := col
			if name == "potion":
				poly.call([Vector2(-0.08, -0.4), Vector2(0.08, -0.4), Vector2(0.08, -0.16), Vector2(-0.08, -0.16)], Color("b8b4ab"))
				circ.call(0, 0.12, 0.28, Color("c8d4dc", 0.35))
				circ.call(0, 0.16, 0.23, liquid)
				circ.call(-0.08, 0.06, 0.05, Color(1, 1, 1, 0.6))
			else:
				poly.call([Vector2(-0.08, -0.4), Vector2(0.08, -0.4), Vector2(0.08, -0.12), Vector2(0.3, 0.38), Vector2(-0.3, 0.38), Vector2(-0.08, -0.12)], Color("c8d4dc", 0.35))
				poly.call([Vector2(-0.16, 0.08), Vector2(0.16, 0.08), Vector2(0.27, 0.34), Vector2(-0.27, 0.34)], liquid)
		"food":
			circ.call(0.05, -0.05, 0.27, Color("b0605a"))
			line.call(Vector2(-0.12, 0.12), Vector2(-0.36, 0.36), 1.2, Color("e0d6c4"))
		"bomb":
			circ.call(0, 0.08, 0.3, Color("3a3a42"))
			line.call(Vector2(0.18, -0.18), Vector2(0.3, -0.34), 0.7, Color("9a7044"))
			circ.call(0.33, -0.38, 0.07, Color("ffb04a"))
		"leather", "scale":
			poly.call([Vector2(-0.3, -0.3), Vector2(0.1, -0.38), Vector2(0.36, -0.1), Vector2(0.3, 0.32), Vector2(-0.1, 0.38), Vector2(-0.36, 0.1)], col)
			if name == "scale":
				for i in 3:
					arc.call(-0.15 + i * 0.15, 0.0, 0.12, 0, PI, 0.6, light)
		"fang":
			poly.call([Vector2(-0.18, -0.36), Vector2(0.18, -0.36), Vector2(0.04, 0.4)], Color("ece6da"))
		"herb", "leaf":
			poly.call([Vector2(0, -0.42), Vector2(0.26, -0.1), Vector2(0.14, 0.24), Vector2(0, 0.3), Vector2(-0.14, 0.24), Vector2(-0.26, -0.1)], Color("7fb05a") if name == "herb" else col)
			line.call(Vector2(0, -0.3), Vector2(0, 0.42), 0.6, Color("4a6a3a"))
		"ore", "gem", "crystal":
			var gemc := col if name != "ore" else Color("8a8f9a")
			poly.call([Vector2(-0.3, -0.12), Vector2(-0.14, -0.34), Vector2(0.14, -0.34), Vector2(0.3, -0.12), Vector2(0, 0.38)], gemc)
			line.call(Vector2(-0.3, -0.12), Vector2(0.3, -0.12), 0.4, gemc.lightened(0.4))
			line.call(Vector2(-0.14, -0.34), Vector2(0, 0.38), 0.3, gemc.lightened(0.3))
			line.call(Vector2(0.14, -0.34), Vector2(0, 0.38), 0.3, gemc.lightened(0.3))
		"key":
			ring.call(-0.2, -0.2, 0.14, 1.1)
			line.call(Vector2(-0.1, -0.1), Vector2(0.32, 0.32), 1.1)
			line.call(Vector2(0.2, 0.2), Vector2(0.28, 0.12), 1.0)
			line.call(Vector2(0.28, 0.28), Vector2(0.36, 0.2), 1.0)
		"coin":
			circ.call(0, 0, 0.36, Color("d9b45a"))
			ring.call(0, 0, 0.26, 0.6, Color("8a6a2a"))
			circ.call(0, 0, 0.08, Color("f0d78c"))
		"bag":
			poly.call([Vector2(-0.12, -0.3), Vector2(0.12, -0.3), Vector2(0.34, 0.1), Vector2(0.28, 0.4), Vector2(-0.28, 0.4), Vector2(-0.34, 0.1)], Color("9a7044"))
			line.call(Vector2(-0.16, -0.26), Vector2(0.16, -0.26), 0.8, Color("6b4a2a"))
		"fire":
			poly.call([Vector2(0, -0.44), Vector2(0.28, -0.02), Vector2(0.22, 0.3), Vector2(0, 0.42), Vector2(-0.22, 0.3), Vector2(-0.28, -0.02), Vector2(-0.12, -0.12)], Color("e07a3a"))
			poly.call([Vector2(0, -0.1), Vector2(0.13, 0.12), Vector2(0, 0.36), Vector2(-0.13, 0.12)], Color("ffd76a"))
		"meteor":
			line.call(Vector2(-0.4, -0.4), Vector2(0.05, 0.05), 1.5, Color("e07a3a", 0.6))
			circ.call(0.12, 0.12, 0.22, Color("e07a3a"))
			circ.call(0.15, 0.15, 0.1, Color("ffd76a"))
		"ice":
			for i in 3:
				var a := PI * i / 3.0
				line.call(Vector2(cos(a), sin(a)) * 0.4, Vector2(cos(a), sin(a)) * -0.4, 0.9, Color("bfe0f0"))
			circ.call(0, 0, 0.08, Color.WHITE)
		"bolt":
			poly.call([Vector2(0.08, -0.44), Vector2(-0.24, 0.04), Vector2(-0.02, 0.04), Vector2(-0.1, 0.44), Vector2(0.24, -0.06), Vector2(0.02, -0.06)], Color("ffd76a"))
		"heart":
			circ.call(-0.13, -0.08, 0.17, Color("d9606a"))
			circ.call(0.13, -0.08, 0.17, Color("d9606a"))
			poly.call([Vector2(-0.29, -0.02), Vector2(0.29, -0.02), Vector2(0, 0.36)], Color("d9606a"))
		"cross":
			poly.call([Vector2(-0.1, -0.36), Vector2(0.1, -0.36), Vector2(0.1, -0.1), Vector2(0.36, -0.1), Vector2(0.36, 0.1), Vector2(0.1, 0.1), Vector2(0.1, 0.36), Vector2(-0.1, 0.36), Vector2(-0.1, 0.1), Vector2(-0.36, 0.1), Vector2(-0.36, -0.1), Vector2(-0.1, -0.1)], Color("8fd48a"))
		"phoenix":
			poly.call([Vector2(0, -0.1), Vector2(-0.42, -0.36), Vector2(-0.2, 0.05), Vector2(0, 0.42), Vector2(0.2, 0.05), Vector2(0.42, -0.36)], Color("e07a3a"))
			circ.call(0, -0.12, 0.08, Color("ffd76a"))
		"horn":
			poly.call([Vector2(-0.36, -0.3), Vector2(0.2, 0.0), Vector2(0.36, 0.32), Vector2(0.2, 0.36), Vector2(-0.36, -0.14)], Color("d9c49a"))
		"spiral":
			arc.call(0, 0, 0.36, 0, PI * 1.5, 0.9)
			arc.call(0.05, 0.05, 0.22, PI * 0.5, TAU, 0.9)
			arc.call(0, 0, 0.08, 0, PI * 1.5, 0.9)
		"wave":
			for i in 2:
				arc.call(-0.18, -0.05 + i * 0.22, 0.17, PI, TAU, 1.0, col)
				arc.call(0.16, -0.05 + i * 0.22, 0.17, 0, PI, 1.0, col)
		"wind":
			arc.call(0.1, -0.12, 0.15, -PI * 0.9, PI * 0.5, 0.9)
			line.call(Vector2(-0.4, 0.03), Vector2(0.1, 0.03), 0.9)
			line.call(Vector2(-0.4, 0.2), Vector2(0.26, 0.2), 0.9)
			line.call(Vector2(-0.3, -0.14), Vector2(-0.05, -0.14), 0.9)
		"mask":
			poly.call([Vector2(-0.38, -0.2), Vector2(0.38, -0.2), Vector2(0.3, 0.12), Vector2(0.06, 0.2), Vector2(0, 0.1), Vector2(-0.06, 0.2), Vector2(-0.3, 0.12)], col)
			circ.call(-0.16, -0.04, 0.07, dark)
			circ.call(0.16, -0.04, 0.07, dark)
		"drop":
			circ.call(0, 0.12, 0.25, col)
			poly.call([Vector2(0, -0.42), Vector2(0.22, 0.02), Vector2(-0.22, 0.02)], col)
		"sun":
			circ.call(0, 0, 0.2, Color("ffd76a"))
			for i in 8:
				var a := TAU * i / 8.0
				line.call(Vector2(cos(a), sin(a)) * 0.28, Vector2(cos(a), sin(a)) * 0.42, 0.8, Color("ffd76a"))
		"moon":
			circ.call(0, 0, 0.34, col)
			circ.call(0.14, -0.08, 0.28, Palette.BG_DEEP)
		"star", "sparkle":
			var pts: Array = []
			for i in 10:
				var a := -PI / 2 + PI * i / 5.0
				var rad := 0.42 if i % 2 == 0 else (0.17 if name == "star" else 0.1)
				pts.append(Vector2(cos(a), sin(a)) * rad)
			poly.call(pts, col)
		"target":
			ring.call(0, 0, 0.36, 0.9)
			ring.call(0, 0, 0.2, 0.9)
			circ.call(0, 0, 0.06)
		"arrow":
			line.call(Vector2(-0.4, 0.4), Vector2(0.28, -0.28), 0.9, Color("b08a5a"))
			poly.call([Vector2(0.4, -0.4), Vector2(0.14, -0.3), Vector2(0.3, -0.14)], light)
			line.call(Vector2(-0.4, 0.4), Vector2(-0.4, 0.24), 0.8, Palette.TEXT)
			line.call(Vector2(-0.4, 0.4), Vector2(-0.24, 0.4), 0.8, Palette.TEXT)
		"chain":
			for i in 3:
				arc.call(-0.24 + i * 0.24, -0.24 + i * 0.24, 0.14, 0, TAU, 0.8)
		"paw":
			circ.call(0, 0.12, 0.17)
			for p in [Vector2(-0.24, -0.08), Vector2(-0.09, -0.24), Vector2(0.09, -0.24), Vector2(0.24, -0.08)]:
				circ.call(p.x, p.y, 0.08)
		"hand":
			poly.call([Vector2(-0.22, 0.4), Vector2(-0.24, -0.04), Vector2(0.24, -0.04), Vector2(0.22, 0.4)], col)
			for i in 4:
				line.call(Vector2(-0.18 + i * 0.12, -0.04), Vector2(-0.18 + i * 0.12, -0.36 + absf(i - 1.5) * 0.06), 1.4)
		"gear":
			for i in 8:
				var a := TAU * i / 8.0
				line.call(Vector2(cos(a), sin(a)) * 0.16, Vector2(cos(a), sin(a)) * 0.4, 1.6)
			circ.call(0, 0, 0.27)
			circ.call(0, 0, 0.1, dark)
		"skull":
			circ.call(0, -0.08, 0.3, Color("e0dccf"))
			poly.call([Vector2(-0.16, 0.12), Vector2(0.16, 0.12), Vector2(0.14, 0.36), Vector2(-0.14, 0.36)], Color("e0dccf"))
			circ.call(-0.11, -0.06, 0.08, Palette.BG_DEEP)
			circ.call(0.11, -0.06, 0.08, Palette.BG_DEEP)
		"spirit":
			circ.call(0, -0.1, 0.24, col)
			poly.call([Vector2(-0.24, -0.08), Vector2(0.24, -0.08), Vector2(0.16, 0.42), Vector2(0, 0.28), Vector2(-0.16, 0.42)], col)
			circ.call(-0.08, -0.12, 0.04, dark)
			circ.call(0.08, -0.12, 0.04, dark)
		"dragon":
			poly.call([Vector2(-0.4, 0.1), Vector2(-0.1, -0.1), Vector2(0.1, -0.4), Vector2(0.18, -0.1), Vector2(0.42, -0.2), Vector2(0.3, 0.1), Vector2(0.1, 0.36), Vector2(-0.2, 0.3)], col)
			circ.call(0.12, -0.14, 0.04, Color("ffd76a"))
		"xp":
			poly.call([Vector2(0, -0.42), Vector2(0.36, 0), Vector2(0, 0.42), Vector2(-0.36, 0)], Color("8fb2e0"))
			poly.call([Vector2(0, -0.2), Vector2(0.17, 0), Vector2(0, 0.2), Vector2(-0.17, 0)], Color("d8e8ff"))
		"chest":
			poly.call([Vector2(-0.38, -0.08), Vector2(0.38, -0.08), Vector2(0.38, 0.36), Vector2(-0.38, 0.36)], Color("8a5a3a"))
			arc.call(0, -0.08, 0.38, PI, TAU, 1.6, Color("9a6a42"))
			line.call(Vector2(-0.38, -0.08), Vector2(0.38, -0.08), 0.8, Color("d9b45a"))
			circ.call(0, 0.04, 0.06, Color("d9b45a"))
		"journal":
			poly.call([Vector2(-0.3, -0.38), Vector2(0.3, -0.38), Vector2(0.3, 0.38), Vector2(-0.3, 0.38)], Color("7a5a3a"))
			poly.call([Vector2(-0.22, -0.38), Vector2(-0.14, -0.38), Vector2(-0.14, 0.38), Vector2(-0.22, 0.38)], Color("5a3a2a"))
			ring.call(0.08, -0.02, 0.1, 0.6, Palette.GOLD)
		"person":
			circ.call(0, -0.18, 0.17)
			poly.call([Vector2(-0.3, 0.4), Vector2(-0.26, 0.08), Vector2(0, 0.0), Vector2(0.26, 0.08), Vector2(0.3, 0.4)], col)
		"run":
			circ.call(0.12, -0.3, 0.1)
			line.call(Vector2(0.08, -0.16), Vector2(-0.04, 0.12), 1.2)
			line.call(Vector2(-0.04, 0.12), Vector2(-0.28, 0.38), 1.1)
			line.call(Vector2(-0.04, 0.12), Vector2(0.2, 0.38), 1.1)
			line.call(Vector2(0.06, -0.1), Vector2(-0.26, -0.02), 1.0)
			line.call(Vector2(0.06, -0.1), Vector2(0.32, 0.02), 1.0)
		"hourglass":
			poly.call([Vector2(-0.26, -0.38), Vector2(0.26, -0.38), Vector2(0, 0.0)], col)
			poly.call([Vector2(-0.26, 0.38), Vector2(0.26, 0.38), Vector2(0, 0.0)], col.darkened(0.2))
		"chat":
			poly.call([Vector2(-0.38, -0.3), Vector2(0.38, -0.3), Vector2(0.38, 0.16), Vector2(-0.06, 0.16), Vector2(-0.22, 0.36), Vector2(-0.2, 0.16), Vector2(-0.38, 0.16)], col)
		"question":
			arc.call(0, -0.14, 0.2, PI, TAU + PI * 0.4, 1.1)
			line.call(Vector2(0.06, 0.04), Vector2(0, 0.16), 1.1)
			circ.call(0, 0.34, 0.06)
		"close":
			line.call(Vector2(-0.3, -0.3), Vector2(0.3, 0.3), 1.3)
			line.call(Vector2(0.3, -0.3), Vector2(-0.3, 0.3), 1.3)
		_:
			circ.call(0, 0, 0.3, col)
			circ.call(0, 0, 0.12, dark)
