extends Control
## Écran du joueur (pensé pour le téléphone, en portrait comme en paysage, et
## adapté au PC).
##
## Parcours : validation éventuelle par le MJ → assistant de création → salon
## « Vous êtes prêt ! » → la partie.
##
## La partie en trois zones :
##   - en haut : le lieu, la situation (phase, tour) et l'objectif en cours ;
##   - au centre : le récit (narration, messages, résultats) et la carte (sur
##     téléphone, un bouton bascule entre les deux ; sur PC, côte à côte) ;
##   - en bas, toujours visible : portrait, PV, ressource, jauge d'ultime, les
##     capacités équipées, l'indicateur de tour, et l'accès au sac, à la fiche,
##     au journal et à la discussion.
## En paysage (téléphone tourné), la barre du bas devient une colonne à droite
## et les actions de tour passent à côté de la carte.
## Les menus s'ouvrent en panneaux superposés faciles à fermer.

const WIDE_MIN := 900.0

var _client: SessionClient
var _wide := false
var _landscape := false
var _outer: VBoxContainer
var _notifier: Notifier
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
var _body: HBoxContainer
var _center_margin: MarginContainer
var _side: VBoxContainer
var _switch: HBoxContainer
var _switch_buttons := {}
var _feed_page: VBoxContainer
var _map_page: VBoxContainer
var _feed: FeedView
var _composer: Composer
var _quick_actions: HFlowContainer
var _ideas_menu: MenuButton
var _map_view: MapView
var _timeline: HBoxContainer
var _timeline_scroll: ScrollContainer
var _turn_bar: VBoxContainer
var _turn_panel: PanelContainer
var _map_row: HBoxContainer
var _view := "story"
var _unread := false

# Barre du bas
var _hud: PanelContainer
var _hud_col: VBoxContainer
var _hud_bottom: HBoxContainer
var _hud_sep: VSeparator
var _hud_buttons: HBoxContainer
var _hud_turn: Label
var _chat_badge: Label
var _unread_chat := 0
var _chat_feed: FeedView
var _portrait: Portrait
var _name_label: Label
var _hp_bar: ResourceBar
var _res_bar: ResourceBar
var _ult_bar: ResourceBar
var _gold_label: Label
var _abilities_row: GridContainer
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
var _prev_sheet := {}


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
	_outer = outer
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
	_notifier = Notifier.new()
	add_child(_notifier)

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
	_client.outbox_changed.connect(func():
		_refresh_outbox()
		if _client.phase.get("turns", false) and _client.is_my_turn():
			_refresh_turn_bar())
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
	# Corps : zone centrale (récit / carte) et, en paysage, colonne de droite.
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 0)
	_game.add_child(_body)
	_center = HBoxContainer.new()
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.add_theme_constant_override("separation", 8)
	_center_margin = MarginContainer.new()
	_center_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		_center_margin.add_theme_constant_override("margin_" + side, 6)
	_center_margin.add_child(_center)
	_body.add_child(_center_margin)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 0)
	_side.visible = false
	_body.add_child(_side)
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
	# Paysage : les idées d'actions tiennent dans un menu (le récit garde la place).
	_ideas_menu = MenuButton.new()
	_ideas_menu.text = "Idées d'actions…"
	_ideas_menu.flat = false
	_ideas_menu.theme_type_variation = "PrimaryButton"
	_ideas_menu.custom_minimum_size.y = 32
	_ideas_menu.add_theme_font_size_override("font_size", 14)
	_ideas_menu.visible = false
	var ideas := [["Examiner…", "J'examine "], ["Parler à…", "Je vais parler à "], ["Interagir avec…", "J'interagis avec "], ["Fouiller…", "Je fouille "], ["Se cacher", "Je me cache "], ["Action libre…", ""], ["Utiliser un objet (sac)", "@bag"]]
	for spec in ideas:
		_ideas_menu.get_popup().add_item(spec[0])
	_ideas_menu.get_popup().index_pressed.connect(func(i):
		if ideas[i][1] == "@bag":
			_open_inventory("bag")
		else:
			_composer.start_action(ideas[i][1]))
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(filler)
	filters.add_child(_ideas_menu)
	_feed = FeedView.new("", false)
	page.add_child(_feed)
	# Actions contextuelles : des idées, jamais une liste fermée.
	_quick_actions = HFlowContainer.new()
	_quick_actions.add_theme_constant_override("h_separation", 6)
	_quick_actions.add_theme_constant_override("v_separation", 6)
	page.add_child(_quick_actions)
	for spec in [["Examiner", "J'examine "], ["Parler à…", "Je vais parler à "], ["Interagir", "J'interagis avec "], ["Fouiller", "Je fouille "], ["Se cacher", "Je me cache "], ["Action libre…", ""]]:
		var b := UIKit.button(spec[0], "PrimaryButton" if spec[1] == "" else "", func(): _composer.start_action(spec[1]))
		b.custom_minimum_size.y = 34
		b.add_theme_font_size_override("font_size", 15)
		b.tooltip_text = "Décrivez librement ce que tente votre personnage : le MJ décide du résultat."
		_quick_actions.add_child(b)
	var use_item := UIKit.button("Utiliser un objet", "", _open_inventory.bind("bag"))
	use_item.custom_minimum_size.y = 34
	use_item.add_theme_font_size_override("font_size", 15)
	_quick_actions.add_child(use_item)
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
	_map_row = HBoxContainer.new()
	_map_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_row.add_theme_constant_override("separation", 6)
	page.add_child(_map_row)
	_map_view = MapView.new()
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.custom_minimum_size.y = 160
	_map_view.move_requested.connect(func(id, x, y): _client.move_pawn(id, x, y))
	_map_view.target_picked.connect(_on_target_picked)
	_map_view.token_selected.connect(_on_token_selected)
	_map_row.add_child(_map_view)
	_turn_panel = PanelContainer.new()
	_turn_panel.theme_type_variation = "InsetPanel"
	page.add_child(_turn_panel)
	_turn_bar = VBoxContainer.new()
	_turn_bar.add_theme_constant_override("separation", 6)
	_turn_panel.add_child(_turn_bar)
	return page


## Barre du bas : portrait, PV, ressource, ultime, or ; capacités ; sac, fiche, journal.
func _build_hud() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "NavPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	_hud_col = col
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
	# Indicateur de tour (combat) : « À vous · 2 PA » / « Tour de Loup ».
	_hud_turn = UIKit.label("", "StrongLabel")
	_hud_turn.add_theme_font_size_override("font_size", 14)
	_hud_turn.visible = false
	name_row.add_child(_hud_turn)
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
	_hud_bottom = bottom
	_abilities_row = GridContainer.new()
	_abilities_row.add_theme_constant_override("h_separation", 6)
	_abilities_row.add_theme_constant_override("v_separation", 6)
	_abilities_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_abilities_row)
	_hud_sep = VSeparator.new()
	bottom.add_child(_hud_sep)
	_hud_buttons = HBoxContainer.new()
	_hud_buttons.add_theme_constant_override("separation", 4)
	_hud_buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_hud_buttons)
	for spec in [["bag", "Sac", _open_inventory.bind("bag")], ["person", "Fiche", _open_sheet], ["journal", "Journal", _open_journal.bind("quests")], ["chat", "Discuter", _open_chat]]:
		var b := _icon_button(spec[0], spec[1], spec[2])
		_hud_buttons.add_child(b)
		if spec[0] == "chat":
			_chat_badge = UIKit.label("", "StrongLabel")
			_chat_badge.add_theme_font_size_override("font_size", 11)
			_chat_badge.add_theme_color_override("font_color", Palette.BG_DEEP)
			_chat_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var bsb := StyleBoxFlat.new()
			bsb.bg_color = Palette.ULT
			bsb.set_corner_radius_all(8)
			bsb.content_margin_left = 4
			bsb.content_margin_right = 4
			_chat_badge.add_theme_stylebox_override("normal", bsb)
			_chat_badge.position = Vector2(26, 0)
			_chat_badge.visible = false
			b.add_child(_chat_badge)
	return panel


## Bouton du bas : icône et petit libellé dessous (tient sur un téléphone).
func _icon_button(icon_name: String, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(40, 60)
	b.tooltip_text = text
	var face := Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.draw.connect(func():
		var isz := 24.0
		Icons.paint(face, icon_name, Rect2(Vector2((face.size.x - isz) * 0.5, 8), Vector2(isz, isz)), Palette.GOLD)
		var font := get_theme_font("font", "StrongLabel")
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		face.draw_string(font, Vector2((face.size.x - w) * 0.5, face.size.y - 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.TEXT))
	b.add_child(face)
	b.pressed.connect(on_pressed)
	return b


# ---------------------------------------------------------------------------
# Disposition et états
# ---------------------------------------------------------------------------

func _layout() -> void:
	var vp := get_viewport_rect().size
	_wide = vp.x >= WIDE_MIN and not App.is_mobile()
	_landscape = App.is_mobile() and vp.x > vp.y * 1.15
	_apply_safe_area()
	if _switch == null:
		return
	_arrange(_landscape)
	_switch.visible = not _wide
	if _wide:
		_map_page.visible = true
		_feed_page.visible = true
	else:
		_show_view(_view)


## Marges des zones système (encoche, barre de navigation) sur téléphone.
func _apply_safe_area() -> void:
	if _outer == null or not App.is_mobile() or OS.get_cmdline_user_args().has("--force-mobile"):
		return
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if safe.size.x <= 0 or win.x <= 0:
		return
	var k := get_viewport_rect().size.x / float(win.x)
	_outer.offset_left = maxf(0.0, safe.position.x * k)
	_outer.offset_top = maxf(0.0, safe.position.y * k)
	_outer.offset_right = -maxf(0.0, (win.x - safe.end.x) * k)
	_outer.offset_bottom = -maxf(0.0, (win.y - safe.end.y) * k)


## Portrait : barre du bas et actions sous la carte. Paysage : colonne de droite
## (bascule Récit/Carte, personnage, capacités, boutons) et actions à côté de la carte.
func _arrange(landscape: bool) -> void:
	var in_side := _hud.get_parent() == _side
	if landscape and not in_side:
		_switch.get_parent().remove_child(_switch)
		_side.add_child(_switch)
		_hud.get_parent().remove_child(_hud)
		_side.add_child(_hud)
		_hud.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_hud_bottom.remove_child(_abilities_row)
		_hud_col.add_child(_abilities_row)
		_hud_bottom.remove_child(_hud_buttons)
		_hud_col.add_child(_hud_buttons)
		_hud_bottom.visible = false
		_turn_panel.get_parent().remove_child(_turn_panel)
		_map_row.add_child(_turn_panel)
		_turn_panel.custom_minimum_size.x = 190
		_side.custom_minimum_size.x = 250
		_side.visible = true
	elif not landscape and in_side:
		_side.remove_child(_switch)
		_game.add_child(_switch)
		_game.move_child(_switch, 0)
		_side.remove_child(_hud)
		_game.add_child(_hud)
		_hud.size_flags_vertical = Control.SIZE_FILL
		_hud_col.remove_child(_abilities_row)
		_hud_bottom.add_child(_abilities_row)
		_hud_bottom.move_child(_abilities_row, 0)
		_hud_col.remove_child(_hud_buttons)
		_hud_bottom.add_child(_hud_buttons)
		_hud_bottom.visible = true
		_map_row.remove_child(_turn_panel)
		_map_page.add_child(_turn_panel)
		_turn_panel.custom_minimum_size.x = 0
		_side.visible = false
	_hud_buttons.alignment = BoxContainer.ALIGNMENT_CENTER if landscape else BoxContainer.ALIGNMENT_BEGIN
	_quick_actions.visible = not landscape
	_ideas_menu.visible = landscape
	_timeline_scroll.custom_minimum_size.y = 56 if landscape else 66
	_refresh_hud()
	_refresh_turn_bar()
	_refresh_header()


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
	Music.set_menu(not started)
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
		if _landscape:
			# Paysage : pas de place pour une ligne de plus, l'objectif suit la situation.
			_situation_label.text += "   ◆ " + (next if next != "" else String(q.title))
	if _landscape:
		_objective.visible = false


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
		_client.create_character(String(payload.class_id), payload.alloc, payload.choices, payload.identity, String(payload.get("species_id", "")))
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
	_prev_sheet = _client.my_character().duplicate(true)
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
	if _chat_feed != null and is_instance_valid(_chat_feed):
		_chat_feed.add_message(m)
	var from_other := String(m.get("from", "")) != _map_view.my_id
	if from_other and kind in [Protocol.KIND_CHAT, Protocol.KIND_NARRATION, Protocol.KIND_ACTION] and _overlay_kind != "chat" and not _wide and _view != "story":
		_unread_chat += 1
		_refresh_chat_badge()
	if from_other and kind == Protocol.KIND_CHAT and String(m.get("to", "")) == _map_view.my_id and _overlay_kind != "chat":
		_notifier.push("Message privé de %s" % m.get("from_name", "?"), "chat")
	_refresh_outbox()


func _refresh_chat_badge() -> void:
	if _chat_badge == null:
		return
	_chat_badge.visible = _unread_chat > 0
	_chat_badge.text = str(mini(_unread_chat, 99))


## Discussion : si le récit est à l'écran, on va droit à la saisie ; sinon un
## panneau superposé montre les messages et la saisie, sans quitter la carte
## (discuter ne coûte aucun point d'action et n'interrompt pas le combat).
func _open_chat() -> void:
	_unread_chat = 0
	_refresh_chat_badge()
	if _wide or (_view == "story" and not _landscape):
		_show_view("story")
		_composer.focus_text()
		return
	var panel := _open_overlay("chat", "Discussion", "chat")
	_chat_feed = FeedView.new(_map_view.my_id, false)
	_chat_feed.custom_minimum_size.y = maxf(180.0, get_viewport_rect().size.y * (0.42 if not _landscape else 0.5))
	_chat_feed.set_messages(_client.messages)
	_chat_feed.set_filter("story")
	panel.body.add_child(_chat_feed)
	var composer := Composer.new(
		[["Au groupe", Protocol.TO_ALL], ["Au MJ (privé)", Protocol.TO_MJ]],
		[["Jet visible", Protocol.TO_ALL], ["Jet secret (MJ)", Protocol.TO_MJ]])
	composer.send_message.connect(func(to, text): _client.send_chat(to, text))
	composer.send_action.connect(func(to, text): _client.declare_action(to, text))
	composer.send_roll.connect(_roll)
	panel.body.add_child(composer)
	panel.body.add_child(GameUI.hint("Parler est gratuit : aucun point d'action dépensé, le combat continue."))
	panel.closed.connect(func(): _chat_feed = null)


func _on_message_updated(m: Dictionary) -> void:
	_feed.update_message(m)
	if _tray_wait.get("message_id", "") == m.get("id", "") and not m.get("roll", {}).is_empty():
		_tray.finish(m.roll, String(_tray_wait.get("label", "")))
		_tray_wait = {}


func _on_characters() -> void:
	var sheet := _client.my_character()
	if not _prev_sheet.is_empty() and not sheet.is_empty() and _client.game_started():
		_notify_changes(_prev_sheet, sheet)
	_prev_sheet = sheet.duplicate(true)
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


## Notifications nées de l'état confirmé par l'hôte (jamais d'une prévision locale).
func _notify_changes(old: Dictionary, new: Dictionary) -> void:
	var dhp := int(new.get("hp", 0)) - int(old.get("hp", 0))
	if dhp > 0:
		_notifier.push("Vous récupérez %d PV." % dhp, "heal")
	elif dhp < 0 and int(new.get("hp", 0)) <= 0:
		_notifier.push("Vous êtes hors de combat !", "danger")
	var dgold := int(new.get("gold", 0)) - int(old.get("gold", 0))
	var before := {}
	for it in old.get("inventory", []):
		before[String(it.get("uid", ""))] = int(it.get("qty", 1))
	var got: Array = []
	for it in new.get("inventory", []):
		var uid := String(it.get("uid", ""))
		var gained := int(it.get("qty", 1)) - int(before.get(uid, 0))
		if gained > 0:
			var shown: Dictionary = it.duplicate()
			shown.qty = gained
			shown.equipped = false
			got.append(shown)
	if not got.is_empty():
		_show_loot(got, maxi(0, dgold))
	elif dgold > 0:
		_notifier.push("+%d pièces d'or" % dgold, "gold")
	var known_before: Array = old.get("known", old.get("abilities", []))
	for a in new.get("known", new.get("abilities", [])):
		var aid := String(a.get("id", a)) if a is Dictionary else String(a)
		var had := known_before.any(func(b): return (String(b.get("id", "")) if b is Dictionary else String(b)) == aid)
		if not had:
			var def: Dictionary = a if a is Dictionary else Content.get_entry(_client.content, "abilities", aid)
			_notifier.push("Nouvelle compétence apprise : %s" % def.get("name", aid), "magic", String(def.get("icon", "sparkle")))
	if int(new.get("ult", 0)) >= 100 and int(old.get("ult", 0)) < 100:
		_notifier.push("Votre ultime est disponible !", "ult")
		Input.vibrate_handheld(60)
	var effects_before := (old.get("effects", []) as Array).map(func(e): return String(e.get("id", "")))
	for e in new.get("effects", []):
		if not effects_before.has(String(e.get("id", ""))):
			_notifier.push("Effet : %s" % e.get("name", "?"), "magic", String(e.get("icon", "sparkle")))


## « Butin ! » : ce qu'on vient de recevoir (monstre vaincu, quête, cadeau du MJ),
## avec les cases d'objets. Ne bloque rien ; se ferme seule ou d'un toucher.
func _show_loot(items: Array, gold: int) -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 45
	add_child(holder)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "HighlightPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var title := UIKit.label("Butin !", "TitleLabel")
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(GameUI.ornament(16))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 8)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	col.add_child(flow)
	for it in items.slice(0, 8):
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.custom_minimum_size.x = 84
		box.add_child(GameUI.item_slot(it, 56))
		box.get_child(0).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var n := UIKit.label(String(it.get("name", "?")), "StrongLabel", true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.add_theme_font_size_override("font_size", 13)
		n.add_theme_color_override("font_color", Content.rarity_color(String(it.get("rarity", "commun"))).lightened(0.15))
		box.add_child(n)
		flow.add_child(box)
	if gold > 0:
		var g := HBoxContainer.new()
		g.alignment = BoxContainer.ALIGNMENT_CENTER
		g.add_child(Icons.new("coin", Palette.GOLD, 22))
		var gl := UIKit.label("+%d pièces d'or" % gold, "StrongLabel")
		gl.add_theme_color_override("font_color", Palette.GOLD)
		g.add_child(gl)
		col.add_child(g)
	col.add_child(UIKit.label("Rangé dans votre sac.", "MutedLabel"))
	col.get_child(col.get_child_count() - 1).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var close := func():
		if is_instance_valid(holder) and not holder.is_queued_for_deletion():
			var tw2 := holder.create_tween()
			tw2.tween_property(panel, "modulate:a", 0.0, 0.2)
			tw2.tween_callback(holder.queue_free)
	var ok := UIKit.button("OK", "", close)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ok)
	var bag := UIKit.button("Voir le sac", "PrimaryButton", func():
		close.call()
		_open_inventory("bag"))
	bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bag)
	Input.vibrate_handheld(60)
	await get_tree().process_frame
	var w := minf(size.x - 24, 420.0)
	panel.size = Vector2(w, 0)
	panel.custom_minimum_size.x = w
	panel.position = Vector2((size.x - w) * 0.5, size.y * 0.22)
	panel.pivot_offset = Vector2(w * 0.5, 60)
	panel.scale = Vector2(0.85, 0.85)
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.chain().tween_interval(6.0)
	tw.chain().tween_callback(close)


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
			# Combattant hors de vue (brouillard) : on sait qu'il est là, sans plus.
			t = {"id": String(rotated[i]), "name": "Hors de vue", "kind": "unknown", "color": "#3a3a49"}
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
		p = Portrait.new({}, Color(String(t.get("color", "#8a6a4a"))), 36, {"monster": "skull", "unknown": "question"}.get(String(t.get("kind", "")), "person"))
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


## Panneau sous la carte (à côté en paysage) : actions de base pendant votre
## tour avec leur coût en PA, sinon qui joue. Les actions impossibles sont grisées.
func _refresh_turn_bar() -> void:
	if _turn_bar == null:
		return
	UIKit.clear(_turn_bar)
	var phase := _client.phase
	if not _pending.is_empty():
		var l := UIKit.label("Choisissez la cible de « %s » : touchez un pion entouré de rouge." % _pending.get("label", ""), "StrongLabel", true)
		l.add_theme_color_override("font_color", Palette.DANGER.lightened(0.35))
		_turn_bar.add_child(l)
		if _map_view.target_ids.is_empty():
			_turn_bar.add_child(GameUI.hint("Aucune cible à portée : rapprochez-vous ou annulez."))
		_turn_bar.add_child(UIKit.button("Annuler", "", _cancel_target))
		return
	if not phase.get("turns", false):
		var move: String = {"free": "Déplacement libre : touchez une case pour y aller.", "none": "Pas de déplacement pendant cette phase."}.get(String(phase.get("move", "free")), "")
		_turn_bar.add_child(UIKit.label("%s — %s" % [phase.get("name", ""), move], "MutedLabel", true))
		_turn_bar.add_child(_dice_row())
		return
	if not _client.is_my_turn():
		var current := MapData.token(_client.map, String(phase.get("current", "")))
		_turn_bar.add_child(UIKit.label("Au tour de %s. Vous pouvez discuter en attendant." % current.get("name", "?") if not current.is_empty() else "Un combattant hors de vue joue…", "MutedLabel", true))
		_turn_bar.add_child(_dice_row())
		return
	var busy := _client.pending_count() > 0
	var ap := int(phase.get("ap", 0))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_turn_bar.add_child(head)
	var title := UIKit.label("À vous !", "HeadingLabel")
	head.add_child(title)
	head.add_child(_ap_pips(ap, int(phase.get("ap_max", 2))))
	var info := ""
	if phase.get("move", "") == "limit":
		if phase.get("type", "") == "combat":
			info = ("%d case%s" % [int(phase.moves_left), "s" if int(phase.moves_left) > 1 else ""]) if int(phase.moves_left) > 0 else "bouger : %d PA" % int(Content.rule(_client.content, "move_ap"))
		else:
			info = "%d case%s" % [int(phase.moves_left), "s" if int(phase.moves_left) > 1 else ""]
	var il := UIKit.label(info, "MutedLabel")
	il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(il)
	var end := UIKit.button("Fin du tour  ›", "PrimaryButton" if ap <= 0 else "", func(): _client.turn_action("end"))
	end.custom_minimum_size = Vector2(0, 40)
	end.add_theme_font_size_override("font_size", 15)
	end.tooltip_text = "Terminer mon tour"
	end.disabled = busy
	if not _landscape:
		head.add_child(end)
	var r := Content.rules(_client.content)
	var actions := GridContainer.new()
	actions.columns = 1 if _landscape else 2
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	_turn_bar.add_child(actions)
	var buttons: Array = []
	if phase.get("type", "") == "combat":
		var reach := int(Rules.attack_profile(_client.my_character(), _client.content, Rules.weapons(_client.my_character())[0]).get("range", 1))
		for spec in [["Attaque rapide", "quick", int(r.quick_attack_ap), "Une attaque avec votre arme."], ["Attaque puissante", "power", int(r.power_attack_ap), "−2 au toucher, +50 % de dégâts."]]:
			var b := UIKit.button("%s · %d PA" % [spec[0], spec[2]], "PrimaryButton" if spec[1] == "quick" and ap >= int(spec[2]) else "", _start_target.bind({"action": spec[1], "label": spec[0], "kind": "enemy", "range": reach}))
			b.disabled = ap < int(spec[2]) or busy
			b.tooltip_text = spec[3]
			buttons.append(b)
		var defend := UIKit.button("Se défendre · %d PA" % int(r.defend_ap), "", func(): _client.turn_action("defend"))
		defend.disabled = ap < int(r.defend_ap) or busy
		defend.tooltip_text = "+3 Défense jusqu'à votre prochain tour."
		buttons.append(defend)
		var item := UIKit.button("Objet · %d PA" % int(r.item_ap), "", _open_inventory.bind("bag"))
		item.disabled = ap < int(r.item_ap) or busy
		item.tooltip_text = "Ouvrir le sac pour boire une potion ou utiliser un objet."
		buttons.append(item)
	for b in buttons:
		b.custom_minimum_size.y = 42 if not _landscape else 38
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.clip_text = true
		actions.add_child(b)
	if _landscape:
		end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_turn_bar.add_child(end)
	if busy:
		_turn_bar.add_child(GameUI.hint("Action envoyée, en attente de l'hôte…"))


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
	var dice := GridContainer.new()
	dice.columns = 3 if _landscape else 6
	dice.add_theme_constant_override("h_separation", 6)
	dice.add_theme_constant_override("v_separation", 6)
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
	# Indicateur de tour.
	var phase := _client.phase
	# (En paysage, le panneau de tour à côté de la carte suffit.)
	_hud_turn.visible = phase.get("turns", false) and _client.game_started() and not _landscape
	if _client.is_my_turn():
		_hud_turn.text = "À VOUS · %d PA" % int(phase.get("ap", 0)) if phase.get("type", "") == "combat" else "À VOUS"
		_hud_turn.add_theme_color_override("font_color", Palette.GOLD)
	else:
		var cur := MapData.token(_client.map, String(phase.get("current", "")))
		_hud_turn.text = "Tour : %s" % cur.get("name", "…")
		_hud_turn.add_theme_color_override("font_color", Palette.MUTED)
	_portrait.active = _client.is_my_turn()
	UIKit.clear(_abilities_row)
	var shown := abilities.slice(0, 6)
	# Portrait : une rangée jusqu'à 4 capacités, deux rangées au-delà (boutons assez grands).
	_abilities_row.columns = 3 if _landscape else (maxi(1, shown.size()) if shown.size() <= 4 else ceili(shown.size() / 2.0))
	if abilities.is_empty():
		_abilities_row.columns = 1
		_abilities_row.add_child(UIKit.label("Aucune capacité équipée (voir la fiche).", "MutedLabel", true))
	for a in shown:
		_abilities_row.add_child(_ability_button(a, sheet))


func _ability_button(a: Dictionary, sheet: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(46, 64)
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
	# États : disponible, sélectionnée (en attente de cible), coût insuffisant, en recharge, inutilisable.
	var chosen := String(_pending.get("id", "")) == String(a.get("id", "")) and not _pending.is_empty()
	var poor := reason.begins_with("Pas assez de %s" % sheet.get("res_name", "ressource"))
	var face := Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.draw.connect(func():
		var r := Rect2(Vector2.ZERO, face.size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.8) if not chosen else col.darkened(0.55)
		sb.border_color = Palette.GOLD if chosen else (col.darkened(0.1) if reason == "" else Palette.BORDER)
		sb.set_border_width_all(3 if chosen else (2 if ult else 1))
		sb.set_corner_radius_all(10)
		face.draw_style_box(sb, r)
		if reason == "" and ult and charge >= 100:
			# Ultime prêt : halo doré.
			face.draw_rect(r.grow(-3), Color(Palette.ULT, 0.15))
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
			face.draw_string(font, Vector2((r.size.x - sw) * 0.5, r.size.y - 4), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.ULT if ult else (Palette.HP.lightened(0.2) if poor else Palette.MANA.lightened(0.3)))
		if chosen:
			var ct := "CIBLE ?"
			var cw2 := font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			face.draw_rect(Rect2(Vector2((r.size.x - cw2) * 0.5 - 3, 1), Vector2(cw2 + 6, 13)), Palette.GOLD)
			face.draw_string(font, Vector2((r.size.x - cw2) * 0.5, 11), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.BG_DEEP)
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
	# Cibles possibles à portée (combat au tour par tour uniquement).
	var target := String(a.get("target", "enemy"))
	if phase.get("turns", false) and _needs_target(a) and not _client.my_token().is_empty():
		var rng := int(a.get("range", 1))
		var ids := _targets_for(target, rng)
		if ids.is_empty():
			return ("Aucun allié à portée (portée %d)." if target.ends_with("ally") else "Aucun ennemi à portée (portée %d) : rapprochez-vous.") % rng
		if target.ends_with("ally") and (a.get("effects", []) as Array).all(func(e): return String(e.get("type", "")) == "heal"):
			var hurt := ids.filter(func(id):
				var t := MapData.token(_client.map, String(id))
				return int(t.get("hp", 0)) < int(t.get("hp_max", 0)))
			if hurt.is_empty():
				return "Aucun allié blessé à soigner à portée."
	return ""


func _needs_target(a: Dictionary) -> bool:
	var target := String(a.get("target", "enemy"))
	return target in ["enemy", "ally", "any"] or (target.begins_with("area") and int(a.get("range", 0)) > 0)


## Pions qui peuvent être visés (selon le type de cible) et, en combat, à portée.
func _targets_for(kind: String, rng: int) -> Array:
	var ids: Array = []
	var me := _client.my_token()
	var limit: bool = bool(_client.phase.get("turns", false)) and rng > 0 and not me.is_empty()
	for t in _client.map.get("tokens", []):
		if String(t.get("kind", "")) == "object":
			continue
		var ally := String(t.get("kind", "")) == "pc" or String(t.get("side", "")) == "players"
		var ko := int(t.get("hp_max", 0)) > 0 and int(t.get("hp", 1)) <= 0
		var ok := true
		match kind:
			"enemy", "area_enemy":
				ok = not ally and not ko
			"ally", "area_ally":
				ok = ally
		if ok and limit:
			ok = Rules.distance(Vector2i(int(me.x), int(me.y)), Vector2i(int(t.x), int(t.y))) <= rng
		if ok:
			ids.append(t.id)
	if kind in ["ally", "any", "area_ally"] and not me.is_empty() and not ids.has(me.id):
		ids.append(me.id)
	return ids


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
	var needs := _needs_target(a)
	var use := UIKit.button("Utiliser" + (" (choisir la cible)" if needs else ""), "PrimaryButton", func():
		_close_overlay()
		var payload := {"action": "ability", "id": String(a.get("id", "")), "label": String(a.get("name", "")), "kind": target, "range": int(a.get("range", 1))}
		if needs:
			_start_target(payload)
		else:
			_client.turn_action("ability", "", 0, {"id": String(a.get("id", ""))}))
	use.custom_minimum_size.y = 56
	use.disabled = reason != ""
	panel.body.add_child(use)
	panel.body.add_child(GameUI.hint("Cibles : %s. Portée en cases (déplacements en diagonale comptés comme 1)." % Content.TARGET_NAMES.get(target, target)))


## Toucher un coffre : l'ouvrir s'il est à côté (le butin va dans le sac).
func _on_token_selected(token_id: String) -> void:
	var t := MapData.token(_client.map, token_id)
	if t.is_empty() or String(t.get("kind", "")) != "object" or String(t.get("loot", "")) == "":
		return
	var me := _client.my_token()
	var near := not me.is_empty() and Rules.distance(Vector2i(int(me.x), int(me.y)), Vector2i(int(t.x), int(t.y))) <= 1
	var panel := _open_overlay("chest", String(t.get("name", "Coffre")), "chest")
	panel.body.add_child(UIKit.label("Un coffre fermé. Qui sait ce qu'il contient ?", "", true))
	if near:
		panel.body.add_child(UIKit.button("Ouvrir le coffre", "PrimaryButton", func():
			_close_overlay()
			_client.open_chest(token_id)))
	else:
		panel.body.add_child(GameUI.hint("Approchez-vous (case voisine) pour l'ouvrir."))
	_map_view.selected = String(me.get("id", ""))


func _start_target(action: Dictionary) -> void:
	_pending = action
	_map_view.target_mode = true
	_map_view.reachable = {}
	_map_view.target_ids = _targets_for(String(action.get("kind", "enemy")), int(action.get("range", 0)))
	_show_view("map")
	_refresh_turn_bar()
	_refresh_hud()
	_map_view.queue_redraw()


func _cancel_target() -> void:
	_pending = {}
	_map_view.target_mode = false
	_map_view.target_ids = []
	_refresh_turn_bar()
	_refresh_reachable()
	_refresh_hud()


func _on_target_picked(token_id: String) -> void:
	var action := _pending
	if not action.is_empty() and not _map_view.target_ids.has(token_id):
		_notifier.push("Cible hors de portée ou non valide : choisissez un pion entouré de rouge.", "warning")
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
	_overlay = OverlayPanel.new(title, _wide or _landscape, icon_name)
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
	if App.is_mobile():
		var disp := UIKit.card(body, "Affichage")
		var orient := OptionButton.new()
		for spec in [["auto", "Automatique (tourner le téléphone)"], ["portrait", "Toujours en portrait"], ["landscape", "Toujours en paysage"]]:
			orient.add_item(spec[1])
			orient.set_item_metadata(orient.item_count - 1, spec[0])
			if String(App.get_setting("display", "orientation", "auto")) == spec[0]:
				orient.select(orient.item_count - 1)
		orient.item_selected.connect(func(i):
			App.set_setting("display", "orientation", String(orient.get_item_metadata(i)))
			App.save_settings()
			Style.apply_orientation())
		UIKit.field(disp, "Orientation de l'écran", orient)
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
		["bag", "Sac, fiche, journal", "Le sac contient vos objets (touchez-en un pour l'équiper ou l'utiliser) et le coffre du groupe. La fiche (ou votre portrait) montre votre personnage et vos montées de niveau. Le journal garde vos quêtes. Tournez le téléphone pour jouer en paysage."],
		["heart", "Points de vie", "À 0 PV, votre personnage est hors de combat (pas forcément mort : le MJ décide). Le repos et les soins font remonter les PV."],
		["eye", "La carte et la vision", "Vous ne voyez qu'autour de votre personnage : plus votre Dextérité est haute, plus vous voyez loin. Les murs et forêts denses cachent ce qu'il y a derrière ; les lieux déjà visités restent dans la pénombre."],
		["chat", "Discuter", "Le bouton « Discuter » de la barre du bas ouvre la conversation à tout moment, même en plein combat : parler ne coûte aucun point d'action."],
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


## Indicateur discret d'envoi en attente de confirmation par l'hôte.
func _refresh_outbox() -> void:
	if _conn_chip == null:
		return
	var n := _client.pending_count()
	if n > 0 and Net.state == Net.State.CONNECTED:
		UIKit.set_chip(_conn_chip, "Envoi…", Palette.WARN)
	elif n > 0:
		UIKit.set_chip(_conn_chip, "%d en attente" % n, Palette.WARN)


func _on_command_failed(_req_id: String, error: String) -> void:
	_feed.add_notice("Impossible : " + error, Palette.DANGER)
	_notifier.push(error, "danger")
	_refresh_turn_bar()


func _on_session_ended(reason: String) -> void:
	App.flash = reason
	App.goto(App.SCENE_JOIN)


func _confirm_leave() -> void:
	ConfirmBox.ask(self, "Quitter la partie ?", "Vous pourrez revenir : votre place et votre personnage sont conservés.", "Quitter", func():
		Net.leave()
		App.goto(App.SCENE_JOIN), true, "Rester")
