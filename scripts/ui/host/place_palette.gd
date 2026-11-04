class_name PlacePalette
extends VBoxContainer
## Palette de placement du MJ : on choisit un monstre, un habitant, un PNJ,
## un objet, un coffre ou un passage, puis on touche la carte (autant de fois
## qu'on veut). Recherche par nom. Le choix reste actif jusqu'au suivant.

signal picked(spec: Dictionary, title: String)

const TABS := [["monster", "Monstres"], ["npc_role", "Habitants"], ["character", "PNJ"], ["item", "Objets"], ["chest", "Coffre"], ["passage", "Passages"]]

var content := {}
var characters := {}
var tab := "monster"
var place_hidden := false
var _search: LineEdit
var _grid: HFlowContainer
var _tab_buttons := {}
var _selected_key := ""


func _init(content_data: Dictionary, chars: Dictionary, start_tab: String = "monster") -> void:
	content = content_data
	characters = chars
	tab = start_tab
	add_theme_constant_override("separation", 8)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	add_child(tabs)
	var group := ButtonGroup.new()
	for spec in TABS:
		var b := UIKit.button(spec[1], "", _set_tab.bind(spec[0]))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = spec[0] == tab
		b.custom_minimum_size = Vector2(0, 36)
		tabs.add_child(b)
		_tab_buttons[spec[0]] = b
	_search = UIKit.line_edit("", "Rechercher… (ex. : loup, potion)")
	_search.text_changed.connect(func(_t): _fill())
	add_child(_search)
	var hide_box := CheckBox.new()
	hide_box.text = "Caché aux joueurs (à révéler plus tard)"
	hide_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hide_box.toggled.connect(func(on): place_hidden = on)
	add_child(hide_box)
	_grid = HFlowContainer.new()
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	add_child(_grid)
	_fill()


func _set_tab(key: String) -> void:
	tab = key
	_fill()


func _fill() -> void:
	UIKit.clear(_grid)
	var q := _search.text.strip_edges().to_lower()
	var entries := _entries()
	for e in entries:
		if q != "" and not String(e.title).to_lower().contains(q) and not String(e.get("sub", "")).to_lower().contains(q):
			continue
		_grid.add_child(_tile(e))
	if _grid.get_child_count() == 0:
		_grid.add_child(UIKit.label("Rien ne correspond.", "MutedLabel", true))


## Entrées de l'onglet : {title, sub, tex, spec}.
func _entries() -> Array:
	var out: Array = []
	match tab:
		"monster":
			for m in Content.list(content, "monsters"):
				var sp := String(m.get("sprite", "")) if String(m.get("sprite", "")) != "" else String(m.id)
				out.append({"title": String(m.name), "sub": "%d PV%s" % [int(m.get("hp", 0)), " · boss" if m.get("boss", false) else ""],
					"tex": Sprites.tex("units", sp) if Sprites.tex("units", sp) != null else Sprites.tex("units", "monstre"), "spec": {"type": "monster", "id": String(m.id)}})
		"npc_role":
			for rid in Prefabs.ROLE_ORDER:
				var r := QuestLibrary.role(rid)
				out.append({"title": String(r.get("title", rid)).capitalize(), "sub": "marchand" if Shop.is_merchant_role(rid) else "", "tex": Sprites.tex("units", rid), "spec": {"type": "npc_role", "role": rid}})
		"character":
			for c in characters.values():
				if String(c.get("owner", "")) != "" or String(c.get("kind", "")) == "monster":
					continue
				var sp := String(c.get("class_id", "pnj"))
				out.append({"title": String(c.name), "sub": "fiche", "tex": Sprites.tex("units", sp) if Sprites.tex("units", sp) != null else Sprites.tex("units", "pnj"), "spec": {"type": "character", "id": String(c.id)}})
		"item":
			for it in Content.list(content, "items"):
				out.append({"title": String(it.name), "sub": String(Content.CATEGORY_NAMES.get(String(it.get("category", "")), "")), "tex": Sprites.item(String(it.get("icon", "bag"))), "spec": {"type": "item", "id": String(it.id)}})
		"chest":
			out.append({"title": "Coffre vide (à remplir)", "sub": "contenu au choix ensuite", "tex": Sprites.tex("items", "chest"), "spec": {"type": "chest", "name": "Coffre"}})
			for l in Content.list(content, "loot"):
				out.append({"title": "Coffre : %s" % l.name, "sub": "butin tiré au hasard", "tex": Sprites.tex("items", "chest"), "spec": {"type": "chest", "name": "Coffre", "loot": String(l.id)}})
		"passage":
			for look in SessionServer.PASSAGE_LOOKS:
				out.append({"title": String(SessionServer.PASSAGE_LOOKS[look]), "sub": "à relier ensuite", "tex": Sprites.tex("props", look), "spec": {"type": "passage", "look": look}})
	return out


func _tile(e: Dictionary) -> Control:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(84, 84)
	b.tooltip_text = String(e.title) + ("\n" + String(e.sub) if String(e.get("sub", "")) != "" else "")
	var key := JSON.stringify(e.spec)
	b.button_pressed = key == _selected_key
	b.pressed.connect(func():
		_selected_key = key
		for o in _grid.get_children():
			if o is Button and o != b:
				o.set_pressed_no_signal(false)
		b.set_pressed_no_signal(true)
		var spec: Dictionary = (e.spec as Dictionary).duplicate()
		if spec.type == "monster":
			spec.hidden = place_hidden
		picked.emit(spec, String(e.title)))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	box.add_theme_constant_override("separation", 0)
	b.add_child(box)
	var tex: Texture2D = e.get("tex")
	if tex != null:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ic)
	var l := UIKit.label(String(e.title), "MutedLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return b
