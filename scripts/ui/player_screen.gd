extends Control
## Écran du joueur (pensé pour le téléphone en portrait, et adapté au PC).
##
## Parcours : validation éventuelle par le MJ → assistant de création → salon
## « Vous êtes prêt ! » → la partie.
##
## La partie en trois zones :
##   - en haut : le lieu, la situation (phase, tour) et l'objectif en cours ;
##   - au centre : le récit (narration, messages, résultats) et la carte (sur
##     téléphone, un bouton bascule entre les deux ; sur PC, côte à côte) ;
##   - en bas, toujours visible : portrait, PV, ressource, jauge d'ultime, les
##     capacités équipées, et l'accès au sac, à la fiche et au journal.
## Les menus s'ouvrent en panneaux superposés faciles à fermer.

const WIDE_MIN := 900.0

var _client: SessionClient
var _wide := false
var _waiting: Control
var _creation: VBoxContainer
var _lobby: VBoxContainer
var _game: VBoxContainer
var _keyboard_pad: Control
var _tray: DiceTray
var _tray_wait := {}

# En-tête
var _place_label: Label
var _situation_label: Label
var _conn_chip: Label
var _objective: Button

# Centre
var _center: BoxContainer
var _switch: HBoxContainer
var _switch_buttons := {}
var _feed_page: VBoxContainer
var _map_page: VBoxContainer
var _feed: FeedView
var _composer: Composer
var _outbox_label: Label
var _quick_actions: HFlowContainer
var _map_view: MapView
var _timeline: HBoxContainer
var _timeline_scroll: ScrollContainer
var _turn_bar: VBoxContainer
var _view := "story"
var _unread := false

# Barre du bas
var _hud: PanelContainer
var _portrait: Portrait
var _name_label: Label
var _hp_bar: ResourceBar
var _res_bar: ResourceBar
var _ult_bar: ResourceBar
var _gold_label: Label
var _abilities_row: HBoxContainer
var _sheet_badge: Control

# Panneaux
var _overlay: OverlayPanel
var _overlay_kind := ""
var _journal_tab := "quests"
var _inventory_tab := "bag"

# Suivi
var _pending := {}
var _was_my_turn := false
var _was_started := false
var _wizard_open := false
var _last_level := 0
var _known_quests := {}


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
	outer.add_child(_build_top_bar())

	_waiting = _center_card("En attente du maître du jeu", "Votre demande a bien été reçue. Le MJ doit l'accepter.")
	outer.add_child(_waiting)

	_creation = VBoxContainer.new()
	_creation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var creation_margin := MarginContainer.new()
	creation_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		creation_margin.add_theme_constant_override("margin_" + side, 10)
	creation_margin.add_child(_creation)
	outer.add_child(creation_margin)

	var lobby_scroll := TouchScroll.new()
	outer.add_child(lobby_scroll)
	var lobby_col := CenteredColumn.new()
	lobby_col.max_width = 600
	lobby_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_scroll.add_child(lobby_col)
	_lobby = VBoxContainer.new()
	_lobby.add_theme_constant_override("separation", 12)
	lobby_col.add_child(_lobby)

	_game = VBoxContainer.new()
	_game.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_game.add_theme_constant_override("separation", 0)
	outer.add_child(_game)
	_build_game()

	_keyboard_pad = Control.new()
	outer.add_child(_keyboard_pad)
	_tray = DiceTray.new()
	add_child(_tray)

	_client.status_changed.connect(func(_s): _refresh_all())
	_client.welcomed.connect(_on_welcomed)
	_client.players_changed.connect(func():
		_refresh_lobby()
		_refresh_overlay("journal"))
	_client.message_received.connect(_on_message)
	_client.message_updated.connect(_on_message_updated)
	_client.characters_changed.connect(_on_characters)
	_client.map_changed.connect(_refresh_map)
	_client.phase_changed.connect(_refresh_phase)
	_client.settings_changed.connect(_refresh_all)
	_client.command_failed.connect(_on_command_failed)
	_client.quests_changed.connect(_on_quests)
	_client.loot_changed.connect(func(): _refresh_overlay("inventory"))
	_client.content_changed.connect(_refresh_hud)
	_client.fx.connect(_on_fx)
	Net.state_changed.connect(func(_s): _refresh_connection())
	Net.session_ended.connect(_on_session_ended)
	get_viewport().size_changed.connect(_layout)

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_refresh_connection)
	add_child(timer)

	if _client.is_accepted():
		_on_welcomed()
	_layout()
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
# Construction
# ---------------------------------------------------------------------------

func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = "BarPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	bar.add_child(col)
	var row := HBoxContainer.new()
	col.add_child(row)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	_place_label = UIKit.label("", "HeadingLabel")
	_place_label.clip_text = true
	titles.add_child(_place_label)
	_situation_label = UIKit.label("", "MutedLabel")
	_situation_label.clip_text = true
	titles.add_child(_situation_label)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	row.add_child(right)
	_conn_chip = UIKit.chip("", Palette.OK)
	_conn_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_conn_chip)
	var menu := MenuButton.new()
	menu.text = "Menu"
	menu.flat = false
	menu.theme_type_variation = "NavButton"
	menu.custom_minimum_size = Vector2(80, 34)
	var popup := menu.get_popup()
	for item in ["Le groupe", "Codex de l'univers", "Musique et réglages", "Comment jouer ?", "Quitter la partie"]:
		popup.add_item(item)
	popup.index_pressed.connect(_on_menu)
	right.add_child(menu)
	_objective = Button.new()
	_objective.flat = true
	_objective.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_objective.clip_text = true
	_objective.custom_minimum_size.y = 30
	_objective.add_theme_color_override("font_color", Palette.GOLD)
	_objective.add_theme_font_size_override("font_size", 15)
	_objective.pressed.connect(func(): _open_journal("quests"))
	_objective.visible = false
	col.add_child(_objective)
	return bar


func _on_menu(index: int) -> void:
	match index:
		0:
			_open_journal("group")
		1:
			_open_journal("codex")
		2:
			_open_journal("settings")
		3:
			_open_help()
		4:
			_confirm_leave()


func _build_game() -> void:
	# Bascule Récit / Carte (téléphone).
	_switch = HBoxContainer.new()
	_switch.add_theme_constant_override("separation", 0)
	_game.add_child(_switch)
	for spec in [["story", "Récit"], ["map", "Carte"]]:
		var b := UIKit.button(spec[1], "NavButton", func(): _show_view(spec[0]))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 40
		_switch.add_child(b)
		_switch_buttons[spec[0]] = b
	_center = HBoxContainer.new()
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.add_theme_constant_override("separation", 8)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	margin.add_child(_center)
	_game.add_child(margin)
	_map_page = _build_map_page()
	_center.add_child(_map_page)
	_feed_page = _build_feed_page()
	_center.add_child(_feed_page)
	_hud = _build_hud()
	_game.add_child(_hud)


func _build_feed_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.size_flags_stretch_ratio = 2.0
	page.add_theme_constant_override("separation", 6)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 4)
	page.add_child(filters)
	var group := ButtonGroup.new()
	for spec in [["all", "Tout"], ["story", "Récit et discussions"], ["combat", "Combat"]]:
		var b := UIKit.button(spec[1], "NavButton", func(): _feed.set_filter(spec[0]))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = spec[0] == "all"
		b.custom_minimum_size.y = 32
		b.add_theme_font_size_override("font_size", 14)
		filters.add_child(b)
	_feed = FeedView.new("", false)
	page.add_child(_feed)
	_outbox_label = UIKit.label("", "MutedLabel", true)
	_outbox_label.add_theme_color_override("font_color", Palette.WARN)
	_outbox_label.visible = false
	page.add_child(_outbox_label)
	# Actions contextuelles : des idées, jamais une liste fermée.
	_quick_actions = HFlowContainer.new()
	_quick_actions.add_theme_constant_override("h_separation", 6)
	_quick_actions.add_theme_constant_override("v_separation", 6)
	page.add_child(_quick_actions)
	for spec in [["Examiner", "J'examine "], ["Fouiller", "Je fouille "], ["Parler à…", "Je vais parler à "], ["Se cacher", "Je me cache "], ["Écouter", "J'écoute attentivement "]]:
		var b := UIKit.button(spec[0], "", func(): _composer.start_action(spec[1]))
		b.custom_minimum_size.y = 34
		b.add_theme_font_size_override("font_size", 15)
		_quick_actions.add_child(b)
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


func _build_map_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.size_flags_stretch_ratio = 3.0
	page.add_theme_constant_override("separation", 6)
	_timeline_scroll = ScrollContainer.new()
	_timeline_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_timeline_scroll.custom_minimum_size.y = 66
	page.add_child(_timeline_scroll)
	_timeline = HBoxContainer.new()
	_timeline.add_theme_constant_override("separation", 6)
	_timeline_scroll.add_child(_timeline)
	_map_view = MapView.new()
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.custom_minimum_size.y = 200
	_map_view.move_requested.connect(func(id, x, y): _client.move_pawn(id, x, y))
	_map_view.target_picked.connect(_on_target_picked)
	page.add_child(_map_view)
	var turn := PanelContainer.new()
	turn.theme_type_variation = "InsetPanel"
	page.add_child(turn)
	_turn_bar = VBoxContainer.new()
	_turn_bar.add_theme_constant_override("separation", 6)
	turn.add_child(_turn_bar)
	return page


## Barre du bas : portrait, PV, ressource, ultime, or ; capacités ; sac, fiche, journal.
func _build_hud() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "NavPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var pbtn := Button.new()
	pbtn.flat = true
	pbtn.custom_minimum_size = Vector2(60, 60)
	pbtn.tooltip_text = "Ma fiche"
	_portrait = Portrait.new({}, Palette.VIOLET, 60)
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pbtn.add_child(_portrait)
	_sheet_badge = Control.new()
	_sheet_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_badge.draw.connect(func():
		_sheet_badge.draw_circle(Vector2(_sheet_badge.size.x - 8, 8), 8, Palette.ULT)
		_sheet_badge.draw_string(get_theme_font("font", "StrongLabel"), Vector2(_sheet_badge.size.x - 12, 13), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.BG_DEEP))
	_sheet_badge.visible = false
	pbtn.add_child(_sheet_badge)
	pbtn.pressed.connect(_open_sheet)
	top.add_child(pbtn)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 3)
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(bars)
	var name_row := HBoxContainer.new()
	bars.add_child(name_row)
	_name_label = UIKit.label("", "StrongLabel")
	_name_label.clip_text = true
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_label)
	name_row.add_child(Icons.new("coin", Palette.GOLD, 18))
	_gold_label = UIKit.label("0", "StrongLabel")
	_gold_label.add_theme_color_override("font_color", Palette.GOLD)
	name_row.add_child(_gold_label)
	_hp_bar = ResourceBar.new("PV", Palette.HP, 22)
	bars.add_child(_hp_bar)
	_res_bar = ResourceBar.new("", Palette.MANA, 16)
	bars.add_child(_res_bar)
	_ult_bar = ResourceBar.new("Ultime", Palette.ULT, 8)
	_ult_bar.show_text = false
	bars.add_child(_ult_bar)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	col.add_child(bottom)
	_abilities_row = HBoxContainer.new()
	_abilities_row.add_theme_constant_override("separation", 6)
	_abilities_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_abilities_row)
	var sep := VSeparator.new()
	bottom.add_child(sep)
	for spec in [["bag", "Sac", _open_inventory.bind("bag")], ["person", "Fiche", _open_sheet], ["journal", "Journal", _open_journal.bind("quests")]]:
		bottom.add_child(_icon_button(spec[0], spec[1], spec[2]))
	return panel


## Bouton du bas : icône et petit libellé dessous (tient sur un téléphone).
func _icon_button(icon_name: String, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(46, 60)
	b.tooltip_text = text
	var face := Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.draw.connect(func():
		var isz := 24.0
		Icons.paint(face, icon_name, Rect2(Vector2((face.size.x - isz) * 0.5, 8), Vector2(isz, isz)), Palette.GOLD)
		var font := get_theme_font("font", "StrongLabel")
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		face.draw_string(font, Vector2((face.size.x - w) * 0.5, face.size.y - 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT))
	b.add_child(face)
	b.pressed.connect(on_pressed)
	return b


# ---------------------------------------------------------------------------
# Disposition et états
# ---------------------------------------------------------------------------

func _layout() -> void:
	_wide = get_viewport_rect().size.x >= WIDE_MIN and not App.is_mobile()
	if _switch == null:
		return
	_switch.visible = not _wide
	if _wide:
		_map_page.visible = true
		_feed_page.visible = true
	else:
		_show_view(_view)


func _show_view(view: String) -> void:
	_view = view
	if _wide:
		return
	_map_page.visible = view == "map"
	_feed_page.visible = view == "story"
	for k in _switch_buttons:
		_switch_buttons[k].set_pressed_no_signal(k == view)
	if view == "story":
		_unread = false
		_switch_buttons.story.text = "Récit"
	if view == "map":
		_map_view.recenter.call_deferred()


func _refresh_all() -> void:
	var accepted := _client.is_accepted()
	var has_sheet := not _client.my_character().is_empty()
	var started := _client.game_started()
	_waiting.visible = not accepted
	_creation.get_parent().visible = accepted and (not has_sheet or _wizard_open)
	_lobby.get_parent().get_parent().visible = accepted and has_sheet and not started and not _wizard_open
	_game.visible = accepted and has_sheet and started and not _wizard_open
	if accepted and not has_sheet and not _wizard_open and _creation.get_child_count() == 0:
		_show_creation_intro()
	if started and not _was_started and has_sheet:
		_splash("La partie commence !", Palette.GOLD)
		_show_view("map")
		if not bool(App.get_setting("help", "seen_welcome", false)):
			_open_help()
			App.set_setting("help", "seen_welcome", true)
			App.save_settings()
	_was_started = started
	_refresh_header()
	_refresh_connection()


func _refresh_header() -> void:
	var map := _client.map
	_place_label.text = String(map.get("name", _client.session.get("name", "Legenders RPG")))
	var phase := _client.phase
	var parts: PackedStringArray = []
	if not phase.is_empty():
		parts.append(String(phase.get("name", "")))
		if phase.get("turns", false):
			parts.append("tour %d" % int(phase.get("round", 1)))
			var cur := MapData.token(map, String(phase.get("current", "")))
			if _client.is_my_turn():
				parts.append("à vous de jouer !")
			elif not cur.is_empty():
				parts.append("au tour de %s" % cur.name)
	else:
		parts.append(String(_client.session.get("name", "")))
	_situation_label.text = "  ·  ".join(parts)
	var quests := _client.active_quests()
	_objective.visible = not quests.is_empty() and _client.game_started()
	if not quests.is_empty():
		var q: Dictionary = quests[0]
		var next := ""
		for o in q.get("objectives", []):
			if not o.get("done", false):
				next = String(o.text)
				break
		_objective.text = "◆  " + (("Objectif : %s" % next) if next != "" else String(q.title)) + ("  (%s)" % q.title if next != "" else "")


func _show_creation_intro() -> void:
	UIKit.clear(_creation)
	var scroll := TouchScroll.new()
	_creation.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	var intro := UIKit.card(col, "Créez votre personnage", "HighlightPanel")
	intro.add_child(UIKit.label("Cinq petites étapes : son nom et son visage, une classe prête à jouer (passif, trois capacités, un ultime), ses caractéristiques, son équipement, puis un récapitulatif. Aucune connaissance des jeux de rôle n'est nécessaire : tout est expliqué en chemin.", "", true))
	var go := UIKit.button("Commencer", "PrimaryButton", _open_wizard)
	go.custom_minimum_size.y = 60
	intro.add_child(go)
	var free := UIKit.card(col, "", "InsetPanel")
	free.add_child(UIKit.label("Vous préférez tout inventer vous-même ? Créez un personnage « libre » (juste une histoire) : le MJ réglera ses valeurs de jeu.", "MutedLabel", true))
	free.add_child(UIKit.button("Création libre (avancée)", "", func():
		_wizard_open = true
		_refresh_all()
		_open_story_editor(_creation)))


func _open_wizard() -> void:
	_close_overlay()
	_wizard_open = true
	UIKit.clear(_creation)
	var base := _client.my_character()
	if base.is_empty() or base.get("public", false):
		base = CharacterData.create(_client.universe, String(_client.me.get("id", "")), String(_client.me.get("id", "")), String(_client.me.get("name", "")), _client.content)
	var wizard := CreationWizard.new(_client.universe, _client.content, base)
	wizard.finished.connect(func(payload):
		_client.create_character(String(payload.class_id), payload.alloc, payload.choices, payload.identity)
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	ready.add_child(row)
	row.add_child(Portrait.for_sheet(sheet, _client.content, 72))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var cls := Rules.get_class_def(_client.content, String(sheet.get("class_id", "")))
	info.add_child(UIKit.label("%s  ·  %s" % [sheet.name, cls.get("name", sheet.get("concept", ""))], "StrongLabel", true))
	var hp := ResourceBar.new("PV", Palette.HP, 20)
	hp.set_values(int(sheet.hp), int(sheet.hp_max), false)
	info.add_child(hp)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	ready.add_child(buttons)
	buttons.add_child(UIKit.button("Voir ma fiche", "", _open_sheet))
	buttons.add_child(UIKit.button("Refaire mon personnage", "", _open_wizard))
	var table := UIKit.card(_lobby, "Autour de la table")
	for p in _client.players:
		var c := _client.character(p.id)
		var line := HBoxContainer.new()
		var n := UIKit.label(String(p.name) + ("  —  " + String(c.name) if not c.is_empty() else ""), "", true)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(n)
		line.add_child(UIKit.chip("Prêt" if not c.is_empty() else "Crée son personnage…", Palette.OK if not c.is_empty() else Palette.WARN))
		table.add_child(line)
	var help := UIKit.card(_lobby, "En attendant : comment on joue ?")
	_help_text(help)


## Grand bandeau animé (« La partie commence ! », « C'est votre tour ! », « Victoire ! »).
func _splash(text: String, color: Color = Palette.GOLD) -> void:
	var label := UIKit.label(text, "TitleLabel")
	label.add_theme_font_size_override("font_size", 38)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.BG_DEEP, 0.94)
	sb.border_color = color
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	sb.skew = Vector2(0.18, 0)
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(label)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	await get_tree().process_frame
	panel.size = Vector2(size.x + 40, panel.get_combined_minimum_size().y)
	panel.position = Vector2(-20, (size.y - panel.size.y) * 0.4)
	panel.modulate.a = 0.0
	var start := panel.position
	panel.position = start + Vector2(-80, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
	tw.tween_property(panel, "position", start, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(1.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)


# ---------------------------------------------------------------------------
# Mises à jour
# ---------------------------------------------------------------------------

func _on_welcomed() -> void:
	_map_view.my_id = String(_client.me.get("id", ""))
	_feed.viewer_id = _map_view.my_id
	_feed.set_messages(_client.messages)
	_was_started = _client.game_started()
	_last_level = int(_client.my_character().get("level", 0))
	for q in _client.quests:
		_known_quests[q.id] = q.status
	_refresh_map()
	_refresh_phase()
	_refresh_hud()
	_refresh_lobby()
	_refresh_all()


func _roll(to: String, expr: String, label: String) -> void:
	_tray_wait = {"kind": "free", "label": label}
	_tray.start(expr, label)
	_client.roll(expr, to, label)
	_refresh_outbox()


func _on_message(m: Dictionary) -> void:
	_feed.add_message(m)
	var kind := String(m.get("kind", ""))
	if _tray_wait.get("kind", "") == "free" and kind == Protocol.KIND_ROLL and m.get("from", "") == _map_view.my_id:
		_tray.finish(m.get("roll", {}), String(_tray_wait.get("label", "")))
		_tray_wait = {}
	if kind == Protocol.KIND_ROLL_REQUEST and m.get("to", "") == _map_view.my_id:
		_show_view("story")
		Input.vibrate_handheld(120)
	match String(m.get("banner", "")) if _client.game_started() and not _wizard_open else "":
		"victory":
			_splash("Victoire !", Palette.ULT)
		"defeat":
			_splash("Défaite…", Palette.DANGER)
		"quest_new":
			_splash("Nouvelle quête", Palette.GOLD)
		"quest_done":
			_splash("Quête accomplie !", Palette.ULT)
	if not _wide and _view != "story" and kind not in [Protocol.KIND_SYSTEM]:
		_unread = true
		_switch_buttons.story.text = "Récit  ◆"
	_refresh_outbox()


func _on_message_updated(m: Dictionary) -> void:
	_feed.update_message(m)
	if _tray_wait.get("message_id", "") == m.get("id", "") and not m.get("roll", {}).is_empty():
		_tray.finish(m.roll, String(_tray_wait.get("label", "")))
		_tray_wait = {}


func _on_characters() -> void:
	var sheet := _client.my_character()
	var level := int(sheet.get("level", 0))
	if _last_level > 0 and level > _last_level:
		_splash("Niveau %d !" % level, Palette.XP)
		Input.vibrate_handheld(200)
	_last_level = level
	_refresh_lobby()
	_refresh_all()
	_refresh_hud()
	_refresh_turn_bar()
	_refresh_timeline()
	_refresh_overlay("sheet")
	_refresh_overlay("inventory")


func _on_quests() -> void:
	for q in _client.quests:
		_known_quests[q.id] = q.status
	_refresh_header()
	_refresh_overlay("journal")


func _on_fx(list: Array) -> void:
	_map_view.show_fx(list)
	var me := String(_client.my_token().get("id", "-"))
	for f in list:
		if String(f.get("token", "")) == me and String(f.get("type", "")) == "dmg":
			Input.vibrate_handheld(80)


func _refresh_map() -> void:
	var map := _client.map
	_map_view.set_map(map)
	for t in map.get("tokens", []):
		if t.get("owner", "") == _map_view.my_id:
			if _map_view.focus_id != t.id:
				_map_view.focus_id = t.id
				_map_view.recenter.call_deferred()
			if _map_view.selected == "":
				_map_view.selected = t.id
	_refresh_header()
	_refresh_reachable()
	_refresh_timeline()


func _refresh_phase() -> void:
	var phase := _client.phase
	_map_view.current_turn = String(phase.get("current", ""))
	var mine := _client.is_my_turn()
	if mine and not _was_my_turn:
		Input.vibrate_handheld(250)
		_splash("C'est votre tour !", Palette.GOLD)
		_show_view("map")
	_was_my_turn = mine
	if not mine and not _pending.is_empty() and phase.get("turns", false):
		_cancel_target()
	_refresh_header()
	_refresh_reachable()
	_refresh_turn_bar()
	_refresh_timeline()
	_refresh_hud()
	_map_view.queue_redraw()


func _refresh_reachable() -> void:
	var phase := _client.phase
	var me := _client.my_token()
	_map_view.reachable = {}
	if _client.is_my_turn() and phase.get("move", "") == "limit" and not me.is_empty() and _pending.is_empty():
		var moves := int(phase.get("moves_left", 0))
		if phase.get("type", "") == "combat" and int(phase.get("ap", 0)) >= int(Content.rule(_client.content, "move_ap")):
			moves += int(Rules.derived(_client.my_character(), _client.content).speed)
		_map_view.reachable = _map_view.compute_reachable(Vector2i(int(me.x), int(me.y)), moves)
	_map_view.queue_redraw()


## Frise des tours : combattant actif en tête, puis les suivants, avec PV et effets.
func _refresh_timeline() -> void:
	if _timeline == null:
		return
	UIKit.clear(_timeline)
	var phase := _client.phase
	_timeline_scroll.visible = phase.get("turns", false) and not (phase.get("order", []) as Array).is_empty()
	if not _timeline_scroll.visible:
		return
	var order: Array = phase.get("order", [])
	var current := String(phase.get("current", ""))
	var start := maxi(0, order.find(current))
	var rotated: Array = order.slice(start) + order.slice(0, start)
	for i in rotated.size():
		var t := MapData.token(_client.map, String(rotated[i]))
		if t.is_empty():
			continue
		_timeline.add_child(_timeline_chip(t, i == 0))


func _timeline_chip(t: Dictionary, active: bool) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var side_col := Palette.HEAL if String(t.get("kind", "")) == "pc" else Palette.HP
	sb.bg_color = Palette.PANEL if not active else Palette.GOLD_DEEP
	sb.border_color = Palette.GOLD if active else side_col.darkened(0.4)
	sb.set_border_width_all(2 if active else 1)
	sb.border_width_bottom = 3
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	var ko := int(t.get("hp_max", 0)) > 0 and int(t.get("hp", 1)) <= 0
	panel.modulate = Color(1, 1, 1, 0.45) if ko else (Color.WHITE if active else Color(0.82, 0.82, 0.82))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	var sheet := _client.character(String(t.get("owner", ""))) if String(t.get("owner", "")) != "" and String(t.get("kind", "")) == "pc" else {}
	var p: Portrait
	if not sheet.is_empty():
		p = Portrait.for_sheet(sheet, _client.content, 36)
	else:
		p = Portrait.new({}, Color(String(t.get("color", "#8a6a4a"))), 36, "skull" if String(t.get("kind", "")) == "monster" else "person")
	p.active = active
	p.ko = ko
	row.add_child(p)
	var name := UIKit.label(String(t.get("name", "?")), "StrongLabel" if active else "")
	name.add_theme_font_size_override("font_size", 14)
	name.custom_minimum_size.x = 60
	name.clip_text = true
	row.add_child(name)
	if int(t.get("hp_max", 0)) > 0:
		var hp := ResourceBar.new("", Palette.HP if String(t.get("kind", "")) != "pc" else Palette.HEAL, 8)
		hp.show_text = false
		hp.custom_minimum_size.x = 96
		hp.set_values(int(t.get("hp", 0)), int(t.hp_max), false)
		col.add_child(hp)
	var effects: Array = t.get("effects", [])
	if not effects.is_empty():
		col.add_child(GameUI.status_row(effects, 14))
	return panel


## Panneau sous la carte : actions de base pendant votre tour, sinon qui joue.
func _refresh_turn_bar() -> void:
	if _turn_bar == null:
		return
	UIKit.clear(_turn_bar)
	var phase := _client.phase
	if not _pending.is_empty():
		_turn_bar.add_child(UIKit.label("Touchez la cible entourée de rouge sur la carte (%s)." % _pending.get("label", ""), "StrongLabel", true))
		_turn_bar.add_child(UIKit.button("Annuler", "", _cancel_target))
		return
	if not phase.get("turns", false):
		var move: String = {"free": "Déplacement libre : touchez une case pour y aller.", "none": "Pas de déplacement pendant cette phase."}.get(String(phase.get("move", "free")), "")
		_turn_bar.add_child(UIKit.label("%s — %s" % [phase.get("name", ""), move], "MutedLabel", true))
		_turn_bar.add_child(_dice_row())
		return
	if not _client.is_my_turn():
		var current := MapData.token(_client.map, String(phase.get("current", "")))
		_turn_bar.add_child(UIKit.label("Au tour de %s. Vous pouvez discuter en attendant." % current.get("name", "?") if not current.is_empty() else "Patientez…", "MutedLabel", true))
		_turn_bar.add_child(_dice_row())
		return
	var head := HBoxContainer.new()
	_turn_bar.add_child(head)
	var title := UIKit.label("À vous !", "HeadingLabel")
	head.add_child(title)
	head.add_child(_ap_pips(int(phase.get("ap", 0)), int(phase.get("ap_max", 2))))
	var info := ""
	if phase.get("move", "") == "limit":
		if phase.get("type", "") == "combat":
			info = ("%d case%s" % [int(phase.moves_left), "s" if int(phase.moves_left) > 1 else ""]) if int(phase.moves_left) > 0 else "bouger : 1 PA"
		else:
			info = "%d case%s" % [int(phase.moves_left), "s" if int(phase.moves_left) > 1 else ""]
	var il := UIKit.label(info, "MutedLabel")
	il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(il)
	var r := Content.rules(_client.content)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	_turn_bar.add_child(actions)
	var ap := int(phase.get("ap", 0))
	var buttons: Array = []
	if phase.get("type", "") == "combat":
		for spec in [["Attaque rapide", "quick", int(r.quick_attack_ap), "Une attaque avec votre arme."], ["Attaque puissante", "power", int(r.power_attack_ap), "−2 au toucher, +50 % de dégâts."]]:
			var b := UIKit.button("%s · %d PA" % [spec[0], spec[2]], "PrimaryButton" if spec[1] == "quick" else "", _start_target.bind({"action": spec[1], "label": spec[0], "kind": "enemy"}))
			b.disabled = ap < int(spec[2])
			b.tooltip_text = spec[3]
			buttons.append(b)
		var defend := UIKit.button("Se défendre · %d PA" % int(r.defend_ap), "", func(): _client.turn_action("defend"))
		defend.disabled = ap < int(r.defend_ap)
		defend.tooltip_text = "+3 Défense jusqu'à votre prochain tour."
		buttons.append(defend)
	var end := UIKit.button("Terminer mon tour  ›", "PrimaryButton" if ap <= 0 else "", func(): _client.turn_action("end"))
	buttons.append(end)
	for b in buttons:
		b.custom_minimum_size.y = 44
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 16)
		b.clip_text = true
		actions.add_child(b)


func _ap_pips(ap: int, ap_max: int) -> Control:
	var c := Control.new()
	var n := maxi(ap_max, ap)
	c.custom_minimum_size = Vector2(n * 22, 22)
	c.draw.connect(func():
		for i in n:
			var center := Vector2(11 + i * 22, 11)
			c.draw_circle(center, 8, Palette.GOLD if i < ap else Palette.BG_DEEP)
			c.draw_arc(center, 8, 0, TAU, 20, Palette.GOLD_DIM, 1.5, true))
	c.tooltip_text = "Points d'action restants"
	return c


func _dice_row() -> Control:
	var dice := HBoxContainer.new()
	dice.add_theme_constant_override("separation", 6)
	for expr in ["d20", "d12", "d10", "d8", "d6", "d4"]:
		var b := UIKit.button(expr, "", _roll.bind(Protocol.TO_ALL, expr, ""))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 42
		dice.add_child(b)
	return dice


## Barre du bas : valeurs et capacités équipées.
func _refresh_hud() -> void:
	if _hud == null:
		return
	var sheet := _client.my_character()
	if sheet.is_empty():
		return
	var content := _client.content
	var cls := Rules.get_class_def(content, String(sheet.get("class_id", "")))
	_portrait.set_data(sheet.get("portrait", {}), Color(String(cls.get("color", sheet.get("pawn", {}).get("color", "#7a6e93")))))
	_portrait.ko = int(sheet.get("hp", 1)) <= 0
	_name_label.text = "%s  ·  niv. %d" % [sheet.get("name", ""), int(sheet.get("level", 1))]
	_gold_label.text = str(int(sheet.get("gold", 0)))
	_hp_bar.set_values(int(sheet.get("hp", 0)), int(sheet.get("hp_max", 1)))
	_res_bar.caption = String(sheet.get("res_name", "Énergie"))
	_res_bar.visible = int(sheet.get("res_max", 0)) > 0
	_res_bar.set_values(int(sheet.get("res", 0)), int(sheet.get("res_max", 1)))
	var pending: Dictionary = sheet.get("pending", {})
	_sheet_badge.visible = int(pending.get("stat_points", 0)) > 0 or int(pending.get("picks", 0)) > 0
	_sheet_badge.queue_redraw()
	var abilities := Rules.usable_abilities(sheet, content)
	_ult_bar.visible = abilities.any(func(a): return a.get("ultimate", false))
	_ult_bar.set_values(int(sheet.get("ult", 0)), 100)
	UIKit.clear(_abilities_row)
	if abilities.is_empty():
		_abilities_row.add_child(UIKit.label("Aucune capacité équipée (voir la fiche).", "MutedLabel", true))
	for a in abilities.slice(0, 6):
		_abilities_row.add_child(_ability_button(a, sheet))


func _ability_button(a: Dictionary, sheet: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(56, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = "%s — %s" % [a.get("name", ""), Effects.ability_costs(a, String(sheet.get("res_name", "Énergie")))]
	var col := GameUI.ability_color(a)
	var reason := _ability_block(a)
	var cd := int(sheet.get("cooldowns", {}).get(String(a.get("id", "")), 0))
	var ult := bool(a.get("ultimate", false))
	var charge := int(sheet.get("ult", 0))
	var short := String(a.get("short", a.get("name", "")))
	var cost := maxi(0, int(a.get("cost", 0)) - (int(a.get("rank", 1)) - 1))
	var icon_name := String(a.get("icon", "star"))
	var face := Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.draw.connect(func():
		var r := Rect2(Vector2.ZERO, face.size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.8)
		sb.border_color = col.darkened(0.1) if reason == "" else Palette.BORDER
		sb.set_border_width_all(2 if ult else 1)
		sb.set_corner_radius_all(10)
		face.draw_style_box(sb, r)
		if ult and charge < 100:
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(Palette.ULT, 0.22)
			fill.set_corner_radius_all(10)
			var h := r.size.y * charge / 100.0
			face.draw_style_box(fill, Rect2(Vector2(0, r.size.y - h), Vector2(r.size.x, h)))
		var isz := minf(r.size.x, r.size.y) * 0.46
		Icons.paint(face, icon_name, Rect2(Vector2((r.size.x - isz) * 0.5, 5), Vector2(isz, isz)), col if reason == "" else col.darkened(0.45))
		var font := get_theme_font("font", "StrongLabel")
		var fs := 12
		var tw := font.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 4, fs).x
		face.draw_string(font, Vector2(maxf(2, (r.size.x - tw) * 0.5), r.size.y - 16), short, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 4, fs, Palette.TEXT if reason == "" else Palette.FAINT)
		var sub := ("%d %%" % charge) if ult and charge < 100 else (str(cost) if cost > 0 else "")
		if sub != "":
			var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			face.draw_string(font, Vector2((r.size.x - sw) * 0.5, r.size.y - 4), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.ULT if ult else Palette.MANA.lightened(0.3))
		if cd > 0:
			face.draw_rect(r, Color(0, 0, 0, 0.5))
			var t := str(cd)
			var cw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			face.draw_string(font, Vector2((r.size.x - cw) * 0.5, r.size.y * 0.5 + 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Palette.TEXT))
	b.add_child(face)
	b.flat = true
	b.pressed.connect(_open_ability.bind(a))
	return b


## Pourquoi une capacité ne peut pas être utilisée maintenant ("" si elle le peut).
func _ability_block(a: Dictionary) -> String:
	var sheet := _client.my_character()
	var phase := _client.phase
	if phase.get("turns", false) and not _client.is_my_turn():
		return "Ce n'est pas votre tour."
	if int(sheet.get("hp", 1)) <= 0:
		return "Vous êtes hors de combat."
	for e in sheet.get("effects", []):
		if String(e.get("id", "")) == "silence":
			return "Vous êtes réduit au silence."
	var cost := maxi(0, int(a.get("cost", 0)) - (int(a.get("rank", 1)) - 1))
	if cost > int(sheet.get("res", 0)):
		return "Pas assez de %s (%d nécessaires, %d restants)." % [sheet.get("res_name", "ressource"), cost, int(sheet.get("res", 0))]
	if a.get("ultimate", false) and int(sheet.get("ult", 0)) < 100:
		return "Ultime pas encore chargé (%d %%). La jauge se remplit en combat." % int(sheet.get("ult", 0))
	var cd := int(sheet.get("cooldowns", {}).get(String(a.get("id", "")), 0))
	if cd > 0:
		return "En recharge : encore %d tour%s." % [cd, "s" if cd > 1 else ""]
	if phase.get("turns", false) and int(phase.get("ap", 0)) < int(a.get("ap", 1)):
		return "Pas assez de points d'action (%d nécessaire%s)." % [int(a.get("ap", 1)), "s" if int(a.get("ap", 1)) > 1 else ""]
	var cond: Dictionary = a.get("conditions", {})
	if cond.has("self_hp_below") and int(sheet.get("hp", 0)) * 100 >= int(cond.self_hp_below) * int(sheet.get("hp_max", 1)):
		return "Utilisable seulement sous %d %% de PV." % int(cond.self_hp_below)
	return ""


# ---------------------------------------------------------------------------
# Actions et ciblage
# ---------------------------------------------------------------------------

func _open_ability(a: Dictionary) -> void:
	var sheet := _client.my_character()
	var panel := _open_overlay("ability", String(a.get("name", "Capacité")), String(a.get("icon", "star")))
	panel.body.add_child(GameUI.ability_card(a, _client.content, String(sheet.get("res_name", "Énergie"))))
	var reason := _ability_block(a)
	if reason != "":
		var l := UIKit.label(reason, "StrongLabel", true)
		l.add_theme_color_override("font_color", Palette.WARN)
		panel.body.add_child(l)
	var target := String(a.get("target", "enemy"))
	var needs := target in ["enemy", "ally", "any"] or (target.begins_with("area") and int(a.get("range", 0)) > 0)
	var use := UIKit.button("Utiliser" + (" (choisir la cible)" if needs else ""), "PrimaryButton", func():
		_close_overlay()
		var payload := {"action": "ability", "id": String(a.get("id", "")), "label": String(a.get("name", "")), "kind": target}
		if needs:
			_start_target(payload)
		else:
			_client.turn_action("ability", "", 0, {"id": String(a.get("id", ""))}))
	use.custom_minimum_size.y = 56
	use.disabled = reason != ""
	panel.body.add_child(use)
	panel.body.add_child(GameUI.hint("Cibles : %s. Portée en cases (déplacements en diagonale comptés comme 1)." % Content.TARGET_NAMES.get(target, target)))


func _start_target(action: Dictionary) -> void:
	_pending = action
	_map_view.target_mode = true
	_map_view.reachable = {}
	var ids: Array = []
	var me := _client.my_token()
	var kind := String(action.get("kind", "enemy"))
	for t in _client.map.get("tokens", []):
		if String(t.get("kind", "")) == "object":
			continue
		var ally := String(t.get("kind", "")) == "pc" or String(t.get("side", "")) == "players"
		var ko := int(t.get("hp_max", 0)) > 0 and int(t.get("hp", 1)) <= 0
		match kind:
			"enemy", "area_enemy":
				if not ally and not ko:
					ids.append(t.id)
			"ally", "area_ally":
				if ally:
					ids.append(t.id)
			_:
				ids.append(t.id)
	if kind in ["ally", "any"] and not me.is_empty() and not ids.has(me.id):
		ids.append(me.id)
	_map_view.target_ids = ids
	_show_view("map")
	_refresh_turn_bar()
	_map_view.queue_redraw()


func _cancel_target() -> void:
	_pending = {}
	_map_view.target_mode = false
	_map_view.target_ids = []
	_refresh_turn_bar()
	_refresh_reachable()


func _on_target_picked(token_id: String) -> void:
	var action := _pending
	if not action.is_empty() and not _map_view.target_ids.has(token_id):
		_feed.add_notice("Cette cible ne convient pas : choisissez un pion entouré de rouge.", Palette.WARN)
		return
	_cancel_target()
	match String(action.get("action", "")):
		"quick", "power":
			_client.turn_action(String(action.action), token_id, 0)
		"ability":
			_client.turn_action("ability", token_id, 0, {"id": String(action.get("id", ""))})


# ---------------------------------------------------------------------------
# Panneaux superposés
# ---------------------------------------------------------------------------

func _open_overlay(kind: String, title: String, icon_name: String = "") -> OverlayPanel:
	_close_overlay()
	_overlay = OverlayPanel.new(title, _wide, icon_name)
	_overlay_kind = kind
	_overlay.closed.connect(func():
		_overlay = null
		_overlay_kind = "")
	add_child(_overlay)
	return _overlay


func _close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.close()
	_overlay = null
	_overlay_kind = ""


func _refresh_overlay(kind: String) -> void:
	if _overlay_kind != kind or _overlay == null:
		return
	match kind:
		"sheet":
			_fill_sheet()
		"inventory":
			_fill_inventory()
		"journal":
			_fill_journal()


func _open_sheet() -> void:
	_open_overlay("sheet", "Ma fiche", "person")
	_fill_sheet()


func _fill_sheet() -> void:
	_overlay.clear_body()
	var sheet := _client.my_character()
	if sheet.is_empty():
		return
	_overlay.body.add_child(CharacterSheet.new(sheet, _client.content, {"mine": true, "act": _on_sheet_act}))
	if _client.can_edit_sheet() and not _client.game_started():
		_overlay.body.add_child(UIKit.button("Refaire avec l'assistant", "", _open_wizard))


func _on_sheet_act(action: String, data: Dictionary) -> void:
	match action:
		"level":
			_client.level_choice(data)
		"equip_ability":
			_client.equip_ability(String(data.id), bool(data.equipped))
		"edit_story":
			var panel := _open_overlay("story", "Mon histoire", "journal")
			_open_story_editor(panel.body)


func _on_inventory_act(action: String, data: Dictionary) -> void:
	match action:
		"item":
			_client.item_action(String(data.action), String(data.uid), {"to": data.get("to", "")})
		"take_loot":
			_client.take_loot(String(data.uid))


func _open_inventory(tab: String = "bag") -> void:
	_inventory_tab = tab
	_open_overlay("inventory", "Inventaire", "bag")
	_fill_inventory()


func _fill_inventory() -> void:
	_overlay.clear_body()
	var others: Array = []
	for p in _client.players:
		if p.id != _client.me.get("id", "") and not _client.character(p.id).is_empty():
			others.append({"id": p.id, "name": _client.character(p.id).get("name", p.name)})
	var view := InventoryView.new(_client.my_character(), _client.content, {"loot": _client.loot, "others": others, "tab": _inventory_tab, "act": _on_inventory_act})
	_overlay.body.add_child(view)


func _open_journal(tab: String = "quests") -> void:
	_journal_tab = tab
	_open_overlay("journal", "Journal", "journal")
	_fill_journal()


func _fill_journal() -> void:
	_overlay.clear_body()
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	_overlay.body.add_child(tabs)
	for spec in [["quests", "Quêtes"], ["group", "Groupe"], ["codex", "Codex"], ["settings", "Réglages"]]:
		var b := UIKit.button(spec[1], "PrimaryButton" if _journal_tab == spec[0] else "", func():
			_journal_tab = spec[0]
			_fill_journal())
		tabs.add_child(b)
	var body := _overlay.body
	match _journal_tab:
		"quests":
			_journal_quests(body)
		"group":
			_journal_group(body)
		"codex":
			body.add_child(CodexView.new(_client.universe))
		"settings":
			_journal_settings(body)


func _journal_quests(body: VBoxContainer) -> void:
	var quests := _client.quests.duplicate()
	if quests.is_empty():
		body.add_child(UIKit.label("Aucune quête pour l'instant. Le MJ vous en confiera au fil de l'aventure.", "MutedLabel", true))
		return
	quests.sort_custom(func(a, b):
		var ra: int = ({"active": 0, "done": 1, "failed": 2} as Dictionary).get(String(a.status), 3) * 2 + (0 if a.kind == "main" else 1)
		var rb: int = ({"active": 0, "done": 1, "failed": 2} as Dictionary).get(String(b.status), 3) * 2 + (0 if b.kind == "main" else 1)
		return ra < rb)
	for q in quests:
		var active: bool = q.status == "active"
		var card := UIKit.card(body, "", "HighlightPanel" if active and q.kind == "main" else ("CardPanel" if active else "InsetPanel"))
		var head := HBoxContainer.new()
		card.add_child(head)
		head.add_child(GameUI.icon_badge("crown" if q.kind == "main" else "journal", Palette.GOLD if active else Palette.FAINT, 32))
		var t := UIKit.label(String(q.title), "HeadingLabel", true)
		head.add_child(t)
		var status: Array = {"active": ["En cours", Palette.GOLD], "done": ["Réussie", Palette.OK], "failed": ["Échouée", Palette.DANGER]}.get(String(q.status), ["?", Palette.MUTED])
		card.add_child(UIKit.chip("%s · %s" % ["Quête principale" if q.kind == "main" else "Quête secondaire", status[0]], status[1]))
		if String(q.get("giver", "")) != "":
			card.add_child(UIKit.label("Confiée par " + String(q.giver), "MutedLabel", true))
		if String(q.get("description", "")) != "":
			card.add_child(UIKit.label(String(q.description), "", true))
		for o in q.get("objectives", []):
			var l := UIKit.label(("◆  " if o.done else "◇  ") + String(o.text), "", true)
			l.add_theme_color_override("font_color", Palette.OK if o.done else Palette.TEXT)
			card.add_child(l)
		var rw: Dictionary = q.get("rewards", {})
		var parts: PackedStringArray = []
		if int(rw.get("xp", 0)) > 0:
			parts.append("%d XP" % int(rw.xp))
		if int(rw.get("gold", 0)) > 0:
			parts.append("%d or" % int(rw.gold))
		for it in rw.get("items", []):
			parts.append(String(it.get("def", {}).get("name", "objet")) if it.has("def") else "un objet")
		if not parts.is_empty():
			var l := UIKit.label("Récompense : " + ", ".join(parts), "StrongLabel", true)
			l.add_theme_color_override("font_color", Palette.ULT)
			card.add_child(l)


func _journal_group(body: VBoxContainer) -> void:
	var mj := HBoxContainer.new()
	body.add_child(mj)
	var mj_name := UIKit.label(String(_client.session.get("mj_name", "MJ")), "StrongLabel")
	mj_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mj_name.add_theme_color_override("font_color", Palette.GOLD)
	mj.add_child(mj_name)
	mj.add_child(UIKit.label("Maître du jeu", "MutedLabel"))
	for p in _client.players:
		var sheet := _client.character(p.id)
		var card := UIKit.card(body, "", "InsetPanel")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		if not sheet.is_empty():
			row.add_child(Portrait.for_sheet(sheet, _client.content, 48))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var title := String(p.name) + ("  (vous)" if p.id == _client.me.get("id", "") else "")
		if not sheet.is_empty():
			title = "%s  —  %s" % [sheet.get("name", ""), title]
		col.add_child(UIKit.label(title, "StrongLabel", true))
		col.add_child(UIKit.chip("En ligne" if p.online else "Hors ligne", Palette.OK if p.online else Palette.FAINT))
		if not sheet.is_empty():
			var hp := ResourceBar.new("PV", Palette.HP, 16)
			hp.set_values(int(sheet.get("hp", 0)), int(sheet.get("hp_max", 1)), false)
			col.add_child(hp)
			if not (sheet.get("effects", []) as Array).is_empty():
				col.add_child(GameUI.status_row(sheet.effects, 18))


func _journal_settings(body: VBoxContainer) -> void:
	var sound := UIKit.card(body, "Musique")
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
	sound.add_child(UIKit.label(("En cours : " + Music.title()) if Music.playing else "Pas de musique pour l'instant (c'est le MJ qui choisit).", "MutedLabel", true))
	var conn := UIKit.card(body, "Connexion")
	var params := Net.join_params()
	conn.add_child(UIKit.label("%s\nHôte : %s  ·  ping %s" % [Net.state_label(), params.get("ip", "?"), UIKit.ping_text(Net.get_peer_rtt(1))], "MutedLabel", true))
	body.add_child(UIKit.button("Comment jouer ?", "", _open_help))
	body.add_child(UIKit.button("Quitter la partie", "DangerButton", _confirm_leave))


## Aide intégrée : l'essentiel pour quelqu'un qui n'a jamais joué.
func _open_help() -> void:
	var panel := _open_overlay("help", "Comment jouer ?", "question")
	_help_text(panel.body)


func _help_text(body: VBoxContainer) -> void:
	for spec in [
		["chat", "Raconter et parler", "Le MJ raconte l'histoire dans le Récit. Vous répondez en Message (au groupe ou au MJ en privé), ou en Action : décrivez librement ce que tente votre personnage. Les boutons « Examiner », « Fouiller »… ne sont que des idées."],
		["run", "Votre tour", "Quand le téléphone vibre et affiche « C'est votre tour ! », vous avez des points d'action (PA). Déplacez-vous en touchant une case dorée, attaquez, utilisez une capacité, puis « Terminer mon tour »."],
		["sword", "Combattre", "Attaque rapide (1 PA) ou puissante (2 PA, plus de dégâts mais moins précise). Le jeu lance les dés et calcule tout : vous voyez les dégâts en rouge, les soins en vert."],
		["star", "Capacités", "Vos capacités sont dans la barre du bas. Touchez-en une pour voir ce qu'elle fait, ce qu'elle coûte et pourquoi elle est indisponible. L'ultime se charge pendant les combats."],
		["bag", "Sac, fiche, journal", "Le sac contient vos objets (touchez-en un pour l'équiper ou l'utiliser) et le coffre du groupe. La fiche montre votre personnage et vos montées de niveau. Le journal garde vos quêtes."],
		["heart", "Points de vie", "À 0 PV, votre personnage est hors de combat (pas forcément mort : le MJ décide). Le repos et les soins font remonter les PV."],
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		body.add_child(row)
		var badge := GameUI.icon_badge(spec[0], Palette.GOLD, 40)
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(badge)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		col.add_child(UIKit.label(spec[1], "StrongLabel", true))
		col.add_child(UIKit.label(spec[2], "", true))


func _open_story_editor(container: VBoxContainer) -> void:
	UIKit.clear(container)
	var sheet := _client.my_character()
	if sheet.is_empty():
		sheet = CharacterData.create(_client.universe, String(_client.me.get("id", "")), String(_client.me.get("id", "")), String(_client.me.get("name", "")), _client.content)
	var editor := CharacterEditor.new(sheet, _client.universe)
	var holder: Control = editor
	if container == _creation:
		var s := TouchScroll.new()
		s.add_child(editor)
		holder = s
	editor.saved.connect(func(data):
		_client.save_character(data)
		_wizard_open = false
		if container == _creation:
			UIKit.clear(container)
		else:
			_close_overlay()
		_refresh_all())
	editor.cancelled.connect(func():
		_wizard_open = false
		if container == _creation:
			UIKit.clear(container)
		else:
			_close_overlay()
		_refresh_all())
	container.add_child(holder)


# ---------------------------------------------------------------------------
# Connexion et erreurs
# ---------------------------------------------------------------------------

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
	_refresh_outbox()


func _refresh_outbox() -> void:
	if _outbox_label == null:
		return
	var n := _client.pending_count()
	_outbox_label.visible = n > 0
	_outbox_label.text = "%d envoi%s en cours…" % [n, "s" if n > 1 else ""]


func _on_command_failed(_req_id: String, error: String) -> void:
	_feed.add_notice("Impossible : " + error, Palette.DANGER)
	_toast(error)


## Message bref et non bloquant en haut de l'écran.
func _toast(text: String) -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("3a2425")
	sb.border_color = Palette.DANGER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, "", true)
	l.add_theme_color_override("font_color", Palette.TEXT)
	panel.add_child(l)
	add_child(panel)
	panel.position = Vector2(12, 70)
	panel.size.x = size.x - 24
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)


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
