class_name ConfirmBox
extends Control
## Fenêtre de confirmation intégrée au jeu (au lieu d'une fenêtre système) :
## fond assombri, carte ornée, deux boutons. Retour / Échap = annuler.
## Utilisée seulement quand c'est utile : action irréversible ou objet rare.

signal answered(ok: bool)


static func ask(parent: Node, title: String, text: String, ok_text: String, on_ok: Callable, danger: bool = false, cancel_text: String = "Annuler") -> ConfirmBox:
	var box := ConfirmBox.new()
	box._build(title, text, ok_text, cancel_text, danger)
	box.answered.connect(func(ok):
		if ok and on_ok.is_valid():
			on_ok.call())
	parent.add_child(box)
	return box


## Fenêtre d'information avec un contenu libre (aperçu…) et un seul bouton.
static func show_content(parent: Node, title: String, content: Control, close_text: String = "Fermer") -> ConfirmBox:
	var box := ConfirmBox.new()
	box._build(title, "", close_text, "", false, content)
	parent.add_child(box)
	return box


func _build(title: String, text: String, ok_text: String, cancel_text: String, danger: bool, content: Control = null) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	add_to_group("touch_block")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DangerPanel" if danger else "HighlightPanel"
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size.x = clampf(get_viewport().get_visible_rect().size.x - 48, 260, 440) if is_inside_tree() else 320
	panel.add_child(col)
	var t := UIKit.label(title, "HeadingLabel", true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	col.add_child(GameUI.ornament())
	if text != "":
		var l := UIKit.label(text, "", true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	if content != null:
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(content)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	if cancel_text != "":
		var no := UIKit.button(cancel_text, "", _answer.bind(false))
		no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(no)
	var yes := UIKit.button(ok_text, "DangerButton" if danger else "PrimaryButton", _answer.bind(true))
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(yes)
	panel.ready.connect(func():
		col.custom_minimum_size.x = clampf(get_viewport().get_visible_rect().size.x - 48, 260, 440)
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2(0.94, 0.94)
		panel.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate:a", 1.0, 0.12))


func _answer(ok: bool) -> void:
	if is_queued_for_deletion():
		return
	answered.emit(ok)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_answer(false)
