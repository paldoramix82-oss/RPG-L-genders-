class_name CharacterSheet
extends VBoxContainer
## Affichage d'une fiche (complète ou vue publique).

var universe := {}


func _init(sheet: Dictionary, universe_data: Dictionary) -> void:
	universe = universe_data
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build(sheet)


func _build(c: Dictionary) -> void:
	# --- En-tête : pion, nom, concept ---
	var head := UIKit.card(self, "", "HighlightPanel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	head.add_child(row)
	row.add_child(_pawn(c))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	var name_label := UIKit.label(String(c.get("name", "Sans nom")), "TitleLabel", true)
	name_label.add_theme_font_size_override("font_size", 28)
	titles.add_child(name_label)
	var sub: PackedStringArray = []
	for key in ["concept", "species", "origin"]:
		if String(c.get(key, "")) != "":
			sub.append(String(c[key]))
	if String(c.get("age", "")) != "":
		sub.append("%s ans" % c.age)
	if not sub.is_empty():
		titles.add_child(UIKit.label("  ·  ".join(sub), "MutedLabel", true))
	var badges := HFlowContainer.new()
	badges.add_theme_constant_override("h_separation", 12)
	titles.add_child(badges)
	if String(c.get("rank", "")) not in ["", "Aucun"]:
		badges.add_child(UIKit.chip("%s %s" % [universe.get("character", {}).get("rank_title", "Rang"), c.rank], Palette.GOLD))
	if int(c.get("level", 0)) > 0:
		badges.add_child(UIKit.chip("Niveau %d" % int(c.level), Palette.VIOLET.lightened(0.3)))
	if String(c.get("status", "")) != "":
		badges.add_child(UIKit.chip(String(c.status), Palette.WARN))

	# --- Jauges ---
	if c.has("hp_max"):
		var gauges := UIKit.card(self, "")
		gauges.add_child(_gauge("Points de vie", int(c.get("hp", 0)), int(c.get("hp_max", 1)), Palette.DANGER))
		if c.has("res_max") and int(c.res_max) > 0:
			gauges.add_child(_gauge(String(universe.get("character", {}).get("resource_name", "Énergie")), int(c.get("res", 0)), int(c.res_max), Palette.VIOLET.lightened(0.2)))
		if c.has("xp"):
			gauges.add_child(UIKit.label("Expérience : %d" % int(c.xp), "MutedLabel"))

	# --- Magie ---
	var magic: Dictionary = c.get("magic", {})
	if String(magic.get("name", "")) != "" or String(magic.get("category", "")) != "":
		var m := UIKit.card(self, String(universe.get("character", {}).get("magic_title", "Magie")))
		var top := String(magic.get("name", ""))
		if String(magic.get("category", "")) != "":
			top += ("  —  " if top != "" else "") + String(magic.category)
		m.add_child(UIKit.label(top, "StrongLabel", true))
		if String(magic.get("origin", "")) != "":
			m.add_child(UIKit.label("Origine : " + String(magic.origin), "MutedLabel", true))
		_para(m, "", magic.get("description", ""))
		_para(m, "Limites", magic.get("limits", ""))

	if not c.get("abilities", []).is_empty():
		var ab := UIKit.card(self, "Capacités")
		for a in c.abilities:
			var box := UIKit.card(ab, "", "InsetPanel")
			box.add_child(UIKit.label(String(a.name), "StrongLabel", true))
			var meta: PackedStringArray = []
			if String(a.get("cost", "")) != "":
				meta.append("Coût : " + String(a.cost))
			if String(a.get("range", "")) != "":
				meta.append("Portée : " + String(a.range))
			if not meta.is_empty():
				box.add_child(UIKit.label("  ·  ".join(meta), "MutedLabel", true))
			_para(box, "", a.get("description", ""))
			_para(box, "Limites", a.get("limits", ""))

	# --- Caractéristiques et compétences ---
	for spec in [["stats", "Caractéristiques"], ["skills", "Compétences"]]:
		var rows: Array = c.get(spec[0], [])
		if rows.is_empty():
			continue
		var card := UIKit.card(self, spec[1])
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		card.add_child(flow)
		for s in rows:
			flow.add_child(_stat(String(s.name), int(s.get("value", 0)), spec[0] == "skills"))

	if not c.get("inventory", []).is_empty():
		var inv := UIKit.card(self, "Inventaire")
		for item in c.inventory:
			var line := HBoxContainer.new()
			var n := UIKit.label(String(item.name), "StrongLabel", true)
			line.add_child(n)
			if int(item.get("qty", 1)) != 1:
				line.add_child(UIKit.label("× %d" % int(item.qty), "MutedLabel"))
			inv.add_child(line)
			if String(item.get("description", "")) != "":
				inv.add_child(UIKit.label(String(item.description), "MutedLabel", true))

	var story_fields := [["appearance", "Apparence"], ["personality", "Personnalité"], ["goals", "Objectifs"],
		["background", "Histoire"], ["relations", "Relations"], ["notes", "Notes"], ["secret", "Secret (vous et le MJ)"]]
	var story: VBoxContainer = null
	for spec in story_fields:
		if String(c.get(spec[0], "")) == "":
			continue
		if story == null:
			story = UIKit.card(self, "Portrait")
		_para(story, spec[1], c[spec[0]])
	if c.get("public", false):
		add_child(UIKit.label("Vous voyez la partie publique de cette fiche.", "MutedLabel", true))


func _pawn(c: Dictionary) -> Control:
	var color := Color(String(c.get("pawn", {}).get("color", "#9a9a9a")))
	var initials := CharacterData.initials(c)
	var ctl := Control.new()
	ctl.custom_minimum_size = Vector2(64, 64)
	ctl.draw.connect(func():
		var center := ctl.size * 0.5
		ctl.draw_circle(center + Vector2(0, 4), 28, Color(0, 0, 0, 0.4))
		ctl.draw_circle(center, 28, color)
		ctl.draw_arc(center, 28, 0, TAU, 40, Palette.GOLD, 2.5, true)
		var font := ctl.get_theme_font("font", "StrongLabel")
		var w := font.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var tc := Color("15141a") if color.get_luminance() > 0.55 else Color("f4efe6")
		ctl.draw_string(font, center + Vector2(-w * 0.5, 8), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, tc))
	return ctl


func _gauge(caption: String, value: int, max_value: int, color: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	var l := UIKit.label(caption, "MutedLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	top.add_child(UIKit.label("%d / %d" % [value, max_value], "StrongLabel"))
	box.add_child(top)
	var bar := Control.new()
	bar.custom_minimum_size.y = 10
	var ratio := clampf(float(value) / maxf(1.0, max_value), 0.0, 1.0)
	bar.draw.connect(func():
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Palette.BG_DEEP)
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * ratio, bar.size.y)), color)
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Palette.BORDER, false, 1.0))
	box.add_child(bar)
	return box


func _stat(stat_name: String, value: int, signed: bool) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	var v := UIKit.label(("%+d" % value) if signed else str(value), "CodeLabel")
	v.add_theme_font_size_override("font_size", 24)
	v.add_theme_color_override("font_color", Palette.GOLD)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(v)
	var n := UIKit.label(stat_name, "MutedLabel")
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	panel.custom_minimum_size.x = 96
	return panel


func _para(parent: Node, caption: String, text: Variant) -> void:
	if String(text) == "":
		return
	if caption != "":
		var c := UIKit.label(caption, "MutedLabel")
		c.add_theme_color_override("font_color", Palette.GOLD_DIM)
		parent.add_child(c)
	parent.add_child(UIKit.label(String(text), "", true))
