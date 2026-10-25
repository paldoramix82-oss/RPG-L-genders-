extends Control
## Écran du maître du jeu (PC) : préparation du serveur puis tableau de bord de session.
##
## Phase 1 : informations de connexion, validation des joueurs, état du réseau,
## messages publics et privés. Les outils de jeu viendront s'ajouter dans le
## panneau central sans changer cette structure.

var _root: Control
var _error_label: Label
var _inputs := {}

# Tableau de bord
var _state_chip: Label
var _count_label: Label
var _players_list: VBoxContainer
var _player_widgets := {}  # player_id -> {ping: Label}
var _messages_list: VBoxContainer
var _target: OptionButton
var _composer: LineEdit
var _net_labels := {}
var _log_list: VBoxContainer
var _refresh_timer: Timer


func _ready() -> void:
	add_child(Backdrop.new())
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	if Net.role == Net.Role.HOST:
		_build_dashboard()
	else:
		_build_setup()


# ---------------------------------------------------------------------------
# Préparation
# ---------------------------------------------------------------------------

func _build_setup() -> void:
	UIKit.clear(_root)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(scroll)
	var column := CenteredColumn.new()
	column.max_width = 560
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	column.add_child(page)

	var gap := Control.new()
	gap.custom_minimum_size.y = 32
	page.add_child(gap)
	page.add_child(UIKit.label("Héberger une partie", "TitleLabel"))
	page.add_child(UIKit.label("Ce PC devient le serveur de la partie. Les joueurs le rejoignent depuis leur téléphone, sur le même Wi-Fi.", "MutedLabel", true))

	var form := UIKit.card(page, "Session")
	_inputs.name = UIKit.field(form, "Nom de la partie", UIKit.line_edit(App.get_setting("host", "name", "Les Cendres de Valombre"), "Nom affiché aux joueurs"))
	_inputs.mj_name = UIKit.field(form, "Nom du maître du jeu", UIKit.line_edit(App.get_setting("host", "mj_name", "Maître du jeu")))
	var row := HBoxContainer.new()
	form.add_child(row)
	_inputs.port = UIKit.field(row, "Port UDP", UIKit.spin(App.get_setting("host", "port", Protocol.DEFAULT_PORT), 1024, 65535))
	_inputs.max_players = UIKit.field(row, "Joueurs maximum", UIKit.spin(App.get_setting("host", "max_players", Protocol.DEFAULT_MAX_PLAYERS), 1, Protocol.MAX_PLAYERS_LIMIT))
	var auto := CheckBox.new()
	auto.text = "Accepter automatiquement les joueurs qui ont le code"
	auto.button_pressed = App.get_setting("host", "auto_accept", false)
	form.add_child(auto)
	_inputs.auto_accept = auto

	_error_label = UIKit.label("", "", true)
	_error_label.add_theme_color_override("font_color", Palette.DANGER)
	_error_label.visible = false
	page.add_child(_error_label)

	var actions := HBoxContainer.new()
	page.add_child(actions)
	actions.add_child(UIKit.button("Retour", "", func(): App.goto(App.SCENE_MAIN_MENU)))
	actions.add_child(UIKit.spacer(false))
	var start := UIKit.button("Lancer le serveur", "PrimaryButton", _on_start_pressed)
	start.custom_minimum_size.x = 220
	actions.add_child(start)

	var hint := UIKit.card(page, "", "InsetPanel")
	hint.add_child(UIKit.label("Pare-feu Windows : au premier lancement, autorisez Legenders RPG sur les « Réseaux privés ». Le réseau Wi-Fi du PC doit être de type « Privé ». Détails dans docs/RESEAU.md.", "MutedLabel", true))


func _on_start_pressed() -> void:
	var settings := {
		"name": (_inputs.name as LineEdit).text,
		"mj_name": (_inputs.mj_name as LineEdit).text,
		"port": int((_inputs.port as SpinBox).value),
		"max_players": int((_inputs.max_players as SpinBox).value),
		"auto_accept": (_inputs.auto_accept as CheckBox).button_pressed,
	}
	for key in settings:
		App.set_setting("host", key, settings[key])
	App.save_settings()
	var error := Net.host(settings)
	if error != "":
		_error_label.text = error
		_error_label.visible = true
		return
	_build_dashboard()


# ---------------------------------------------------------------------------
# Tableau de bord
# ---------------------------------------------------------------------------

func _build_dashboard() -> void:
	UIKit.clear(_root)
	var server := Net.server
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	_root.add_child(outer)

	# --- Barre supérieure ---
	var bar := PanelContainer.new()
	bar.theme_type_variation = "BarPanel"
	outer.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 18)
	bar.add_child(bar_row)
	var title := UIKit.label(server.session.name, "HeadingLabel")
	title.add_theme_font_size_override("font_size", 24)
	bar_row.add_child(title)
	bar_row.add_child(UIKit.label("MJ : " + server.session.mj_name, "MutedLabel"))
	_state_chip = UIKit.chip("Serveur actif", Palette.OK)
	bar_row.add_child(_state_chip)
	bar_row.add_child(UIKit.spacer(false))
	_count_label = UIKit.label("", "StrongLabel")
	bar_row.add_child(_count_label)
	bar_row.add_child(UIKit.button("Terminer la session", "DangerButton", _confirm_end))

	# --- Trois colonnes ---
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	outer.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 340
	left.add_theme_constant_override("separation", 16)
	columns.add_child(left)
	_build_join_card(left)
	var players_card := UIKit.card(left, "Joueurs")
	players_card.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_players_list = UIKit.vscroll(players_card)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(center)
	var messages_card := UIKit.card(center, "Messages")
	messages_card.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_messages_list = UIKit.vscroll(messages_card)
	_messages_list.add_theme_constant_override("separation", 8)
	UIKit.follow_bottom(_messages_list)
	var composer := HBoxContainer.new()
	messages_card.add_child(composer)
	_target = OptionButton.new()
	_target.custom_minimum_size = Vector2(210, UIKit.TOUCH_HEIGHT)
	composer.add_child(_target)
	_composer = UIKit.line_edit("", "Écrire au groupe ou en privé…")
	_composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composer.max_length = Protocol.MAX_MESSAGE_LENGTH
	_composer.text_submitted.connect(func(_t): _send_message())
	composer.add_child(_composer)
	composer.add_child(UIKit.button("Envoyer", "PrimaryButton", _send_message))

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300
	right.add_theme_constant_override("separation", 16)
	columns.add_child(right)
	var net_card := UIKit.card(right, "Réseau")
	for key in ["state", "online", "pending", "port", "discovery", "started"]:
		var row := HBoxContainer.new()
		net_card.add_child(row)
		var caption := UIKit.label({
			"state": "État", "online": "Connectés", "pending": "En attente",
			"port": "Port UDP", "discovery": "Découverte Wi-Fi", "started": "Démarré à",
		}[key], "MutedLabel")
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		_net_labels[key] = UIKit.label("")
		row.add_child(_net_labels[key])
	var log_card := UIKit.card(right, "Journal des connexions")
	log_card.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_list = UIKit.vscroll(log_card)
	_log_list.add_theme_constant_override("separation", 4)
	UIKit.follow_bottom(_log_list)

	server.players_changed.connect(_refresh_players)
	server.message_added.connect(_add_message)
	server.log_added.connect(_add_log)
	for m in server.messages:
		_add_message(m)
	for entry in server.connection_log:
		_add_log(entry)
	_refresh_players()

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_refresh_live)
	add_child(_refresh_timer)
	_refresh_live()
	_composer.grab_focus.call_deferred()


func _build_join_card(parent: Node) -> void:
	var server := Net.server
	var card := UIKit.card(parent, "Pour rejoindre", "HighlightPanel")
	card.add_child(UIKit.label("Adresse IP de ce PC", "MutedLabel"))
	var ips := NetUtils.get_lan_ipv4_addresses()
	if ips.is_empty():
		var none := UIKit.label("Aucun réseau détecté. Connectez le PC au Wi-Fi.", "", true)
		none.add_theme_color_override("font_color", Palette.DANGER)
		card.add_child(none)
	for i in ips.size():
		var ip_label := UIKit.label(ips[i], "CodeLabel")
		ip_label.add_theme_font_size_override("font_size", 30 if i == 0 else 20)
		if i > 0:
			ip_label.add_theme_color_override("font_color", Palette.MUTED)
		card.add_child(ip_label)
	if ips.size() > 1:
		card.add_child(UIKit.label("Plusieurs réseaux : utilisez l'adresse du Wi-Fi partagé avec les joueurs.", "MutedLabel", true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	card.add_child(row)
	var port_box := VBoxContainer.new()
	port_box.add_theme_constant_override("separation", 0)
	port_box.add_child(UIKit.label("Port", "MutedLabel"))
	var port_label := UIKit.label(str(server.session.port), "CodeLabel")
	port_label.add_theme_font_size_override("font_size", 30)
	port_box.add_child(port_label)
	row.add_child(port_box)
	var code_box := VBoxContainer.new()
	code_box.add_theme_constant_override("separation", 0)
	code_box.add_child(UIKit.label("Code de la partie", "MutedLabel"))
	var code_label := UIKit.label(server.session.code, "CodeLabel")
	code_label.add_theme_color_override("font_color", Palette.GOLD)
	code_box.add_child(code_label)
	row.add_child(code_box)


func _refresh_players() -> void:
	if _players_list == null:
		return
	var server := Net.server
	UIKit.clear(_players_list)
	_player_widgets.clear()
	var list: Array = server.players.values()
	var order := {Protocol.STATUS_PENDING: 0, Protocol.STATUS_ACCEPTED: 1, Protocol.STATUS_REFUSED: 2}
	list.sort_custom(func(a, b):
		if order[a.status] != order[b.status]:
			return order[a.status] < order[b.status]
		if a.online != b.online:
			return a.online
		return String(a.name).naturalnocasecmp_to(b.name) < 0)
	if list.is_empty():
		_players_list.add_child(UIKit.label("Aucun joueur pour l'instant. Donnez-leur l'adresse IP, le port et le code ci-dessus.", "MutedLabel", true))
	for p in list:
		_players_list.add_child(_player_row(p))
	_refresh_targets()
	_refresh_live()


func _player_row(p: Dictionary) -> Control:
	var body := UIKit.card(null, "", "InsetPanel")
	var panel := body.get_parent()
	body.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	body.add_child(head)
	var name_label := UIKit.label(p.name, "StrongLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	head.add_child(name_label)
	match p.status:
		Protocol.STATUS_PENDING:
			head.add_child(UIKit.chip("Demande" if p.online else "Demande · hors ligne", Palette.WARN))
		Protocol.STATUS_REFUSED:
			head.add_child(UIKit.chip("Refusé", Palette.DANGER))
		_:
			head.add_child(UIKit.chip("Connecté" if p.online else "Hors ligne", Palette.OK if p.online else Palette.FAINT))
	var info := UIKit.label("", "MutedLabel", true)
	body.add_child(info)
	_player_widgets[p.id] = {"info": info}

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	body.add_child(actions)
	var pid: String = p.id
	match p.status:
		Protocol.STATUS_PENDING:
			actions.add_child(_small_button("Accepter", "PrimaryButton", func(): Net.server.accept_player(pid)))
			actions.add_child(_small_button("Refuser", "DangerButton", func(): Net.server.refuse_player(pid)))
		Protocol.STATUS_ACCEPTED:
			actions.add_child(_small_button("Message privé", "", func(): _select_target(pid)))
			if p.online:
				actions.add_child(_small_button("Déconnecter", "", func(): Net.server.kick_player(pid)))
			actions.add_child(_small_button("Retirer", "DangerButton", func(): _confirm_remove(pid, p.name)))
		Protocol.STATUS_REFUSED:
			actions.add_child(_small_button("Oublier", "", func(): Net.server.remove_player(pid)))
	return panel


func _small_button(text: String, variation: String, cb: Callable) -> Button:
	var b := UIKit.button(text, variation, cb)
	b.custom_minimum_size.y = 38
	b.add_theme_font_size_override("font_size", 16)
	return b


## Mise à jour chaque seconde : ping, compteurs (sans reconstruire les listes).
func _refresh_live() -> void:
	var server := Net.server
	if server == null or _count_label == null:
		return
	var online := server.count_online()
	var pending := server.count_status(Protocol.STATUS_PENDING)
	_count_label.text = "%d / %d joueurs connectés" % [online, server.session.max_players]
	_net_labels.state.text = Net.state_label()
	_net_labels.online.text = str(online)
	_net_labels.pending.text = str(pending)
	_net_labels.pending.add_theme_color_override("font_color", Palette.WARN if pending > 0 else Palette.TEXT)
	_net_labels.port.text = str(server.session.port)
	_net_labels.discovery.text = "active"
	_net_labels.started.text = Protocol.format_time(server.session.created)
	for pid in _player_widgets:
		var p: Dictionary = server.players.get(pid, {})
		if p.is_empty():
			continue
		var parts: PackedStringArray = [p.ip]
		if p.online:
			parts.append("ping " + UIKit.ping_text(Net.get_peer_rtt(p.peer_id)))
		else:
			parts.append("vu à " + Protocol.format_time(p.last_seen))
		if p.disconnects > 0:
			parts.append("%d coupure%s" % [p.disconnects, "s" if p.disconnects > 1 else ""])
		(_player_widgets[pid].info as Label).text = "  ·  ".join(parts)


func _refresh_targets() -> void:
	var previous := _current_target()
	_target.clear()
	_target.add_item("Tout le groupe")
	_target.set_item_metadata(0, Protocol.TO_ALL)
	for p in Net.server.players.values():
		if p.status == Protocol.STATUS_ACCEPTED:
			_target.add_item("Privé : " + p.name)
			_target.set_item_metadata(_target.item_count - 1, p.id)
	_select_target(previous, false)


func _current_target() -> String:
	if _target == null or _target.selected < 0:
		return Protocol.TO_ALL
	return String(_target.get_item_metadata(_target.selected))


func _select_target(target: String, focus: bool = true) -> void:
	for i in _target.item_count:
		if _target.get_item_metadata(i) == target:
			_target.select(i)
			break
	if focus:
		_composer.grab_focus()


func _send_message() -> void:
	var text := _composer.text.strip_edges()
	if text == "":
		return
	if Net.server.mj_send_message(_current_target(), text):
		_composer.clear()


func _add_message(message: Dictionary) -> void:
	_messages_list.add_child(UIKit.message_bubble(message, Protocol.MJ_ID))


func _add_log(entry: Dictionary) -> void:
	var color := {"ok": Palette.OK, "warn": Palette.WARN, "ask": Palette.GOLD}.get(entry.kind, Palette.MUTED) as Color
	var l := UIKit.label("%s  %s" % [Protocol.format_time(entry.ts), entry.text], "MutedLabel", true)
	l.add_theme_color_override("font_color", color)
	_log_list.add_child(l)
	if _log_list.get_child_count() > 300:
		_log_list.get_child(0).queue_free()


func _confirm_remove(pid: String, player_name: String) -> void:
	_confirm("Retirer %s de la partie ? Son nom et sa place seront libérés." % player_name, func(): Net.server.remove_player(pid))


func _confirm_end() -> void:
	_confirm("Terminer la session ? Tous les joueurs seront déconnectés.", func():
		Net.leave()
		App.goto(App.SCENE_MAIN_MENU))


func _confirm(text: String, on_ok: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Confirmation"
	dialog.dialog_text = text
	dialog.ok_button_text = "Confirmer"
	dialog.cancel_button_text = "Annuler"
	dialog.confirmed.connect(on_ok)
	dialog.visibility_changed.connect(func(): if not dialog.visible: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
