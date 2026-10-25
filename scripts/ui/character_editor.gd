class_name CharacterEditor
extends VBoxContainer
## Éditeur de fiche libre : identité, pion, magie et pouvoirs, caractéristiques,
## compétences, état, inventaire, histoire. Les listes de l'univers ne sont que
## des suggestions : tout champ accepte du texte libre.

signal saved(sheet: Dictionary)
signal cancelled

var sheet := {}
var universe := {}
var is_mj := false
var _f := {}  # champs simples : clé -> Control
var _lists := {}  # clé -> VBoxContainer de lignes
var _pawn_color := ""
var _swatches: Array = []


func _init(data: Dictionary, universe_data: Dictionary, mj: bool = false) -> void:
	sheet = data.duplicate(true)
	universe = universe_data
	is_mj = mj
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


func _cfg(key: String, default: Variant) -> Variant:
	return universe.get("character", {}).get(key, default)


func _build() -> void:
	var title := UIKit.label("Fiche de personnage", "TitleLabel")
	title.add_theme_font_size_override("font_size", 30)
	add_child(title)
	add_child(UIKit.label("Tout est libre : les listes proposées ne sont que des idées. Laissez vide ce qui ne vous sert pas.", "MutedLabel", true))

	# --- Identité ---
	var id := UIKit.card(self, "Identité")
	_line(id, "name", "Nom du personnage", "Ex. : Shin, Lysa Vent-d'Argent…")
	_line(id, "concept", "Concept / titre", "Ex. : apprentie mage de feu, mercenaire repenti…")
	_suggest_line(id, "species", "Espèce", _cfg("species", []))
	_suggest_line(id, "origin", "Origine", _cfg("origins", []))
	_line(id, "age", "Âge", "")
	_text(id, "appearance", "Apparence")

	# --- Pion ---
	var pawn := UIKit.card(self, "Pion sur la carte")
	_pawn_color = String(sheet.get("pawn", {}).get("color", CharacterData.PAWN_COLORS[0]))
	var colors := HFlowContainer.new()
	colors.add_theme_constant_override("h_separation", 6)
	colors.add_theme_constant_override("v_separation", 6)
	pawn.add_child(colors)
	for c in CharacterData.PAWN_COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(42, 42)
		b.toggle_mode = true
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(c)
		sb.set_corner_radius_all(21)
		sb.set_border_width_all(3)
		sb.border_color = Color(0, 0, 0, 0)
		var sbp := sb.duplicate()
		sbp.border_color = Palette.TEXT
		for s in ["normal", "hover", "focus"]:
			b.add_theme_stylebox_override(s, sb)
		b.add_theme_stylebox_override("pressed", sbp)
		b.add_theme_stylebox_override("hover_pressed", sbp)
		b.button_pressed = c == _pawn_color
		b.pressed.connect(_pick_color.bind(c))
		b.set_meta("color", c)
		_swatches.append(b)
		colors.add_child(b)
	var sym := UIKit.line_edit(String(sheet.get("pawn", {}).get("symbol", "")), "Initiales sur le pion (2 lettres, facultatif)")
	sym.max_length = 2
	UIKit.field(pawn, "Symbole", sym)
	_f["pawn_symbol"] = sym

	# --- Magie et pouvoirs ---
	var magic_card := UIKit.card(self, String(_cfg("magic_title", "Magie et pouvoirs")))
	var magic: Dictionary = sheet.get("magic", {})
	var cats: Array = _cfg("magic_categories", [])
	var cat_names: Array = cats.map(func(c): return c.name)
	_suggest_line(magic_card, "magic_category", "Catégorie", cat_names, String(magic.get("category", "")))
	var hint := UIKit.label("", "MutedLabel", true)
	magic_card.add_child(hint)
	var update_hint := func(text: String):
		hint.text = ""
		for c in cats:
			if c.name == text:
				hint.text = String(c.get("hint", ""))
	(_f["magic_category"] as LineEdit).text_changed.connect(update_hint)
	update_hint.call(String(magic.get("category", "")))
	_line(magic_card, "magic_name", "Nom de la magie / du pouvoir", "Ex. : Renforcement des flammes", String(magic.get("name", "")))
	_suggest_line(magic_card, "magic_origin", "Origine du pouvoir", _cfg("magic_origins", []), String(magic.get("origin", "")))
	_text(magic_card, "magic_description", "Ce que fait la magie", String(magic.get("description", "")))
	_text(magic_card, "magic_limits", "Limites, coûts, faiblesses", String(magic.get("limits", "")))
	var pub := CheckBox.new()
	pub.text = "Les autres joueurs voient le nom et la catégorie de ma magie"
	pub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pub.button_pressed = bool(magic.get("public", true))
	magic_card.add_child(pub)
	_f["magic_public"] = pub

	_list_section("abilities", "Capacités et techniques", "Ajouter une capacité", [
		{"key": "name", "label": "Nom", "kind": "line"},
		{"key": "description", "label": "Description", "kind": "text"},
		{"key": "cost", "label": "Coût (ex. 3 AEC)", "kind": "line", "half": true},
		{"key": "range", "label": "Portée", "kind": "line", "half": true},
		{"key": "limits", "label": "Conditions et limites", "kind": "text"},
	])

	# --- Caractéristiques et compétences ---
	_list_section("stats", "Caractéristiques", "Ajouter une caractéristique", [
		{"key": "name", "label": "Nom", "kind": "line"}, {"key": "value", "label": "Valeur", "kind": "int"},
	], true)
	_list_section("skills", "Compétences", "Ajouter une compétence", [
		{"key": "name", "label": "Nom", "kind": "line"}, {"key": "value", "label": "Bonus", "kind": "int"},
	], true, _cfg("skills", []))

	# --- État ---
	var state := UIKit.card(self, "État")
	var res_name := String(_cfg("resource_name", "Énergie"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	state.add_child(grid)
	for spec in [["hp", "Points de vie"], ["hp_max", "PV maximum"], ["res", res_name], ["res_max", res_name + " maximum"], ["level", "Niveau"], ["xp", "Expérience"]]:
		var s := UIKit.spin(int(sheet.get(spec[0], 0)), -999, 99999)
		UIKit.field(grid, spec[1], s)
		_f[spec[0]] = s
	var ranks: Array = _cfg("ranks", [])
	if not ranks.is_empty():
		_suggest_line(state, "rank", String(_cfg("rank_title", "Rang")), ranks)
	_line(state, "status", "État actuel (blessures, effets…)", "Ex. : bras gauche blessé")

	_list_section("inventory", "Inventaire", "Ajouter un objet", [
		{"key": "name", "label": "Objet", "kind": "line"},
		{"key": "qty", "label": "Qté", "kind": "int"},
		{"key": "description", "label": "Description, effets", "kind": "text"},
	])

	# --- Histoire ---
	var story := UIKit.card(self, "Histoire et personnalité")
	_text(story, "personality", "Personnalité")
	_text(story, "goals", "Objectifs")
	_text(story, "background", "Histoire personnelle")
	_text(story, "relations", "Relations importantes")
	_text(story, "notes", "Notes")
	_text(story, "secret", "Secret (visible uniquement par vous et le MJ)")

	var actions := HBoxContainer.new()
	add_child(actions)
	actions.add_child(UIKit.button("Annuler", "", func(): cancelled.emit()))
	actions.add_child(UIKit.spacer(false))
	var save := UIKit.button("Enregistrer la fiche", "PrimaryButton", func(): saved.emit(collect()))
	save.custom_minimum_size.x = 200
	actions.add_child(save)
	var gap := Control.new()
	gap.custom_minimum_size.y = 40
	add_child(gap)


func _pick_color(c: String) -> void:
	_pawn_color = c
	for b in _swatches:
		b.set_pressed_no_signal(b.get_meta("color") == c)


func _line(parent: Node, key: String, caption: String, placeholder: String = "", value: Variant = null) -> LineEdit:
	var e := UIKit.line_edit(String(sheet.get(key, "")) if value == null else String(value), placeholder)
	UIKit.field(parent, caption, e)
	_f[key] = e
	return e


## Champ texte libre + menu de suggestions.
func _suggest_line(parent: Node, key: String, caption: String, options: Array, value: Variant = null) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UIKit.label(caption, "MutedLabel"))
	var row := HBoxContainer.new()
	box.add_child(row)
	var e := UIKit.line_edit(String(sheet.get(key, "")) if value == null else String(value), "Texte libre ou choix dans la liste")
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	if not options.is_empty():
		var menu := MenuButton.new()
		menu.text = "Choisir"
		menu.flat = false
		menu.custom_minimum_size = Vector2(90, UIKit.TOUCH_HEIGHT)
		menu.theme_type_variation = "Button"
		for o in options:
			menu.get_popup().add_item(String(o))
		menu.get_popup().index_pressed.connect(func(i):
			e.text = menu.get_popup().get_item_text(i)
			e.text_changed.emit(e.text))
		row.add_child(menu)
	parent.add_child(box)
	_f[key] = e


func _text(parent: Node, key: String, caption: String, value: Variant = null) -> TextEdit:
	var t := TextEdit.new()
	t.text = String(sheet.get(key, "")) if value == null else String(value)
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.scroll_fit_content_height = true
	t.custom_minimum_size.y = 76
	UIKit.field(parent, caption, t)
	_f[key] = t
	return t


## Section de lignes répétables. compact = une ligne « nom + valeur ».
func _list_section(key: String, title: String, add_text: String, fields: Array, compact: bool = false, suggestions: Array = []) -> void:
	var card := UIKit.card(self, title)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	card.add_child(rows)
	_lists[key] = rows
	for item in sheet.get(key, []):
		_add_row(rows, fields, item, compact)
	var bar := HBoxContainer.new()
	card.add_child(bar)
	bar.add_child(UIKit.button("+  " + add_text, "", func(): _add_row(rows, fields, {}, compact)))
	if not suggestions.is_empty():
		var menu := MenuButton.new()
		menu.text = "Suggestions"
		menu.flat = false
		menu.theme_type_variation = "Button"
		menu.custom_minimum_size.y = UIKit.TOUCH_HEIGHT
		for s in suggestions:
			menu.get_popup().add_item(String(s))
		menu.get_popup().index_pressed.connect(func(i):
			_add_row(rows, fields, {"name": menu.get_popup().get_item_text(i), "value": 0}, compact))
		bar.add_child(menu)


func _add_row(rows: VBoxContainer, fields: Array, item: Dictionary, compact: bool) -> void:
	var holder: Container
	var body: Container
	if compact:
		holder = HBoxContainer.new()
		body = holder
	else:
		var panel := PanelContainer.new()
		panel.theme_type_variation = "InsetPanel"
		holder = panel
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", 6)
		panel.add_child(body)
	holder.set_meta("fields", fields)
	var halves: HBoxContainer = null
	for f in fields:
		var c: Control
		match f.kind:
			"int":
				var s := UIKit.spin(int(item.get(f.key, 1 if f.key == "qty" else 0)), -9999, 99999)
				s.custom_minimum_size.x = 96
				c = s
			"text":
				var t := TextEdit.new()
				t.text = String(item.get(f.key, ""))
				t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
				t.scroll_fit_content_height = true
				t.custom_minimum_size.y = 60
				t.placeholder_text = f.label
				c = t
			_:
				var e := UIKit.line_edit(String(item.get(f.key, "")), f.label)
				c = e
		c.set_meta("key", f.key)
		if compact:
			if f.kind != "int":
				c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_child(c)
		elif f.get("half", false):
			if halves == null:
				halves = HBoxContainer.new()
				body.add_child(halves)
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			halves.add_child(c)
		else:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_child(c)
	var del := UIKit.button("×", "DangerButton", func():
		rows.remove_child(holder)
		holder.queue_free())
	del.custom_minimum_size = Vector2(44, 44)
	if compact:
		body.add_child(del)
	else:
		del.text = "Retirer"
		del.size_flags_horizontal = Control.SIZE_SHRINK_END
		body.add_child(del)
	rows.add_child(holder)


func _value(c: Control) -> Variant:
	if c is SpinBox:
		return int(c.value)
	if c is TextEdit or c is LineEdit:
		return c.text
	if c is CheckBox:
		return c.button_pressed
	return null


func _collect_rows(rows: VBoxContainer) -> Array:
	var out: Array = []
	for holder in rows.get_children():
		if holder.is_queued_for_deletion():
			continue
		var row := {}
		for c in _all_children(holder):
			if c.has_meta("key"):
				row[c.get_meta("key")] = _value(c)
		out.append(row)
	return out


func _all_children(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		out.append(c)
		out.append_array(_all_children(c))
	return out


func collect() -> Dictionary:
	var out := sheet.duplicate(true)
	for key in ["name", "concept", "species", "origin", "age", "appearance", "rank", "status",
			"personality", "goals", "background", "relations", "notes", "secret",
			"hp", "hp_max", "res", "res_max", "level", "xp"]:
		if _f.has(key):
			out[key] = _value(_f[key])
	out.magic = {
		"category": _value(_f.magic_category), "name": _value(_f.magic_name),
		"origin": _value(_f.magic_origin), "description": _value(_f.magic_description),
		"limits": _value(_f.magic_limits), "public": _value(_f.magic_public),
	}
	out.pawn = {"color": _pawn_color, "symbol": _value(_f.pawn_symbol)}
	for key in _lists:
		out[key] = _collect_rows(_lists[key])
	return out
