extends Control
## Écran « Rejoindre une partie » : un nom et l'adresse IP de l'hôte, c'est tout.
## L'adresse se tape avec un pavé numérique intégré (le point fonctionne toujours,
## contrairement à certains claviers Android) ; le début de l'adresse est
## pré-rempli d'après le Wi-Fi du téléphone. Les parties détectées se rejoignent
## d'un seul toucher.

var _name: LineEdit
var _ip: LineEdit
var _port: SpinBox
var _join_button: Button
var _status: Label
var _found_list: VBoxContainer
var _found_empty: Label
var _keypad: GridContainer


func _ready() -> void:
	add_child(Backdrop.new())
	var scroll := TouchScroll.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	# --- Parties détectées : un toucher suffit ---
	var found := UIKit.card(page, "Parties sur ce Wi-Fi")
	_found_list = VBoxContainer.new()
	found.add_child(_found_list)
	_found_empty = UIKit.label("Recherche… Si rien n'apparaît, tapez l'adresse affichée chez l'hôte ci-dessous.", "MutedLabel", true)
	found.add_child(_found_empty)

	# --- Saisie manuelle ---
	var form := UIKit.card(page, "Votre nom et l'adresse de l'hôte")
	_name = UIKit.field(form, "Votre nom", UIKit.line_edit(App.get_setting("join", "name", ""), "Ex. : Camille"))
	_name.max_length = Protocol.MAX_NAME_LENGTH
	_ip = UIKit.field(form, "Adresse IP de l'hôte (affichée sur son écran)", UIKit.line_edit(_initial_ip(), "Ex. : 192.168.1.20"))
	_ip.add_theme_font_size_override("font_size", 26)
	_ip.custom_minimum_size.y = 58
	if App.is_mobile():
		# Pavé intégré à la place du clavier du téléphone.
		_ip.virtual_keyboard_enabled = false
	_ip.text_submitted.connect(func(_t): _on_join())
	_keypad = _build_keypad()
	_keypad.visible = App.is_mobile()
	form.add_child(_keypad)

	_status = UIKit.label("", "", true)
	_status.visible = false
	form.add_child(_status)
	_join_button = UIKit.button("Rejoindre la partie", "PrimaryButton", _on_join)
	_join_button.custom_minimum_size.y = 60
	form.add_child(_join_button)

	var advanced := UIKit.card(page, "", "InsetPanel")
	var adv_toggle := UIKit.button("Options avancées  ›", "NavButton")
	adv_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	advanced.add_child(adv_toggle)
	var adv_box := VBoxContainer.new()
	adv_box.visible = false
	advanced.add_child(adv_box)
	_port = UIKit.field(adv_box, "Port (7777, sauf si l'hôte l'a changé)", UIKit.spin(App.get_setting("join", "port", Protocol.DEFAULT_PORT), 1024, 65535))
	adv_box.add_child(UIKit.label("Votre appareil et celui de l'hôte doivent être sur le même Wi-Fi (box, routeur ou partage de connexion d'un joueur). Les données mobiles ne sont pas utilisées.", "MutedLabel", true))
	adv_toggle.pressed.connect(func():
		adv_box.visible = not adv_box.visible
		adv_toggle.text = "Options avancées  " + ("▼" if adv_box.visible else "›"))

	Net.joined.connect(_on_joined)
	Net.join_failed.connect(_on_failed)
	Net.discovery.server_found.connect(func(_info): _refresh_found())
	Net.discovery.start_listening()
	var refresh := Timer.new()
	refresh.wait_time = 2.0
	refresh.autostart = true
	refresh.timeout.connect(_refresh_found)
	add_child(refresh)


## Dernière adresse utilisée, sinon le début de l'adresse du Wi-Fi du téléphone.
func _initial_ip() -> String:
	var last := String(App.get_setting("join", "ip", ""))
	if last != "":
		return last
	var mine := NetUtils.get_lan_ipv4_addresses()
	if mine.is_empty():
		return ""
	var parts := mine[0].split(".")
	return "%s.%s.%s." % [parts[0], parts[1], parts[2]]


func _build_keypad() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for key in ["1", "2", "3", "‹", "4", "5", "6", ".", "7", "8", "9", "Effacer", "", "0", "", ""]:
		if key == "":
			grid.add_child(Control.new())
			continue
		var b := UIKit.button(key, "", _on_key.bind(key))
		b.custom_minimum_size = Vector2(0, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 24 if key.length() == 1 else 15)
		if key == "‹":
			b.tooltip_text = "Effacer le dernier caractère"
		grid.add_child(b)
	return grid


func _on_key(key: String) -> void:
	match key:
		"‹":
			_ip.text = _ip.text.substr(0, maxi(0, _ip.text.length() - 1))
		"Effacer":
			_ip.text = ""
		".":
			if _ip.text != "" and not _ip.text.ends_with(".") and _ip.text.count(".") < 3:
				_ip.text += "."
		_:
			_ip.text += key
	_ip.caret_column = _ip.text.length()


func _exit_tree() -> void:
	if Net.discovery.is_listening():
		Net.discovery.stop()


func _on_back() -> void:
	Net.leave()
	App.goto(App.SCENE_MAIN_MENU)


func _on_join(ip: String = "", port: int = 0) -> void:
	if ip == "":
		ip = _ip.text.strip_edges().trim_suffix(".")
	if port == 0:
		port = int(_port.value)
	if _name.text.strip_edges() == "":
		_show_status("Indiquez d'abord votre nom.", Palette.DANGER)
		_name.grab_focus()
		return
	App.set_setting("join", "name", _name.text.strip_edges())
	App.set_setting("join", "ip", ip)
	App.set_setting("join", "port", port)
	App.save_settings()
	var error := Net.join(ip, port, _name.text)
	if error != "":
		_show_status(error, Palette.DANGER)
		return
	_join_button.disabled = true
	_join_button.text = "Connexion…"
	_show_status("Connexion à %s…" % ip, Palette.MUTED)


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
		var b := UIKit.button("", "PrimaryButton", func():
			_ip.text = info.ip
			_on_join(info.ip, info.port))
		b.text = "Rejoindre « %s »\nMJ : %s  ·  %d/%d joueurs" % [info.name, info.mj, info.players, info.max]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.y = 68
		if info.proto != Protocol.VERSION:
			b.disabled = true
			b.text += "  ·  version différente"
		_found_list.add_child(b)
