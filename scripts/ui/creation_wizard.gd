class_name CreationWizard
extends VBoxContainer
## Création de personnage guidée en 4 étapes :
##   1. la classe (capacités et équipement prêts à jouer),
##   2. la répartition des points de caractéristiques (réserve limitée),
##   3. l'équipement (choix propres à la classe, ex. trois dagues pour l'Ombre),
##   4. le nom et l'apparence.
## Les PV, l'énergie, la défense, l'initiative et la vitesse se calculent tout seuls.

signal finished(sheet: Dictionary)
signal cancelled

const STEPS := ["Classe", "Caractéristiques", "Équipement", "Identité"]
const STAT_HINTS := {
	"Force": "Coups au contact, porter, enfoncer.",
	"Agilité": "Défense, initiative, armes fines.",
	"Endurance": "Points de vie, résistance.",
	"Intelligence": "Magie de savoir, analyse, énergie de certaines classes.",
	"Perception": "Tir, repérer, initiative.",
	"Charisme": "Persuader, invoquer, soigner pour certaines classes.",
}

var universe := {}
var base := {}
var classes: Array = []
var step := 0
var class_id := ""
var alloc := {}
var choices: Array = []
var identity := {}
var _content: VBoxContainer
var _scroll: TouchScroll
var _title: Label
var _dots: HBoxContainer
var _back: Button
var _next: Button
var _points_label: Label
var _preview: VBoxContainer
var _value_labels := {}


func _init(universe_data: Dictionary, base_sheet: Dictionary) -> void:
	universe = universe_data
	base = base_sheet
	classes = Rules.classes(String(universe.get("id", "")))
	identity = {"name": String(base.get("name", "")), "color": String(base.get("pawn", {}).get("color", CharacterData.PAWN_COLORS[0])),
		"species": "", "appearance": "", "concept": ""}
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	add_child(head)
	_title = UIKit.label("", "TitleLabel", true)
	_title.add_theme_font_size_override("font_size", 26)
	head.add_child(_title)
	_dots = HBoxContainer.new()
	head.add_child(_dots)
	_scroll = TouchScroll.new()
	add_child(_scroll)
	var column := CenteredColumn.new()
	column.max_width = 640
	column.side_margin = 0
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(column)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	column.add_child(_content)
	var nav := HBoxContainer.new()
	add_child(nav)
	_back = UIKit.button("‹  Retour", "", _go.bind(-1))
	_back.custom_minimum_size = Vector2(120, 56)
	nav.add_child(_back)
	nav.add_child(UIKit.spacer(false))
	_next = UIKit.button("Suivant  ›", "PrimaryButton", _go.bind(1))
	_next.custom_minimum_size = Vector2(170, 56)
	nav.add_child(_next)
	_show_step()


func _go(delta: int) -> void:
	if delta > 0 and step == STEPS.size() - 1:
		_finish()
		return
	if delta < 0 and step == 0:
		cancelled.emit()
		return
	step = clampi(step + delta, 0, STEPS.size() - 1)
	_show_step()


func _show_step() -> void:
	UIKit.clear(_content)
	_value_labels.clear()
	_scroll.scroll_vertical = 0
	_title.text = "Étape %d/4 — %s" % [step + 1, ["Choisis ta classe", "Répartis tes points", "Choisis ton équipement", "Qui es-tu ?"][step]]
	UIKit.clear(_dots)
	for i in STEPS.size():
		var chip := UIKit.chip(STEPS[i], Palette.GOLD if i == step else (Palette.OK if i < step else Palette.FAINT))
		_dots.add_child(chip)
	_back.text = "‹  Retour" if step > 0 else "Annuler"
	_next.text = "Créer mon personnage" if step == STEPS.size() - 1 else "Suivant  ›"
	match step:
		0:
			_step_class()
		1:
			_step_points()
		2:
			_step_gear()
		3:
			_step_identity()
	_update_next()


func _update_next() -> void:
	match step:
		0:
			_next.disabled = class_id == ""
		1:
			_next.disabled = Rules.points_spent(alloc) > Rules.POINT_POOL
		3:
			_next.disabled = String(identity.name).strip_edges() == ""
		_:
			_next.disabled = false


func _cls() -> Dictionary:
	return Rules.get_class_def(String(universe.get("id", "")), class_id)


func _preview_sheet() -> Dictionary:
	return Rules.build_sheet(base, String(universe.get("id", "")), class_id, alloc, choices)


# --- 1. Classe ---------------------------------------------------------------

func _step_class() -> void:
	_content.add_child(UIKit.label("Chaque classe arrive avec ses capacités et son équipement. Tout reste modifiable plus tard.", "MutedLabel", true))
	for c in classes:
		var selected: bool = c.id == class_id
		var card := UIKit.card(_content, "", "HighlightPanel" if selected else "CardPanel")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		row.add_child(Emblem.new(String(c.get("emblem", "sword")), Color(String(c.get("color", "#c9a96e"))), 60))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var name_label := UIKit.label(String(c.name), "HeadingLabel", true)
		col.add_child(name_label)
		col.add_child(UIKit.chip(String(c.get("role", "")), Color(String(c.get("color", "#c9a96e"))).lightened(0.3)))
		col.add_child(UIKit.label(String(c.get("tagline", "")), "", true))
		var bonus: PackedStringArray = []
		for k in c.get("bonus", {}):
			bonus.append("%s +%d" % [k, c.bonus[k]])
		col.add_child(UIKit.label("PV %d  ·  Vitesse %d cases  ·  %s" % [c.hp_base, c.speed, ", ".join(bonus)], "MutedLabel", true))
		var abil: PackedStringArray = []
		for a in c.get("abilities", []):
			abil.append(String(a.name))
		col.add_child(UIKit.label("Capacités : " + ", ".join(abil), "MutedLabel", true))
		var pick := UIKit.button("Classe choisie" if selected else "Choisir " + String(c.name), "PrimaryButton" if selected else "", func():
			if class_id != c.id:
				class_id = c.id
				alloc = (c.get("recommended", {}) as Dictionary).duplicate()
				choices = []
			_show_step())
		card.add_child(pick)


# --- 2. Points -----------------------------------------------------------------

func _step_points() -> void:
	var cls := _cls()
	_points_label = UIKit.label("", "CodeLabel")
	_points_label.add_theme_font_size_override("font_size", 24)
	var top := UIKit.card(_content, "", "HighlightPanel")
	top.add_child(_points_label)
	top.add_child(UIKit.label("Chaque caractéristique part de 10. Baissez-en une (jusqu'à 6) pour gagner des points. Votre classe ajoute ses bonus.", "MutedLabel", true))
	var row := HBoxContainer.new()
	top.add_child(row)
	row.add_child(UIKit.button("Répartition conseillée", "", func():
		alloc = (cls.get("recommended", {}) as Dictionary).duplicate()
		_refresh_points()))
	row.add_child(UIKit.button("Tout à zéro", "", func():
		alloc = {}
		_refresh_points()))
	var list := UIKit.card(_content, "Caractéristiques")
	for s in Rules.STATS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		list.add_child(line)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(info)
		info.add_child(UIKit.label(s, "StrongLabel"))
		info.add_child(UIKit.label(STAT_HINTS[s], "MutedLabel", true))
		var minus := UIKit.button("−", "", _bump.bind(s, -1))
		minus.custom_minimum_size = Vector2(52, 52)
		line.add_child(minus)
		var value := UIKit.label("", "CodeLabel")
		value.add_theme_font_size_override("font_size", 24)
		value.custom_minimum_size.x = 76
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_child(value)
		var plus := UIKit.button("+", "PrimaryButton", _bump.bind(s, 1))
		plus.custom_minimum_size = Vector2(52, 52)
		line.add_child(plus)
		_value_labels[s] = value
	_preview = UIKit.card(_content, "Ce que ça donne")
	_refresh_points()


func _bump(stat_name: String, delta: int) -> void:
	var v := int(alloc.get(stat_name, 0)) + delta
	if v < Rules.ALLOC_MIN or v > Rules.ALLOC_MAX:
		return
	if delta > 0 and Rules.points_spent(alloc) >= Rules.POINT_POOL:
		return
	alloc[stat_name] = v
	_refresh_points()


func _refresh_points() -> void:
	var cls := _cls()
	var values := Rules.stat_values(alloc, cls)
	var left := Rules.POINT_POOL - Rules.points_spent(alloc)
	_points_label.text = "Points restants : %d" % left
	_points_label.add_theme_color_override("font_color", Palette.GOLD if left > 0 else (Palette.OK if left == 0 else Palette.DANGER))
	for s in _value_labels:
		var bonus := int(cls.get("bonus", {}).get(s, 0))
		var m := Rules.mod(values[s])
		(_value_labels[s] as Label).text = "%d (%+d)" % [values[s], m]
		(_value_labels[s] as Label).tooltip_text = "dont +%d de classe" % bonus if bonus > 0 else ""
	_fill_preview()
	_update_next()


func _fill_preview() -> void:
	if _preview == null:
		return
	for child in _preview.get_children().slice(2):
		_preview.remove_child(child)
		child.queue_free()
	var sheet := _preview_sheet()
	var d := Rules.derived(sheet, String(universe.get("id", "")))
	var res_name := String(universe.get("character", {}).get("resource_name", "Énergie"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_preview.add_child(grid)
	for spec in [["PV", d.hp_max], [res_name, d.res_max], ["Défense", d.defense], ["Initiative", "%+d" % d.initiative], ["Vitesse", "%d cases" % d.speed]]:
		grid.add_child(_stat_box(spec[0], str(spec[1])))
	for w in Rules.weapons(sheet):
		var p := Rules.attack_profile(sheet, String(universe.get("id", "")), w)
		_preview.add_child(UIKit.label(_attack_text(p), "MutedLabel", true))


func _stat_box(caption: String, value: String) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	var v := UIKit.label(value, "CodeLabel")
	v.add_theme_font_size_override("font_size", 22)
	v.add_theme_color_override("font_color", Palette.GOLD)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(v)
	var c := UIKit.label(caption, "MutedLabel")
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(c)
	return panel


static func _attack_text(p: Dictionary) -> String:
	var crit := "Critique sur 20" if int(p.crit) >= 20 else "Critique sur %d-20" % int(p.crit)
	var dmg := String(p.damage) + ("%+d" % int(p.damage_mod) if int(p.damage_mod) != 0 else "")
	return "%s : toucher %+d, dégâts %s, %s, portée %d" % [p.name, p.to_hit, dmg, crit, p.range]


# --- 3. Équipement -------------------------------------------------------------

func _step_gear() -> void:
	var cls := _cls()
	var groups: Array = cls.get("choices", [])
	while choices.size() < groups.size():
		choices.append(0)
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var card := UIKit.card(_content, String(g.title))
		var options: Array = g.get("options", [])
		for oi in options.size():
			var o: Dictionary = options[oi]
			var selected: bool = int(choices[gi]) == oi
			var opt := UIKit.card(card, "", "HighlightPanel" if selected else "InsetPanel")
			opt.add_child(UIKit.label(String(o.name), "StrongLabel", true))
			opt.add_child(UIKit.label(_item_stats(o), "", true))
			if String(o.get("description", "")) != "":
				opt.add_child(UIKit.label(String(o.description), "MutedLabel", true))
			opt.add_child(UIKit.button("Équipé" if selected else "Prendre", "PrimaryButton" if selected else "", func():
				choices[gi] = oi
				_show_step()))
	var kit: Array = cls.get("kit", [])
	if not kit.is_empty():
		var bag := UIKit.card(_content, "Aussi dans votre sac")
		for i in kit:
			bag.add_child(UIKit.label("%s%s — %s" % [i.name, " ×%d" % int(i.qty) if int(i.get("qty", 1)) > 1 else "", _item_stats(i) if _item_stats(i) != "" else String(i.get("description", ""))], "", true))
	var abil := UIKit.card(_content, "Vos capacités")
	for a in cls.get("abilities", []):
		abil.add_child(UIKit.label(String(a.name), "StrongLabel", true))
		abil.add_child(UIKit.label(_ability_text(a, String(universe.get("character", {}).get("resource_name", "Énergie"))), "MutedLabel", true))


static func _item_stats(i: Dictionary) -> String:
	match String(i.get("category", "")):
		"arme":
			var crit := int(i.get("crit", 20))
			return "Arme · dégâts %s (%s) · critique %s · portée %d" % [i.get("damage", "1d4"), i.get("stat", "Force"), "20" if crit >= 20 else "%d-20" % crit, int(i.get("range", 1))]
		"armure", "bouclier":
			return "%s · défense +%d" % ["Bouclier" if i.category == "bouclier" else "Armure", int(i.get("defense", 0))]
		"consommable":
			return "À utiliser : soigne %s" % i.get("heal", "") if String(i.get("heal", "0")) not in ["", "0"] else "Consommable"
	return ""


static func _ability_text(a: Dictionary, res_name: String) -> String:
	var parts: PackedStringArray = []
	match String(a.get("kind", "")):
		"attack":
			parts.append("Attaque %s (+%s)" % [a.get("damage", ""), a.get("stat", "")])
		"heal":
			parts.append("Soin %s (+%s)" % [a.get("heal", ""), a.get("stat", "")])
	if int(a.get("res_cost", 0)) > 0:
		parts.append("coût %d %s" % [int(a.res_cost), res_name])
	if int(a.get("range", 0)) > 1:
		parts.append("portée %d" % int(a.range))
	parts.append(String(a.get("description", "")))
	return "  ·  ".join(parts)


# --- 4. Identité ----------------------------------------------------------------

func _step_identity() -> void:
	var card := UIKit.card(_content, "")
	var n := UIKit.line_edit(String(identity.name), "Nom de votre personnage")
	n.text_changed.connect(func(t):
		identity.name = t
		_update_next())
	UIKit.field(card, "Nom du personnage", n)
	var species := UIKit.line_edit(String(identity.species), "Ex. : Humain")
	species.text_changed.connect(func(t): identity.species = t)
	var row := HBoxContainer.new()
	row.add_child(species)
	species.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var options: Array = universe.get("character", {}).get("species", [])
	if not options.is_empty():
		var menu := MenuButton.new()
		menu.text = "Choisir"
		menu.flat = false
		menu.theme_type_variation = "Button"
		menu.custom_minimum_size = Vector2(90, UIKit.TOUCH_HEIGHT)
		for o in options:
			menu.get_popup().add_item(String(o))
		menu.get_popup().index_pressed.connect(func(i):
			species.text = menu.get_popup().get_item_text(i)
			identity.species = species.text)
		row.add_child(menu)
	card.add_child(UIKit.label("Espèce (facultatif)", "MutedLabel"))
	card.add_child(row)
	card.add_child(UIKit.label("Couleur de votre pion", "MutedLabel"))
	var colors := HFlowContainer.new()
	colors.add_theme_constant_override("h_separation", 6)
	colors.add_theme_constant_override("v_separation", 6)
	card.add_child(colors)
	for c in CharacterData.PAWN_COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(46, 46)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(c)
		sb.set_corner_radius_all(23)
		sb.set_border_width_all(4 if c == identity.color else 0)
		sb.border_color = Palette.TEXT
		for s in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(s, sb)
		b.pressed.connect(func():
			identity.color = c
			_show_step())
		colors.add_child(b)
	var look := TextEdit.new()
	look.text = String(identity.appearance)
	look.placeholder_text = "Apparence, une phrase sur son histoire… (facultatif)"
	look.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	look.scroll_fit_content_height = true
	look.custom_minimum_size.y = 80
	look.text_changed.connect(func(): identity.appearance = look.text)
	UIKit.field(card, "Description (facultatif)", look)
	var recap := UIKit.card(_content, "Récapitulatif", "HighlightPanel")
	var sheet := _preview_sheet()
	var d := Rules.derived(sheet, String(universe.get("id", "")))
	recap.add_child(UIKit.label("%s  ·  PV %d  ·  Défense %d  ·  Vitesse %d" % [_cls().get("name", ""), d.hp_max, d.defense, d.speed], "StrongLabel", true))
	for w in Rules.weapons(sheet):
		recap.add_child(UIKit.label(_attack_text(Rules.attack_profile(sheet, String(universe.get("id", "")), w)), "MutedLabel", true))


func _finish() -> void:
	var sheet := _preview_sheet()
	sheet.name = Protocol.sanitize_name(identity.name)
	sheet.species = identity.species
	sheet.appearance = identity.appearance
	sheet.pawn = {"color": identity.color, "symbol": ""}
	finished.emit(sheet)
