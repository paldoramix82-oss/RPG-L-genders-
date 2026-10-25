extends Control
## Écran du joueur (téléphone Android, portrait).
##
## Phase 1 : attente de validation, messages (groupe / privé au MJ), liste du
## groupe, état de la connexion et reconnexion automatique. Les sections
## Personnage, Inventaire, Carte et Journal s'ajouteront à la barre de navigation.

var _client: SessionClient
var _session_label: Label
var _me_label: Label
var _conn_chip: Label
var _pages := {}
var _nav_buttons := {}
var _waiting_label: Label
var _messages_list: VBoxContainer
var _target: OptionButton
var _composer: LineEdit
var _outbox_label: Label
var _group_list: VBoxContainer
var _ping_label: Label
var _keyboard_pad: Control
var _nav_bar: Control


func _ready() -> void:
	_client = Net.client
	if _client == null:
		App.goto(App.SCENE_JOIN)
		return
	add_child(Backdrop.new())
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)

	# --- En-tête : partie, joueur, état de connexion ---
	var bar := PanelContainer.new()
	bar.theme_type_variation = "BarPanel"
	outer.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar.add_child(bar_row)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(titles)
	_session_label = UIKit.label("", "HeadingLabel")
	_session_label.clip_text = true
	titles.add_child(_session_label)
	_me_label = UIKit.label("", "MutedLabel")
	_me_label.clip_text = true
	titles.add_child(_me_label)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	bar_row.add_child(right)
	_conn_chip = UIKit.chip("", Palette.OK)
	_conn_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_conn_chip)
	var quit := UIKit.button("Quitter", "NavButton", _confirm_leave)
	quit.custom_minimum_size.y = 36
	right.add_child(quit)

	# --- Pages ---
	var stack := MarginContainer.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		stack.add_theme_constant_override("margin_" + side, 10)
	outer.add_child(stack)
	_pages.waiting = _build_waiting_page(stack)
	_pages.adventure = _build_adventure_page(stack)
	_pages.group = _build_group_page(stack)

	# Espace réservé au clavier virtuel Android pour que le champ reste visible.
	_keyboard_pad = Control.new()
	outer.add_child(_keyboard_pad)

	# --- Navigation basse ---
	var nav := PanelContainer.new()
	nav.theme_type_variation = "NavPanel"
	outer.add_child(nav)
	_nav_bar = nav
	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 6)
	nav.add_child(nav_row)
	var group := ButtonGroup.new()
	for key in ["adventure", "group"]:
		var b := UIKit.button({"adventure": "Aventure", "group": "Groupe"}[key], "NavButton", _show_page.bind(key))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 54
		nav_row.add_child(b)
		_nav_buttons[key] = b

	_client.status_changed.connect(func(_s): _refresh_all())
	_client.welcomed.connect(_on_welcomed)
	_client.players_changed.connect(_refresh_group)
	_client.message_received.connect(_add_message)
	_client.command_failed.connect(_on_command_failed)
	Net.state_changed.connect(func(_s): _refresh_connection())
	Net.session_ended.connect(_on_session_ended)

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_refresh_connection)
	add_child(timer)

	if _client.is_accepted():
		_on_welcomed()
	_refresh_all()


func _process(_delta: float) -> void:
	if not App.is_mobile() or _keyboard_pad == null:
		return
	var kb_height := DisplayServer.virtual_keyboard_get_height()
	# Hauteur du clavier en pixels physiques -> unités de l'interface.
	var ratio := get_viewport().get_visible_rect().size.y / maxf(1.0, float(DisplayServer.window_get_size().y))
	var pad := maxf(0.0, kb_height * ratio - (_nav_bar.size.y if _nav_bar.visible else 0.0))
	if absf(_keyboard_pad.custom_minimum_size.y - pad) > 1.0:
		_keyboard_pad.custom_minimum_size.y = pad


# ---------------------------------------------------------------------------
# Construction des pages
# ---------------------------------------------------------------------------

func _build_waiting_page(parent: Node) -> Control:
	var body := UIKit.card(parent, "", "HighlightPanel")
	var panel := body.get_parent() as Control
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UIKit.label("En attente du maître du jeu", "HeadingLabel", true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	_waiting_label = UIKit.label("Votre demande a bien été reçue. Le MJ doit l'accepter depuis son PC.", "", true)
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_waiting_label)
	return panel


func _build_adventure_page(parent: Node) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	parent.add_child(page)
	_messages_list = UIKit.vscroll(page)
	_messages_list.add_theme_constant_override("separation", 8)
	UIKit.follow_bottom(_messages_list)

	_outbox_label = UIKit.label("", "MutedLabel", true)
	_outbox_label.add_theme_color_override("font_color", Palette.WARN)
	_outbox_label.visible = false
	page.add_child(_outbox_label)

	var composer := UIKit.card(page, "", "InsetPanel")
	composer.add_theme_constant_override("separation", 8)
	_target = OptionButton.new()
	_target.custom_minimum_size.y = 44
	_target.add_item("Au groupe")
	_target.set_item_metadata(0, Protocol.TO_ALL)
	_target.add_item("Au MJ, en privé")
	_target.set_item_metadata(1, Protocol.TO_MJ)
	composer.add_child(_target)
	var row := HBoxContainer.new()
	composer.add_child(row)
	_composer = UIKit.line_edit("", "Votre message…")
	_composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composer.max_length = Protocol.MAX_MESSAGE_LENGTH
	_composer.text_submitted.connect(func(_t): _send())
	row.add_child(_composer)
	var send := UIKit.button("Envoyer", "PrimaryButton", _send)
	send.custom_minimum_size.x = 100
	row.add_child(send)
	return page


func _build_group_page(parent: Node) -> Control:
	var page := VBoxContainer.new()
	parent.add_child(page)
	var conn := UIKit.card(page, "Connexion")
	_ping_label = UIKit.label("", "MutedLabel", true)
	conn.add_child(_ping_label)
	var members := UIKit.card(page, "Le groupe")
	members.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_group_list = UIKit.vscroll(members)
	return page


# ---------------------------------------------------------------------------
# Mises à jour
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	var accepted := _client.is_accepted()
	if not accepted:
		_pages.waiting.visible = true
		_pages.adventure.visible = false
		_pages.group.visible = false
		_nav_bar.visible = false
	elif _pages.waiting.visible or not (_pages.adventure.visible or _pages.group.visible):
		_nav_bar.visible = true
		_show_page("adventure")
	_session_label.text = String(_client.session.get("name", "Legenders RPG"))
	var me_name := String(_client.me.get("name", Net.join_params().get("name", "")))
	_me_label.text = me_name + ("" if accepted else "  ·  en attente")
	_refresh_connection()


func _show_page(key: String) -> void:
	for k in ["adventure", "group"]:
		_pages[k].visible = k == key
		_nav_buttons[k].set_pressed_no_signal(k == key)
	_pages.waiting.visible = false


func _on_welcomed() -> void:
	UIKit.clear(_messages_list)
	if _client.messages.is_empty():
		var hello := UIKit.label("Bienvenue à la table. Les messages du groupe et du MJ apparaîtront ici.", "MutedLabel", true)
		hello.name = "Hello"
		_messages_list.add_child(hello)
	for m in _client.messages:
		_messages_list.add_child(UIKit.message_bubble(m, String(_client.me.get("id", ""))))
	_refresh_group()
	_refresh_all()


func _add_message(message: Dictionary) -> void:
	var hello := _messages_list.get_node_or_null("Hello")
	if hello:
		hello.queue_free()
	_messages_list.add_child(UIKit.message_bubble(message, String(_client.me.get("id", ""))))
	_refresh_outbox()


func _refresh_group() -> void:
	UIKit.clear(_group_list)
	var mj_row := HBoxContainer.new()
	var mj_name := UIKit.label(String(_client.session.get("mj_name", "MJ")), "StrongLabel")
	mj_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mj_name.add_theme_color_override("font_color", Palette.GOLD)
	mj_row.add_child(mj_name)
	mj_row.add_child(UIKit.label("Maître du jeu", "MutedLabel"))
	_group_list.add_child(mj_row)
	_group_list.add_child(HSeparator.new())
	for p in _client.players:
		var row := HBoxContainer.new()
		var n := UIKit.label(String(p.name) + ("  (vous)" if p.id == _client.me.get("id", "") else ""), "")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		row.add_child(n)
		row.add_child(UIKit.chip("En ligne" if p.online else "Hors ligne", Palette.OK if p.online else Palette.FAINT))
		_group_list.add_child(row)


func _refresh_connection() -> void:
	match Net.state:
		Net.State.CONNECTED:
			if _client.is_accepted():
				UIKit.set_chip(_conn_chip, "Connecté", Palette.OK)
			else:
				UIKit.set_chip(_conn_chip, "En attente", Palette.WARN)
		Net.State.RECONNECTING, Net.State.CONNECTING:
			UIKit.set_chip(_conn_chip, "Reconnexion…", Palette.WARN)
		_:
			UIKit.set_chip(_conn_chip, "Hors ligne", Palette.DANGER)
	var params := Net.join_params()
	var rtt := Net.get_peer_rtt(1)
	_ping_label.text = "%s\nPC du MJ : %s:%s  ·  ping %s" % [Net.state_label(), params.get("ip", "?"), params.get("port", "?"), UIKit.ping_text(rtt)]
	_refresh_outbox()


func _refresh_outbox() -> void:
	var n := _client.pending_count()
	_outbox_label.visible = n > 0
	_outbox_label.text = "%d message%s en cours d'envoi…" % [n, "s" if n > 1 else ""]


func _send() -> void:
	var text := _composer.text.strip_edges()
	if text == "":
		return
	var to := String(_target.get_item_metadata(_target.selected))
	_client.send_chat(to, text)
	_composer.clear()
	_refresh_outbox()


func _on_command_failed(_req_id: String, error: String) -> void:
	var l := UIKit.label("⚠  " + error, "MutedLabel", true)
	l.add_theme_color_override("font_color", Palette.DANGER)
	_messages_list.add_child(l)


func _on_session_ended(reason: String) -> void:
	App.flash = reason
	App.goto(App.SCENE_JOIN)


func _confirm_leave() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Quitter la partie"
	dialog.dialog_text = "Vous pourrez revenir : votre place est conservée par le MJ."
	dialog.ok_button_text = "Quitter"
	dialog.cancel_button_text = "Rester"
	dialog.confirmed.connect(func():
		Net.leave()
		App.goto(App.SCENE_JOIN))
	add_child(dialog)
	dialog.popup_centered()
