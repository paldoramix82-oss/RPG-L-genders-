class_name UIKit
extends RefCounted
## Petites fabriques d'éléments d'interface pour garder les écrans cohérents.

const TOUCH_HEIGHT := 48.0


static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, variation: String = "", on_pressed: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = TOUCH_HEIGHT
	if variation != "":
		b.theme_type_variation = variation
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


## Ajoute un panneau à `parent` (si fourni) et renvoie la colonne intérieure
## où placer le contenu ; le panneau lui-même est `body.get_parent()`.
static func card(parent: Node, title: String = "", variation: String = "CardPanel") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = variation
	if parent:
		parent.add_child(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	if title != "":
		body.add_child(label(title, "HeadingLabel", true))
		body.add_child(HSeparator.new())
	return body


## Ligne « libellé au-dessus du champ » dans une colonne.
static func field(parent: Node, caption: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(label(caption, "MutedLabel"))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if control is LineEdit or control is SpinBox or control is OptionButton:
		control.custom_minimum_size.y = TOUCH_HEIGHT
	box.add_child(control)
	parent.add_child(box)
	return control


static func line_edit(text: String = "", placeholder: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size.y = TOUCH_HEIGHT
	e.clear_button_enabled = false
	return e


static func spin(value: int, min_value: int, max_value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = 1
	s.rounded = true
	s.value = value
	s.custom_minimum_size.y = TOUCH_HEIGHT
	return s


## Pastille d'état : « ◆ Connecté ».
static func chip(text: String, color: Color) -> Label:
	var l := label("◆  " + text)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 15)
	return l


static func set_chip(chip_label: Label, text: String, color: Color) -> void:
	chip_label.text = "◆  " + text
	chip_label.add_theme_color_override("font_color", color)


static func spacer(vertical: bool = true) -> Control:
	var c := Control.new()
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Zone défilante verticale (jamais de défilement horizontal).
static func vscroll(parent: Node) -> VBoxContainer:
	var scroll := TouchScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


## Fait suivre automatiquement le bas de la liste (fil de discussion), sauf si
## l'utilisateur est remonté lire l'historique.
static func follow_bottom(list: VBoxContainer) -> void:
	var scroll := list.get_parent() as ScrollContainer
	if scroll == null:
		return
	var bar := scroll.get_v_scroll_bar()
	bar.set_meta("last_max", bar.max_value)
	bar.changed.connect(func():
		var last_max: float = bar.get_meta("last_max", 0.0)
		if bar.max_value != last_max:
			var was_at_bottom := bar.value + bar.page >= last_max - 80.0
			bar.set_meta("last_max", bar.max_value)
			if was_at_bottom:
				scroll.set_deferred("scroll_vertical", int(bar.max_value)))


## Bulle de message. viewer_id : identifiant de celui qui lit (Protocol.MJ_ID pour le MJ).
static func message_bubble(message: Dictionary, viewer_id: String) -> Control:
	var is_private := String(message.get("to", "")) != Protocol.TO_ALL
	var from_id := String(message.get("from", ""))
	var variation := "BubbleOther"
	if from_id == viewer_id:
		variation = "BubbleMine"
	elif from_id == Protocol.MJ_ID:
		variation = "BubbleMJ"
	if is_private and from_id != viewer_id:
		variation = "BubblePrivate"

	var panel := PanelContainer.new()
	panel.theme_type_variation = variation
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var header := "%s" % message.get("from_name", "?")
	if is_private:
		header += "  →  %s  · privé" % message.get("to_name", "?")
	header += "  ·  " + Protocol.format_time(float(message.get("ts", 0)))
	var head := label(header, "MutedLabel", true)
	if from_id == Protocol.MJ_ID:
		head.add_theme_color_override("font_color", Palette.GOLD)
	elif is_private:
		head.add_theme_color_override("font_color", Palette.PRIVATE)
	col.add_child(head)
	# Label (et non RichTextLabel) : aucun balisage interprété dans le texte des joueurs.
	col.add_child(label(String(message.get("text", "")), "", true))
	return panel


static func ping_text(rtt: int) -> String:
	return "—" if rtt < 0 else "%d ms" % rtt


static func ping_color(rtt: int) -> Color:
	if rtt < 0:
		return Palette.FAINT
	if rtt < 80:
		return Palette.OK
	if rtt < 200:
		return Palette.WARN
	return Palette.DANGER
