class_name TabbedPages
extends VBoxContainer
## Pages avec barre d'onglets (en haut sur PC, en bas sur téléphone) et pastilles
## de notification (« • ») sur les onglets non affichés.

signal page_changed(key: String)

var current := ""
var _bar: HBoxContainer
var _bar_panel: PanelContainer
var _stack: MarginContainer
var _buttons := {}
var _pages := {}
var _titles := {}
var _group := ButtonGroup.new()
var _bottom := false


func _init(bottom: bool = false, margin: int = 12) -> void:
	_bottom = bottom
	add_theme_constant_override("separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar_panel = PanelContainer.new()
	_bar_panel.theme_type_variation = "NavPanel" if bottom else "BarPanel"
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 4)
	_bar_panel.add_child(_bar)
	_stack = MarginContainer.new()
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		_stack.add_theme_constant_override("margin_" + side, margin)
	if bottom:
		add_child(_stack)
		add_child(_bar_panel)
	else:
		add_child(_bar_panel)
		add_child(_stack)


func add_page(key: String, title: String, page: Control) -> void:
	var b := UIKit.button(title, "NavButton", show_page.bind(key))
	b.toggle_mode = true
	b.button_group = _group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 50
	b.clip_text = true
	if _bottom:
		# Marges réduites : cinq onglets doivent tenir sur un écran de téléphone.
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			var sb: StyleBox = get_theme_stylebox(state, "NavButton").duplicate()
			sb.content_margin_left = 2
			sb.content_margin_right = 2
			b.add_theme_stylebox_override(state, sb)
		b.add_theme_font_size_override("font_size", 16)
	_bar.add_child(b)
	_buttons[key] = b
	_titles[key] = title
	page.visible = false
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(page)
	_pages[key] = page
	if current == "":
		show_page(key)


func page(key: String) -> Control:
	return _pages.get(key)


func show_page(key: String) -> void:
	if not _pages.has(key):
		return
	current = key
	for k in _pages:
		_pages[k].visible = k == key
		_buttons[k].set_pressed_no_signal(k == key)
	set_badge(key, false)
	page_changed.emit(key)


func set_badge(key: String, on: bool) -> void:
	if not _buttons.has(key):
		return
	if on and key == current:
		return
	_buttons[key].text = _titles[key] + ("  •" if on else "")
	_buttons[key].add_theme_color_override("font_color", Palette.GOLD if on else Palette.MUTED)


func set_bar_visible(on: bool) -> void:
	_bar_panel.visible = on
