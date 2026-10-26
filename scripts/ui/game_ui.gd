class_name GameUI
extends RefCounted
## Éléments d'interface propres au jeu : cartes de capacité, passif, objets
## (rareté), caractéristiques, effets de statut. Partagés par l'assistant de
## création, la fiche, l'inventaire, la barre rapide et le tableau du MJ.


static func element_color(element: String) -> Color:
	match element:
		"magique":
			return Palette.MANA
		"soin":
			return Palette.HEAL
	return Palette.GOLD


static func ability_color(a: Dictionary) -> Color:
	if a.get("ultimate", false):
		return Palette.ULT
	var target := String(a.get("target", ""))
	if target in ["ally", "area_ally", "self"] and String(a.get("element", "")) != "magique":
		for e in a.get("effects", []):
			if String(e.get("type", "")) == "heal":
				return Palette.HEAL
		return Palette.VIOLET.lightened(0.35)
	return element_color(String(a.get("element", "physique")))


## Pastille ronde avec icône (taille px).
static func icon_badge(icon_name: String, col: Color, px: float = 40.0) -> Icons:
	var i := Icons.new(icon_name, col, px)
	i.backing = col.darkened(0.78)
	i.frame = col.darkened(0.2)
	return i


## Carte détaillée d'une capacité : icône, nom, coûts, effets.
static func ability_card(a: Dictionary, content: Dictionary, res_name: String = "Énergie", note: String = "") -> PanelContainer:
	var col := ability_color(a)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "HighlightPanel" if a.get("ultimate", false) else "InsetPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var badge := icon_badge(String(a.get("icon", "star")), col, 44)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	var col_box := VBoxContainer.new()
	col_box.add_theme_constant_override("separation", 2)
	col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col_box)
	var title := HBoxContainer.new()
	col_box.add_child(title)
	var n := UIKit.label(String(a.get("name", "?")), "StrongLabel", true)
	n.add_theme_color_override("font_color", col.lightened(0.2) if a.get("ultimate", false) else Palette.TEXT)
	title.add_child(n)
	if a.get("ultimate", false):
		title.add_child(tag("ULTIME", Palette.ULT))
	if int(a.get("rank", 1)) > 1:
		title.add_child(tag("RANG %d" % int(a.rank), Palette.XP))
	var costs := UIKit.label(Effects.ability_costs(a, res_name), "MutedLabel", true)
	costs.add_theme_color_override("font_color", Palette.MANA.lightened(0.3))
	col_box.add_child(costs)
	if String(a.get("description", "")) != "":
		col_box.add_child(UIKit.label(String(a.description), "", true))
	var fx := UIKit.label(Effects.ability_text(a, content), "MutedLabel", true)
	col_box.add_child(fx)
	if note != "":
		var nl := UIKit.label(note, "MutedLabel", true)
		nl.add_theme_color_override("font_color", Palette.WARN)
		col_box.add_child(nl)
	return panel


static func passive_card(p: Dictionary, content: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var badge := icon_badge(String(p.get("icon", "star")), Palette.VIOLET.lightened(0.4), 44)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var title := HBoxContainer.new()
	box.add_child(title)
	title.add_child(UIKit.label(String(p.get("name", "Passif")), "StrongLabel", true))
	title.add_child(tag("PASSIF", Palette.VIOLET.lightened(0.4)))
	box.add_child(UIKit.label(Effects.passive_text(p, content), "", true))
	box.add_child(UIKit.label("Fonctionne tout seul, sans rien faire.", "MutedLabel", true))
	return panel


## Peuple : trait, bonus, et synergie avec la classe s'il y en a une.
static func species_card(sp: Dictionary, syn: Dictionary, content: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var badge := icon_badge(String(sp.get("icon", "person")), Palette.GOLD, 44)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var title := HBoxContainer.new()
	box.add_child(title)
	var tr: Dictionary = sp.get("trait", {})
	title.add_child(UIKit.label(String(tr.get("name", sp.get("name", ""))) if String(tr.get("name", "")) != "" else String(sp.get("name", "")), "StrongLabel", true))
	title.add_child(tag(String(sp.get("name", "PEUPLE")).to_upper(), Palette.GOLD))
	if String(tr.get("description", "")) != "":
		box.add_child(UIKit.label(String(tr.description), "", true))
	var bonus := CreationWizard.species_bonus_text(sp, content)
	if bonus != "":
		box.add_child(UIKit.label(bonus, "MutedLabel", true))
	if not syn.is_empty():
		var l := UIKit.label("◆  %s : %s" % [syn.get("name", ""), syn.get("description", "")], "StrongLabel", true)
		l.add_theme_color_override("font_color", Palette.ULT)
		box.add_child(l)
	return panel


## Petite étiquette colorée en capitales.
static func tag(text: String, col: Color) -> Label:
	var l := UIKit.label(text)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


static func rarity_name(item: Dictionary) -> String:
	return String(Content.RARITY_NAMES.get(String(item.get("rarity", "commun")), "Commun"))


## Case d'objet (icône sur fond de rareté, quantité, marque « équipé »).
static func item_slot(item: Dictionary, px: float = 64.0) -> Control:
	var rc := Content.rarity_color(String(item.get("rarity", "commun")))
	var box := Control.new()
	box.custom_minimum_size = Vector2(px, px)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_name := String(item.get("icon", "bag"))
	var qty := int(item.get("qty", 1))
	var equipped := bool(item.get("equipped", false))
	box.draw.connect(func():
		var r := Rect2(Vector2.ZERO, box.size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = rc.darkened(0.82)
		sb.border_color = rc.darkened(0.15) if not equipped else Palette.GOLD
		sb.set_border_width_all(2 if equipped else 1)
		sb.set_corner_radius_all(8)
		box.draw_style_box(sb, r)
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(rc, 0.12)
		glow.set_corner_radius_all(8)
		box.draw_style_box(glow, Rect2(Vector2(2, 2), Vector2(box.size.x - 4, box.size.y * 0.45)))
		Icons.paint(box, icon_name, r.grow(-box.size.x * 0.18), rc.lightened(0.25))
		var font := box.get_theme_font("font", "StrongLabel")
		if qty > 1:
			var t := "×%d" % qty
			var fs := int(box.size.y * 0.24)
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			box.draw_string(font, Vector2(box.size.x - tw - 4, box.size.y - 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.TEXT)
		if equipped:
			box.draw_circle(Vector2(box.size.x - 9, 9), 6, Palette.GOLD)
			box.draw_string(font, Vector2(box.size.x - 13, 13), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.BG_DEEP))
	return box


## Ligne d'objet détaillée : case, nom coloré par la rareté, catégorie, effets.
static func item_card(item: Dictionary, content: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var slot := item_slot(item, 56)
	slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(slot)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var n := UIKit.label(String(item.get("name", "?")) + ((" ×%d" % int(item.qty)) if int(item.get("qty", 1)) > 1 else ""), "StrongLabel", true)
	n.add_theme_color_override("font_color", Content.rarity_color(String(item.get("rarity", "commun"))).lightened(0.15))
	box.add_child(n)
	box.add_child(UIKit.label("%s · %s%s" % [rarity_name(item), Content.CATEGORY_NAMES.get(String(item.get("category", "")), "Objet"),
		"  ·  équipé" if item.get("equipped", false) else ""], "MutedLabel", true))
	var stats := Inventory.describe(item, content)
	if stats != "":
		box.add_child(UIKit.label(stats, "", true))
	if String(item.get("description", "")) != "":
		box.add_child(UIKit.label(String(item.description), "MutedLabel", true))
	return panel


## Case de caractéristique : grande valeur, abréviation, nom.
static func stat_tile(stat_name: String, value: int, content: Dictionary, bonus: int = 0) -> PanelContainer:
	var info := Content.stat_info(content, stat_name)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	panel.custom_minimum_size.x = 92
	panel.tooltip_text = String(info.get("description", ""))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	var v := UIKit.label(str(value), "CodeLabel")
	v.add_theme_font_size_override("font_size", 28)
	v.add_theme_color_override("font_color", Palette.GOLD if bonus == 0 else (Palette.HEAL if bonus > 0 else Palette.HP))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(v)
	var n := UIKit.label(String(info.get("short", stat_name.substr(0, 3))), "StrongLabel")
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	var full := UIKit.label(stat_name, "MutedLabel")
	full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	full.add_theme_font_size_override("font_size", 13)
	col.add_child(full)
	if bonus != 0:
		# Base + bonus d'équipement / d'effet, pour distinguer les deux.
		var detail := UIKit.label("%d %s %d" % [value - bonus, "+" if bonus > 0 else "−", absi(bonus)], "MutedLabel")
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.add_theme_font_size_override("font_size", 12)
		detail.add_theme_color_override("font_color", Palette.HEAL if bonus > 0 else Palette.HP)
		col.add_child(detail)
	return panel


## Valeur dérivée : « Défense 14 ».
static func value_tile(caption: String, value: String, col: Color = Palette.GOLD, hint: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.tooltip_text = hint
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var v := UIKit.label(value, "StrongLabel")
	v.add_theme_font_size_override("font_size", 22)
	v.add_theme_color_override("font_color", col)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(v)
	var c := UIKit.label(caption, "MutedLabel")
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_theme_font_size_override("font_size", 13)
	box.add_child(c)
	return panel


## Rangée d'effets de statut (icônes colorées et tours restants).
static func status_row(effects: Array, px: float = 22.0) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	for e in effects:
		var col := Color(String(e.get("color", "#a07cc9")))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.tooltip_text = "%s%s — %s" % [e.get("name", "?"), (" (%d tours)" % int(e.turns)) if int(e.get("turns", 0)) > 0 else "", e.get("description", "")]
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		var ic := icon_badge(String(e.get("icon", "sparkle")), col, px)
		box.add_child(ic)
		if int(e.get("turns", 0)) > 0 or int(e.get("value", 0)) > 0:
			var t := UIKit.label(str(int(e.value)) if int(e.get("value", 0)) > 0 else str(int(e.turns)))
			t.add_theme_font_size_override("font_size", 12)
			t.add_theme_color_override("font_color", col.lightened(0.3))
			box.add_child(t)
		flow.add_child(box)
	return flow


## Filet décoratif : deux traits dorés et un losange au centre.
static func ornament(height: float = 22.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var mid := c.size * 0.5
		var w := minf(c.size.x * 0.42, 170.0)
		c.draw_line(mid - Vector2(w, 0), mid - Vector2(12, 0), Palette.GOLD_DIM, 1.0, true)
		c.draw_line(mid + Vector2(12, 0), mid + Vector2(w, 0), Palette.GOLD_DIM, 1.0, true)
		c.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -6), mid + Vector2(6, 0), mid + Vector2(0, 6), mid + Vector2(-6, 0)]), Palette.GOLD)
		c.draw_circle(mid - Vector2(w, 0), 2, Palette.GOLD_DIM)
		c.draw_circle(mid + Vector2(w, 0), 2, Palette.GOLD_DIM))
	return c


## Titre de section : icône dorée, nom en capitales, filet qui file jusqu'au bord.
static func section_title(text: String, icon_name: String = "", col: Color = Palette.GOLD) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if icon_name != "":
		var i := Icons.new(icon_name, col, 22)
		i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(i)
	var l := UIKit.label(text, "HeadingLabel")
	l.add_theme_color_override("font_color", col)
	row.add_child(l)
	var line := Control.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func():
		var y := line.size.y * 0.55
		line.draw_line(Vector2(4, y), Vector2(line.size.x, y), Color(col, 0.35), 1.0, true)
		line.draw_colored_polygon(PackedVector2Array([Vector2(4, y - 3), Vector2(7, y), Vector2(4, y + 3), Vector2(1, y)]), Color(col, 0.7)))
	row.add_child(line)
	return row


## Carte avec titre de section orné (remplace UIKit.card quand un titre compte).
static func section(parent: Node, title: String, icon_name: String = "", variation: String = "CardPanel") -> VBoxContainer:
	var body := UIKit.card(parent, "", variation)
	if title != "":
		body.add_child(section_title(title, icon_name))
	return body


## Panneau « pourquoi c'est bloqué » / astuce : petite ligne d'aide.
static func hint(text: String) -> Label:
	var l := UIKit.label("◆  " + text, "MutedLabel", true)
	l.add_theme_color_override("font_color", Palette.VIOLET.lightened(0.45))
	return l
