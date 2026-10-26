class_name Emblem
extends Control
## Petit blason dessiné pour chaque classe (épée, dague, flamme, œil, cœur…).

var kind := "sword"
var color := Palette.GOLD


func _init(emblem_kind: String = "sword", emblem_color: Color = Palette.GOLD, px: float = 56.0) -> void:
	kind = emblem_kind
	color = emblem_color
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	# Écu
	var shield := PackedVector2Array([c + Vector2(-0.42, -0.45) * s, c + Vector2(0.42, -0.45) * s, c + Vector2(0.42, 0.05) * s,
		c + Vector2(0, 0.48) * s, c + Vector2(-0.42, 0.05) * s])
	draw_colored_polygon(shield, color.darkened(0.55))
	var outline := shield.duplicate()
	outline.append(shield[0])
	draw_polyline(outline, Palette.GOLD, 2.0, true)
	var fg := color.lightened(0.25)
	var w := maxf(2.0, s * 0.06)
	match kind:
		"sword":
			draw_line(c + Vector2(0, -0.32) * s, c + Vector2(0, 0.22) * s, fg, w * 1.2)
			draw_line(c + Vector2(-0.16, 0.08) * s, c + Vector2(0.16, 0.08) * s, Palette.GOLD, w)
			draw_line(c + Vector2(0, 0.08) * s, c + Vector2(0, 0.3) * s, Palette.GOLD, w)
		"dagger":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.32) * s, c + Vector2(0.07, 0.05) * s, c + Vector2(-0.07, 0.05) * s]), fg)
			draw_line(c + Vector2(-0.13, 0.07) * s, c + Vector2(0.13, 0.07) * s, Palette.GOLD, w)
			draw_line(c + Vector2(0, 0.07) * s, c + Vector2(0, 0.25) * s, Palette.GOLD, w)
		"fist", "claw":
			for i in 3:
				var x := (-0.16 + i * 0.16) * s
				if kind == "claw":
					draw_line(c + Vector2(x - 0.04 * s, 0.2 * s), c + Vector2(x + 0.06 * s, -0.28 * s), fg, w)
				else:
					draw_circle(c + Vector2(x, -0.08 * s), s * 0.09, fg)
			if kind == "fist":
				draw_rect(Rect2(c + Vector2(-0.24, -0.02) * s, Vector2(0.48, 0.24) * s), fg)
		"flame":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.33) * s, c + Vector2(0.2, 0.0) * s, c + Vector2(0.12, 0.25) * s,
				c + Vector2(-0.12, 0.25) * s, c + Vector2(-0.2, 0.0) * s]), Color("e07a3a"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.1) * s, c + Vector2(0.09, 0.1) * s, c + Vector2(0, 0.24) * s, c + Vector2(-0.09, 0.1) * s]), Color("ffd76a"))
		"spirit":
			draw_circle(c + Vector2(0, -0.08) * s, s * 0.17, fg)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.17, -0.06) * s, c + Vector2(0.17, -0.06) * s, c + Vector2(0.1, 0.28) * s, c + Vector2(0, 0.18) * s, c + Vector2(-0.1, 0.28) * s]), fg)
			draw_circle(c + Vector2(-0.06, -0.1) * s, s * 0.03, color.darkened(0.6))
			draw_circle(c + Vector2(0.06, -0.1) * s, s * 0.03, color.darkened(0.6))
		"eye":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.3, 0) * s, c + Vector2(0, -0.17) * s, c + Vector2(0.3, 0) * s, c + Vector2(0, 0.17) * s]), fg)
			draw_circle(c, s * 0.09, color.darkened(0.6))
		"heart":
			draw_circle(c + Vector2(-0.1, -0.06) * s, s * 0.12, Color("d9606a"))
			draw_circle(c + Vector2(0.1, -0.06) * s, s * 0.12, Color("d9606a"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.215, -0.02) * s, c + Vector2(0.215, -0.02) * s, c + Vector2(0, 0.26) * s]), Color("d9606a"))
		"paw":
			draw_circle(c + Vector2(0, 0.08) * s, s * 0.13, fg)
			for p in [Vector2(-0.17, -0.1), Vector2(-0.06, -0.2), Vector2(0.06, -0.2), Vector2(0.17, -0.1)]:
				draw_circle(c + p * s, s * 0.055, fg)
		"gear":
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * s * 0.12, c + Vector2(cos(a), sin(a)) * s * 0.27, fg, w * 1.4)
			draw_circle(c, s * 0.17, fg)
			draw_circle(c, s * 0.07, color.darkened(0.55))
		"staff":
			draw_line(c + Vector2(-0.15, 0.28) * s, c + Vector2(0.1, -0.2) * s, Color("9a7044"), w)
			draw_circle(c + Vector2(0.12, -0.24) * s, s * 0.09, Color("9fc3d4"))
		"bow":
			draw_arc(c + Vector2(-0.1, 0) * s, s * 0.3, -PI * 0.4, PI * 0.4, 16, fg, w, true)
			draw_line(c + Vector2(-0.1 + 0.3 * cos(PI * 0.4), -0.3 * sin(PI * 0.4)) * s, c + Vector2(-0.1 + 0.3 * cos(PI * 0.4), 0.3 * sin(PI * 0.4)) * s, Palette.TEXT, 1.0)
			draw_line(c + Vector2(-0.25, 0) * s, c + Vector2(0.25, 0) * s, Palette.GOLD, w * 0.7)
		"lute":
			draw_circle(c + Vector2(-0.05, 0.1) * s, s * 0.15, Color("9a7044"))
			draw_line(c + Vector2(0.03, 0.02) * s, c + Vector2(0.22, -0.25) * s, Color("6b4a2a"), w)
			draw_circle(c + Vector2(-0.05, 0.1) * s, s * 0.05, color.darkened(0.6))
		_:
			draw_circle(c, s * 0.15, fg)
