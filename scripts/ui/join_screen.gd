extends Control
## Écran « Rejoindre une partie » (pensé pour le téléphone, utilisable sur PC).
## La saisie manuelle de l'adresse IP fonctionne toujours ; la liste des parties
## détectées sur le Wi-Fi n'est qu'un raccourci.

var _name: LineEdit
var _ip: LineEdit
var _port: SpinBox
var _code: LineEdit
var _join_button: Button
var _status: Label
var _found_list: VBoxContainer
var _found_empty: Label


func _ready() -> void:
	add_child(Backdrop.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var column := CenteredColumn.new()
	column.max_width = 520
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	column.add_child(page)

	var top := HBoxContainer.new()
	page.add_child(top)
	top.add_child(UIKit.button("‹  Retour", "NavButton", _on_back))
	page.add_child(UIKit.label("Rejoindre", "TitleLabel"))

	if App.flash != "":
		var flash_body := UIKit.card(page, "", "HighlightPanel")
		flash_body.add_child(UIKit.label(App.flash, "", true))
		App.flash = ""

	var form := UIKit.card(page, "Votre table")
	_name = UIKit.field(form, "Votre nom de joueur", UIKit.line_edit(App.get_setting("join", "name", ""), "Ex. : Camille"))
	_name.max_length = Protocol.MAX_NAME_LENGTH
	_ip = UIKit.field(form, "Adresse IP du PC du MJ", UIKit.line_edit(App.get_setting("join", "ip", ""), "Ex. : 192.168.1.20"))
	_ip.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	var row := HBoxContainer.new()
	form.add_child(row)
	_port = UIKit.field(row, "Port", UIKit.spin(App.get_setting("join", "port", Protocol.DEFAULT_PORT), 1024, 65535))
	_port.size_flags_stretch_ratio = 0.8
	_code = UIKit.field(row, "Code de la partie", UIKit.line_edit(App.get_setting("join", "code", ""), "ABC123"))
	_code.max_length = Protocol.CODE_LENGTH + 2
	_code.text_changed.connect(func(t):
		var caret := _code.caret_column
		_code.text = t.to_upper()
		_code.caret_column = caret)
	_code.text_submitted.connect(func(_t): _on_join())

	_status = UIKit.label("", "", true)
	_status.visible = false
	form.add_child(_status)
	_join_button = UIKit.button("Rejoindre la partie", "PrimaryButton", _on_join)
	_join_button.custom_minimum_size.y = 56
	form.add_child(_join_button)

	var found := UIKit.card(page, "Parties détectées sur ce Wi-Fi")
	_found_list = VBoxContainer.new()
	found.add_child(_found_list)
	_found_empty = UIKit.label("Recherche en cours… Si rien n'apparaît, saisissez l'adresse affichée sur le PC du MJ.", "MutedLabel", true)
	found.add_child(_found_empty)

	var help := UIKit.card(page, "", "InsetPanel")
	help.add_child(UIKit.label("Le téléphone et le PC doivent être sur le même Wi-Fi (box, routeur ou partage de connexion d'un joueur). Les données mobiles ne sont pas utilisées.", "MutedLabel", true))

	Net.joined.connect(_on_joined)
	Net.join_failed.connect(_on_failed)
	Net.discovery.server_found.connect(func(_info): _refresh_found())
	Net.discovery.start_listening()
	var refresh := Timer.new()
	refresh.wait_time = 2.0
	refresh.autostart = true
	refresh.timeout.connect(_refresh_found)
	add_child(refresh)


func _exit_tree() -> void:
	if Net.discovery.is_listening():
		Net.discovery.stop()


func _on_back() -> void:
	Net.leave()
	App.goto(App.SCENE_MAIN_MENU)


func _on_join() -> void:
	App.set_setting("join", "name", _name.text.strip_edges())
	App.set_setting("join", "ip", _ip.text.strip_edges())
	App.set_setting("join", "port", int(_port.value))
	App.set_setting("join", "code", Protocol.normalize_code(_code.text))
	App.save_settings()
	var error := Net.join(_ip.text, int(_port.value), _code.text, _name.text)
	if error != "":
		_show_status(error, Palette.DANGER)
		return
	_join_button.disabled = true
	_join_button.text = "Connexion…"
	_show_status("Connexion à %s:%d…" % [_ip.text.strip_edges(), int(_port.value)], Palette.MUTED)


func _on_joined() -> void:
	App.goto(App.SCENE_PLAYER)


func _on_failed(reason: String) -> void:
	_join_button.disabled = false
	_join_button.text = "Rejoindre la partie"
	_show_status(reason, Palette.DANGER)


func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	_status.visible = true


func _refresh_found() -> void:
	UIKit.clear(_found_list)
	var servers: Array = Net.discovery.servers.values()
	_found_empty.visible = servers.is_empty()
	for info in servers:
		var b := UIKit.button("", "", func():
			_ip.text = info.ip
			_port.value = info.port
			_code.grab_focus())
		b.text = "%s  —  %s\n%s:%d  ·  %d/%d joueurs" % [info.name, info.mj, info.ip, info.port, info.players, info.max]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 64
		if info.proto != Protocol.VERSION:
			b.disabled = true
			b.text += "  ·  version différente"
		_found_list.add_child(b)
