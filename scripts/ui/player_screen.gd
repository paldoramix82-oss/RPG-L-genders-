extends Control
## Écran du joueur (pensé pour le téléphone en portrait, utilisable sur PC).
## Onglets : Aventure (fil + saisie), Carte (pions), Fiche, Groupe, Codex.

var _client: SessionClient
var _session_label: Label
var _me_label: Label
var _conn_chip: Label
var _tabs: TabbedPages
var _waiting: Control
var _feed: FeedView
var _composer: Composer
var _outbox_label: Label
var _map_view: MapView
var _map_title: Label
var _map_info: Label
var _combat_strip: HFlowContainer
var _sheet_box: VBoxContainer
var _editing := false
var _group_list: VBoxContainer
var _ping_label: Label
var _codex_holder: VBoxContainer
var _keyboard_pad: Control


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

	# --- En-tête ---
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
	quit.custom_minimum_size.y = 34
	right.add_child(quit)

	# --- Attente de validation ---
	_waiting = CenterContainer.new()
	_waiting.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_waiting)
	var wait_col := CenteredColumn.new()
	wait_col.custom_minimum_size.x = 340
	_waiting.add_child(wait_col)
	var wait_card := UIKit.card(wait_col, "", "HighlightPanel")
	var wt := UIKit.label("En attente du maître du jeu", "HeadingLabel", true)
	wt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait_card.add_child(wt)
	var wl := UIKit.label("Votre demande a bien été reçue. Le MJ doit l'accepter.", "", true)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait_card.add_child(wl)

	# --- Onglets ---
	_tabs = TabbedPages.new(true, 8)
	outer.add_child(_tabs)
	_tabs.add_page("adventure", "Aventure", _build_adventure())
	_tabs.add_page("map", "Carte", _build_map())
	_tabs.add_page("sheet", "Fiche", _build_sheet_page())
	_tabs.add_page("group", "Groupe", _build_group())
	_codex_holder = VBoxContainer.new()
	_tabs.add_page("codex", "Codex", _codex_holder)
	_tabs.page_changed.connect(func(key):
		if key == "map":
			_map_view.recenter.call_deferred())

	_keyboard_pad = Control.new()
	outer.add_child(_keyboard_pad)

	_client.status_changed.connect(func(_s): _refresh_all())
	_client.welcomed.connect(_on_welcomed)
	_client.players_changed.connect(_refresh_group)
	_client.message_received.connect(_on_message)
	_client.message_updated.connect(func(m): _feed.update_message(m))
	_client.characters_changed.connect(_on_characters)
	_client.map_changed.connect(_refresh_map)
	_client.combat_changed.connect(_refresh_combat)
	_client.settings_changed.connect(_refresh_sheet)
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
	# Hauteur du clavier en pixels physiques -> unités de l'interface.
	var kb_height := DisplayServer.virtual_keyboard_get_height()
	var ratio := get_viewport().get_visible_rect().size.y / maxf(1.0, float(DisplayServer.window_get_size().y))
	var pad := maxf(0.0, kb_height * ratio - 60.0)
	if absf(_keyboard_pad.custom_minimum_size.y - pad) > 1.0:
		_keyboard_pad.custom_minimum_size.y = pad


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------

func _build_adventure() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	_feed = FeedView.new("", false)
	page.add_child(_feed)
	_outbox_label = UIKit.label("", "MutedLabel", true)
	_outbox_label.add_theme_color_override("font_color", Palette.WARN)
	_outbox_label.visible = false
	page.add_child(_outbox_label)
	_composer = Composer.new(
		[["Au groupe", Protocol.TO_ALL], ["Au MJ (privé)", Protocol.TO_MJ]],
		[["Jet visible", Protocol.TO_ALL], ["Jet secret (MJ)", Protocol.TO_MJ]])
	_composer.send_message.connect(func(to, text):
		_client.send_chat(to, text)
		_refresh_outbox())
	_composer.send_action.connect(func(to, text):
		_client.declare_action(to, text)
		_refresh_outbox())
	_composer.send_roll.connect(func(to, expr, label):
		_client.roll(expr, to, label)
		_refresh_outbox())
	page.add_child(_composer)
	return page


func _build_map() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	_map_title = UIKit.label("", "HeadingLabel", true)
	page.add_child(_map_title)
	_combat_strip = HFlowContainer.new()
	_combat_strip.add_theme_constant_override("h_separation", 6)
	_combat_strip.add_theme_constant_override("v_separation", 4)
	page.add_child(_combat_strip)
	_map_view = MapView.new()
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.custom_minimum_size.y = 240
	_map_view.move_requested.connect(func(id, x, y): _client.move_pawn(id, x, y))
	_map_view.token_selected.connect(func(_id): _refresh_map_info())
	page.add_child(_map_view)
	_map_info = UIKit.label("", "MutedLabel", true)
	page.add_child(_map_info)
	return page


func _build_sheet_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := CenteredColumn.new()
	column.max_width = 640
	column.side_margin = 0
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_sheet_box = VBoxContainer.new()
	_sheet_box.add_theme_constant_override("separation", 12)
	column.add_child(_sheet_box)
	return scroll


func _build_group() -> Control:
	var page := VBoxContainer.new()
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
	_waiting.visible = not accepted
	_tabs.visible = accepted
	_session_label.text = String(_client.session.get("name", "Legenders RPG"))
	var sheet := _client.my_character()
	var me_name := String(_client.me.get("name", Net.join_params().get("name", "")))
	if not sheet.is_empty() and String(sheet.get("name", "")) != "":
		me_name = "%s  ·  %s" % [sheet.name, me_name]
	_me_label.text = me_name + ("" if accepted else "  ·  en attente")
	_refresh_connection()


func _on_welcomed() -> void:
	_map_view.my_id = String(_client.me.get("id", ""))
	_feed.viewer_id = _map_view.my_id
	_feed.set_messages(_client.messages)
	UIKit.clear(_codex_holder)
	_codex_holder.add_child(CodexView.new(_client.universe))
	_refresh_group()
	_refresh_map()
	_refresh_combat()
	_editing = false
	_refresh_sheet()
	_refresh_all()
	if _client.my_character().is_empty():
		_tabs.set_badge("sheet", true)


func _on_message(m: Dictionary) -> void:
	_feed.add_message(m)
	_tabs.set_badge("adventure", true)
	_refresh_outbox()


func _on_characters() -> void:
	_refresh_group()
	if not _editing:
		_refresh_sheet()
	_refresh_all()


func _refresh_map() -> void:
	var map := _client.map
	_map_view.set_map(map)
	_map_title.text = String(map.get("name", "Pas de carte"))
	if map.is_empty():
		_map_info.text = "Le MJ n'a pas encore affiché de carte."
		return
	# Sélectionne d'office son propre pion : il suffit ensuite de toucher une case.
	for t in map.get("tokens", []):
		if t.get("owner", "") == _map_view.my_id:
			if _map_view.focus_id != t.id:
				_map_view.focus_id = t.id
				_map_view.recenter.call_deferred()
			if _map_view.selected == "":
				_map_view.selected = t.id
	_tabs.set_badge("map", true)
	_refresh_map_info()


func _refresh_map_info() -> void:
	var map := _client.map
	var t := MapData.token(map, _map_view.selected)
	var mine: bool = not t.is_empty() and t.get("owner", "") == _map_view.my_id
	var lines: PackedStringArray = []
	if not t.is_empty():
		var info := "%s  ·  %s" % [t.name, MapData.KIND_NAMES.get(t.kind, "")]
		if int(t.get("hp_max", 0)) > 0:
			info += "  ·  PV %d/%d" % [int(t.hp), int(t.hp_max)]
		lines.append(info)
	if _client.my_character().is_empty():
		lines.append("Créez votre fiche (onglet Fiche) pour obtenir votre pion.")
	elif not map.get("players_can_move", true):
		lines.append("Le MJ déplace les pions sur cette carte.")
	elif mine:
		lines.append("Touchez une case pour y déplacer votre pion (ou faites-le glisser).")
	else:
		lines.append("Touchez votre pion pour le sélectionner. Deux doigts : zoom.")
	_map_info.text = "\n".join(lines)


func _refresh_combat() -> void:
	UIKit.clear(_combat_strip)
	var combat := _client.combat
	var active: bool = combat.get("active", false)
	_combat_strip.visible = active
	_map_view.current_turn = String(combat.get("current", "")) if active else ""
	if not active:
		_map_view.queue_redraw()
		return
	_combat_strip.add_child(UIKit.chip("Combat · tour %d" % int(combat.get("round", 1)), Palette.DANGER))
	for id in combat.get("order", []):
		var t := MapData.token(_client.map, id)
		if t.is_empty():
			continue
		var l := UIKit.label(String(t.name), "StrongLabel" if id == combat.get("current", "") else "MutedLabel")
		if id == combat.get("current", ""):
			l.add_theme_color_override("font_color", Palette.GOLD)
			l.text = "› " + l.text
		_combat_strip.add_child(l)
	var current := MapData.token(_client.map, String(combat.get("current", "")))
	if not current.is_empty() and current.get("owner", "") == _map_view.my_id:
		_combat_strip.add_child(UIKit.chip("C'est votre tour !", Palette.GOLD))
		_tabs.set_badge("map", true)
	_map_view.queue_redraw()


func _refresh_sheet() -> void:
	if _editing:
		return
	UIKit.clear(_sheet_box)
	var sheet := _client.my_character()
	if sheet.is_empty():
		var intro := UIKit.card(_sheet_box, "Votre personnage", "HighlightPanel")
		intro.add_child(UIKit.label("Créez votre personnage comme vous le souhaitez : nom, apparence, magie, pouvoirs, caractéristiques, objets, histoire… Rien n'est imposé.", "", true))
		intro.add_child(UIKit.button("Créer mon personnage", "PrimaryButton", _open_editor))
		return
	if _client.can_edit_sheet():
		_sheet_box.add_child(UIKit.button("Modifier ma fiche", "PrimaryButton", _open_editor))
	else:
		_sheet_box.add_child(UIKit.label("Le MJ a verrouillé les fiches : demandez-lui les modifications.", "MutedLabel", true))
	_sheet_box.add_child(CharacterSheet.new(sheet, _client.universe))


func _open_editor() -> void:
	_editing = true
	UIKit.clear(_sheet_box)
	var sheet := _client.my_character()
	if sheet.is_empty():
		sheet = CharacterData.create(_client.universe, String(_client.me.get("id", "")), String(_client.me.get("id", "")), String(_client.me.get("name", "")))
	var editor := CharacterEditor.new(sheet, _client.universe)
	editor.saved.connect(func(data):
		_client.save_character(data)
		_editing = false
		UIKit.clear(_sheet_box)
		_sheet_box.add_child(UIKit.label("Enregistrement…", "MutedLabel")))
	editor.cancelled.connect(func():
		_editing = false
		_refresh_sheet())
	_sheet_box.add_child(editor)


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
		var sheet := _client.character(p.id)
		var panel := PanelContainer.new()
		panel.theme_type_variation = "InsetPanel"
		var col := VBoxContainer.new()
		panel.add_child(col)
		var row := HBoxContainer.new()
		col.add_child(row)
		var title := String(p.name) + ("  (vous)" if p.id == _client.me.get("id", "") else "")
		if not sheet.is_empty():
			title = "%s  —  %s" % [sheet.get("name", ""), title]
		var b := Button.new()
		b.text = title
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 44
		row.add_child(b)
		row.add_child(UIKit.chip("En ligne" if p.online else "Hors ligne", Palette.OK if p.online else Palette.FAINT))
		if not sheet.is_empty():
			var detail := CharacterSheet.new(sheet, _client.universe)
			detail.visible = false
			col.add_child(detail)
			b.pressed.connect(func(): detail.visible = not detail.visible)
		_group_list.add_child(panel)


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
	_ping_label.text = "%s\nHôte : %s:%s  ·  ping %s" % [Net.state_label(), params.get("ip", "?"), params.get("port", "?"), UIKit.ping_text(Net.get_peer_rtt(1))]
	_refresh_outbox()


func _refresh_outbox() -> void:
	var n := _client.pending_count()
	_outbox_label.visible = n > 0
	_outbox_label.text = "%d envoi%s en cours…" % [n, "s" if n > 1 else ""]


func _on_command_failed(_req_id: String, error: String) -> void:
	_feed.add_notice("Erreur : " + error, Palette.DANGER)
	_editing = false
	_refresh_sheet()


func _on_session_ended(reason: String) -> void:
	App.flash = reason
	App.goto(App.SCENE_JOIN)


func _confirm_leave() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Quitter la partie"
	dialog.dialog_text = "Vous pourrez revenir : votre place et votre personnage sont conservés."
	dialog.ok_button_text = "Quitter"
	dialog.cancel_button_text = "Rester"
	dialog.confirmed.connect(func():
		Net.leave()
		App.goto(App.SCENE_JOIN))
	add_child(dialog)
	dialog.popup_centered()
