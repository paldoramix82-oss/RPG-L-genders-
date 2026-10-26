class_name Portrait
extends Control
## Portrait de personnage dessiné en code (buste stylisé) à partir de quelques
## choix : forme du visage, teint, coiffure et couleur, yeux, barbe, marque.
## Les monstres et PNJ sans portrait affichent une icône sur leur couleur.

const SKINS := ["f1d2b6", "e0b48e", "c68e64", "9a6a46", "6e4a32", "4a3426"]
const HAIR_COLORS := ["2a211c", "5a3a24", "9a6a3a", "d9b46a", "c25a3a", "e8e4dc", "4a5a8a", "7a4a8a"]
const HAIR_NAMES := ["Rasé", "Court", "Mi-long", "Long", "Queue", "Hérissé", "Tresses", "Capuche"]
const FACE_NAMES := ["Ovale", "Carré", "Fin", "Rond"]
const EYE_NAMES := ["Calmes", "Perçants", "Fermés", "Lumineux"]
const BEARD_NAMES := ["Aucune", "Courte", "Longue", "Moustache"]
const MARK_NAMES := ["Aucune", "Cicatrice", "Tatouage", "Peinture de guerre"]

var data := {}
var tint := Palette.VIOLET
var icon := ""
var ko := false
var active := false


func _init(portrait: Dictionary = {}, background: Color = Palette.VIOLET, px: float = 64.0, fallback_icon: String = "") -> void:
	data = portrait
	tint = background
	icon = fallback_icon
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Portrait d'une fiche (ou d'un pion sans fiche).
static func for_sheet(sheet: Dictionary, content: Dictionary, px: float = 64.0) -> Portrait:
	var cls := Content.get_entry(content, "classes", String(sheet.get("class_id", "")))
	var bg := Color(String(cls.get("color", sheet.get("pawn", {}).get("color", "#7a6e93"))))
	var kind := String(sheet.get("kind", ""))
	var fallback := ""
	if kind == "monster" or (sheet.get("portrait", {}) as Dictionary).is_empty():
		fallback = "skull" if kind == "monster" else "person"
	var p := Portrait.new(sheet.get("portrait", {}), bg, px, fallback if kind == "monster" else "")
	p.ko = int(sheet.get("hp_max", 0)) > 0 and int(sheet.get("hp", 1)) <= 0
	return p


func set_data(portrait: Dictionary, background: Color) -> void:
	data = portrait
	tint = background
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := o + Vector2(s, s) * 0.5
	# Fond : dégradé sombre de la couleur de classe, coins arrondis.
	var bg_top := tint.darkened(0.35)
	var bg_bot := tint.darkened(0.75)
	var bands := 10
	for i in bands:
		var t := float(i) / bands
		draw_rect(Rect2(o + Vector2(0, s * t), Vector2(s, s / bands + 1)), bg_top.lerp(bg_bot, t))
	if icon != "":
		Icons.paint(self, icon, Rect2(o + Vector2(s, s) * 0.18, Vector2(s, s) * 0.64), tint.lightened(0.45))
	else:
		_bust(o, s)
	if ko:
		draw_rect(Rect2(o, Vector2(s, s)), Color(0, 0, 0, 0.55))
		draw_line(o + Vector2(s * 0.2, s * 0.2), o + Vector2(s * 0.8, s * 0.8), Palette.DANGER, maxf(2, s * 0.05))
		draw_line(o + Vector2(s * 0.8, s * 0.2), o + Vector2(s * 0.2, s * 0.8), Palette.DANGER, maxf(2, s * 0.05))
	var frame_col := Palette.GOLD if active else Palette.GOLD_DIM
	draw_rect(Rect2(o, Vector2(s, s)), frame_col, false, maxf(1.5, s * (0.05 if active else 0.03)))


func _bust(o: Vector2, s: float) -> void:
	var skin := Color(String(SKINS[int(data.get("skin", 1)) % SKINS.size()]))
	var hair := Color(String(HAIR_COLORS[int(data.get("hair_color", 1)) % HAIR_COLORS.size()]))
	var face := int(data.get("face", 0)) % 4
	var hair_style := int(data.get("hair", 1)) % 8
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	# Épaules et vêtement.
	var cloth := tint.lerp(Color("2a2630"), 0.35)
	draw_colored_polygon(PackedVector2Array([P.call(0.08, 1.0), P.call(0.14, 0.8), P.call(0.32, 0.72), P.call(0.68, 0.72), P.call(0.86, 0.8), P.call(0.92, 1.0)]), cloth)
	draw_colored_polygon(PackedVector2Array([P.call(0.42, 0.72), P.call(0.5, 0.86), P.call(0.58, 0.72)]), cloth.lightened(0.25))
	# Cou.
	draw_rect(Rect2(P.call(0.43, 0.58), Vector2(0.14, 0.16) * s), skin.darkened(0.15))
	# Cheveux arrière (longs, tresses, capuche).
	if hair_style in [3, 4, 6]:
		draw_colored_polygon(PackedVector2Array([P.call(0.28, 0.3), P.call(0.72, 0.3), P.call(0.76, 0.78 if hair_style == 3 else 0.62), P.call(0.24, 0.78 if hair_style == 3 else 0.62)]), hair.darkened(0.15))
	if hair_style == 7:
		draw_colored_polygon(PackedVector2Array([P.call(0.2, 0.75), P.call(0.24, 0.22), P.call(0.5, 0.08), P.call(0.76, 0.22), P.call(0.8, 0.75)]), cloth.darkened(0.2))
	# Visage.
	var fw: float = [0.2, 0.22, 0.18, 0.23][face]
	var fh: float = [0.26, 0.25, 0.27, 0.23][face]
	var center: Vector2 = P.call(0.5, 0.42)
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		var v := Vector2(cos(a) * fw, sin(a) * fh)
		if face == 1 and sin(a) > 0.3:
			v.x *= 1.08
		if face == 2 and sin(a) > 0:
			v.x *= 1.0 - 0.35 * sin(a)
		pts.append(center + v * s)
	draw_colored_polygon(pts, skin)
	# Yeux.
	var eyes := int(data.get("eyes", 0)) % 4
	var ey := 0.42
	for ex in [0.42, 0.58]:
		match eyes:
			0:
				draw_circle(P.call(ex, ey), s * 0.022, Color("2a211c"))
			1:
				draw_line(P.call(ex - 0.035, ey - 0.01), P.call(ex + 0.035, ey + 0.005), Color("2a211c"), maxf(1.5, s * 0.022))
			2:
				draw_arc(P.call(ex, ey - 0.01), s * 0.03, 0.2, PI - 0.2, 8, Color("2a211c"), maxf(1.2, s * 0.016))
			3:
				draw_circle(P.call(ex, ey), s * 0.028, tint.lightened(0.6))
				draw_circle(P.call(ex, ey), s * 0.012, Color.WHITE)
	# Nez et bouche.
	draw_line(P.call(0.5, 0.45), P.call(0.49, 0.5), skin.darkened(0.3), maxf(1.0, s * 0.012))
	draw_line(P.call(0.46, 0.56), P.call(0.54, 0.56), skin.darkened(0.4), maxf(1.0, s * 0.014))
	# Barbe.
	match int(data.get("beard", 0)) % 4:
		1:
			draw_colored_polygon(PackedVector2Array([P.call(0.33, 0.48), P.call(0.67, 0.48), P.call(0.6, 0.66), P.call(0.4, 0.66)]), Color(hair, 0.85))
			draw_line(P.call(0.46, 0.56), P.call(0.54, 0.56), skin.darkened(0.4), maxf(1.0, s * 0.014))
		2:
			draw_colored_polygon(PackedVector2Array([P.call(0.32, 0.48), P.call(0.68, 0.48), P.call(0.58, 0.8), P.call(0.5, 0.84), P.call(0.42, 0.8)]), hair)
		3:
			draw_line(P.call(0.42, 0.53), P.call(0.58, 0.53), hair, maxf(2.0, s * 0.03))
	# Marque.
	match int(data.get("mark", 0)) % 4:
		1:
			draw_line(P.call(0.58, 0.33), P.call(0.64, 0.5), Color("b05a5a"), maxf(1.2, s * 0.014))
		2:
			draw_arc(P.call(0.38, 0.47), s * 0.035, 0, TAU, 10, tint.lightened(0.5), maxf(1.0, s * 0.012))
		3:
			draw_line(P.call(0.36, 0.46), P.call(0.64, 0.46), Color(tint.lightened(0.4), 0.7), maxf(2.0, s * 0.025))
	# Cheveux avant.
	match hair_style:
		0:
			draw_arc(center, s * fw, PI * 1.1, PI * 1.9, 12, hair.darkened(0.2), maxf(1.5, s * 0.02))
		1, 3, 4, 6:
			draw_colored_polygon(PackedVector2Array([P.call(0.29, 0.38), P.call(0.32, 0.22), P.call(0.5, 0.15), P.call(0.68, 0.22), P.call(0.71, 0.38), P.call(0.6, 0.27), P.call(0.44, 0.3)]), hair)
		2:
			draw_colored_polygon(PackedVector2Array([P.call(0.27, 0.56), P.call(0.29, 0.24), P.call(0.5, 0.14), P.call(0.71, 0.24), P.call(0.73, 0.56), P.call(0.66, 0.3), P.call(0.36, 0.3)]), hair)
		5:
			var spikes := PackedVector2Array([P.call(0.29, 0.36)])
			for i in 6:
				spikes.append(P.call(0.3 + i * 0.08, 0.1 + (i % 2) * 0.1))
			spikes.append(P.call(0.71, 0.36))
			spikes.append(P.call(0.5, 0.28))
			draw_colored_polygon(spikes, hair)
		7:
			draw_colored_polygon(PackedVector2Array([P.call(0.3, 0.32), P.call(0.36, 0.2), P.call(0.5, 0.17), P.call(0.64, 0.2), P.call(0.7, 0.32), P.call(0.5, 0.26)]), cloth.darkened(0.3))
	if hair_style == 4:
		draw_circle(P.call(0.74, 0.3), s * 0.05, hair)
	if hair_style == 6:
		for side in [0.27, 0.73]:
			for k in 3:
				draw_circle(P.call(side, 0.5 + k * 0.08), s * 0.035, hair.darkened(0.1))
