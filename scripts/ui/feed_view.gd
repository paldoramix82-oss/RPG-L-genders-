class_name FeedView
extends VBoxContainer
## Fil de l'aventure : messages, actions déclarées, jets de dés, événements du récit.
## Côté MJ, les actions en attente peuvent être résolues directement depuis le fil.

signal resolve_requested(message_id: String, status: String, result: String, roll_expr: String)

var viewer_id := ""
var is_mj := false
var _list: VBoxContainer
var _nodes := {}  # message id -> Control
var _empty: Label


func _init(viewer: String = "", mj: bool = false) -> void:
	viewer_id = viewer
	is_mj = mj
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = UIKit.vscroll(self)
	_list.add_theme_constant_override("separation", 8)
	UIKit.follow_bottom(_list)
	_empty = UIKit.label("Le récit commence ici. Messages, actions et jets de dés apparaîtront au fil de la partie.", "MutedLabel", true)
	_list.add_child(_empty)


func set_messages(messages: Array) -> void:
	for child in _list.get_children():
		if child != _empty:
			_list.remove_child(child)
			child.queue_free()
	_nodes.clear()
	for m in messages:
		add_message(m)
	_empty.visible = messages.is_empty()


func add_message(m: Dictionary) -> void:
	_empty.visible = false
	var node := build(m)
	_nodes[m.get("id", "")] = node
	_list.add_child(node)


func update_message(m: Dictionary) -> void:
	var old: Control = _nodes.get(m.get("id", ""))
	if old == null:
		add_message(m)
		return
	var node := build(m)
	_list.add_child(node)
	_list.move_child(node, old.get_index())
	_list.remove_child(old)
	old.queue_free()
	_nodes[m.id] = node


func add_notice(text: String, color: Color) -> void:
	var l := UIKit.label(text, "MutedLabel", true)
	l.add_theme_color_override("font_color", color)
	_list.add_child(l)


func build(m: Dictionary) -> Control:
	match String(m.get("kind", Protocol.KIND_CHAT)):
		Protocol.KIND_SYSTEM:
			return _system(m)
		Protocol.KIND_ROLL:
			return _roll(m)
		Protocol.KIND_ACTION:
			return _action(m)
	return UIKit.message_bubble(m, viewer_id)


func _system(m: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var l := UIKit.label("◆  " + String(m.get("text", "")), "", true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Palette.GOLD)
	l.add_theme_font_size_override("font_size", 17)
	box.add_child(l)
	return box


func _bubble_base(m: Dictionary, variation: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = variation
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	return col


func _header(m: Dictionary, tag: String, tag_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var t := UIKit.label(tag, "")
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", tag_color)
	row.add_child(t)
	var who := String(m.get("from_name", "?"))
	if String(m.get("to", "")) != Protocol.TO_ALL:
		who += "  →  %s  · privé" % m.get("to_name", "?")
	var h := UIKit.label(who, "MutedLabel", true)
	if m.get("from", "") == Protocol.MJ_ID:
		h.add_theme_color_override("font_color", Palette.GOLD)
	row.add_child(h)
	var time := UIKit.label(Protocol.format_time(float(m.get("ts", 0))), "MutedLabel")
	time.add_theme_color_override("font_color", Palette.FAINT)
	row.add_child(time)
	return row


func _roll(m: Dictionary) -> Control:
	var secret := String(m.get("to", "")) != Protocol.TO_ALL
	var col := _bubble_base(m, "BubblePrivate" if secret else "BubbleOther")
	col.add_child(_header(m, "DÉS", Palette.VIOLET.lightened(0.3)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var roll: Dictionary = m.get("roll", {})
	var total_panel := PanelContainer.new()
	total_panel.theme_type_variation = "HighlightPanel"
	var total := UIKit.label(str(roll.get("total", "?")), "CodeLabel")
	total.add_theme_font_size_override("font_size", 30)
	total.add_theme_color_override("font_color", Palette.GOLD)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total.custom_minimum_size.x = 56
	total_panel.add_child(total)
	row.add_child(total_panel)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var label := String(m.get("text", ""))
	info.add_child(UIKit.label(label if label != "" else "Jet de dés", "StrongLabel", true))
	info.add_child(UIKit.label("%s  :  %s" % [roll.get("expr", ""), roll.get("detail", "")], "MutedLabel", true))
	return col.get_parent()


func _action(m: Dictionary) -> Control:
	var status := String(m.get("status", Protocol.ACTION_PENDING))
	var col := _bubble_base(m, "BubbleMine" if m.get("from", "") == viewer_id else "BubbleOther")
	col.add_child(_header(m, "ACTION", Palette.WARN))
	col.add_child(UIKit.label(String(m.get("text", "")), "", true))
	var chip: Array = {
		Protocol.ACTION_PENDING: ["En attente du MJ", Palette.WARN],
		Protocol.ACTION_RESOLVED: ["Résolue", Palette.OK],
		Protocol.ACTION_REFUSED: ["Refusée", Palette.DANGER],
	}.get(status, ["?", Palette.MUTED])
	col.add_child(UIKit.chip(chip[0], chip[1]))
	var roll: Dictionary = m.get("roll", {})
	var result := String(m.get("result", ""))
	if not roll.is_empty() or result != "":
		var res := UIKit.card(col, "", "BubbleMJ")
		if not roll.is_empty():
			res.add_child(UIKit.label("Jet %s → %s  (%s)" % [roll.get("expr", ""), roll.get("total", ""), roll.get("detail", "")], "StrongLabel", true))
		if result != "":
			res.add_child(UIKit.label(result, "", true))
	return col.get_parent()


## Formulaire de résolution d'une action (MJ).
func resolve_form(message_id: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var result := UIKit.line_edit("", "Résultat, conséquence…")
	box.add_child(result)
	var row := HBoxContainer.new()
	box.add_child(row)
	var roll := UIKit.line_edit("", "Jet (ex. d20+2)")
	roll.custom_minimum_size.x = 120
	roll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(roll)
	var ok := UIKit.button("Résoudre", "PrimaryButton", func():
		resolve_requested.emit(message_id, Protocol.ACTION_RESOLVED, result.text, roll.text))
	row.add_child(ok)
	var no := UIKit.button("Refuser", "DangerButton", func():
		resolve_requested.emit(message_id, Protocol.ACTION_REFUSED, result.text, ""))
	row.add_child(no)
	return box
