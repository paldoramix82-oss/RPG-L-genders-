class_name FeedView
extends VBoxContainer
## Fil de l'aventure : messages, actions déclarées, jets de dés, événements du récit.
## Côté MJ, les actions en attente peuvent être résolues directement depuis le fil.

signal resolve_requested(message_id: String, status: String, result: String, roll_expr: String)
## Le MJ demande au joueur de lancer lui-même un dé pour cette action.
signal roll_request_requested(message_id: String, expr: String, difficulty: int)
## Le joueur touche « Lancer le dé ».
signal roll_answer_requested(message_id: String, expr: String, label: String)
## MJ : épreuve en un clic sur une action (player_rolls : le joueur lance lui-même).
signal check_requested(message_id: String, skill: String, dc: int, player_rolls: bool)
## MJ : conséquence en un clic (dégâts, soins, XP…) sur une action.
signal consequence_requested(message_id: String, kind: String)

var viewer_id := ""
var is_mj := false
var _list: VBoxContainer
var _nodes := {}  # message id -> Control
var _empty: Label
## Filtre d'affichage : all | story | combat
var filter := "all"

const LINE_COLORS := {
	"dmg": Color("e07a70"), "heal": Color("8fd48a"), "miss": Color("8a857c"), "crit": Color("f0c75a"),
	"status": Color("c4a8e8"), "buff": Color("e3c27a"), "ko": Color("e05a50"), "passive": Color("b8a8e0"),
	"res": Color("8fa8ef"), "ult": Color("f0c75a"), "info": Color("bdb6aa"), "xp": Color("9fc0ec"),
	"gold": Color("e8c25a"), "loot": Color("e8dcc0"), "level": Color("9fc0ec"), "quest": Color("e3c27a"),
	"hit": Color("e8dcc0"),
}
const LINE_ICONS := {
	"dmg": "sword", "heal": "heart", "miss": "wind", "crit": "star", "status": "spiral", "buff": "star",
	"ko": "skull", "passive": "sparkle", "res": "drop", "ult": "sun", "info": "", "xp": "xp", "gold": "coin",
	"loot": "chest", "level": "star", "quest": "journal", "hit": "target",
}


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
	node.set_meta("kind", String(m.get("kind", Protocol.KIND_CHAT)))
	node.visible = _passes(node)
	_nodes[m.get("id", "")] = node
	_list.add_child(node)


func set_filter(mode: String) -> void:
	filter = mode
	for node in _nodes.values():
		node.visible = _passes(node)


func _passes(node: Control) -> bool:
	var kind := String(node.get_meta("kind", Protocol.KIND_CHAT))
	match filter:
		"story":
			return kind not in [Protocol.KIND_COMBAT, Protocol.KIND_ROLL]
		"combat":
			return kind in [Protocol.KIND_COMBAT, Protocol.KIND_ROLL, Protocol.KIND_REWARD]
	return true


func update_message(m: Dictionary) -> void:
	var old: Control = _nodes.get(m.get("id", ""))
	if old == null:
		add_message(m)
		return
	var node := build(m)
	node.set_meta("kind", String(m.get("kind", Protocol.KIND_CHAT)))
	node.visible = _passes(node)
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
		Protocol.KIND_ROLL_REQUEST:
			return _roll_request(m)
		Protocol.KIND_COMBAT:
			return _combat(m)
		Protocol.KIND_NARRATION:
			return _narration(m)
		Protocol.KIND_REWARD:
			return _reward(m)
	return UIKit.message_bubble(m, viewer_id)


## Résultat mécanique : titre de l'action puis lignes colorées (dégâts, soins, effets…).
func _combat(m: Dictionary) -> Control:
	var banner := String(m.get("banner", ""))
	var col := _bubble_base(m, "HighlightPanel" if banner == "victory" else ("BubblePrivate" if String(m.get("to", "")) != Protocol.TO_ALL else "InsetPanel"))
	if banner == "victory" or banner == "defeat":
		var t := UIKit.label("VICTOIRE !" if banner == "victory" else "DÉFAITE", "TitleLabel", true)
		t.add_theme_font_size_override("font_size", 30)
		t.add_theme_color_override("font_color", Palette.ULT if banner == "victory" else Palette.DANGER)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(t)
	else:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		col.add_child(head)
		head.add_child(GameUI.icon_badge("sword", Palette.HP.lightened(0.2), 22))
		var title := UIKit.label(String(m.get("text", "")), "StrongLabel", true)
		head.add_child(title)
	_add_lines(col, m.get("lines", []))
	if m.get("roll") is Dictionary and not (m.roll as Dictionary).is_empty():
		col.add_child(UIKit.label(String(m.roll.get("detail", "")), "MutedLabel", true))
	return col.get_parent()


func _add_lines(col: VBoxContainer, lines: Array) -> void:
	for line in lines:
		if not line is Dictionary:
			continue
		var kind := String(line.get("t", "info"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var c: Color = LINE_COLORS.get(kind, Palette.TEXT)
		if kind == "loot" and String(line.get("rarity", "")) != "":
			c = Content.rarity_color(String(line.rarity)).lightened(0.2)
		var icon := String(LINE_ICONS.get(kind, ""))
		if icon != "":
			row.add_child(Icons.new(icon, c, 18))
		var l := UIKit.label(String(line.get("text", "")), "StrongLabel" if kind in ["dmg", "heal", "crit", "ko", "xp", "gold", "loot", "level"] else "", true)
		l.add_theme_color_override("font_color", c)
		l.add_theme_font_size_override("font_size", 17)
		row.add_child(l)
		col.add_child(row)


## Narration du MJ : bloc « récit » sur parchemin sombre.
func _narration(m: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2b2620")
	sb.border_color = Palette.GOLD_DIM
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	if String(m.get("title", "")) != "":
		var t := UIKit.label(String(m.title), "HeadingLabel", true)
		col.add_child(t)
	var text := UIKit.label(String(m.get("text", "")), "", true)
	text.add_theme_color_override("font_color", Color("efe4cc"))
	text.add_theme_font_size_override("font_size", 20)
	col.add_child(text)
	var who := UIKit.label("— " + String(m.get("from_name", "MJ")) + ((" · à " + String(m.get("to_name", ""))) if String(m.get("to", "")) != Protocol.TO_ALL else ""), "MutedLabel")
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(who)
	return panel


## Récompense, quête, montée de niveau : bandeau doré.
func _reward(m: Dictionary) -> Control:
	var banner := String(m.get("banner", ""))
	var col := _bubble_base(m, "HighlightPanel")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var icon: String = {"quest_new": "journal", "quest_done": "chest", "quest_failed": "skull", "level": "star", "reward": "chest"}.get(banner, "coin")
	head.add_child(GameUI.icon_badge(icon, Palette.ULT if banner != "quest_failed" else Palette.DANGER, 34))
	var t := UIKit.label(String(m.get("text", "")), "HeadingLabel" if banner != "" else "StrongLabel", true)
	if banner == "quest_failed":
		t.add_theme_color_override("font_color", Palette.DANGER)
	head.add_child(t)
	_add_lines(col, m.get("lines", []))
	return col.get_parent()


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
	if roll.has("difficulty"):
		info.add_child(_success_chip(roll))
	return col.get_parent()


func _action(m: Dictionary) -> Control:
	var status := String(m.get("status", Protocol.ACTION_PENDING))
	var col := _bubble_base(m, "BubbleMine" if m.get("from", "") == viewer_id else "BubbleOther")
	col.add_child(_header(m, "ACTION", Palette.WARN))
	col.add_child(UIKit.label(String(m.get("text", "")), "", true))
	var chip: Array = {
		Protocol.ACTION_PENDING: ["En attente du MJ", Palette.WARN],
		Protocol.ACTION_ROLL: ["Jet demandé", Palette.GOLD],
		Protocol.ACTION_ROLLED: ["Dé lancé, le MJ conclut", Palette.WARN],
		Protocol.ACTION_RESOLVED: ["Résolue", Palette.OK],
		Protocol.ACTION_REFUSED: ["Refusée", Palette.DANGER],
	}.get(status, ["?", Palette.MUTED])
	var check: Dictionary = m.get("check", {})
	if not check.is_empty():
		_check_block(col, m)
		if is_mj:
			col.add_child(consequence_row(String(m.id)))
		return col.get_parent()
	col.add_child(UIKit.chip(chip[0], chip[1]))
	if status == Protocol.ACTION_ROLL:
		col.add_child(_roll_prompt(m, String(m.get("text", "")).substr(0, 40)))
	var roll: Dictionary = m.get("roll", {})
	var result := String(m.get("result", ""))
	if not (m.get("lines", []) as Array).is_empty():
		_add_lines(col, m.lines)
	if is_mj and status == Protocol.ACTION_RESOLVED:
		col.add_child(consequence_row(String(m.id)))
	if not roll.is_empty() or result != "":
		var res := UIKit.card(col, "", "BubbleMJ")
		if not roll.is_empty():
			res.add_child(UIKit.label("Jet %s → %s  (%s)" % [roll.get("expr", ""), roll.get("total", ""), roll.get("detail", "")], "StrongLabel", true))
			if roll.has("difficulty"):
				res.add_child(_success_chip(roll))
		if result != "":
			res.add_child(UIKit.label(result, "", true))
	return col.get_parent()


func _roll_request(m: Dictionary) -> Control:
	var col := _bubble_base(m, "BubbleMJ")
	col.add_child(_header(m, "JET DEMANDÉ", Palette.GOLD))
	var label := String(m.get("text", ""))
	if label != "":
		col.add_child(UIKit.label(label, "StrongLabel", true))
	var roll: Dictionary = m.get("roll", {})
	if not (m.get("check", {}) as Dictionary).is_empty():
		_check_block(col, m)
	elif m.get("status", "") == "open":
		col.add_child(_roll_prompt(m, label))
	elif not roll.is_empty():
		col.add_child(UIKit.label("Résultat : %s  (%s : %s)" % [roll.get("total", ""), roll.get("expr", ""), roll.get("detail", "")], "", true))
		if roll.has("difficulty"):
			col.add_child(_success_chip(roll))
	return col.get_parent()


## Consigne du jet ; pour le joueur concerné, un grand bouton pour lancer lui-même.
func _roll_prompt(m: Dictionary, label: String) -> Control:
	var request: Dictionary = m.get("request", {})
	var box := VBoxContainer.new()
	var text := "Lancez %s" % request.get("expr", "d20")
	if String(request.get("skill", "")) != "" and Checks.SKILLS.has(String(request.skill)):
		text = "Épreuve de %s (d20 + %s)" % [Checks.SKILLS[request.skill].name, Checks.SKILLS[request.skill].stat]
	if int(request.get("difficulty", 0)) > 0:
		text += "  ·  difficulté %d" % int(request.difficulty)
	box.add_child(UIKit.label(text, "", true))
	var mine: bool = (m.get("kind", "") == Protocol.KIND_ACTION and m.get("from", "") == viewer_id) \
			or (m.get("kind", "") == Protocol.KIND_ROLL_REQUEST and m.get("to", "") == viewer_id)
	if mine and not is_mj:
		var b := UIKit.button("Lancer le dé", "PrimaryButton", func():
			roll_answer_requested.emit(String(m.id), String(request.get("expr", "d20")), label))
		b.custom_minimum_size.y = 56
		box.add_child(b)
	elif is_mj:
		box.add_child(UIKit.label("En attente du jet du joueur…", "MutedLabel", true))
	return box


func _success_chip(roll: Dictionary) -> Control:
	var ok: bool = roll.get("success", false)
	return UIKit.chip(("Réussite" if ok else "Échec") + "  (difficulté %d)" % int(roll.get("difficulty", 0)), Palette.OK if ok else Palette.DANGER)


## Formulaire de résolution d'une action (MJ) : épreuve en un clic (compétence
## devinée d'après le texte, difficulté), ou résultat écrit à la main.
func resolve_form(message_id: String, text: String = "") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	box.add_child(row)
	var skill := OptionButton.new()
	skill.fit_to_longest_item = false
	skill.custom_minimum_size = Vector2(190, 38)
	var guess := Checks.detect(text)
	for id in Checks.SKILLS:
		skill.add_item("%s (%s)" % [Checks.SKILLS[id].name, Checks.SKILLS[id].stat])
		skill.set_item_metadata(skill.item_count - 1, id)
		if id == guess:
			skill.select(skill.item_count - 1)
	row.add_child(skill)
	var picked := func() -> String: return String(skill.get_item_metadata(skill.selected))
	for k in Checks.DC:
		var dc := int(Checks.DC[k])
		var b := UIKit.button("%s %d" % [Checks.DC_NAMES[k], dc], "PrimaryButton" if k == "moyen" else "", func():
			check_requested.emit(message_id, picked.call(), dc, false))
		b.tooltip_text = "Lancer l'épreuve maintenant : jet, résultat et conséquences automatiques."
		row.add_child(b)
	var ask := UIKit.button("Le joueur lance (DD 14)", "", func(): check_requested.emit(message_id, picked.call(), 14, true))
	ask.tooltip_text = "Le joueur touche « Lancer le dé » sur son téléphone ; le reste est automatique."
	row.add_child(ask)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	var result := UIKit.line_edit("", "Ou écrivez le résultat vous-même…")
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(result)
	row2.add_child(UIKit.button("Résoudre", "", func():
		resolve_requested.emit(message_id, Protocol.ACTION_RESOLVED, result.text, "")))
	row2.add_child(UIKit.button("Refuser", "DangerButton", func():
		resolve_requested.emit(message_id, Protocol.ACTION_REFUSED, result.text, "")))
	return box


## Conséquences en un clic (MJ), appliquées à l'auteur de l'action.
func consequence_row(message_id: String) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	var l := UIKit.label("Ajouter :", "MutedLabel")
	row.add_child(l)
	for spec in CheckRunner.CONSEQUENCES:
		var kind: String = spec[1]
		var b := UIKit.button(String(spec[0]), "", func(): consequence_requested.emit(message_id, kind))
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 13)
		row.add_child(b)
	return row


## Bloc d'une épreuve : compétence, dé, total contre DD, issue, récit et conséquences.
func _check_block(col: VBoxContainer, m: Dictionary) -> void:
	var c: Dictionary = m.get("check", {})
	var outcome := String(c.get("outcome", "failure"))
	var color: Color = {"crit": Palette.ULT, "success": Palette.OK, "partial": Palette.WARN, "failure": Palette.DANGER, "fumble": Palette.DANGER}.get(outcome, Palette.TEXT)
	var box := UIKit.card(col, "", "InsetPanel")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	head.add_child(GameUI.icon_badge(String(Checks.get_skill(String(c.get("skill", ""))).get("icon", "target")), color, 26))
	var title := UIKit.label("%s (%s)%s" % [c.get("name", "?"), c.get("stat", ""), ("  →  " + String(c.target_name)) if String(c.get("target_name", "")) != "" else ""], "StrongLabel", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UIKit.chip(String(c.get("label", outcome)), color))
	var dice := UIKit.label("d20 : %d   %+d   =   %d     contre DD %d (%s)" % [int(c.d20), int(c.bonus), int(c.total), int(c.dc), Checks.dc_name(int(c.dc))], "StrongLabel", true)
	dice.add_theme_font_size_override("font_size", 18)
	dice.add_theme_color_override("font_color", color.lightened(0.15))
	box.add_child(dice)
	if String(m.get("result", "")) != "":
		box.add_child(UIKit.label(String(m.result), "", true))
	_add_lines(box, m.get("lines", []))
