extends Control
## Écran du joueur (pensé pour le téléphone en portrait, utilisable sur PC).
##
## Parcours : validation éventuelle par le MJ -> création guidée du personnage ->
## « Prêt ! » en attendant que le MJ lance la partie -> la partie (onglets
## Carte, Aventure, Fiche, Groupe, Codex), avec la phase en cours, ses règles
## et, à votre tour, un panneau d'actions (déplacement, attaque, capacité, objet,
## fin du tour).

var _client: SessionClient
var _session_label: Label
var _me_label: Label
var _conn_chip: Label
var _tabs: TabbedPages
var _waiting: Control
var _creation: VBoxContainer
var _lobby: VBoxContainer
var _feed: FeedView
var _composer: Composer
var _outbox_label: Label
var _map_view: MapView
var _map_title: Label
var _phase_boxes: Array[VBoxContainer] = []
var _turn_panel: VBoxContainer
var _sheet_box: VBoxContainer
var _editing := false
var _group_list: VBoxContainer
var _ping_label: Label
var _codex_holder: VBoxContainer
var _keyboard_pad: Control
var _tray: DiceTray
## Jet en cours d'animation : {"kind": "free"} ou {"message_id": …}.
var _tray_wait := {}
var _music_label: Label
var _pending_action := {}
var _was_my_turn := false
var _was_started := false
var _wizard_open := false


func _ready() -> void:
	_client = Net.client
	if _client == null:
		App.goto(App.SCENE_JOIN)
		return
	add_child(Backdrop.new())
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	# --- Attente de validation par le MJ ---
	_waiting = _center_card("En attente du maître du jeu", "Votre demande a bien été reçue. Le MJ doit l'accepter.")
	outer.add_child(_waiting)

	# --- Création guidée ---
	_creation = VBoxContainer.new()
	_creation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var creation_margin := MarginContainer.new()
	creation_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		creation_margin.add_theme_constant_override("margin_" + side, 10)
	creation_margin.add_child(_creation)
	outer.add_child(creation_margin)

	# --- Salle d'attente ---
	var lobby_scroll := TouchScroll.new()
	outer.add_child(lobby_scroll)
	var lobby_col := CenteredColumn.new()
	lobby_col.max_width = 600
	lobby_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_scroll.add_child(lobby_col)
	_lobby = VBoxContainer.new()
	_lobby.add_theme_constant_override("separation", 12)
	lobby_col.add_child(_lobby)

	# --- La partie ---
	_tabs = TabbedPages.new(true, 8)
	outer.add_child(_tabs)
	_tabs.add_page("map", "Carte", _build_map())
	_tabs.add_page("adventure", "Aventure", _build_adventure())
	_tabs.add_page("sheet", "Fiche", _build_sheet_page())
	_tabs.add_page("group", "Groupe", _build_group())
	_codex_holder = VBoxContainer.new()
	_tabs.add_page("codex", "Codex", _codex_holder)
	_tabs.page_changed.connect(func(key):
		if key == "map":
			_map_view.recenter.call_deferred())

	_keyboard_pad = Control.new()
	outer.add_child(_keyboard_pad)
	_tray = DiceTray.new()
	add_child(_tray)

	_client.status_changed.connect(func(_s): _refresh_all())
	_client.welcomed.connect(_on_welcomed)
	_client.players_changed.connect(func():
		_refresh_group()
		_refresh_lobby())
	_client.message_received.connect(_on_message)
	_client.message_updated.connect(_on_message_updated)
	_client.characters_changed.connect(_on_characters)
	_client.map_changed.connect(_refresh_map)
	_client.phase_changed.connect(_refresh_phase)
	_client.settings_changed.connect(_on_settings)
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


func _center_card(title: String, text: String) -> Control:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := CenteredColumn.new()
	col.custom_minimum_size.x = 340
	center.add_child(col)
	var card := UIKit.card(col, "", "HighlightPanel")
	var t := UIKit.label(title, "HeadingLabel", true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(t)
	var l := UIKit.label(text, "", true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(l)
	return center


# ---------------------------------------------------------------------------
# Pages de la partie
# ---------------------------------------------------------------------------

func _build_phase_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_phase_boxes.append(box)
	return box


func _build_map() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.add_child(_build_phase_box())
	_map_title = UIKit.label("", "MutedLabel", true)
	page.add_child(_map_title)
	_map_view = MapView.new()
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.custom_minimum_size.y = 220
	_map_view.move_requested.connect(func(id, x, y): _client.move_pawn(id, x, y))
	_map_view.target_picked.connect(_on_target_picked)
	page.add_child(_map_view)
	var turn := PanelContainer.new()
	turn.theme_type_variation = "InsetPanel"
	page.add_child(turn)
	_turn_panel = VBoxContainer.new()
	_turn_panel.add_theme_constant_override("separation", 6)
	turn.add_child(_turn_panel)
	return page


func _build_adventure() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.add_child(_build_phase_box())
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
	_composer.send_roll.connect(_roll)
	_feed.roll_answer_requested.connect(func(id, expr, label):
		_tray_wait = {"message_id": id, "label": label}
		_tray.start(expr, label)
		_client.answer_roll(id))
	page.add_child(_composer)
	return page


func _build_sheet_page() -> Control:
	var scroll := TouchScroll.new()
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
	var scroll := TouchScroll.new()
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	var members := UIKit.card(page, "Le groupe")
	_group_list = VBoxContainer.new()
	members.add_child(_group_list)
	var sound := UIKit.card(page, "Musique")
	var enabled := CheckBox.new()
	enabled.text = "Jouer la musique de la partie sur cet appareil"
	enabled.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enabled.button_pressed = Music.enabled()
	enabled.toggled.connect(Music.set_enabled)
	sound.add_child(enabled)
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = Music.volume()
	volume.custom_minimum_size.y = 40
	volume.value_changed.connect(Music.set_volume)
	volume.drag_ended.connect(func(_c): App.save_settings())
	UIKit.field(sound, "Volume", volume)
	_music_label = UIKit.label("", "MutedLabel", true)
	sound.add_child(_music_label)
	var show_music := func():
		_music_label.text = ("En cours : " + Music.title()) if Music.playing else "Pas de musique pour l'instant (c'est le MJ qui choisit)."
	Music.changed.connect(show_music)
	show_music.call()
	var conn := UIKit.card(page, "Connexion")
	_ping_label = UIKit.label("", "MutedLabel", true)
	conn.add_child(_ping_label)
	return scroll


# ---------------------------------------------------------------------------
# États : validation, création, salle d'attente, partie
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	var accepted := _client.is_accepted()
	var has_sheet := not _client.my_character().is_empty()
	var started := _client.game_started()
	_waiting.visible = not accepted
	_creation.get_parent().visible = accepted and (not has_sheet or _wizard_open)
	_lobby.get_parent().get_parent().visible = accepted and has_sheet and not started and not _wizard_open
	_tabs.visible = accepted and has_sheet and started and not _wizard_open
	if accepted and not has_sheet and not _wizard_open and _creation.get_child_count() == 0:
		_show_creation_intro()
	_session_label.text = String(_client.session.get("name", "Legenders RPG"))
	var sheet := _client.my_character()
	var me_name := String(_client.me.get("name", Net.join_params().get("name", "")))
	if not sheet.is_empty() and String(sheet.get("name", "")) != "":
		me_name = "%s  ·  %s" % [sheet.name, me_name]
	_me_label.text = me_name + ("" if accepted else "  ·  en attente")
	if started and not _was_started and has_sheet:
		_splash("La partie commence !")
		_tabs.show_page("map")
	_was_started = started
	_refresh_connection()


func _show_creation_intro() -> void:
	UIKit.clear(_creation)
	var intro := UIKit.card(_creation, "Créez votre personnage", "HighlightPanel")
	intro.add_child(UIKit.label("En 4 étapes : une classe prête à jouer (capacités et équipement), vos points de caractéristiques, votre arme, puis votre nom. Tout reste modifiable ensuite.", "", true))
	var go := UIKit.button("Commencer", "PrimaryButton", _open_wizard)
	go.custom_minimum_size.y = 60
	intro.add_child(go)
	var free := UIKit.card(_creation, "", "InsetPanel")
	free.add_child(UIKit.label("Vous préférez tout inventer vous-même ?", "MutedLabel", true))
	free.add_child(UIKit.button("Création libre (avancée)", "", func():
		_wizard_open = true
		_refresh_all()
		_open_editor(_creation)))


func _open_wizard() -> void:
	_wizard_open = true
	UIKit.clear(_creation)
	var base := _client.my_character()
	if base.is_empty():
		base = CharacterData.create(_client.universe, String(_client.me.get("id", "")), String(_client.me.get("id", "")), String(_client.me.get("name", "")))
	var wizard := CreationWizard.new(_client.universe, base)
	wizard.finished.connect(func(sheet):
		_client.save_character(sheet)
		_wizard_open = false
		UIKit.clear(_creation)
		_creation.add_child(_center_card("Création…", "Votre personnage est envoyé au MJ."))
		_refresh_all())
	wizard.cancelled.connect(func():
		_wizard_open = false
		UIKit.clear(_creation)
		_refresh_all())
	_creation.add_child(wizard)
	_refresh_all()


func _refresh_lobby() -> void:
	if _lobby == null:
		return
	UIKit.clear(_lobby)
	var sheet := _client.my_character()
	if sheet.is_empty():
		return
	var ready := UIKit.card(_lobby, "", "HighlightPanel")
	var t := UIKit.label("Vous êtes prêt !", "TitleLabel", true)
	t.add_theme_font_size_override("font_size", 30)
	ready.add_child(t)
	ready.add_child(UIKit.label("Le MJ lancera la partie quand tout le monde aura créé son personnage.", "", true))
	var d := Rules.derived(sheet, String(_client.universe.get("id", "")))
	ready.add_child(UIKit.label("%s  ·  %s  ·  PV %d  ·  Défense %d  ·  Vitesse %d" % [sheet.name, sheet.get("concept", ""), int(sheet.hp_max), d.defense, d.speed], "StrongLabel", true))
	var row := HBoxContainer.new()
	ready.add_child(row)
	row.add_child(UIKit.button("Refaire mon personnage", "", _open_wizard))
	var table := UIKit.card(_lobby, "Autour de la table")
	for p in _client.players:
		var c := _client.character(p.id)
		var line := HBoxContainer.new()
		var n := UIKit.label(String(p.name) + ("  —  " + String(c.name) if not c.is_empty() else ""), "", true)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(n)
		line.add_child(UIKit.chip("Prêt" if not c.is_empty() else "Crée son personnage…", Palette.OK if not c.is_empty() else Palette.WARN))
		table.add_child(line)
	var codex := UIKit.card(_lobby, "En attendant : l'univers")
	codex.add_child(UIKit.label(String(_client.universe.get("description", "")), "", true))


func _on_settings() -> void:
	_refresh_sheet()
	_refresh_all()


## Grand bandeau animé (« La partie commence ! », « C'est votre tour ! »).
func _splash(text: String) -> void:
	var label := UIKit.label(text, "TitleLabel")
	label.add_theme_font_size_override("font_size", 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var panel := PanelContainer.new()
	panel.theme_type_variation = "HighlightPanel"
	panel.add_child(label)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(panel)
	await get_tree().process_frame
	panel.size.x = minf(size.x - 32, 520)
	panel.position = (size - panel.size) * 0.5
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	tw.tween_interval(1.4)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(panel.queue_free)


# ---------------------------------------------------------------------------
# Mises à jour
# ---------------------------------------------------------------------------

func _on_welcomed() -> void:
	_map_view.my_id = String(_client.me.get("id", ""))
	_feed.viewer_id = _map_view.my_id
	_feed.set_messages(_client.messages)
	UIKit.clear(_codex_holder)
	_codex_holder.add_child(CodexView.new(_client.universe))
	_was_started = _client.game_started()
	_refresh_group()
	_refresh_map()
	_refresh_phase()
	_editing = false
	_refresh_sheet()
	_refresh_lobby()
	_refresh_all()


func _roll(to: String, expr: String, label: String) -> void:
	_tray_wait = {"kind": "free", "label": label}
	_tray.start(expr, label)
	_client.roll(expr, to, label)
	_refresh_outbox()


func _on_message(m: Dictionary) -> void:
	_feed.add_message(m)
	if _tray_wait.get("kind", "") == "free" and m.get("kind", "") == Protocol.KIND_ROLL and m.get("from", "") == _map_view.my_id:
		_tray.finish(m.get("roll", {}), String(_tray_wait.get("label", "")))
		_tray_wait = {}
	elif _tray_wait.get("kind", "") == "attack" and m.get("kind", "") == Protocol.KIND_ROLL and m.get("from", "") == _map_view.my_id:
		_tray.finish(m.get("roll", {}), String(m.get("text", "")))
		_tray_wait = {}
	if m.get("kind", "") == Protocol.KIND_ROLL_REQUEST and m.get("to", "") == _map_view.my_id:
		_tabs.show_page("adventure")
	_tabs.set_badge("adventure", true)
	_refresh_outbox()


func _on_message_updated(m: Dictionary) -> void:
	_feed.update_message(m)
	if _tray_wait.get("message_id", "") == m.get("id", "") and not m.get("roll", {}).is_empty():
		_tray.finish(m.roll, String(_tray_wait.get("label", "")))
		_tray_wait = {}
	elif m.get("kind", "") == Protocol.KIND_ACTION and m.get("from", "") == _map_view.my_id:
		_tabs.set_badge("adventure", true)


func _on_characters() -> void:
	_refresh_group()
	_refresh_lobby()
	if not _editing:
		_refresh_sheet()
	_refresh_all()
	_refresh_turn_panel()


func _refresh_map() -> void:
	var map := _client.map
	_map_view.set_map(map)
	_map_title.text = String(map.get("name", "Pas de carte"))
	for t in map.get("tokens", []):
		if t.get("owner", "") == _map_view.my_id:
			if _map_view.focus_id != t.id:
				_map_view.focus_id = t.id
				_map_view.recenter.call_deferred()
			if _map_view.selected == "":
				_map_view.selected = t.id
	_refresh_reachable()


func _refresh_phase() -> void:
	var phase := _client.phase
	for box in _phase_boxes:
		UIKit.clear(box)
		if phase.is_empty():
			continue
		var row := HBoxContainer.new()
		box.add_child(row)
		var phase_chip := UIKit.chip("Phase : " + String(phase.get("name", "")), Palette.GOLD)
		phase_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(phase_chip)
		if phase.get("turns", false):
			row.add_child(UIKit.label("Tour %d" % int(phase.get("round", 1)), "MutedLabel"))
		var rules := UIKit.label(String(phase.get("rules", "")), "MutedLabel", true)
		rules.visible = false
		var toggle := UIKit.button("Règles", "NavButton", func(): rules.visible = not rules.visible)
		toggle.custom_minimum_size = Vector2(70, 32)
		row.add_child(toggle)
		box.add_child(rules)
		if phase.get("turns", false):
			var order := HFlowContainer.new()
			order.add_theme_constant_override("h_separation", 8)
			box.add_child(order)
			for id in phase.get("order", []):
				var t := MapData.token(_client.map, id)
				if t.is_empty():
					continue
				var current: bool = id == phase.get("current", "")
				var l := UIKit.label(("› " if current else "") + String(t.name), "StrongLabel" if current else "MutedLabel")
				if current:
					l.add_theme_color_override("font_color", Palette.GOLD)
				order.add_child(l)
	_map_view.current_turn = String(phase.get("current", ""))
	var mine := _client.is_my_turn()
	if mine and not _was_my_turn:
		Input.vibrate_handheld(250)
		_splash("C'est votre tour !")
		_tabs.show_page("map")
	_was_my_turn = mine
	_refresh_reachable()
	_refresh_turn_panel()
	_map_view.queue_redraw()


func _refresh_reachable() -> void:
	var phase := _client.phase
	var me := _client.my_token()
	_map_view.reachable = {}
	if _client.is_my_turn() and phase.get("move", "") == "limit" and not me.is_empty():
		_map_view.reachable = _map_view.compute_reachable(Vector2i(int(me.x), int(me.y)), int(phase.get("moves_left", 0)))
	_map_view.queue_redraw()


func _refresh_turn_panel() -> void:
	if _turn_panel == null:
		return
	UIKit.clear(_turn_panel)
	var phase := _client.phase
	var sheet := _client.my_character()
	if _pending_action.size() > 0:
		_turn_panel.add_child(UIKit.label("Touchez la cible sur la carte.", "StrongLabel", true))
		_turn_panel.add_child(UIKit.button("Annuler", "", _cancel_target))
		return
	if not phase.get("turns", false):
		var move: String = {"free": "Déplacement libre : touchez une case pour y aller.", "none": "Pas de déplacement pendant cette phase."}.get(String(phase.get("move", "free")), "")
		_turn_panel.add_child(UIKit.label(move, "MutedLabel", true))
		_turn_panel.add_child(_dice_row())
		return
	if not _client.is_my_turn():
		var current := MapData.token(_client.map, String(phase.get("current", "")))
		_turn_panel.add_child(UIKit.label("Au tour de %s. Patientez…" % current.get("name", "?") if not current.is_empty() else "Patientez…", "MutedLabel", true))
		_turn_panel.add_child(_dice_row())
		return
	var title := UIKit.label("C'est votre tour !", "HeadingLabel")
	_turn_panel.add_child(title)
	var used: bool = phase.get("action_used", false)
	var info := "Action : %s" % ("faite" if used else "disponible")
	if phase.get("move", "") == "limit":
		info = "Déplacement : %d case%s  ·  " % [int(phase.moves_left), "s" if int(phase.moves_left) > 1 else ""] + info
	_turn_panel.add_child(UIKit.label(info, "", true))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_turn_panel.add_child(actions)
	var attack := UIKit.button("Attaquer", "PrimaryButton", _choose_attack)
	var ability := UIKit.button("Capacité", "", _choose_ability)
	var item := UIKit.button("Objet", "", _choose_item)
	for b in [attack, ability, item]:
		b.disabled = used or sheet.is_empty()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 52
		actions.add_child(b)
	var end := UIKit.button("Fin du tour  ›", "PrimaryButton" if used else "", func(): _client.turn_action("end"))
	end.custom_minimum_size.y = 52
	_turn_panel.add_child(end)


func _dice_row() -> Control:
	var dice := HBoxContainer.new()
	dice.add_theme_constant_override("separation", 6)
	for expr in ["d20", "d12", "d10", "d8", "d6", "d4"]:
		var b := UIKit.button(expr, "", _roll.bind(Protocol.TO_ALL, expr, ""))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 44
		dice.add_child(b)
	return dice


# --- Actions de tour ---

func _menu(items: Array, on_pick: Callable) -> void:
	var popup := PopupMenu.new()
	for i in items.size():
		popup.add_item(String(items[i][0]))
		popup.set_item_disabled(i, items[i].size() > 2 and items[i][2])
		popup.set_item_metadata(i, items[i][1])
	popup.id_pressed.connect(func(id): on_pick.call(popup.get_item_metadata(popup.get_item_index(id))))
	popup.popup_hide.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(int(minf(size.x - 20, 420)), 0))


func _choose_attack() -> void:
	var sheet := _client.my_character()
	var uid := String(_client.universe.get("id", ""))
	var list := Rules.weapons(sheet)
	if list.size() == 1:
		_start_target({"action": "attack", "index": 0})
		return
	var items: Array = []
	for i in list.size():
		items.append([CreationWizard._attack_text(Rules.attack_profile(sheet, uid, list[i])), i])
	_menu(items, func(i): _start_target({"action": "attack", "index": i}))


func _choose_ability() -> void:
	var sheet := _client.my_character()
	var abilities: Array = sheet.get("abilities", [])
	if abilities.is_empty():
		_feed.add_notice("Vous n'avez pas de capacité utilisable.", Palette.WARN)
		return
	var res := int(sheet.get("res", 0))
	var res_name := String(_client.universe.get("character", {}).get("resource_name", "Énergie"))
	var items: Array = []
	for i in abilities.size():
		var a: Dictionary = abilities[i]
		var cost := int(a.get("res_cost", 0))
		items.append(["%s%s" % [a.name, ("  (%d %s)" % [cost, res_name]) if cost > 0 else ""], i, cost > res])
	_menu(items, func(i):
		var a: Dictionary = abilities[i]
		var kind := String(a.get("kind", "effect"))
		var needs_target := kind == "attack" or (kind == "heal" and int(a.get("range", 0)) > 0) or (kind == "effect" and int(a.get("range", 1)) > 1)
		if needs_target:
			_start_target({"action": "ability", "index": i})
		else:
			_client.turn_action("ability", "", i))


func _choose_item() -> void:
	var sheet := _client.my_character()
	var inv: Array = sheet.get("inventory", [])
	var items: Array = []
	for i in inv.size():
		if String(inv[i].get("category", "")) == "consommable" and int(inv[i].get("qty", 1)) > 0:
			items.append(["%s ×%d" % [inv[i].name, int(inv[i].get("qty", 1))], i])
	if items.is_empty():
		_feed.add_notice("Aucun objet utilisable (potions, rations…).", Palette.WARN)
		return
	_menu(items, func(i): _client.turn_action("item", "", i))


func _start_target(action: Dictionary) -> void:
	_pending_action = action
	_map_view.target_mode = true
	_tabs.show_page("map")
	_refresh_turn_panel()
	_map_view.queue_redraw()


func _cancel_target() -> void:
	_pending_action = {}
	_map_view.target_mode = false
	_refresh_turn_panel()
	_map_view.queue_redraw()


func _on_target_picked(token_id: String) -> void:
	var action := _pending_action
	_cancel_target()
	if action.get("action", "") == "attack" or action.get("action", "") == "ability":
		_tray_wait = {"kind": "attack"}
		_tray.start("d20", "")
	_client.turn_action(String(action.get("action", "")), token_id, int(action.get("index", 0)))


# --- Fiche ---

func _refresh_sheet() -> void:
	if _editing:
		return
	UIKit.clear(_sheet_box)
	var sheet := _client.my_character()
	if sheet.is_empty():
		return
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	_sheet_box.add_child(row)
	if _client.can_edit_sheet():
		row.add_child(UIKit.button("Modifier en détail", "", _open_editor.bind(_sheet_box)))
		row.add_child(UIKit.button("Refaire avec l'assistant", "", _open_wizard))
	else:
		_sheet_box.add_child(UIKit.label("Le MJ a verrouillé les fiches : demandez-lui les modifications.", "MutedLabel", true))
	_sheet_box.add_child(CharacterSheet.new(sheet, _client.universe))


func _open_editor(container: VBoxContainer) -> void:
	_editing = true
	UIKit.clear(container)
	var sheet := _client.my_character()
	if sheet.is_empty():
		sheet = CharacterData.create(_client.universe, String(_client.me.get("id", "")), String(_client.me.get("id", "")), String(_client.me.get("name", "")))
	var editor := CharacterEditor.new(sheet, _client.universe)
	var scroll: Control = editor
	if container == _creation:
		var s := TouchScroll.new()
		s.add_child(editor)
		scroll = s
	editor.saved.connect(func(data):
		_client.save_character(data)
		_editing = false
		_wizard_open = false
		UIKit.clear(container)
		_refresh_all())
	editor.cancelled.connect(func():
		_editing = false
		_wizard_open = false
		UIKit.clear(container)
		_refresh_sheet()
		_refresh_all())
	container.add_child(scroll)


func _refresh_group() -> void:
	if _group_list == null:
		return
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
	if _ping_label:
		_ping_label.text = "%s\nHôte : %s  ·  ping %s" % [Net.state_label(), params.get("ip", "?"), UIKit.ping_text(Net.get_peer_rtt(1))]
	_refresh_outbox()


func _refresh_outbox() -> void:
	if _outbox_label == null:
		return
	var n := _client.pending_count()
	_outbox_label.visible = n > 0
	_outbox_label.text = "%d envoi%s en cours…" % [n, "s" if n > 1 else ""]


func _on_command_failed(_req_id: String, error: String) -> void:
	_feed.add_notice("Impossible : " + error, Palette.DANGER)
	if _tray_wait.get("kind", "") == "attack":
		_tray.visible = false
		_tray_wait = {}
	var toast := UIKit.label(error, "", true)
	toast.add_theme_color_override("font_color", Palette.DANGER)
	if _turn_panel:
		_turn_panel.add_child(toast)
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
