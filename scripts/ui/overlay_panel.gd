class_name OverlayPanel
extends Control
## Panneau superposé facile à fermer (fond assombri, croix, bouton retour) :
## glisse du bas sur téléphone, s'ouvre à droite sur PC. La scène en cours reste
## visible derrière : on ne quitte jamais la partie pour consulter un menu.

signal closed

var body: VBoxContainer
var _sheet: PanelContainer
var _title: Label
var _scroll: TouchScroll
var _wide := false


func _init(title: String, wide_layout: bool = false, icon_name: String = "") -> void:
	_wide = wide_layout
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("touch_block")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			close())
	add_child(dim)
	_sheet = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.BG
	sb.border_color = Palette.GOLD_DIM
	sb.set_corner_radius_all(14)
	if not _wide:
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.border_width_top = 2
	else:
		sb.corner_radius_top_right = 0
		sb.corner_radius_bottom_right = 0
		sb.border_width_left = 2
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	_sheet.add_theme_stylebox_override("panel", sb)
	add_child(_sheet)
	if _wide:
		_sheet.anchor_left = 0.42
		_sheet.anchor_right = 1.0
		_sheet.anchor_top = 0.0
		_sheet.anchor_bottom = 1.0
	else:
		_sheet.anchor_left = 0.0
		_sheet.anchor_right = 1.0
		_sheet.anchor_top = 0.1
		_sheet.anchor_bottom = 1.0
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_sheet.add_child(col)
	if not _wide:
		var grip := Control.new()
		grip.custom_minimum_size.y = 8
		grip.draw.connect(func(): grip.draw_rect(Rect2(grip.size.x * 0.5 - 28, 1, 56, 5), Palette.BORDER))
		col.add_child(grip)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	if icon_name != "":
		head.add_child(GameUI.icon_badge(icon_name, Palette.GOLD, 34))
	_title = UIKit.label(title, "HeadingLabel", true)
	_title.add_theme_font_size_override("font_size", 24)
	head.add_child(_title)
	var x := Button.new()
	x.custom_minimum_size = Vector2(48, 48)
	x.flat = true
	x.tooltip_text = "Fermer"
	x.add_child(Icons.new("close", Palette.MUTED, 22))
	x.get_child(0).set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	x.pressed.connect(close)
	head.add_child(x)
	_scroll = TouchScroll.new()
	col.add_child(_scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)


func _ready() -> void:
	# Petite entrée animée.
	var from := Vector2(0, 60) if not _wide else Vector2(60, 0)
	_sheet.modulate.a = 0.0
	_sheet.position += from
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_sheet, "modulate:a", 1.0, 0.16)
	tw.tween_property(_sheet, "position", _sheet.position - from, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func set_title(text: String) -> void:
	_title.text = text


func clear_body() -> void:
	UIKit.clear(body)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		close()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
