class_name Composer
extends PanelContainer
## Zone de saisie du fil : Message, Action libre ou Dés.
## Les cibles possibles sont fournies par l'écran (joueur ou MJ).

signal send_message(target: String, text: String)
signal send_action(target: String, text: String)
signal send_roll(target: String, expr: String, label: String)

var _mode := "message"
var _mode_buttons := {}
var _target: OptionButton
var _text: LineEdit
var _dice_box: VBoxContainer
var _text_row: HBoxContainer
var _expr: LineEdit
var _modifier: SpinBox
var _label: LineEdit
var _count: SpinBox
var _dice_targets: Array = []
var _text_targets: Array = []
var _allow_action := true


## targets : [[libellé, cible], …] pour messages/actions ; dice_targets pour les dés.
func _init(text_targets: Array, dice_targets: Array, allow_action: bool = true) -> void:
	theme_type_variation = "InsetPanel"
	_text_targets = text_targets
	_dice_targets = dice_targets
	_allow_action = allow_action
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	col.add_child(modes)
	var group := ButtonGroup.new()
	var mode_list := [["message", "Message"], ["action", "Action"], ["dice", "Dés"]]
	for spec in mode_list:
		if spec[0] == "action" and not allow_action:
			continue
		var b := UIKit.button(spec[1], "NavButton", _set_mode.bind(spec[0]))
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.y = 38
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(b)
		_mode_buttons[spec[0]] = b
	_target = OptionButton.new()
	_target.custom_minimum_size = Vector2(150, 38)
	_target.fit_to_longest_item = false
	modes.add_child(_target)

	_text_row = HBoxContainer.new()
	col.add_child(_text_row)
	_text = UIKit.line_edit("", "")
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.max_length = Protocol.MAX_MESSAGE_LENGTH
	_text.text_submitted.connect(func(_t): _submit())
	_text_row.add_child(_text)
	var send := UIKit.button("Envoyer", "PrimaryButton", _submit)
	send.custom_minimum_size.x = 96
	_text_row.add_child(send)

	_dice_box = VBoxContainer.new()
	_dice_box.add_theme_constant_override("separation", 6)
	col.add_child(_dice_box)
	var quick := HFlowContainer.new()
	quick.add_theme_constant_override("h_separation", 6)
	quick.add_theme_constant_override("v_separation", 6)
	_dice_box.add_child(quick)
	_count = UIKit.spin(1, 1, 20)
	_count.prefix = "×"
	_count.custom_minimum_size.x = 90
	quick.add_child(_count)
	for sides in Dice.COMMON:
		var b := UIKit.button("d%d" % sides, "", _quick_roll.bind(sides))
		b.custom_minimum_size = Vector2(54, 44)
		quick.add_child(b)
	var row := HBoxContainer.new()
	_dice_box.add_child(row)
	_modifier = UIKit.spin(0, -50, 50)
	_modifier.prefix = "mod."
	_modifier.custom_minimum_size.x = 110
	row.add_child(_modifier)
	_label = UIKit.line_edit("", "Pour quoi ? (ex. Escalade)")
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)
	var row2 := HBoxContainer.new()
	_dice_box.add_child(row2)
	_expr = UIKit.line_edit("", "Formule libre : 2d6+3, d20-1…")
	_expr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_expr.text_submitted.connect(func(_t): _roll_expr())
	row2.add_child(_expr)
	row2.add_child(UIKit.button("Lancer", "PrimaryButton", _roll_expr))

	_mode_buttons["message"].button_pressed = true
	_set_mode("message")


func set_targets(text_targets: Array, dice_targets: Array) -> void:
	_text_targets = text_targets
	_dice_targets = dice_targets
	_fill_targets()


func focus_text() -> void:
	_text.grab_focus()


func select_target(target: String) -> void:
	for i in _target.item_count:
		if _target.get_item_metadata(i) == target:
			_target.select(i)


func _set_mode(mode: String) -> void:
	_mode = mode
	_text_row.visible = mode != "dice"
	_dice_box.visible = mode == "dice"
	_text.placeholder_text = {
		"message": "Écrire un message…",
		"action": "Décrivez librement ce que vous tentez…",
	}.get(mode, "")
	_fill_targets()


func _fill_targets() -> void:
	var previous := String(_target.get_item_metadata(_target.selected)) if _target.selected >= 0 else ""
	_target.clear()
	for t in (_dice_targets if _mode == "dice" else _text_targets):
		_target.add_item(t[0])
		_target.set_item_metadata(_target.item_count - 1, t[1])
	select_target(previous)


func _current_target() -> String:
	return String(_target.get_item_metadata(_target.selected)) if _target.selected >= 0 else Protocol.TO_ALL


func _submit() -> void:
	var text := _text.text.strip_edges()
	if text == "":
		return
	if _mode == "action":
		send_action.emit(_current_target(), text)
	else:
		send_message.emit(_current_target(), text)
	_text.clear()


func _quick_roll(sides: int) -> void:
	var expr := "%dd%d" % [int(_count.value), sides]
	if int(_modifier.value) != 0:
		expr += "%+d" % int(_modifier.value)
	send_roll.emit(_current_target(), expr, _label.text.strip_edges())


func _roll_expr() -> void:
	var expr := _expr.text.strip_edges()
	if expr == "":
		return
	send_roll.emit(_current_target(), expr, _label.text.strip_edges())
