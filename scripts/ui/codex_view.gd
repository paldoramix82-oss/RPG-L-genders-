class_name CodexView
extends VBoxContainer
## Codex de l'univers : lore, magie, monde, créatures. Recherche et sections repliables.

var _entries: Array = []
var _list: VBoxContainer
var _search: LineEdit


func _init(universe: Dictionary, is_mj: bool = false) -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var head := UIKit.card(self, "", "HighlightPanel")
	var title := UIKit.label(String(universe.get("name", "Univers")), "TitleLabel", true)
	title.add_theme_font_size_override("font_size", 28)
	head.add_child(title)
	if String(universe.get("tagline", "")) != "":
		head.add_child(UIKit.label(String(universe.tagline), "MutedLabel", true))
	if String(universe.get("description", "")) != "":
		head.add_child(UIKit.label(String(universe.description), "", true))
	_search = UIKit.line_edit("", "Rechercher dans le codex…")
	_search.text_changed.connect(func(_t): _refresh())
	add_child(_search)
	_list = UIKit.vscroll(self)
	_list.add_theme_constant_override("separation", 6)
	_entries = universe.get("codex", [])
	if is_mj:
		_list.add_child(UIKit.label("Les entrées marquées « MJ » ne sont jamais envoyées aux joueurs.", "MutedLabel", true))
	_refresh()


func _refresh() -> void:
	for child in _list.get_children():
		if child is PanelContainer or child.has_meta("codex"):
			_list.remove_child(child)
			child.queue_free()
	var query := _search.text.strip_edges().to_lower()
	var category := ""
	for e in _entries:
		var haystack := (String(e.title) + " " + String(e.text) + " " + String(e.category)).to_lower()
		if query != "" and not haystack.contains(query):
			continue
		if e.category != category:
			category = e.category
			var h := UIKit.label(category.to_upper(), "HeadingLabel")
			h.add_theme_font_size_override("font_size", 16)
			h.set_meta("codex", true)
			_list.add_child(h)
		_list.add_child(_entry(e, query != ""))


func _entry(e: Dictionary, expanded: bool) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := Button.new()
	head.text = ("▼  " if expanded else "›  ") + String(e.title) + ("   · MJ" if e.get("mj_only", false) else "")
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.flat = true
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size.y = 44
	head.add_theme_color_override("font_color", Palette.PRIVATE if e.get("mj_only", false) else Palette.TEXT)
	head.add_theme_font_override("font", get_theme_font("font", "StrongLabel"))
	col.add_child(head)
	var body := UIKit.label(String(e.text), "", true)
	body.visible = expanded
	col.add_child(body)
	head.pressed.connect(func():
		body.visible = not body.visible
		head.text = ("▼  " if body.visible else "›  ") + String(e.title) + ("   · MJ" if e.get("mj_only", false) else ""))
	return panel
