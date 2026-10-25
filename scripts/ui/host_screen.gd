extends Control
## Écran du maître du jeu : préparation (nouvelle campagne ou reprise) puis
## tableau de bord. S'adapte à la largeur : colonnes sur PC, onglets sur téléphone.

const NARROW_WIDTH := 900.0

var _root: Control
var _error_label: Label
var _inputs := {}

# --- Tableau de bord ---
var _narrow := false
var _tabs: TabbedPages
var _count_label: Label
var _save_label: Label
var _players_list: VBoxContainer
var _player_widgets := {}
var _net_labels := {}
var _log_list: VBoxContainer
var _refresh_timer: Timer

# Table (carte)
var _edit_map := ""
var _map_view: MapView
var _map_select: OptionButton
var _map_status: Label
var _move_check: CheckBox
var _tool := "move"
var _tool_buttons := {}
var _tool_options: VBoxContainer
var _paint_code := "."
var _brush := 0
var _token_tpl := {"kind": "monster", "name": "Monstre", "color": "#b0605a", "hp": 10, "hidden": true}
var _label_tpl := {"text": "", "hidden": false}
var _inspector: VBoxContainer
var _insp_widgets := {}
var _combat_box: VBoxContainer

# Récit
var _feed: FeedView
var _composer: Composer
var _pending_box: VBoxContainer
var _pending_title: Label

# Personnages
var _char_list: HFlowContainer
var _char_detail: VBoxContainer
var _char_selected := ""
var _char_editing := false


func _ready() -> void:
	add_child(Backdrop.new())
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	resized.connect(_on_resized)
	if Net.role == Net.Role.HOST:
		_build_dashboard.call_deferred()
	else:
		_build_setup()


func _on_resized() -> void:
	if Net.role != Net.Role.HOST or _tabs == null:
		return
	if (size.x < NARROW_WIDTH) != _narrow:
		_build_dashboard()


# ---------------------------------------------------------------------------
# Préparation
# ---------------------------------------------------------------------------

func _build_setup() -> void:
	UIKit.clear(_root)
	_tabs = null
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(scroll)
	var column := CenteredColumn.new()
	column.max_width = 620
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	column.add_child(page)

	var top := HBoxContainer.new()
	page.add_child(top)
	top.add_child(UIKit.button("‹  Retour", "NavButton", func(): App.goto(App.SCENE_MAIN_MENU)))
	page.add_child(UIKit.label("Héberger une partie", "TitleLabel", true))
	page.add_child(UIKit.label("Cet appareil devient l'hôte : il garde la partie et la sauvegarde. Les joueurs le rejoignent sur le même Wi-Fi.", "MutedLabel", true))

	_error_label = UIKit.label("", "", true)
	_error_label.add_theme_color_override("font_color", Palette.DANGER)
	_error_label.visible = false
	page.add_child(_error_label)

	# --- Nouvelle campagne ---
	var form := UIKit.card(page, "Nouvelle campagne")
	_inputs.name = UIKit.field(form, "Nom de la campagne", UIKit.line_edit(App.get_setting("host", "name", "Les Cendres de Valombre"), "Nom affiché aux joueurs"))
	_inputs.mj_name = UIKit.field(form, "Nom du maître du jeu", UIKit.line_edit(App.get_setting("host", "mj_name", "Maître du jeu")))
	var universe := OptionButton.new()
	var tagline := UIKit.label("", "MutedLabel", true)
	var universes := Universe.all()
	for u in universes:
		universe.add_item(String(u.name))
		universe.set_item_metadata(universe.item_count - 1, u.id)
		if u.id == App.get_setting("host", "universe", Universe.DEFAULT_ID):
			universe.select(universe.item_count - 1)
	var show_tagline := func(_i: int = 0):
		for u in universes:
			if u.id == universe.get_item_metadata(universe.selected):
				tagline.text = "%s\n%s" % [u.get("tagline", ""), u.get("description", "")]
	universe.item_selected.connect(show_tagline)
	UIKit.field(form, "Univers", universe)
	form.add_child(tagline)
	show_tagline.call()
	_inputs.universe = universe
	form.add_child(UIKit.label("L'univers fournit le codex, des cartes et des suggestions (espèces, magies, rangs) ; tout reste modifiable.", "MutedLabel", true))
	var start := UIKit.button("Créer la campagne et ouvrir la partie", "PrimaryButton", _on_new_pressed)
	start.custom_minimum_size.y = 56
	form.add_child(start)

	# --- Reprendre ---
	var saves := CampaignStore.list()
	var resume := UIKit.card(page, "Reprendre une campagne")
	if saves.is_empty():
		resume.add_child(UIKit.label("Aucune sauvegarde sur cet appareil pour l'instant. Les campagnes sont sauvegardées automatiquement pendant la partie.", "MutedLabel", true))
	for s in saves:
		var row := HBoxContainer.new()
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UIKit.label(String(s.name), "StrongLabel", true))
		var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		var date := Time.get_datetime_string_from_unix_time(int(s.saved_at) + bias, true)
		info.add_child(UIKit.label("%s  ·  %d joueur%s  ·  %s" % [Universe.get_by_id(s.universe).get("name", s.universe), s.players, "s" if s.players > 1 else "", date], "MutedLabel", true))
		row.add_child(info)
		var sid: String = s.id
		var sname: String = s.name
		row.add_child(UIKit.button("Reprendre", "PrimaryButton", func(): _on_load_pressed(sid)))
		row.add_child(UIKit.button("×", "DangerButton", func(): _confirm("Supprimer définitivement la sauvegarde « %s » ?" % sname, func():
			CampaignStore.delete(sid)
			_build_setup())))
		resume.add_child(row)

	# --- Réseau ---
	var net := UIKit.card(page, "Réseau")
	var row2 := HBoxContainer.new()
	net.add_child(row2)
	_inputs.port = UIKit.field(row2, "Port UDP", UIKit.spin(App.get_setting("host", "port", Protocol.DEFAULT_PORT), 1024, 65535))
	_inputs.max_players = UIKit.field(row2, "Joueurs maximum", UIKit.spin(App.get_setting("host", "max_players", Protocol.DEFAULT_MAX_PLAYERS), 1, Protocol.MAX_PLAYERS_LIMIT))
	var auto := CheckBox.new()
	auto.text = "Accepter automatiquement les joueurs qui ont le code"
	auto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto.button_pressed = App.get_setting("host", "auto_accept", false)
	net.add_child(auto)
	_inputs.auto_accept = auto
	net.add_child(UIKit.label("PC Windows : au premier lancement, autorisez l'application sur les « Réseaux privés ». Téléphone hôte : gardez l'application ouverte et l'écran allumé pendant la partie.", "MutedLabel", true))
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	page.add_child(gap)


func _network_settings() -> Dictionary:
	var settings := {
		"port": int((_inputs.port as SpinBox).value),
		"max_players": int((_inputs.max_players as SpinBox).value),
		"auto_accept": (_inputs.auto_accept as CheckBox).button_pressed,
	}
	for key in settings:
		App.set_setting("host", key, settings[key])
	return settings


func _on_new_pressed() -> void:
	var settings := _network_settings()
	var universe := _inputs.universe as OptionButton
	settings.name = (_inputs.name as LineEdit).text
	settings.mj_name = (_inputs.mj_name as LineEdit).text
	settings.universe = String(universe.get_item_metadata(universe.selected))
	for key in ["name", "mj_name", "universe"]:
		App.set_setting("host", key, settings[key])
	App.save_settings()
	_start(settings, {})


func _on_load_pressed(id: String) -> void:
	var data := CampaignStore.load_campaign(id)
	if data.is_empty():
		_show_error("Sauvegarde illisible.")
		return
	var settings := _network_settings()
	App.save_settings()
	_start(settings, data)


func _start(settings: Dictionary, data: Dictionary) -> void:
	var error := Net.host(settings, data)
	if error != "":
		_show_error(error)
		return
	if data.is_empty():
		Net.server.save()
	_build_dashboard()


func _show_error(text: String) -> void:
	_error_label.text = text
	_error_label.visible = true


# ---------------------------------------------------------------------------
# Tableau de bord
# ---------------------------------------------------------------------------

func _build_dashboard() -> void:
	UIKit.clear(_root)
	if _refresh_timer:
		_refresh_timer.queue_free()
	_player_widgets.clear()
	_net_labels.clear()
	_tool_buttons.clear()
	_insp_widgets.clear()
	_narrow = size.x < NARROW_WIDTH
	var server := Net.server
	for sig in [server.players_changed, server.message_added, server.message_updated, server.log_added,
			server.characters_changed, server.maps_changed, server.combat_changed, server.saved]:
		for c in sig.get_connections():
			if c.callable.get_object() == self:
				sig.disconnect(c.callable)
	if _edit_map == "" or not server.maps.has(_edit_map):
		_edit_map = server.active_map
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	_root.add_child(outer)
	outer.add_child(_build_top_bar())

	_tabs = TabbedPages.new(_narrow, 12)
	if _narrow:
		outer.add_child(_tabs)
		var players_page := VBoxContainer.new()
		_build_players_column(players_page)
		_tabs.add_page("players", "Joueurs", players_page)
	else:
		var body := HBoxContainer.new()
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 0)
		outer.add_child(body)
		var left_margin := MarginContainer.new()
		for side in ["left", "top", "bottom"]:
			left_margin.add_theme_constant_override("margin_" + side, 12)
		body.add_child(left_margin)
		var left := VBoxContainer.new()
		left.custom_minimum_size.x = 320
		left_margin.add_child(left)
		_build_players_column(left)
		body.add_child(_tabs)
	_tabs.add_page("table", "Table", _build_table())
	_tabs.add_page("chars", "Fiches" if _narrow else "Personnages", _build_characters())
	_tabs.add_page("story", "Récit", _build_story())
	_tabs.add_page("codex", "Codex", CodexView.new(server.universe, true))
	_tabs.add_page("net", "Réseau", _build_network())
	_tabs.show_page("table")

	server.players_changed.connect(_on_players_changed)
	server.message_added.connect(_on_message_added)
	server.message_updated.connect(_on_message_updated)
	server.log_added.connect(_add_log)
	server.characters_changed.connect(_refresh_characters)
	server.maps_changed.connect(_on_maps_changed)
	server.combat_changed.connect(_refresh_combat)
	server.saved.connect(_on_saved)

	for entry in server.connection_log:
		_add_log(entry)
	_feed.set_messages(server.messages)
	_on_players_changed()
	_refresh_map_select()
	_load_edit_map()
	_refresh_pending()

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_refresh_live)
	add_child(_refresh_timer)
	_refresh_live()


func _build_top_bar() -> Control:
	var server := Net.server
	var bar := PanelContainer.new()
	bar.theme_type_variation = "BarPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	var title := UIKit.label(server.session.name, "HeadingLabel")
	title.add_theme_font_size_override("font_size", 22 if _narrow else 24)
	title.clip_text = true
	titles.add_child(title)
	_count_label = UIKit.label("", "MutedLabel")
	_count_label.clip_text = true
	titles.add_child(_count_label)
	if not _narrow:
		row.add_child(UIKit.chip(String(server.universe.get("name", "")), Palette.VIOLET.lightened(0.3)))
	_save_label = UIKit.label("", "MutedLabel")
	_save_label.visible = not _narrow
	row.add_child(_save_label)
	row.add_child(UIKit.button("Sauver", "", func(): Net.server.save()))
	row.add_child(UIKit.button("Terminer" if _narrow else "Terminer la session", "DangerButton", _confirm_end))
	return bar


# --- Joueurs et connexion ---

func _build_players_column(parent: Node) -> void:
	var server := Net.server
	var card := UIKit.card(parent, "Pour rejoindre", "HighlightPanel")
	var ips := NetUtils.get_lan_ipv4_addresses()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	card.add_child(grid)
	grid.add_child(UIKit.label("Adresse IP", "MutedLabel"))
	var ip_label := UIKit.label(ips[0] if not ips.is_empty() else "Pas de Wi-Fi", "CodeLabel")
	ip_label.add_theme_font_size_override("font_size", 26)
	grid.add_child(ip_label)
	grid.add_child(UIKit.label("Port", "MutedLabel"))
	var port := UIKit.label(str(server.session.port), "CodeLabel")
	port.add_theme_font_size_override("font_size", 22)
	grid.add_child(port)
	grid.add_child(UIKit.label("Code", "MutedLabel"))
	var code := UIKit.label(server.session.code, "CodeLabel")
	code.add_theme_font_size_override("font_size", 30)
	code.add_theme_color_override("font_color", Palette.GOLD)
	grid.add_child(code)
	if ips.size() > 1:
		card.add_child(UIKit.label("Autres adresses : " + ", ".join(ips.slice(1)), "MutedLabel", true))
	var players_card := UIKit.card(parent, "Joueurs")
	players_card.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_players_list = UIKit.vscroll(players_card)


func _on_players_changed() -> void:
	_refresh_players()
	_refresh_composer_targets()
	_refresh_characters()


func _refresh_players() -> void:
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
		_players_list.add_child(UIKit.label("Aucun joueur pour l'instant. Donnez-leur l'adresse IP, le port et le code.", "MutedLabel", true))
	for p in list:
		_players_list.add_child(_player_row(p))
	if _narrow and server.count_status(Protocol.STATUS_PENDING) > 0:
		_tabs.set_badge("players", true)
	_refresh_live()


func _player_row(p: Dictionary) -> Control:
	var body := UIKit.card(null, "", "InsetPanel")
	var panel := body.get_parent()
	body.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	body.add_child(head)
	var sheet: Dictionary = Net.server.characters.get(p.id, {})
	var title := String(p.name)
	if not sheet.is_empty():
		title += "  —  " + String(sheet.name)
	var name_label := UIKit.label(title, "StrongLabel")
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
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	body.add_child(actions)
	var pid: String = p.id
	var pname: String = p.name
	match p.status:
		Protocol.STATUS_PENDING:
			actions.add_child(_small_button("Accepter", "PrimaryButton", func(): Net.server.accept_player(pid)))
			actions.add_child(_small_button("Refuser", "DangerButton", func(): Net.server.refuse_player(pid)))
		Protocol.STATUS_ACCEPTED:
			actions.add_child(_small_button("Écrire", "", func():
				_tabs.show_page("story")
				_composer.select_target(pid)
				_composer.focus_text()))
			if not sheet.is_empty():
				actions.add_child(_small_button("Fiche", "", func():
					_tabs.show_page("chars")
					_select_character(pid)))
			if p.online:
				actions.add_child(_small_button("Déconnecter", "", func(): Net.server.kick_player(pid)))
			actions.add_child(_small_button("Retirer", "DangerButton", func(): _confirm("Retirer %s de la partie ? Sa fiche devient un PNJ." % pname, func(): Net.server.remove_player(pid))))
		Protocol.STATUS_REFUSED:
			actions.add_child(_small_button("Oublier", "", func(): Net.server.remove_player(pid)))
	return panel


func _small_button(text: String, variation: String, cb: Callable) -> Button:
	var b := UIKit.button(text, variation, cb)
	b.custom_minimum_size.y = 38
	b.add_theme_font_size_override("font_size", 16)
	return b


func _refresh_live() -> void:
	var server := Net.server
	if server == null or _count_label == null:
		return
	var online := server.count_online()
	var pending := server.count_status(Protocol.STATUS_PENDING)
	_count_label.text = "%d / %d joueurs connectés%s  ·  code %s" % [online, server.session.max_players, ("  ·  %d en attente" % pending) if pending > 0 else "", server.session.code]
	if _net_labels.has("state"):
		_net_labels.state.text = Net.state_label()
		_net_labels.online.text = str(online)
		_net_labels.pending.text = str(pending)
		_net_labels.port.text = str(server.session.port)
		_net_labels.started.text = Protocol.format_time(server.session.created)
		_net_labels.ip.text = ", ".join(NetUtils.get_lan_ipv4_addresses())
	for pid in _player_widgets:
		var p: Dictionary = server.players.get(pid, {})
		if p.is_empty():
			continue
		var parts: PackedStringArray = [p.ip if p.ip != "" else "—"]
		if p.online:
			parts.append("ping " + UIKit.ping_text(Net.get_peer_rtt(p.peer_id)))
		else:
			parts.append("vu à " + Protocol.format_time(p.last_seen))
		if p.disconnects > 0:
			parts.append("%d coupure%s" % [p.disconnects, "s" if p.disconnects > 1 else ""])
		(_player_widgets[pid].info as Label).text = "  ·  ".join(parts)


func _on_saved(error: String) -> void:
	if error == "":
		_save_label.text = "Sauvegardé à " + Protocol.format_time(Protocol.now())
		_save_label.remove_theme_color_override("font_color")
	else:
		_save_label.text = error
		_save_label.add_theme_color_override("font_color", Palette.DANGER)
		_save_label.visible = true


# ---------------------------------------------------------------------------
# Table : carte, outils, sélection, combat
# ---------------------------------------------------------------------------

func _build_table() -> Control:
	var page: BoxContainer = VBoxContainer.new() if _narrow else HBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	_map_view = MapView.new()
	_map_view.is_mj = true
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_stretch_ratio = 2.2 if _narrow else 1.4
	_map_view.custom_minimum_size = Vector2(200, 260)
	_map_view.move_requested.connect(func(id, x, y): Net.server.mj_update_token(_edit_map, id, {"x": x, "y": y}))
	_map_view.token_selected.connect(func(_id): _refresh_inspector())
	_map_view.paint_requested.connect(func(x, y): Net.server.mj_paint(_edit_map, x, y, _paint_code, _brush))
	_map_view.cell_tapped.connect(_on_cell_tapped)
	page.add_child(_map_view)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = 0 if _narrow else 330
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 12)
	scroll.add_child(side)

	# --- Cartes ---
	var mc := UIKit.card(side, "Cartes")
	_map_select = OptionButton.new()
	_map_select.custom_minimum_size.y = UIKit.TOUCH_HEIGHT
	_map_select.item_selected.connect(func(i):
		_edit_map = String(_map_select.get_item_metadata(i))
		_load_edit_map())
	mc.add_child(_map_select)
	_map_status = UIKit.label("", "MutedLabel", true)
	mc.add_child(_map_status)
	mc.add_child(UIKit.button("Montrer cette carte aux joueurs", "PrimaryButton", func():
		Net.server.mj_set_active_map(_edit_map)
		_refresh_combat()))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	mc.add_child(row)
	row.add_child(_small_button("Nouvelle", "", _dialog_new_map))
	row.add_child(_small_button("Propriétés", "", _dialog_map_props))
	row.add_child(_small_button("Dupliquer", "", func():
		var m := Net.server.mj_duplicate_map(_edit_map)
		if not m.is_empty():
			_edit_map = m.id
			_refresh_map_select()
			_load_edit_map()))
	row.add_child(_small_button("Supprimer", "DangerButton", func():
		_confirm("Supprimer cette carte et ses pions ?", func():
			Net.server.mj_delete_map(_edit_map)
			_edit_map = Net.server.active_map
			_refresh_map_select()
			_load_edit_map())))
	_move_check = CheckBox.new()
	_move_check.text = "Les joueurs déplacent leur pion"
	_move_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_move_check.toggled.connect(func(on): Net.server.mj_update_map(_edit_map, {"players_can_move": on}))
	mc.add_child(_move_check)

	# --- Outils ---
	var tc := UIKit.card(side, "Outils")
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	tc.add_child(tools)
	var group := ButtonGroup.new()
	for spec in [["move", "Déplacer"], ["paint", "Peindre"], ["token", "Pion"], ["label", "Étiquette"], ["erase", "Gomme"], ["spawn", "Départ"]]:
		var b := _small_button(spec[1], "", _set_tool.bind(spec[0]))
		b.toggle_mode = true
		b.button_group = group
		_tool_buttons[spec[0]] = b
		tools.add_child(b)
	_tool_options = VBoxContainer.new()
	tc.add_child(_tool_options)

	_inspector = UIKit.card(side, "")
	_combat_box = UIKit.card(side, "")
	_set_tool(_tool)
	return page


func _refresh_map_select() -> void:
	var server := Net.server
	_map_select.clear()
	for id in server.map_order:
		var m: Dictionary = server.maps[id]
		_map_select.add_item(("› " if id == server.active_map else "") + String(m.name))
		_map_select.set_item_metadata(_map_select.item_count - 1, id)
		if id == _edit_map:
			_map_select.select(_map_select.item_count - 1)


func _load_edit_map() -> void:
	var map: Dictionary = Net.server.maps.get(_edit_map, {})
	_map_view.selected = ""
	_map_view.set_map(map)
	_refresh_map_status()
	_refresh_inspector()
	_refresh_combat()


func _refresh_map_status() -> void:
	var map: Dictionary = Net.server.maps.get(_edit_map, {})
	if map.is_empty():
		return
	var shown := _edit_map == Net.server.active_map
	_map_status.text = ("Affichée aux joueurs." if shown else "Non affichée : vous seul la voyez.") + "  %d × %d cases, %d pions." % [map.w, map.h, map.tokens.size()]
	_map_status.add_theme_color_override("font_color", Palette.OK if shown else Palette.MUTED)
	_move_check.set_pressed_no_signal(map.get("players_can_move", true))


func _on_maps_changed() -> void:
	if not Net.server.maps.has(_edit_map):
		_edit_map = Net.server.active_map
	var map: Dictionary = Net.server.maps.get(_edit_map, {})
	if not is_same(map, _map_view.map):
		_map_view.set_map(map)
	else:
		_map_view.queue_redraw()
	_refresh_map_select()
	_refresh_map_status()
	_sync_inspector()


func _set_tool(tool: String) -> void:
	_tool = tool
	_map_view.tool = tool
	if _tool_buttons.has(tool):
		_tool_buttons[tool].set_pressed_no_signal(true)
	UIKit.clear(_tool_options)
	match tool:
		"move":
			_tool_options.add_child(UIKit.label("Touchez un pion pour le sélectionner, puis une case pour l'y déplacer (ou glissez-le). Molette ou deux doigts : zoom.", "MutedLabel", true))
		"paint":
			var palette := GridContainer.new()
			palette.columns = 4
			palette.add_theme_constant_override("h_separation", 4)
			palette.add_theme_constant_override("v_separation", 4)
			_tool_options.add_child(palette)
			var pgroup := ButtonGroup.new()
			for code in MapData.TERRAINS:
				palette.add_child(_terrain_button(code, pgroup))
			var brush := UIKit.spin(_brush, 0, 4)
			brush.value_changed.connect(func(v): _brush = int(v))
			UIKit.field(_tool_options, "Taille du pinceau (0 = une case)", brush)
		"token":
			var kind := OptionButton.new()
			for k in MapData.KINDS:
				if k == "pc":
					continue
				kind.add_item(MapData.KIND_NAMES[k])
				kind.set_item_metadata(kind.item_count - 1, k)
				if k == _token_tpl.kind:
					kind.select(kind.item_count - 1)
			kind.item_selected.connect(func(i): _token_tpl.kind = kind.get_item_metadata(i))
			UIKit.field(_tool_options, "Type", kind)
			var n := UIKit.line_edit(_token_tpl.name, "Nom du pion")
			n.text_changed.connect(func(t): _token_tpl.name = t)
			UIKit.field(_tool_options, "Nom", n)
			_tool_options.add_child(_color_row(_token_tpl.color, func(c): _token_tpl.color = c))
			var hp := UIKit.spin(_token_tpl.hp, 0, 9999)
			hp.value_changed.connect(func(v): _token_tpl.hp = int(v))
			UIKit.field(_tool_options, "Points de vie (0 = sans jauge)", hp)
			var hidden := CheckBox.new()
			hidden.text = "Caché aux joueurs (à révéler plus tard)"
			hidden.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hidden.button_pressed = _token_tpl.hidden
			hidden.toggled.connect(func(on): _token_tpl.hidden = on)
			_tool_options.add_child(hidden)
			_tool_options.add_child(UIKit.label("Touchez une case pour poser le pion.", "MutedLabel", true))
		"label":
			var t := UIKit.line_edit(_label_tpl.text, "Ex. : Porte secrète, Auberge…")
			t.text_changed.connect(func(v): _label_tpl.text = v)
			UIKit.field(_tool_options, "Texte", t)
			var hidden := CheckBox.new()
			hidden.text = "Secret (visible seulement par le MJ)"
			hidden.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hidden.button_pressed = _label_tpl.hidden
			hidden.toggled.connect(func(on): _label_tpl.hidden = on)
			_tool_options.add_child(hidden)
			_tool_options.add_child(UIKit.label("Touchez une case pour poser l'étiquette. Toucher une étiquette existante la rend secrète ou visible.", "MutedLabel", true))
		"erase":
			_tool_options.add_child(UIKit.label("Touchez un pion (hors pions de joueurs) ou une étiquette pour la supprimer.", "MutedLabel", true))
		"spawn":
			_tool_options.add_child(UIKit.label("Touchez la case où apparaissent les pions des joueurs.", "MutedLabel", true))


func _terrain_button(code: String, group: ButtonGroup) -> Button:
	var info: Array = MapData.TERRAINS[code]
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.tooltip_text = info[0]
	b.text = info[0]
	b.clip_text = true
	b.custom_minimum_size = Vector2(66, 40)
	b.add_theme_font_size_override("font_size", 12)
	var col := Color(info[1])
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = col.darkened(0.3)
	var sbp := sb.duplicate()
	sbp.border_color = Palette.GOLD
	sbp.set_border_width_all(3)
	for s in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover_pressed", sbp)
	var fc := Color("15141a") if col.get_luminance() > 0.5 else Color("f0ebe0")
	for c in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fc)
	b.button_pressed = code == _paint_code
	b.pressed.connect(func(): _paint_code = code)
	return b


func _color_row(current: String, on_pick: Callable) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	var group := ButtonGroup.new()
	for c in CharacterData.PAWN_COLORS + ["#7b5a3a", "#2a2733"]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(34, 34)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(c)
		sb.set_corner_radius_all(17)
		var sbp := sb.duplicate()
		sbp.set_border_width_all(3)
		sbp.border_color = Palette.TEXT
		for s in ["normal", "hover", "focus"]:
			b.add_theme_stylebox_override(s, sb)
		b.add_theme_stylebox_override("pressed", sbp)
		b.add_theme_stylebox_override("hover_pressed", sbp)
		b.button_pressed = c == current
		b.pressed.connect(func(): on_pick.call(c))
		flow.add_child(b)
	return flow


func _on_cell_tapped(x: int, y: int) -> void:
	var server := Net.server
	var map: Dictionary = server.maps.get(_edit_map, {})
	if map.is_empty():
		return
	match _tool:
		"token":
			var p := Vector2i(x, y)
			if not MapData.token_at(map, x, y).is_empty():
				p = MapData.free_cell_near(map, x, y)
			var hp := int(_token_tpl.hp)
			var t := server.mj_add_token(_edit_map, {
				"kind": _token_tpl.kind, "name": _token_tpl.name, "x": p.x, "y": p.y,
				"color": _token_tpl.color, "hp": hp, "hp_max": hp, "hidden": _token_tpl.hidden,
			})
			if not t.is_empty():
				_map_view.selected = t.id
				_refresh_inspector()
		"label":
			var existing: Array = map.labels.filter(func(l): return int(l.x) == x and int(l.y) == y)
			if not existing.is_empty():
				server.mj_toggle_label_hidden_at(_edit_map, x, y)
			elif String(_label_tpl.text).strip_edges() != "":
				server.mj_add_label(_edit_map, x, y, _label_tpl.text, _label_tpl.hidden)
		"erase":
			var t := MapData.token_at(map, x, y)
			if not t.is_empty() and t.kind != "pc":
				server.mj_remove_token(_edit_map, t.id)
			elif not server.mj_remove_label_at(_edit_map, x, y) and not t.is_empty():
				_map_status.text = "Les pions des joueurs ne se suppriment pas : retirez le joueur si besoin."
				_map_status.add_theme_color_override("font_color", Palette.WARN)
		"spawn":
			server.mj_update_map(_edit_map, {"spawn_x": x, "spawn_y": y})


# --- Inspecteur du pion sélectionné ---

func _refresh_inspector() -> void:
	UIKit.clear(_inspector)
	_insp_widgets.clear()
	_inspector.add_child(UIKit.label("Sélection", "HeadingLabel"))
	var map: Dictionary = Net.server.maps.get(_edit_map, {})
	var t := MapData.token(map, _map_view.selected)
	if t.is_empty():
		_inspector.add_child(UIKit.label("Aucun pion sélectionné. Outil « Déplacer », puis touchez un pion.", "MutedLabel", true))
		return
	var tid: String = t.id
	var upd := func(data: Dictionary): Net.server.mj_update_token(_edit_map, tid, data)
	var name_edit := UIKit.line_edit(t.name)
	name_edit.text_submitted.connect(func(v): upd.call({"name": v}))
	name_edit.focus_exited.connect(func(): upd.call({"name": name_edit.text}))
	UIKit.field(_inspector, MapData.KIND_NAMES.get(t.kind, "Pion"), name_edit)
	var hp_row := HBoxContainer.new()
	_inspector.add_child(hp_row)
	var hp := UIKit.spin(int(t.hp), -9999, 99999)
	hp.prefix = "PV"
	hp.value_changed.connect(func(v): upd.call({"hp": int(v)}))
	hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(hp)
	var hp_max := UIKit.spin(int(t.hp_max), 0, 99999)
	hp_max.prefix = "max"
	hp_max.value_changed.connect(func(v): upd.call({"hp_max": int(v)}))
	hp_max.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(hp_max)
	_insp_widgets = {"hp": hp, "hp_max": hp_max, "id": tid}
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 4)
	_inspector.add_child(quick)
	for d in [-5, -1, 1, 5]:
		var b := _small_button("%+d" % d, "DangerButton" if d < 0 else "", func():
			var cur := MapData.token(Net.server.maps.get(_edit_map, {}), tid)
			if not cur.is_empty():
				upd.call({"hp": int(cur.hp) + d}))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick.add_child(b)
	var hidden := CheckBox.new()
	hidden.text = "Caché aux joueurs"
	hidden.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hidden.button_pressed = t.hidden
	hidden.toggled.connect(func(on): upd.call({"hidden": on}))
	_inspector.add_child(hidden)
	if t.kind != "pc":
		_inspector.add_child(_color_row(t.color, func(c): upd.call({"color": c})))
	var note := UIKit.line_edit(String(t.get("note", "")), "Note secrète du MJ")
	note.text_submitted.connect(func(v): upd.call({"note": v}))
	note.focus_exited.connect(func(): upd.call({"note": note.text}))
	_inspector.add_child(note)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	_inspector.add_child(actions)
	var cid: String = t.char_id if t.char_id != "" else t.owner
	if Net.server.characters.has(cid):
		actions.add_child(_small_button("Fiche", "", func():
			_tabs.show_page("chars")
			_select_character(cid)))
	if Net.server.combat.active and _edit_map == Net.server.active_map:
		actions.add_child(_small_button("Retirer du combat" if Net.server.combat.order.has(tid) else "Ajouter au combat", "", func():
			Net.server.mj_combat_toggle(tid)
			_refresh_inspector()))
	if t.kind != "pc":
		actions.add_child(_small_button("Supprimer", "DangerButton", func():
			Net.server.mj_remove_token(_edit_map, tid)
			_map_view.selected = ""
			_refresh_inspector()))


## Met à jour les PV affichés sans reconstruire (pour ne pas gêner la saisie).
func _sync_inspector() -> void:
	if _insp_widgets.is_empty():
		if _map_view.selected != "":
			_refresh_inspector()
		return
	var t := MapData.token(Net.server.maps.get(_edit_map, {}), String(_insp_widgets.id))
	if t.is_empty() or t.id != _map_view.selected:
		_refresh_inspector()
		return
	(_insp_widgets.hp as SpinBox).set_value_no_signal(int(t.hp))
	(_insp_widgets.hp_max as SpinBox).set_value_no_signal(int(t.hp_max))


# --- Combat ---

func _refresh_combat() -> void:
	if _combat_box == null:
		return
	var server := Net.server
	UIKit.clear(_combat_box)
	_combat_box.add_child(UIKit.label("Combat", "HeadingLabel"))
	var on_active := _edit_map == server.active_map
	var combat: Dictionary = server.combat
	_map_view.current_turn = server._current_combat_token() if (combat.active and on_active) else ""
	_map_view.queue_redraw()
	if not on_active:
		_combat_box.add_child(UIKit.label("Le combat se joue sur la carte affichée aux joueurs.", "MutedLabel", true))
		return
	if not combat.active:
		_combat_box.add_child(UIKit.label("Combat au tour par tour avec les pions visibles de la carte. L'initiative (d20) est tirée automatiquement ; vous pouvez réordonner.", "MutedLabel", true))
		_combat_box.add_child(UIKit.button("Démarrer le combat", "PrimaryButton", func(): server.mj_combat_start(false)))
		_combat_box.add_child(_small_button("Démarrer en incluant les pions cachés", "", func(): server.mj_combat_start(true)))
		return
	_combat_box.add_child(UIKit.chip("Tour %d" % combat.round, Palette.DANGER))
	var map: Dictionary = server.maps[server.active_map]
	var current := server._current_combat_token()
	var initiative: Dictionary = combat.get("initiative", {})
	for id in combat.order:
		var t := MapData.token(map, id)
		if t.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var text := String(t.name)
		if initiative.has(id):
			text += "  (%d)" % initiative[id]
		var n := UIKit.label(("› " if id == current else "") + text, "StrongLabel" if id == current else "")
		if id == current:
			n.add_theme_color_override("font_color", Palette.GOLD)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		row.add_child(n)
		var tid: String = id
		var up := _small_button("▲", "", func(): server.mj_combat_move(tid, -1))
		up.custom_minimum_size.x = 38
		row.add_child(up)
		var down := _small_button("▼", "", func(): server.mj_combat_move(tid, 1))
		down.custom_minimum_size.x = 38
		row.add_child(down)
		var x := _small_button("×", "DangerButton", func(): server.mj_combat_toggle(tid))
		x.custom_minimum_size.x = 38
		row.add_child(x)
		_combat_box.add_child(row)
	var actions := HBoxContainer.new()
	_combat_box.add_child(actions)
	var next := UIKit.button("Tour suivant", "PrimaryButton", func(): server.mj_combat_next())
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(next)
	actions.add_child(UIKit.button("Terminer", "DangerButton", func(): server.mj_combat_end()))


# --- Dialogues de carte ---

func _dialog_new_map() -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 340
	var n := UIKit.line_edit("", "Nom de la carte")
	UIKit.field(box, "Nom", n)
	var tpl := OptionButton.new()
	tpl.add_item("Carte vierge (dimensions ci-dessous)")
	tpl.set_item_metadata(0, "")
	for t in MapData.templates():
		var u := String(t.get("universe", "*"))
		tpl.add_item(String(t.name) + ("" if u == "*" else "  (%s)" % Universe.get_by_id(u).get("name", u)))
		tpl.set_item_metadata(tpl.item_count - 1, t.id)
	UIKit.field(box, "Modèle", tpl)
	var row := HBoxContainer.new()
	box.add_child(row)
	var w := UIKit.field(row, "Largeur", UIKit.spin(24, 4, MapData.MAX_SIZE)) as SpinBox
	var h := UIKit.field(row, "Hauteur", UIKit.spin(16, 4, MapData.MAX_SIZE)) as SpinBox
	_dialog("Nouvelle carte", box, func():
		var m := Net.server.mj_create_map(n.text, int(w.value), int(h.value), String(tpl.get_item_metadata(tpl.selected)))
		if not m.is_empty():
			_edit_map = m.id
			_refresh_map_select()
			_load_edit_map())


func _dialog_map_props() -> void:
	var map: Dictionary = Net.server.maps.get(_edit_map, {})
	if map.is_empty():
		return
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 340
	var n := UIKit.line_edit(map.name)
	UIKit.field(box, "Nom", n)
	var d := UIKit.line_edit(String(map.get("description", "")), "Ambiance, description…")
	UIKit.field(box, "Description", d)
	var row := HBoxContainer.new()
	box.add_child(row)
	var w := UIKit.field(row, "Largeur", UIKit.spin(int(map.w), 4, MapData.MAX_SIZE)) as SpinBox
	var h := UIKit.field(row, "Hauteur", UIKit.spin(int(map.h), 4, MapData.MAX_SIZE)) as SpinBox
	_dialog("Propriétés de la carte", box, func():
		Net.server.mj_update_map(_edit_map, {"name": n.text, "description": d.text, "w": int(w.value), "h": int(h.value)})
		_load_edit_map())


# ---------------------------------------------------------------------------
# Personnages
# ---------------------------------------------------------------------------

func _build_characters() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 10)
	top.add_theme_constant_override("v_separation", 6)
	page.add_child(top)
	top.add_child(UIKit.button("+  Nouveau PNJ", "PrimaryButton", func():
		var c := Net.server.mj_create_npc()
		_char_selected = c.id
		_char_editing = true
		_refresh_characters()
		_open_character_editor()))
	var lock := CheckBox.new()
	lock.text = "Les joueurs peuvent modifier leur fiche"
	lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lock.button_pressed = Net.server.session.players_edit_sheets
	lock.toggled.connect(func(on): Net.server.set_players_edit_sheets(on))
	top.add_child(lock)
	_char_list = HFlowContainer.new()
	_char_list.add_theme_constant_override("h_separation", 6)
	_char_list.add_theme_constant_override("v_separation", 6)
	page.add_child(_char_list)
	page.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var column := CenteredColumn.new()
	column.max_width = 760
	column.side_margin = 0
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_char_detail = VBoxContainer.new()
	_char_detail.add_theme_constant_override("separation", 10)
	column.add_child(_char_detail)
	return page


func _select_character(id: String) -> void:
	_char_selected = id
	_char_editing = false
	_refresh_characters()


func _refresh_characters() -> void:
	if _char_list == null:
		return
	var server := Net.server
	UIKit.clear(_char_list)
	var group := ButtonGroup.new()
	var ids: Array = server.characters.keys()
	ids.sort_custom(func(a, b):
		var pa: bool = server.players.has(a)
		var pb: bool = server.players.has(b)
		if pa != pb:
			return pa
		return String(server.characters[a].name).naturalnocasecmp_to(server.characters[b].name) < 0)
	if ids.is_empty():
		_char_list.add_child(UIKit.label("Les fiches des joueurs apparaîtront ici dès qu'ils les auront créées. Créez vos PNJ, monstres importants et alliés avec « Nouveau PNJ ».", "MutedLabel", true))
	for id in ids:
		var c: Dictionary = server.characters[id]
		var who := String(server.players[id].name) if server.players.has(id) else "PNJ"
		var b := _small_button("%s  ·  %s" % [c.name, who], "", _select_character.bind(id))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == _char_selected
		_char_list.add_child(b)
	if _char_editing:
		return
	UIKit.clear(_char_detail)
	if not server.characters.has(_char_selected) and not ids.is_empty():
		_char_selected = ids[0]
		for b in _char_list.get_children():
			if b is Button:
				b.set_pressed_no_signal(true)
				break
	var sheet: Dictionary = server.characters.get(_char_selected, {})
	if sheet.is_empty():
		_char_detail.add_child(UIKit.label("Choisissez une fiche ci-dessus.", "MutedLabel", true))
		return
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	_char_detail.add_child(actions)
	actions.add_child(UIKit.button("Modifier", "PrimaryButton", func():
		_char_editing = true
		_open_character_editor()))
	var cid := _char_selected
	if not server.players.has(cid):
		actions.add_child(UIKit.button("Placer sur la carte affichée", "", func():
			var t := server.mj_place_character(cid)
			if not t.is_empty():
				_edit_map = server.active_map
				_refresh_map_select()
				_load_edit_map()
				_map_view.selected = t.id
				_refresh_inspector()
				_tabs.show_page("table")))
		actions.add_child(UIKit.button("Supprimer", "DangerButton", func():
			_confirm("Supprimer la fiche de %s ?" % sheet.name, func():
				server.mj_delete_character(cid)
				_char_selected = ""
				_refresh_characters())))
	_char_detail.add_child(CharacterSheet.new(sheet, server.universe))


func _open_character_editor() -> void:
	var server := Net.server
	var sheet: Dictionary = server.characters.get(_char_selected, {})
	if sheet.is_empty():
		_char_editing = false
		return
	UIKit.clear(_char_detail)
	var editor := CharacterEditor.new(sheet, server.universe, true)
	editor.saved.connect(func(data):
		server.mj_save_character(data)
		_char_editing = false
		_refresh_characters())
	editor.cancelled.connect(func():
		_char_editing = false
		_refresh_characters())
	_char_detail.add_child(editor)


# ---------------------------------------------------------------------------
# Récit : fil, actions en attente, saisie
# ---------------------------------------------------------------------------

func _build_story() -> Control:
	var page: BoxContainer = VBoxContainer.new() if _narrow else HBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	_feed = FeedView.new(Protocol.MJ_ID, true)
	_feed.resolve_requested.connect(_on_resolve)
	main.add_child(_feed)
	_composer = Composer.new([], [], false)
	_composer.send_message.connect(func(to, text): Net.server.mj_send_message(to, text))
	_composer.send_roll.connect(func(to, expr, label):
		var err := Net.server.mj_roll(expr, to, label)
		if err != "":
			_feed.add_notice(err, Palette.DANGER))
	main.add_child(_composer)
	var pending := UIKit.card(null, "")
	var pending_panel := pending.get_parent() as Control
	_pending_title = UIKit.label("Actions en attente", "HeadingLabel")
	pending.add_child(_pending_title)
	_pending_box = UIKit.vscroll(pending)
	_pending_box.add_theme_constant_override("separation", 8)
	if _narrow:
		pending_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		page.add_child(pending_panel)
		page.add_child(main)
	else:
		pending_panel.custom_minimum_size.x = 340
		page.add_child(main)
		page.add_child(pending_panel)
	return page


func _refresh_composer_targets() -> void:
	if _composer == null:
		return
	var text_targets := [["Tout le groupe", Protocol.TO_ALL]]
	var dice_targets := [["Jet public", Protocol.TO_ALL], ["Jet secret (MJ seul)", Protocol.TO_MJ]]
	for p in Net.server.players.values():
		if p.status == Protocol.STATUS_ACCEPTED:
			text_targets.append(["Privé : " + p.name, p.id])
			dice_targets.append(["Jet montré à " + p.name, p.id])
	_composer.set_targets(text_targets, dice_targets)


func _on_message_added(m: Dictionary) -> void:
	_feed.add_message(m)
	if m.get("from", "") != Protocol.MJ_ID:
		_tabs.set_badge("story", true)
	if m.get("kind", "") == Protocol.KIND_ACTION:
		_refresh_pending()


func _on_message_updated(m: Dictionary) -> void:
	_feed.update_message(m)
	_refresh_pending()


func _on_resolve(message_id: String, status: String, result: String, roll_expr: String) -> void:
	var err := Net.server.mj_resolve_action(message_id, status, result, roll_expr)
	if err != "":
		_feed.add_notice(err, Palette.DANGER)


func _refresh_pending() -> void:
	if _pending_box == null:
		return
	UIKit.clear(_pending_box)
	var pending := Net.server.pending_actions()
	_pending_title.text = "Actions en attente (%d)" % pending.size()
	if _narrow:
		(_pending_box.get_parent() as Control).custom_minimum_size.y = 0 if pending.is_empty() else 220
	if pending.is_empty():
		_pending_box.add_child(UIKit.label("Aucune. Les joueurs déclarent leurs actions depuis l'onglet Aventure (mode « Action »).", "MutedLabel", true))
		return
	for m in pending:
		var card := UIKit.card(_pending_box, "", "InsetPanel")
		card.add_child(UIKit.label("%s  ·  %s%s" % [m.from_name, Protocol.format_time(m.ts), "  · privé" if m.to != Protocol.TO_ALL else ""], "MutedLabel", true))
		card.add_child(UIKit.label(String(m.text), "", true))
		card.add_child(_feed.resolve_form(String(m.id)))


# ---------------------------------------------------------------------------
# Réseau
# ---------------------------------------------------------------------------

func _build_network() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var net_card := UIKit.card(page, "Réseau")
	for spec in [["state", "État"], ["ip", "Adresses IP"], ["port", "Port UDP"], ["online", "Connectés"], ["pending", "En attente"], ["started", "Démarré à"]]:
		var row := HBoxContainer.new()
		net_card.add_child(row)
		var caption := UIKit.label(spec[1], "MutedLabel")
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		_net_labels[spec[0]] = UIKit.label("")
		row.add_child(_net_labels[spec[0]])
	var log_card := UIKit.card(page, "Journal des connexions")
	log_card.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_list = UIKit.vscroll(log_card)
	_log_list.add_theme_constant_override("separation", 4)
	UIKit.follow_bottom(_log_list)
	return page


func _add_log(entry: Dictionary) -> void:
	if _log_list == null:
		return
	var color := {"ok": Palette.OK, "warn": Palette.WARN, "ask": Palette.GOLD}.get(entry.kind, Palette.MUTED) as Color
	var l := UIKit.label("%s  %s" % [Protocol.format_time(entry.ts), entry.text], "MutedLabel", true)
	l.add_theme_color_override("font_color", color)
	_log_list.add_child(l)
	if _log_list.get_child_count() > 300:
		_log_list.get_child(0).queue_free()


# ---------------------------------------------------------------------------
# Dialogues
# ---------------------------------------------------------------------------

func _confirm_end() -> void:
	_confirm("Terminer la session ? La campagne est sauvegardée et tous les joueurs sont déconnectés.", func():
		await Net.leave()
		App.goto(App.SCENE_MAIN_MENU))


func _confirm(text: String, on_ok: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Confirmation"
	dialog.dialog_text = text
	dialog.dialog_autowrap = true
	dialog.ok_button_text = "Confirmer"
	dialog.cancel_button_text = "Annuler"
	dialog.confirmed.connect(on_ok)
	dialog.visibility_changed.connect(func(): if not dialog.visible: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 0))


func _dialog(title: String, content: Control, on_ok: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.ok_button_text = "Valider"
	dialog.cancel_button_text = "Annuler"
	dialog.add_child(content)
	dialog.confirmed.connect(on_ok)
	dialog.visibility_changed.connect(func(): if not dialog.visible: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
