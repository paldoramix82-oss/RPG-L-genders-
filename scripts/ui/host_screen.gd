extends Control
## Écran du maître du jeu : préparation (nouvelle campagne ou reprise) puis
## tableau de bord en quatre zones (PC) :
##   - à gauche : comment rejoindre, les joueurs et l'état de leurs personnages ;
##   - au centre : la carte et le récit (narration, événements, actions) ;
##   - à droite : les outils (combat, monde, quêtes, créations, fiches, réseau) ;
##   - en bas : la saisie (narration, messages, dés) et les événements rapides.
## Sur téléphone, les mêmes zones deviennent des onglets.

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
var _fog_check: CheckBox
var _fog_preview: CheckBox
var _tool := "move"
var _tool_buttons := {}
var _tool_options: VBoxContainer
var _paint_code := "."
var _brush := 0
var _stroke := false
var _rect_start := Vector2i(-1, -1)
## Bâtiment prêt / habitant à poser au prochain toucher.
var _prefab_id := ""
var _prefab_npc := true
var _role_id := ""
var _token_tpl := {"kind": "monster", "name": "Monstre", "color": "#b0605a", "hp": 10, "hidden": true}
var _label_tpl := {"text": "", "hidden": false}
var _inspector: VBoxContainer
var _insp_widgets := {}
var _phase_box: VBoxContainer
var _encounters_box: VBoxContainer
var _phase_refresh_queued := false
var _lobby_bar: PanelContainer
var _include_hidden := false
var _mj_pending := {}

# Récit
var _feed: FeedView
var _composer: Composer
var _pending_box: VBoxContainer
var _pending_title: Label

# Personnages
var _char_list: VBoxContainer
var _char_selected := ""

# Zones et panneaux
var _tools_tabs: TabbedPages
var _quest_panel: QuestPanel
var _content_panel: ContentPanel
var _loot_box: VBoxContainer
var _overlay: OverlayPanel
var _overlay_kind := ""
var _char_tools: CharacterTools
var _narrate_mode := true

# Musique et dés
var _music_select: OptionButton
var _music_status: Label
var _tray: DiceTray
var _tray_waiting := false
var _journal_list: VBoxContainer
var _adventure_box: VBoxContainer
var _events_menu: MenuButton
var _notifier: Notifier


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
	var scroll := TouchScroll.new()
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
	var adventure := OptionButton.new()
	var adv_text := UIKit.label("", "MutedLabel", true)
	var fill_adventures := func():
		adventure.clear()
		adventure.add_item("Aucune : je prépare tout moi-même")
		adventure.set_item_metadata(0, "")
		for a in Adventures.all(String(universe.get_item_metadata(universe.selected))):
			adventure.add_item("%s  (%s)" % [a.name, a.get("length", "")])
			adventure.set_item_metadata(adventure.item_count - 1, String(a.id))
		adventure.select(mini(1, adventure.item_count - 1))
	var show_adventure := func(_i: int = 0):
		var a := Adventures.get_by_id(String(adventure.get_item_metadata(adventure.selected)))
		adv_text.text = ("%s\n%s" % [a.get("tagline", ""), a.get("description", "")]) if not a.is_empty() else "Une campagne vide : cartes de l'univers, à vous de créer quêtes et rencontres."
	var show_tagline := func(_i: int = 0):
		for u in universes:
			if u.id == universe.get_item_metadata(universe.selected):
				tagline.text = "%s\n%s" % [u.get("tagline", ""), u.get("description", "")]
		fill_adventures.call()
		show_adventure.call()
	universe.item_selected.connect(show_tagline)
	adventure.item_selected.connect(show_adventure)
	UIKit.field(form, "Univers", universe)
	form.add_child(tagline)
	UIKit.field(form, "Aventure prête à jouer (conseillé pour débuter)", adventure)
	form.add_child(adv_text)
	show_tagline.call()
	_inputs.universe = universe
	_inputs.adventure = adventure
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
	var validate := CheckBox.new()
	validate.text = "Valider moi-même chaque nouveau joueur"
	validate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validate.button_pressed = not App.get_setting("host", "auto_accept", true)
	net.add_child(validate)
	_inputs.validate = validate
	net.add_child(UIKit.label("PC Windows : au premier lancement, autorisez l'application sur les « Réseaux privés ». Téléphone hôte : gardez l'application ouverte et l'écran allumé pendant la partie.", "MutedLabel", true))
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	page.add_child(gap)


func _network_settings() -> Dictionary:
	var settings := {
		"port": int((_inputs.port as SpinBox).value),
		"max_players": int((_inputs.max_players as SpinBox).value),
		"auto_accept": not (_inputs.validate as CheckBox).button_pressed,
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
	var adv := _inputs.adventure as OptionButton
	var adv_id := String(adv.get_item_metadata(adv.selected)) if adv != null else ""
	_start(settings, {})
	if Net.server != null and adv_id != "":
		Net.server.mj_load_adventure(adv_id)
		Net.server.save()
		_show_tools("adventure")


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
			server.characters_changed, server.maps_changed, server.phase_changed, server.saved,
			server.quests_changed, server.content_changed, server.loot_changed, server.fx, server.adventure_changed]:
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
	_lobby_bar = PanelContainer.new()
	_lobby_bar.theme_type_variation = "HighlightPanel"
	_lobby_bar.add_child(HBoxContainer.new())
	outer.add_child(_lobby_bar)

	if _narrow:
		_tabs = TabbedPages.new(false, 8, true)
		_tools_tabs = _tabs
		outer.add_child(_tabs)
		var players_page := VBoxContainer.new()
		_build_players_column(players_page)
		_tabs.add_page("players", "Joueurs", players_page)
		_tabs.add_page("table", "Carte", _build_map_center())
		var story := VBoxContainer.new()
		story.add_child(_build_story())
		story.add_child(_build_bottom_bar())
		_tabs.add_page("story", "Récit", story)
	else:
		# Quatre zones, séparateurs déplaçables : joueurs | scène (carte / récit,
		# et zone basse saisie + journal) | outils du MJ.
		var body := HSplitContainer.new()
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(body)
		var left_margin := MarginContainer.new()
		for side in ["left", "top", "bottom"]:
			left_margin.add_theme_constant_override("margin_" + side, 10)
		body.add_child(left_margin)
		var left := VBoxContainer.new()
		left.custom_minimum_size.x = 250
		left_margin.add_child(left)
		_build_players_column(left)
		var rest := HSplitContainer.new()
		rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(rest)
		var center := VSplitContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rest.add_child(center)
		_tabs = TabbedPages.new(false, 8)
		_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_tabs.custom_minimum_size.y = 260
		center.add_child(_tabs)
		_tabs.add_page("table", "Carte", _build_map_center())
		_tabs.add_page("story", "Récit", _build_story())
		var low := HSplitContainer.new()
		low.custom_minimum_size.y = 150
		center.add_child(low)
		var bar := _build_bottom_bar()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_stretch_ratio = 2.0
		low.add_child(bar)
		low.add_child(_build_journal())
		var right := VBoxContainer.new()
		right.custom_minimum_size.x = 360
		rest.add_child(right)
		_tools_tabs = TabbedPages.new(false, 8, true)
		right.add_child(_tools_tabs)
	_tools_tabs.add_page("adventure", "Aventure", _build_adventure_panel())
	_tools_tabs.add_page("combat", "Combat", _build_combat_tools())
	_tools_tabs.add_page("world", "Monde", _build_world_tools())
	_quest_panel = QuestPanel.new()
	_quest_panel.edit_requested.connect(_open_quest_editor)
	_tools_tabs.add_page("quests", "Quêtes", _scroll_of(_quest_panel))
	_content_panel = ContentPanel.new()
	_content_panel.edit_requested.connect(_open_content_editor)
	_content_panel.show_requested.connect(_show_info)
	_tools_tabs.add_page("create", "Créer", _scroll_of(_content_panel))
	_tools_tabs.add_page("chars", "Fiches", _build_characters())
	_tools_tabs.add_page("codex", "Codex", CodexView.new(server.universe, true))
	_tools_tabs.add_page("net", "Réseau", _build_network())
	_show("table")
	if not _narrow:
		_tools_tabs.show_page("combat")
	server.quests_changed.connect(func(): _quest_panel.rebuild())
	_tools_tabs.page_changed.connect(func(key):
		if key == "create":
			_content_panel.rebuild()
		elif key == "quests":
			_quest_panel.rebuild())
	server.adventure_changed.connect(_refresh_adventure)
	server.content_changed.connect(_on_content_changed)
	server.loot_changed.connect(_refresh_loot)
	server.fx.connect(func(list): _map_view.show_fx(list))

	server.players_changed.connect(_on_players_changed)
	server.message_added.connect(_on_message_added)
	server.message_updated.connect(_on_message_updated)
	server.log_added.connect(_add_log)
	server.characters_changed.connect(_refresh_characters)
	server.characters_changed.connect(_refresh_players)
	server.maps_changed.connect(_on_maps_changed)
	server.phase_changed.connect(_queue_phase_refresh)
	server.saved.connect(_on_saved)

	for entry in server.connection_log:
		_add_log(entry)
	_feed.set_messages(server.messages)
	_on_players_changed()
	_refresh_map_select()
	_load_edit_map()
	_refresh_pending()
	_refresh_loot()

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_refresh_live)
	add_child(_refresh_timer)
	_refresh_live()
	if _tray:
		_tray.queue_free()
	_tray = DiceTray.new()
	add_child(_tray)
	if _notifier:
		_notifier.queue_free()
	_notifier = Notifier.new()
	add_child(_notifier)
	if not Music.changed.is_connected(_refresh_music_status):
		Music.changed.connect(_refresh_music_status)
	_refresh_music_status()


## Bascule vers une page, qu'elle soit au centre ou dans la colonne d'outils.
func _show(key: String) -> void:
	if _tabs.has_page(key):
		_tabs.show_page(key)
	elif _tools_tabs != null and _tools_tabs.has_page(key):
		_tools_tabs.show_page(key)


func _show_tools(key: String) -> void:
	if _tools_tabs != null and _tools_tabs.has_page(key):
		_tools_tabs.show_page(key)


# --- Aventure prête à jouer ---

func _build_adventure_panel() -> Control:
	_adventure_box = VBoxContainer.new()
	_adventure_box.add_theme_constant_override("separation", 10)
	_refresh_adventure()
	return _scroll_of(_adventure_box)


## Guide de l'aventure chargée (scènes à raconter, conseils, actions en un clic),
## ou la liste des aventures disponibles pour cet univers.
func _refresh_adventure() -> void:
	if _adventure_box == null:
		return
	var server := Net.server
	UIKit.clear(_adventure_box)
	var adv: Dictionary = server.adventure
	if not adv.is_empty():
		var head := GameUI.section(_adventure_box, String(adv.name), "book", "HighlightPanel")
		head.add_child(UIKit.label(String(adv.get("tagline", "")), "StrongLabel", true))
		head.add_child(UIKit.label(String(adv.get("description", "")), "MutedLabel", true))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		head.add_child(row)
		if String(adv.get("music", "")) != "":
			row.add_child(_small_button("Lancer sa musique", "", func(): server.mj_music(String(adv.music), true)))
		row.add_child(_small_button("Voir les quêtes", "", func(): _show_tools("quests")))
		row.add_child(_small_button("Révéler les monstres cachés", "", func():
			var n := server.mj_reveal_monsters()
			_notifier.push("%d monstre%s révélé%s." % [n, "s" if n > 1 else "", "s" if n > 1 else ""], "warning")))
		_adventure_box.add_child(GameUI.hint("Jouez les scènes dans l'ordre (ou non !) : « Raconter » envoie le texte aux joueurs et déclenche l'action indiquée. Les conseils ne sont visibles que par vous."))
		var done: Array = adv.get("done", [])
		var scenes: Array = adv.get("scenes", [])
		for i in scenes.size():
			var sc: Dictionary = scenes[i]
			var card := GameUI.section(_adventure_box, "%d. %s" % [i + 1, sc.get("title", "")], "star" if not done.has(i) else "sparkle", "InsetPanel" if done.has(i) else "CardPanel")
			card.add_child(UIKit.label(String(sc.get("narration", "")), "", true))
			var tip := UIKit.label("Conseil MJ : " + String(sc.get("tips", "")), "MutedLabel", true)
			tip.add_theme_color_override("font_color", Palette.PRIVATE)
			card.add_child(tip)
			var action: Dictionary = sc.get("action", {})
			var what: String = {"give_quest": " + donner la quête", "group_check": " + épreuve de groupe", "reveal_combat": " + révéler et combattre", "start_combat": " + lancer le combat"}.get(String(action.get("type", "")), "")
			var idx := i
			card.add_child(_small_button(("Raconter à nouveau" if done.has(i) else "Raconter") + what, "" if done.has(i) else "PrimaryButton", func(): server.mj_play_scene(idx)))
		_adventure_box.add_child(UIKit.label("Une autre aventure ?", "HeadingLabel"))
	else:
		_adventure_box.add_child(GameUI.hint("Une aventure prête à jouer installe une carte, des PNJ, des monstres cachés, des coffres et des quêtes en brouillon, avec des scènes à raconter. Parfait pour découvrir le jeu."))
	for a in Adventures.all(String(server.universe.get("id", ""))):
		if String(a.id) == String(adv.get("id", "")):
			continue
		var card := UIKit.card(_adventure_box, "", "InsetPanel")
		card.add_child(UIKit.label(String(a.name), "StrongLabel", true))
		card.add_child(UIKit.label("%s · %s" % [a.get("tagline", ""), a.get("length", "")], "MutedLabel", true))
		var aid := String(a.id)
		var aname := String(a.name)
		card.add_child(_small_button("Charger cette aventure", "", func():
			_confirm("Charger « %s » ? Une nouvelle carte est créée et montrée aux joueurs ; vos cartes et quêtes actuelles sont conservées." % aname, func():
				var err := server.mj_load_adventure(aid)
				if err != "":
					_notifier.push(err, "danger")
				else:
					_edit_map = server.active_map
					_refresh_map_select()
					_load_edit_map())))


func _badge(key: String, on: bool) -> void:
	if _tabs.has_page(key):
		_tabs.set_badge(key, on)
	elif _tools_tabs != null:
		_tools_tabs.set_badge(key, on)


func _scroll_of(content: Control) -> Control:
	var scroll := TouchScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


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
	if not _narrow:
		row.add_child(UIKit.button("Raccourcis", "NavButton", func():
			var box := VBoxContainer.new()
			for s in SHORTCUTS:
				var line := HBoxContainer.new()
				var key := UIKit.label(s[0], "StrongLabel")
				key.custom_minimum_size.x = 120
				key.add_theme_color_override("font_color", Palette.GOLD)
				line.add_child(key)
				line.add_child(UIKit.label(s[1]))
				box.add_child(line)
			_show_info("Raccourcis clavier", box)))
	row.add_child(UIKit.button("Sauver", "", func(): Net.server.save()))
	row.add_child(UIKit.button("Terminer" if _narrow else "Terminer la session", "DangerButton", _confirm_end))
	return bar


# --- Joueurs et connexion ---

func _build_players_column(parent: Node) -> void:
	var server := Net.server
	var card := GameUI.section(parent, "Pour rejoindre", "castle", "HighlightPanel")
	var ips := NetUtils.get_lan_ipv4_addresses()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var ip_label := UIKit.label(ips[0] if not ips.is_empty() else "Pas de Wi-Fi", "CodeLabel")
	ip_label.add_theme_font_size_override("font_size", 26)
	ip_label.add_theme_color_override("font_color", Palette.GOLD)
	row.add_child(ip_label)
	var port := UIKit.label("port %d" % int(server.session.port), "MutedLabel")
	port.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(port)
	if ips.size() > 1:
		card.add_child(UIKit.label("Autres adresses : " + ", ".join(ips.slice(1)), "MutedLabel", true))
	var players_card := GameUI.section(parent, "Joueurs", "person")
	players_card.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_players_list = UIKit.vscroll(players_card)


func _on_players_changed() -> void:
	_refresh_lobby_bar()
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
		_players_list.add_child(UIKit.label("Aucun joueur pour l'instant. Donnez-leur l'adresse IP affichée ci-dessus.", "MutedLabel", true))
	for p in list:
		_players_list.add_child(_player_row(p))
	if _narrow and server.count_status(Protocol.STATUS_PENDING) > 0:
		_badge("players", true)
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
	if not sheet.is_empty() and p.status == Protocol.STATUS_ACCEPTED:
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 8)
		body.add_child(srow)
		srow.add_child(Portrait.for_sheet(sheet, Net.server.content, 44))
		var bars := VBoxContainer.new()
		bars.add_theme_constant_override("separation", 2)
		bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		srow.add_child(bars)
		var hp := ResourceBar.new("PV", Palette.HP, 18)
		hp.set_values(int(sheet.get("hp", 0)), int(sheet.get("hp_max", 1)), false)
		bars.add_child(hp)
		if int(sheet.get("res_max", 0)) > 0:
			var res := ResourceBar.new(String(sheet.get("res_name", "")), Palette.MANA, 14)
			res.set_values(int(sheet.get("res", 0)), int(sheet.res_max), false)
			bars.add_child(res)
		var cls := Rules.get_class_def(Net.server.content, String(sheet.get("class_id", "")))
		var weapon: Dictionary = Rules.weapons(sheet)[0]
		var line := UIKit.label("%s · niv. %d · %d or · %s" % [cls.get("name", sheet.get("concept", "Libre")), int(sheet.get("level", 1)), int(sheet.get("gold", 0)), weapon.get("name", "")], "MutedLabel", true)
		line.add_theme_font_size_override("font_size", 14)
		bars.add_child(line)
		if not (sheet.get("effects", []) as Array).is_empty():
			body.add_child(GameUI.status_row(sheet.effects, 18))
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
				_show("story")
				_composer.select_target(pid)
				_composer.focus_text()))
			actions.add_child(_small_button("Jet", "", func(): _dialog_request_roll(pid, pname)))
			if not sheet.is_empty():
				actions.add_child(_small_button("Fiche et outils", "PrimaryButton", func(): _open_char_tools(pid)))
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
	_count_label.text = "%d / %d joueurs connectés%s  ·  phase : %s" % [online, server.session.max_players, ("  ·  %d en attente" % pending) if pending > 0 else "", Phases.def(server.phase.type).name]
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

func _build_map_center() -> Control:
	_map_view = MapView.new()
	_map_view.is_mj = true
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.custom_minimum_size = Vector2(200, 260)
	_map_view.move_requested.connect(func(id, x, y): Net.server.mj_update_token(_edit_map, id, {"x": x, "y": y}))
	_map_view.token_selected.connect(func(_id):
		_refresh_inspector()
		if not _narrow:
			_tools_tabs.show_page("combat"))
	_map_view.paint_requested.connect(func(x, y):
		if not _stroke:
			# Début d'un coup de pinceau : on mémorise pour pouvoir annuler.
			_stroke = true
			Net.server.mj_snapshot(_edit_map)
		Net.server.mj_paint(_edit_map, x, y, _paint_code, _brush))
	_map_view.paint_finished.connect(func(): _stroke = false)
	_map_view.cell_tapped.connect(_on_cell_tapped)
	_map_view.target_picked.connect(_on_mj_target)
	return _map_view


func _side_scroll() -> Array:
	var scroll := TouchScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 12)
	scroll.add_child(side)
	return [scroll, side]


## Combat : phase et tours, pion sélectionné, coffre du groupe.
func _build_combat_tools() -> Control:
	var parts := _side_scroll()
	var side: VBoxContainer = parts[1]
	_encounters_box = UIKit.card(side, "")
	_phase_box = UIKit.card(side, "", "HighlightPanel")
	_inspector = UIKit.card(side, "")
	var loot := UIKit.card(side, "Coffre du groupe")
	_loot_box = VBoxContainer.new()
	loot.add_child(_loot_box)
	return parts[0]


## Monde : musique, cartes, outils de dessin.
func _build_world_tools() -> Control:
	var parts := _side_scroll()
	var side: VBoxContainer = parts[1]
	var music := UIKit.card(side, "Ambiance musicale")
	_music_select = OptionButton.new()
	_music_select.custom_minimum_size.y = UIKit.TOUCH_HEIGHT
	_music_select.fit_to_longest_item = false
	for t in MusicLibrary.tracks():
		_music_select.add_item("%s — %s" % [t.mood, t.title])
		_music_select.set_item_metadata(_music_select.item_count - 1, t.id)
		if t.id == Net.server.music.track:
			_music_select.select(_music_select.item_count - 1)
	_music_select.item_selected.connect(func(i):
		if Net.server.music.playing:
			Net.server.mj_music(String(_music_select.get_item_metadata(i)), true))
	music.add_child(_music_select)
	var mrow := HBoxContainer.new()
	music.add_child(mrow)
	var play := UIKit.button("Lecture", "PrimaryButton", func():
		Net.server.mj_music(String(_music_select.get_item_metadata(_music_select.selected)), true))
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(play)
	mrow.add_child(UIKit.button("Suivant", "", _music_next))
	mrow.add_child(UIKit.button("Stop", "", func(): Net.server.mj_music(Net.server.music.track, false)))
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = Music.volume()
	volume.custom_minimum_size.y = 32
	volume.value_changed.connect(Music.set_volume)
	volume.drag_ended.connect(func(_c): App.save_settings())
	UIKit.field(music, "Volume sur cet appareil", volume)
	var broadcast := CheckBox.new()
	broadcast.text = "Jouer aussi sur les téléphones des joueurs"
	broadcast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	broadcast.button_pressed = Net.server.music.broadcast
	music.add_child(broadcast)
	var auto := CheckBox.new()
	auto.text = "Musique de combat automatique"
	auto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto.button_pressed = Net.server.music.auto_combat
	music.add_child(auto)
	broadcast.toggled.connect(func(on): Net.server.mj_music_settings(on, auto.button_pressed))
	auto.toggled.connect(func(on): Net.server.mj_music_settings(broadcast.button_pressed, on))
	_music_status = UIKit.label("", "MutedLabel", true)
	music.add_child(_music_status)

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
		_refresh_phase()))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	mc.add_child(row)
	row.add_child(_small_button("Générer…", "PrimaryButton", _dialog_generate_map))
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
	_fog_check = CheckBox.new()
	_fog_check.text = "Brouillard de guerre (chacun ne voit qu'autour de lui ; vision = Dextérité)"
	_fog_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fog_check.toggled.connect(func(on): Net.server.mj_update_map(_edit_map, {"fog": on}))
	mc.add_child(_fog_check)
	var fog_row := HFlowContainer.new()
	fog_row.add_theme_constant_override("h_separation", 6)
	mc.add_child(fog_row)
	_fog_preview = CheckBox.new()
	_fog_preview.text = "Voir le brouillard des joueurs"
	_fog_preview.toggled.connect(func(_on): _refresh_fog_preview())
	fog_row.add_child(_fog_preview)
	fog_row.add_child(_small_button("Oublier l'exploration", "", func():
		_confirm("Les joueurs oublient tout ce qu'ils ont exploré sur cette carte ?", func(): Net.server.mj_reset_fog(_edit_map))))

	# --- Outils ---
	var tc := UIKit.card(side, "Outils")
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	tc.add_child(tools)
	var group := ButtonGroup.new()
	for spec in [["move", "Déplacer"], ["paint", "Peindre"], ["fill", "Remplir"], ["rect", "Rectangle"], ["room", "Pièce"], ["token", "Pion"], ["label", "Étiquette"], ["erase", "Gomme"], ["spawn", "Départ"]]:
		var b := _small_button(spec[1], "", _set_tool.bind(spec[0]))
		b.toggle_mode = true
		b.button_group = group
		_tool_buttons[spec[0]] = b
		tools.add_child(b)
	var undo := _small_button("Annuler la dernière retouche", "", func():
		if not Net.server.mj_undo(_edit_map):
			_notifier.push("Rien à annuler sur cette carte.", "warning"))
	undo.tooltip_text = "Ctrl + Z"
	tc.add_child(undo)
	_tool_options = VBoxContainer.new()
	tc.add_child(_tool_options)

	# --- Bâtiments prêts ---
	var bc := UIKit.card(side, "Bâtiments prêts")
	bc.add_child(UIKit.label("Choisissez, puis touchez la carte : murs, porte, meubles, nom, coffre et habitant (avec une quête prête) sont posés d'un coup.", "MutedLabel", true))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	bc.add_child(grid)
	for id in Prefabs.LIST:
		grid.add_child(_prefab_button(String(id)))
	var with_npc := CheckBox.new()
	with_npc.text = "Avec son habitant (PNJ qui propose des quêtes)"
	with_npc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	with_npc.button_pressed = _prefab_npc
	with_npc.toggled.connect(func(on): _prefab_npc = on)
	bc.add_child(with_npc)

	# --- Habitants ---
	var hc := UIKit.card(side, "Habitants")
	hc.add_child(UIKit.label("Un PNJ avec un métier : il salue, propose des quêtes secondaires prêtes dès qu'on lui parle, et en invente de nouvelles. Déplacez-le ensuite avec l'outil « Déplacer ».", "MutedLabel", true))
	var roles := HFlowContainer.new()
	roles.add_theme_constant_override("h_separation", 6)
	roles.add_theme_constant_override("v_separation", 6)
	hc.add_child(roles)
	for rid in Prefabs.ROLE_ORDER:
		var r := QuestLibrary.role(rid)
		var b := _small_button(String(r.title).capitalize(), "", func():
			_role_id = rid
			_set_tool("npc_role"))
		b.icon = null
		roles.add_child(b)

	_set_tool(_tool)
	return parts[0]


## Morceau suivant de la même ambiance (au hasard).
func _music_next() -> void:
	var current := MusicLibrary.track(Net.server.music.track)
	var pool := MusicLibrary.by_mood(String(current.get("mood", ""))) if not current.is_empty() else MusicLibrary.tracks()
	pool = pool.filter(func(t): return t.id != Net.server.music.track)
	if pool.is_empty():
		pool = MusicLibrary.tracks()
	var pick: Dictionary = pool[randi() % pool.size()]
	Net.server.mj_music(pick.id, true)
	for i in _music_select.item_count:
		if _music_select.get_item_metadata(i) == pick.id:
			_music_select.select(i)


func _refresh_music_status() -> void:
	if _music_status == null or Net.server == null:
		return
	var m: Dictionary = Net.server.music
	var title := String(MusicLibrary.track(m.track).get("title", ""))
	_music_status.text = ("En cours : %s" % title) if m.playing else "Aucune musique."
	for i in _music_select.item_count:
		if _music_select.get_item_metadata(i) == m.track:
			_music_select.select(i)


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
	_refresh_phase()


func _refresh_map_status() -> void:
	var map: Dictionary = Net.server.maps.get(_edit_map, {})
	if map.is_empty():
		return
	var shown := _edit_map == Net.server.active_map
	_map_status.text = ("Affichée aux joueurs." if shown else "Non affichée : vous seul la voyez.") + "  %d × %d cases, %d pions." % [map.w, map.h, map.tokens.size()]
	_map_status.add_theme_color_override("font_color", Palette.OK if shown else Palette.MUTED)
	_move_check.set_pressed_no_signal(map.get("players_can_move", true))
	_fog_check.set_pressed_no_signal(Vision.enabled(map))
	_refresh_fog_preview()


func _refresh_fog_preview() -> void:
	if _fog_preview == null:
		return
	_map_view.fog_alpha = 0.6
	_map_view.fog_override = Net.server.fog_preview(_edit_map) if _fog_preview.button_pressed else {}
	_map_view.queue_redraw()


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
	_map_view.stamp_size = Prefabs.size_of(_prefab_id) if tool == "prefab" else Vector2i.ZERO
	_rect_start = Vector2i(-1, -1)
	if _tool_buttons.has(tool):
		_tool_buttons[tool].set_pressed_no_signal(true)
	else:
		for b in _tool_buttons.values():
			b.set_pressed_no_signal(false)
	UIKit.clear(_tool_options)
	match tool:
		"prefab":
			_tool_options.add_child(GameUI.hint("%s : touchez la carte pour le poser (centré sur la case). « Annuler la dernière retouche » le retire." % Prefabs.get_def(_prefab_id).get("name", "")))
		"npc_role":
			_tool_options.add_child(GameUI.hint("Touchez une case pour placer : %s." % String(QuestLibrary.role(_role_id).get("title", ""))))
		"move":
			_tool_options.add_child(UIKit.label("Touchez un pion pour le sélectionner, puis une case pour l'y déplacer (ou glissez-le). Molette ou deux doigts : zoom.", "MutedLabel", true))
		"paint", "fill", "rect", "room":
			var hint: String = {"paint": "Glissez sur la carte pour peindre.", "fill": "Touchez une zone : elle est entièrement repeinte (même terrain, d'un seul tenant).",
				"rect": "Touchez un coin, puis le coin opposé : le rectangle est rempli.", "room": "Touchez un coin, puis le coin opposé : une pièce (sol choisi, murs autour)."}[tool]
			_tool_options.add_child(GameUI.hint(hint))
			var palette := GridContainer.new()
			palette.columns = 4
			palette.add_theme_constant_override("h_separation", 4)
			palette.add_theme_constant_override("v_separation", 4)
			_tool_options.add_child(palette)
			var pgroup := ButtonGroup.new()
			for code in MapData.TERRAINS:
				palette.add_child(_terrain_button(code, pgroup))
			if tool == "paint":
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


## Bouton de bâtiment avec son plan en miniature.
func _prefab_button(id: String) -> Control:
	var def := Prefabs.get_def(id)
	var b := Button.new()
	b.tooltip_text = String(def.name)
	b.custom_minimum_size = Vector2(96, 84)
	b.pressed.connect(func():
		_prefab_id = id
		_set_tool("prefab"))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	b.add_child(box)
	var plan := Control.new()
	plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plan.size_flags_vertical = Control.SIZE_EXPAND_FILL
	plan.custom_minimum_size = Vector2(80, 50)
	plan.draw.connect(func():
		var rows: Array = def.rows
		var sz := Prefabs.size_of(id)
		var cs := minf(plan.size.x / sz.x, plan.size.y / sz.y)
		var off := (plan.size - Vector2(sz) * cs) * 0.5
		for j in rows.size():
			for i in String(rows[j]).length():
				var ch := String(rows[j])[i]
				if ch == " ":
					continue
				var code := Prefabs.cell_code(ch, String(def.get("floor", "d")))
				var col := MapData.terrain_color(code)
				if Prefabs.DECOR.has(ch):
					col = Color("b07a44")
				elif ch == "#":
					col = Color("8a8378")
				elif ch == "@":
					col = Palette.GOLD
				elif ch == "$":
					col = Color("a07a3a")
				plan.draw_rect(Rect2(off + Vector2(i, j) * cs, Vector2(cs, cs)), col))
	box.add_child(plan)
	var l := UIKit.label(String(def.name), "MutedLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return b


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
		"fill":
			server.mj_fill(_edit_map, x, y, _paint_code)
		"rect", "room":
			if _rect_start.x < 0:
				_rect_start = Vector2i(x, y)
				_map_status.text = "Premier coin posé (%d, %d) : touchez le coin opposé." % [x, y]
				_map_status.add_theme_color_override("font_color", Palette.GOLD)
			else:
				server.mj_paint_rect(_edit_map, _rect_start, Vector2i(x, y), _paint_code, _tool == "room")
				_rect_start = Vector2i(-1, -1)
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
		"prefab":
			var res := server.mj_place_prefab(_edit_map, _prefab_id, x, y, _prefab_npc)
			if not (res.get("npc", {}) as Dictionary).is_empty():
				_notifier.push("%s posé, avec %s." % [Prefabs.get_def(_prefab_id).name, res.npc.name], "success")
		"npc_role":
			var npc := server.mj_place_role_npc(_edit_map, _role_id, x, y)
			if not npc.is_empty():
				_map_view.selected = String(npc.id)
				_refresh_inspector()


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
	var cid_check: String = t.char_id if t.char_id != "" else t.owner
	if not Net.server.characters.has(cid_check):
		# Pion sans fiche : valeurs de combat simples.
		var combat_row := HBoxContainer.new()
		_inspector.add_child(combat_row)
		var def := UIKit.spin(int(t.get("defense", 10)) if int(t.get("defense", 0)) > 0 else 10, 1, 40)
		def.prefix = "Déf."
		def.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		def.value_changed.connect(func(v): upd.call({"defense": int(v)}))
		combat_row.add_child(def)
		var atk := UIKit.line_edit(String(t.get("attack", "1d6")) if String(t.get("attack", "")) != "" else "1d6", "Dégâts")
		atk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		atk.text_submitted.connect(func(v): upd.call({"attack": v}))
		atk.focus_exited.connect(func(): upd.call({"attack": atk.text}))
		combat_row.add_child(atk)
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
		actions.add_child(_small_button("Fiche et outils", "PrimaryButton", func(): _open_char_tools(cid)))
	if _edit_map == Net.server.active_map:
		# Effets de statut sur le pion.
		var st := OptionButton.new()
		st.fit_to_longest_item = false
		for s in Content.list(Net.server.content, "statuses"):
			st.add_item(String(s.name))
			st.set_item_metadata(st.item_count - 1, String(s.id))
		var srow := HBoxContainer.new()
		_inspector.add_child(srow)
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		srow.add_child(st)
		var turns := UIKit.spin(2, 0, 99)
		turns.prefix = "t."
		srow.add_child(turns)
		srow.add_child(_small_button("Appliquer", "", func():
			if st.selected >= 0:
				Net.server.mj_apply_status(tid, String(st.get_item_metadata(st.selected)), int(turns.value))
				_refresh_inspector()))
		var effects: Array = t.get("effects", [])
		if not effects.is_empty():
			_inspector.add_child(GameUI.status_row(effects, 22))
	if Phases.def(Net.server.phase.type).turns and _edit_map == Net.server.active_map:
		actions.add_child(_small_button("Retirer des tours" if Net.server.phase.order.has(tid) else "Ajouter aux tours", "", func():
			Net.server.mj_turn_toggle(tid)
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


# --- Phases et tours ---

## Le serveur signale un changement de phase parfois au milieu d'une action de
## combat local (le combat lui est alors « prêté ») : on rafraîchit après coup,
## une seule fois par image.
func _queue_phase_refresh() -> void:
	if _phase_refresh_queued:
		return
	_phase_refresh_queued = true
	(func():
		_phase_refresh_queued = false
		_refresh_phase()).call_deferred()


## Combats locaux en cours : qui se bat, à qui le tour, et de quoi reprendre la main.
func _refresh_encounters() -> void:
	if _encounters_box == null:
		return
	var server := Net.server
	UIKit.clear(_encounters_box)
	_encounters_box.visible = not server.encounters.is_empty() or Content.rule(server.content, "auto_aggro")
	_encounters_box.add_child(UIKit.label("Combats en cours", "HeadingLabel"))
	if server.encounters.is_empty():
		_encounters_box.add_child(UIKit.label("Aucun. Un combat commence tout seul quand un monstre voit un héros, ou quand un joueur attaque. Il ne concerne que les héros présents ; les autres continuent leur aventure.", "MutedLabel", true))
		return
	var map: Dictionary = server.maps.get(server.active_map, {})
	for enc in server.encounters.values():
		var card := UIKit.card(_encounters_box, "", "InsetPanel")
		var heroes: PackedStringArray = []
		var foes: PackedStringArray = []
		for id in enc.order:
			var t := MapData.token(map, String(id))
			if t.is_empty():
				continue
			if String(t.kind) == "pc":
				heroes.append(String(t.name))
			else:
				foes.append("%s %d/%d" % [t.name, int(t.get("hp", 0)), int(t.get("hp_max", 0))])
		card.add_child(UIKit.label(", ".join(heroes) + "  contre  " + ", ".join(foes), "StrongLabel", true))
		var current := String(enc.order[clampi(int(enc.turn), 0, enc.order.size() - 1)]) if not enc.order.is_empty() else ""
		var ct := MapData.token(map, current)
		var info := "Tour %d" % int(enc.get("round", 1))
		if not ct.is_empty():
			info += "  ·  au tour de %s" % ct.name
		if enc.get("manual", false):
			info += "  ·  monstres joués par vous"
		card.add_child(UIKit.label(info, "MutedLabel", true))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		card.add_child(row)
		var eid := String(enc.id)
		if not ct.is_empty() and String(ct.kind) != "pc":
			row.add_child(_small_button("Jouer ce tour", "PrimaryButton", func(): server.mj_encounter_auto(eid)))
		row.add_child(_small_button("Tour suivant", "", func(): server.mj_encounter_next(eid)))
		var manual: bool = enc.get("manual", false)
		row.add_child(_small_button("Monstres automatiques" if manual else "Je joue les monstres", "", func(): server.mj_encounter_manual(eid, not manual)))
		row.add_child(_small_button("Terminer", "DangerButton", func(): server.mj_encounter_end(eid)))


func _refresh_phase() -> void:
	_refresh_encounters()
	if _phase_box == null:
		return
	var server := Net.server
	UIKit.clear(_phase_box)
	_phase_box.add_child(UIKit.label("Phase de jeu", "HeadingLabel"))
	var on_active := _edit_map == server.active_map
	var phase: Dictionary = server.phase
	var rules := Phases.def(phase.type)
	_map_view.current_turn = server._current_token() if on_active else ""
	_map_view.queue_redraw()
	_refresh_lobby_bar()
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	_phase_box.add_child(buttons)
	for type in Phases.LIST:
		var b := _small_button(Phases.def(type).name, "PrimaryButton" if type == phase.type else "", func(): server.mj_set_phase(type, _include_hidden))
		buttons.add_child(b)
	var hidden := CheckBox.new()
	hidden.text = "Inclure les pions cachés dans le combat"
	hidden.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hidden.button_pressed = _include_hidden
	hidden.toggled.connect(func(on): _include_hidden = on)
	_phase_box.add_child(hidden)
	_phase_box.add_child(UIKit.label(String(rules.rules), "MutedLabel", true))
	if not on_active:
		_phase_box.add_child(UIKit.label("Les tours se jouent sur la carte affichée aux joueurs.", "MutedLabel", true))
		return
	if not rules.turns:
		return
	_phase_box.add_child(UIKit.chip("Tour %d" % int(phase.round), Palette.GOLD))
	var map: Dictionary = server.maps[server.active_map]
	var current := server._current_token()
	var initiative: Dictionary = phase.get("initiative", {})
	for id in phase.order:
		var t := MapData.token(map, id)
		if t.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var text := String(t.name)
		if initiative.has(id):
			text += "  (%d)" % initiative[id]
		if int(t.get("hp_max", 0)) > 0:
			text += "  ·  %d/%d PV" % [int(t.hp), int(t.hp_max)]
		var n := UIKit.label(("› " if id == current else "") + text, "StrongLabel" if id == current else "")
		if id == current:
			n.add_theme_color_override("font_color", Palette.GOLD)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		row.add_child(n)
		var tid: String = id
		var up := _small_button("▲", "", func(): server.mj_turn_move(tid, -1))
		up.custom_minimum_size.x = 38
		row.add_child(up)
		var down := _small_button("▼", "", func(): server.mj_turn_move(tid, 1))
		down.custom_minimum_size.x = 38
		row.add_child(down)
		var x := _small_button("×", "DangerButton", func(): server.mj_turn_toggle(tid))
		x.custom_minimum_size.x = 38
		row.add_child(x)
		_phase_box.add_child(row)
	var current_token := MapData.token(map, current)
	if String(phase.get("result", "")) == "victory":
		var win := UIKit.card(_phase_box, "", "HighlightPanel")
		win.add_child(UIKit.label("Victoire ! XP, or et butin ont été distribués.", "StrongLabel", true))
		var next_row := HFlowContainer.new()
		next_row.add_theme_constant_override("h_separation", 6)
		win.add_child(next_row)
		next_row.add_child(_small_button("Retour au récit libre", "PrimaryButton", func(): server.mj_set_phase("libre")))
		next_row.add_child(_small_button("Exploration", "", func(): server.mj_set_phase("exploration")))
		next_row.add_child(_small_button("Repos", "", func(): server.mj_set_phase("repos")))
	elif String(phase.get("result", "")) == "defeat":
		var lose := UIKit.card(_phase_box, "", "HighlightPanel")
		lose.add_child(UIKit.label("Tout le groupe est à terre. À vous de raconter la suite (capture, sauvetage, réveil…).", "StrongLabel", true))
		lose.add_child(_small_button("Retour au récit libre", "PrimaryButton", func(): server.mj_set_phase("libre")))
	if not current_token.is_empty() and current_token.kind != "pc" and String(phase.get("result", "")) == "":
		# C'est au tour d'un PNJ ou d'un monstre : le MJ le joue (ou le laisse jouer tout seul).
		var npc := UIKit.card(_phase_box, "", "HighlightPanel")
		npc.add_child(UIKit.label("À vous de jouer : %s" % current_token.name, "StrongLabel", true))
		var ap := int(phase.get("ap", 0))
		var info := "Points d'action : %d" % ap
		if rules.move == "limit":
			info += "  ·  déplacez le pion sur la carte (le MJ n'est pas limité)"
		npc.add_child(UIKit.label(info, "MutedLabel", true))
		var acts := HFlowContainer.new()
		acts.add_theme_constant_override("h_separation", 6)
		acts.add_theme_constant_override("v_separation", 6)
		npc.add_child(acts)
		var r := Content.rules(server.content)
		var tid := String(current_token.id)
		acts.add_child(_small_button("Jouer automatiquement", "PrimaryButton", func():
			var err := server.turn_action(tid, {"action": "auto"})
			if err != "":
				_feed.add_notice(err, Palette.WARN)
			_refresh_phase()))
		var quick := _small_button("Attaque rapide (%d PA)" % int(r.quick_attack_ap), "", func(): _mj_target({"action": "quick", "label": "attaque rapide"}))
		quick.disabled = ap < int(r.quick_attack_ap)
		acts.add_child(quick)
		var power := _small_button("Attaque puissante (%d PA)" % int(r.power_attack_ap), "", func(): _mj_target({"action": "power", "label": "attaque puissante"}))
		power.disabled = ap < int(r.power_attack_ap)
		acts.add_child(power)
		var defend := _small_button("Se défendre", "", func():
			server.turn_action(tid, {"action": "defend"})
			_refresh_phase())
		defend.disabled = ap < int(r.defend_ap)
		acts.add_child(defend)
		var sheet := server._sheet_for_token(current_token)
		for a in Rules.usable_abilities(sheet, server.content):
			var id := String(a.get("id", ""))
			var reason := server.combat.ability_block_reason(current_token, a)
			var target := String(a.get("target", "enemy"))
			var b := _small_button(String(a.name), "", func():
				if target == "self" or (target.begins_with("area") and int(a.get("range", 0)) == 0):
					var err := server.turn_action(tid, {"action": "ability", "id": id})
					if err != "":
						_feed.add_notice(err, Palette.WARN)
					_refresh_phase()
				else:
					_mj_target({"action": "ability", "id": id, "label": String(a.name)}))
			b.disabled = reason != ""
			b.tooltip_text = reason if reason != "" else Effects.ability_costs(a)
			acts.add_child(b)
		if not _mj_pending.is_empty():
			npc.add_child(UIKit.label("Touchez la cible sur la carte (%s)." % _mj_pending.get("label", ""), "StrongLabel", true))
			npc.add_child(_small_button("Annuler", "", func():
				_mj_pending = {}
				_map_view.target_mode = false
				_refresh_phase()))
	elif not current_token.is_empty():
		_phase_box.add_child(UIKit.label("Au tour de %s (joueur). Il dispose de %d PA." % [current_token.name, int(phase.get("ap", 0))], "MutedLabel", true))
	var next := UIKit.button("Tour suivant  ›", "PrimaryButton", func(): server.mj_next_turn())
	_phase_box.add_child(next)


func _mj_target(action: Dictionary) -> void:
	_mj_pending = action
	_map_view.target_mode = true
	_map_view.target_ids = []
	_show("table")
	_map_view.queue_redraw()
	_refresh_phase()


func _on_mj_target(token_id: String) -> void:
	var action := _mj_pending
	_mj_pending = {}
	_map_view.target_mode = false
	if action.is_empty():
		return
	var payload := action.duplicate()
	payload.target = token_id
	var err := Net.server.turn_action(Net.server._current_token(), payload)
	if err != "":
		_map_status.text = err
		_map_status.add_theme_color_override("font_color", Palette.DANGER)
	_refresh_phase()


## Bandeau « Préparation » tant que la partie n'est pas lancée.
func _refresh_lobby_bar() -> void:
	if _lobby_bar == null:
		return
	var server := Net.server
	var started: bool = server.session.get("started", false)
	Music.set_menu(not started)
	_lobby_bar.visible = not started
	if started:
		return
	var body := _lobby_bar.get_child(0) as HBoxContainer
	UIKit.clear(body)
	var accepted := server.players.values().filter(func(p): return p.status == Protocol.STATUS_ACCEPTED)
	var ready := accepted.filter(func(p): return server.characters.has(p.id))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(col)
	col.add_child(UIKit.label("Préparation : %d/%d joueurs ont créé leur personnage" % [ready.size(), accepted.size()], "StrongLabel", true))
	var names: PackedStringArray = []
	for p in accepted:
		names.append(("%s (prêt)" if server.characters.has(p.id) else "%s (en création)") % p.name)
	col.add_child(UIKit.label(", ".join(names) if not names.is_empty() else "En attente des joueurs… Donnez-leur l'adresse IP affichée à gauche.", "MutedLabel", true))
	var go := UIKit.button("La partie commence !", "PrimaryButton", func():
		# Monstres agressifs : chacun explore librement, les combats se déclenchent seuls.
		server.mj_start_game("libre" if Content.rule(server.content, "auto_aggro") else "exploration")
		_refresh_phase())
	go.custom_minimum_size = Vector2(240, 56)
	go.disabled = ready.is_empty()
	body.add_child(go)


# --- Dialogues de carte ---

## Carte générée en un clic : type, taille, nom. Le MJ la retouche ensuite.
func _dialog_generate_map() -> void:
	var panel := _open_overlay("generate", "Générer une carte", "map")
	panel.body.add_child(GameUI.hint("Une carte jouable en un clic, avec des lieux nommés (et quelques secrets pour le MJ). Villages et villes arrivent avec leurs bâtiments et leurs habitants, qui proposent des quêtes. Retouchez-la ensuite avec Peindre, Remplir, Rectangle ou Pièce."))
	var kind := OptionButton.new()
	for k in MapGen.KINDS:
		kind.add_item(MapGen.KINDS[k])
		kind.set_item_metadata(kind.item_count - 1, k)
	UIKit.field(panel.body, "Type de lieu", kind)
	var size := OptionButton.new()
	for k in MapGen.SIZES:
		size.add_item(String(MapGen.SIZE_NAMES[k]))
		size.set_item_metadata(size.item_count - 1, k)
	size.select(2)
	UIKit.field(panel.body, "Taille", size)
	var name_edit := UIKit.line_edit("", "Ex. : Bois des Murmures (facultatif)")
	UIKit.field(panel.body, "Nom", name_edit)
	panel.body.add_child(UIKit.button("Générer", "PrimaryButton", func():
		var m := Net.server.mj_generate_map(String(kind.get_item_metadata(kind.selected)), String(size.get_item_metadata(size.selected)), name_edit.text)
		if m.is_empty():
			return
		_edit_map = m.id
		_refresh_map_select()
		_load_edit_map()
		_close_overlay()
		_notifier.push("Carte « %s » créée. Pas à votre goût ? Générez-en une autre." % m.name, "success")))


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
	var parts := _side_scroll()
	var page: VBoxContainer = parts[1]
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 8)
	top.add_theme_constant_override("v_separation", 6)
	page.add_child(top)
	top.add_child(_small_button("+  Nouveau PNJ", "PrimaryButton", func():
		var c := Net.server.mj_create_npc()
		_open_char_tools(c.id)))
	top.add_child(_small_button("Packs de PNJ…", "", _dialog_npc_packs))
	var lock := CheckBox.new()
	lock.text = "Les joueurs peuvent modifier leur histoire et refaire leur personnage"
	lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lock.button_pressed = Net.server.session.players_edit_sheets
	lock.toggled.connect(func(on): Net.server.set_players_edit_sheets(on))
	page.add_child(lock)
	page.add_child(GameUI.hint("Les monstres du catalogue se placent depuis « Créer › Monstres » : leur fiche est créée automatiquement."))
	_char_list = VBoxContainer.new()
	_char_list.add_theme_constant_override("separation", 6)
	page.add_child(_char_list)
	return parts[0]


func _select_character(id: String) -> void:
	_open_char_tools(id)


func _refresh_characters() -> void:
	_refresh_lobby_bar()
	if _overlay_kind == "char" and _char_tools != null and is_instance_valid(_char_tools):
		_char_tools.rebuild()
	if _char_list == null:
		return
	var server := Net.server
	UIKit.clear(_char_list)
	var ids: Array = server.characters.keys()
	ids.sort_custom(func(a, b):
		var pa: bool = server.players.has(a)
		var pb: bool = server.players.has(b)
		if pa != pb:
			return pa
		return String(server.characters[a].name).naturalnocasecmp_to(server.characters[b].name) < 0)
	if ids.is_empty():
		_char_list.add_child(UIKit.label("Les fiches des joueurs apparaîtront ici dès qu'ils les auront créées.", "MutedLabel", true))
	for id in ids:
		var c: Dictionary = server.characters[id]
		var card := UIKit.card(_char_list, "", "InsetPanel")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		row.add_child(Portrait.for_sheet(c, server.content, 40))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var who := String(server.players[id].name) if server.players.has(id) else ("Monstre" if c.get("kind", "") == "monster" else "PNJ")
		col.add_child(UIKit.label("%s  ·  %s" % [c.name, who], "StrongLabel", true))
		var hp := ResourceBar.new("PV", Palette.HP, 14)
		hp.set_values(int(c.get("hp", 0)), int(c.get("hp_max", 1)), false)
		col.add_child(hp)
		var cid: String = id
		row.add_child(_small_button("Ouvrir", "", func(): _open_char_tools(cid)))


## Panneau des outils du MJ pour un personnage.
func _open_char_tools(cid: String) -> void:
	var server := Net.server
	if not server.characters.has(cid):
		return
	var panel := _open_overlay("char", String(server.characters[cid].name), "person")
	_char_tools = CharacterTools.new(cid)
	_char_tools.edit_requested.connect(_open_character_editor)
	_char_tools.create_item_requested.connect(func(target):
		_open_content_editor("items", {"name": "Nouvel objet", "category": "unique", "rarity": "rare", "icon": "gem"}, target))
	_char_tools.place_requested.connect(func(id):
		var t := server.mj_place_character(id)
		if not t.is_empty():
			_edit_map = server.active_map
			_refresh_map_select()
			_load_edit_map()
			_map_view.selected = t.id
			_refresh_inspector()
			_close_overlay()
			_show("table"))
	_char_tools.deleted.connect(_close_overlay)
	panel.body.add_child(_char_tools)


func _open_character_editor(cid: String) -> void:
	var server := Net.server
	var sheet: Dictionary = server.characters.get(cid, {})
	if sheet.is_empty():
		return
	var panel := _open_overlay("edit", "Modifier %s" % sheet.name, "journal")
	var editor := CharacterEditor.new(sheet, server.universe, true)
	editor.saved.connect(func(data):
		server.mj_save_character(data)
		_open_char_tools(cid))
	editor.cancelled.connect(func(): _open_char_tools(cid))
	panel.body.add_child(editor)


# ---------------------------------------------------------------------------
# Panneaux superposés, éditeurs de contenu et de quêtes
# ---------------------------------------------------------------------------

func _open_overlay(kind: String, title: String, icon_name: String = "") -> OverlayPanel:
	_close_overlay()
	_overlay = OverlayPanel.new(title, not _narrow, icon_name)
	_overlay_kind = kind
	_overlay.closed.connect(func():
		_overlay = null
		_overlay_kind = ""
		_char_tools = null)
	add_child(_overlay)
	return _overlay


func _close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.close()
	_overlay = null
	_overlay_kind = ""
	_char_tools = null


func _show_info(title: String, content: Control) -> void:
	var panel := _open_overlay("info", title, "star")
	panel.body.add_child(content)


## Éditeur d'une entrée du catalogue. give_to : personnage qui reçoit l'objet créé.
func _open_content_editor(kind: String, entry: Dictionary, give_to: String = "", on_saved: Callable = Callable()) -> void:
	var server := Net.server
	var title := "%s : %s" % [ContentPanel.KIND_LABELS.get(kind, kind), entry.get("name", "")]
	var panel := _open_overlay("content", title, "sparkle")
	var editor := ContentEditor.new(kind, entry, server.content)
	editor.saved.connect(func(k, data):
		var clean := server.mj_content_save(k, data)
		if clean.is_empty():
			return
		if on_saved.is_valid():
			on_saved.call(clean)
			return
		if give_to != "" and k == "items":
			server.mj_give_item(give_to, String(clean.id), 1)
			_open_char_tools(give_to)
			return
		_close_overlay()
		_content_panel.rebuild())
	editor.cancelled.connect(func():
		if give_to != "":
			_open_char_tools(give_to)
		else:
			_close_overlay())
	panel.body.add_child(editor)


func _on_content_changed() -> void:
	if _overlay_kind != "content" and _content_panel != null:
		_content_panel.rebuild()


func _open_quest_editor(quest: Dictionary) -> void:
	var server := Net.server
	var panel := _open_overlay("quest", "Quête" if quest.is_empty() else String(quest.get("title", "Quête")), "journal")
	var editor := QuestEditor.new(quest)
	editor.saved.connect(func(data, give):
		data["give"] = give
		server.mj_quest_save(data)
		_close_overlay())
	editor.cancelled.connect(_close_overlay)
	editor.create_item_requested.connect(func():
		# L'objet sur mesure est ajouté au catalogue puis à la récompense.
		var draft := editor.collect()
		_open_content_editor("items", {"name": "Récompense", "category": "unique", "rarity": "rare", "icon": "gem"}, "", func(clean):
			draft.rewards.items.append({"item": String(clean.id), "qty": 1})
			_open_quest_editor(draft)))
	panel.body.add_child(editor)


## Coffre commun : ce que les joueurs peuvent se partager.
func _refresh_loot() -> void:
	if _loot_box == null:
		return
	var server := Net.server
	UIKit.clear(_loot_box)
	if server.loot.is_empty():
		_loot_box.add_child(UIKit.label("Vide. Le butin des combats et certaines récompenses arrivent ici.", "MutedLabel", true))
		return
	for item in server.loot:
		var row := HBoxContainer.new()
		_loot_box.add_child(row)
		row.add_child(GameUI.item_slot(item, 36))
		var l := UIKit.label(String(item.name), "", true)
		l.add_theme_color_override("font_color", Content.rarity_color(String(item.get("rarity", "commun"))).lightened(0.15))
		row.add_child(l)
		var uid := String(item.uid)
		var menu := MenuButton.new()
		menu.text = "Donner"
		menu.flat = false
		menu.theme_type_variation = "Button"
		var targets: Array = []
		for cid in server.characters:
			if server.players.has(cid):
				targets.append(cid)
				menu.get_popup().add_item(String(server.characters[cid].name))
		menu.get_popup().index_pressed.connect(func(i): server.give_loot_to(uid, String(targets[i])))
		row.add_child(menu)
		row.add_child(_small_button("×", "DangerButton", func(): server.mj_loot_remove(uid)))


# ---------------------------------------------------------------------------
# Récit : fil, actions en attente, saisie
# ---------------------------------------------------------------------------

func _build_story() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	_feed = FeedView.new(Protocol.MJ_ID, true)
	_feed.resolve_requested.connect(_on_resolve)
	_feed.roll_request_requested.connect(_on_request_action_roll)
	_feed.check_requested.connect(_on_check_requested)
	_feed.consequence_requested.connect(func(id, kind):
		var err := Net.server.mj_action_consequence(id, kind)
		if err != "":
			_feed.add_notice(err, Palette.DANGER))
	main.add_child(_feed)
	var pending := UIKit.card(null, "")
	var pending_panel := pending.get_parent() as Control
	_pending_title = UIKit.label("Actions en attente", "HeadingLabel")
	pending.add_child(_pending_title)
	_pending_box = UIKit.vscroll(pending)
	_pending_box.add_theme_constant_override("separation", 8)
	# Actions en attente au-dessus du fil (repliées quand il n'y en a pas).
	pending_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.add_child(pending_panel)
	page.add_child(main)
	return page


## Barre du bas : narration / messages / dés, et événements rapides.
func _build_bottom_bar() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "NavPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var quick := HFlowContainer.new()
	quick.add_theme_constant_override("h_separation", 6)
	quick.add_theme_constant_override("v_separation", 6)
	col.add_child(quick)
	var narr := CheckBox.new()
	narr.text = "Narration (mise en forme récit)"
	narr.button_pressed = _narrate_mode
	narr.toggled.connect(func(on): _narrate_mode = on)
	quick.add_child(narr)
	var events := MenuButton.new()
	_events_menu = events
	events.tooltip_text = "Ctrl + E"
	events.text = "Événement rapide…"
	events.flat = false
	events.theme_type_variation = "PrimaryButton"
	events.custom_minimum_size.y = 38
	var actions := [["Épreuve de groupe (jet pour chacun)", _event_check], ["Dégâts ou soins de groupe", _event_group_hp],
		["Récompense de groupe (XP, or, objet)", _event_reward], ["Embuscade (monstres + combat)", _event_ambush],
		["Créer un objet", func(): _open_content_editor("items", {"name": "Nouvel objet", "category": "unique", "rarity": "rare", "icon": "gem"})],
		["Nouvelle quête", func(): _open_quest_editor({})]]
	for a in actions:
		events.get_popup().add_item(a[0])
	events.get_popup().index_pressed.connect(func(i): actions[i][1].call())
	quick.add_child(events)
	quick.add_child(_small_button("Nouvelle quête", "", func(): _open_quest_editor({})))
	_composer = Composer.new([], [], false)
	_composer.send_message.connect(func(to, text):
		if _narrate_mode:
			Net.server.mj_narrate(text, to)
		else:
			Net.server.mj_send_message(to, text))
	_composer.send_roll.connect(func(to, expr, label):
		_tray_waiting = true
		_tray.start(expr, label)
		var err := Net.server.mj_roll(expr, to, label)
		if err != "":
			_tray_waiting = false
			_tray.visible = false
			_feed.add_notice(err, Palette.DANGER))
	col.add_child(_composer)
	return panel


# --- Événements rapides ---

func _event_form(title: String, build: Callable, on_ok: Callable) -> void:
	var panel := _open_overlay("event", title, "sparkle")
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	panel.body.add_child(form)
	var getters: Dictionary = build.call(form)
	var ok := UIKit.button("Lancer", "PrimaryButton", func():
		var values := {}
		for k in getters:
			values[k] = getters[k].call()
		var err: String = on_ok.call(values)
		if err != "":
			_feed.add_notice(err, Palette.DANGER)
		_close_overlay())
	ok.custom_minimum_size.y = 52
	panel.body.add_child(ok)


func _event_check() -> void:
	_event_form("Épreuve de groupe", _form_check, func(v): return Net.server.mj_event("group_check", v))


func _form_check(form: VBoxContainer) -> Dictionary:
	form.add_child(UIKit.label("Chaque joueur reçoit une demande de jet. Avec une caractéristique, le jeu ajoute sa valeur au d20.", "MutedLabel", true))
	var label := UIKit.line_edit("", "Ex. : Grimper la falaise")
	UIKit.field(form, "Épreuve", label)
	var st := OptionButton.new()
	st.add_item("Aucune (d20 seul)")
	st.set_item_metadata(0, "")
	for s in Content.stat_names(Net.server.content):
		st.add_item(String(s))
		st.set_item_metadata(st.item_count - 1, String(s))
	UIKit.field(form, "Caractéristique", st)
	var diff := UIKit.spin(15, 1, 40)
	UIKit.field(form, "Difficulté (10 facile, 15 moyen, 20 difficile)", diff)
	var getters := {}
	getters["text"] = func(): return label.text
	getters["stat"] = func(): return String(st.get_item_metadata(st.selected))
	getters["difficulty"] = func(): return int(diff.value)
	return getters


func _event_group_hp() -> void:
	_event_form("Dégâts ou soins de groupe", _form_group_hp, func(v): return Net.server.mj_event("group_damage" if int(v.kind) == 0 else "group_heal", v))


func _form_group_hp(form: VBoxContainer) -> Dictionary:
	var kind := OptionButton.new()
	kind.add_item("Dégâts (piège, explosion, chute…)")
	kind.add_item("Soins (source, bénédiction…)")
	UIKit.field(form, "Type", kind)
	var dice := UIKit.line_edit("2d6", "2d6, 1d10+2…")
	UIKit.field(form, "Dés (tirés pour chacun)", dice)
	var text := UIKit.line_edit("", "Ex. : Le sol s'effondre sous vos pieds !")
	UIKit.field(form, "Ce qui se passe", text)
	var getters := {}
	getters["kind"] = func(): return kind.selected
	getters["dice"] = func(): return dice.text
	getters["text"] = func(): return text.text
	return getters


func _event_reward() -> void:
	_event_form("Récompense de groupe", _form_reward, func(v): return Net.server.mj_event("group_reward", v))


func _form_reward(form: VBoxContainer) -> Dictionary:
	var xp := UIKit.spin(50, 0, 99999)
	UIKit.field(form, "XP pour chacun", xp)
	var gold := UIKit.spin(0, -9999, 99999)
	UIKit.field(form, "Or pour chacun", gold)
	var item := OptionButton.new()
	item.add_item("(aucun objet)")
	item.set_item_metadata(0, "")
	for e in Content.list(Net.server.content, "items"):
		item.add_item("%s (%s)" % [e.name, GameUI.rarity_name(e)])
		item.set_item_metadata(item.item_count - 1, String(e.id))
	UIKit.field(form, "Objet (dans le coffre du groupe)", item)
	var text := UIKit.line_edit("", "Ex. : Le roi vous remercie.")
	UIKit.field(form, "Message", text)
	var getters := {}
	getters["xp"] = func(): return int(xp.value)
	getters["gold"] = func(): return int(gold.value)
	getters["item"] = func(): return String(item.get_item_metadata(item.selected))
	getters["text"] = func(): return text.text
	return getters


func _event_ambush() -> void:
	_event_form("Embuscade", _form_ambush, func(v): return Net.server.mj_event("ambush", v))


func _form_ambush(form: VBoxContainer) -> Dictionary:
	form.add_child(UIKit.label("Les monstres apparaissent près du point de départ de la carte affichée, puis le combat commence.", "MutedLabel", true))
	var pickers: Array = []
	for i in 3:
		var row := HBoxContainer.new()
		form.add_child(row)
		var o := OptionButton.new()
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		o.add_item("(aucun)")
		o.set_item_metadata(0, "")
		for m in Content.list(Net.server.content, "monsters"):
			o.add_item("%s (%d PV)" % [m.name, int(m.hp)])
			o.set_item_metadata(o.item_count - 1, String(m.id))
		if i == 0 and o.item_count > 1:
			o.select(1)
		row.add_child(o)
		var n := UIKit.spin(2 if i == 0 else 1, 1, 8)
		n.prefix = "×"
		row.add_child(n)
		pickers.append([o, n])
	var text := UIKit.line_edit("", "Ex. : Des silhouettes surgissent des fourrés !")
	UIKit.field(form, "Annonce", text)
	var getters := {}
	getters["monsters"] = func():
		var ids: Array = []
		for p in pickers:
			var id := String(p[0].get_item_metadata(p[0].selected))
			if id != "":
				for k in int(p[1].value):
					ids.append(id)
		return ids
	getters["text"] = func(): return text.text
	return getters


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
	_journal_message(m)
	if _tray_waiting and m.get("kind", "") == Protocol.KIND_ROLL and m.get("from", "") == Protocol.MJ_ID:
		_tray_waiting = false
		_tray.finish(m.get("roll", {}), String(m.get("text", "")))
	if m.get("from", "") != Protocol.MJ_ID:
		_badge("story", true)
	if m.get("kind", "") == Protocol.KIND_ACTION:
		_refresh_pending()


func _on_message_updated(m: Dictionary) -> void:
	_feed.update_message(m)
	_refresh_pending()


func _on_check_requested(message_id: String, skill: String, dc: int, player_rolls: bool) -> void:
	var err := Net.server.mj_request_action_roll(message_id, "d20", dc, skill) if player_rolls else Net.server.mj_check_action(message_id, skill, dc)
	if err != "":
		_feed.add_notice(err, Palette.DANGER)


func _on_request_action_roll(message_id: String, expr: String, difficulty: int) -> void:
	var err := Net.server.mj_request_action_roll(message_id, expr, difficulty)
	if err != "":
		_feed.add_notice(err, Palette.DANGER)


func _dialog_request_roll(player_id: String, player_name: String) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 340
	var skill := OptionButton.new()
	skill.fit_to_longest_item = false
	for id in Checks.SKILLS:
		skill.add_item("%s (d20 + %s)" % [Checks.SKILLS[id].name, Checks.SKILLS[id].stat])
		skill.set_item_metadata(skill.item_count - 1, id)
	skill.add_item("Dé libre (formule ci-dessous)")
	skill.set_item_metadata(skill.item_count - 1, "")
	UIKit.field(box, "Épreuve (résultat et conséquences automatiques)", skill)
	var label := UIKit.line_edit("", "Ex. : Grimper au clocher")
	UIKit.field(box, "Pour quoi ? (facultatif)", label)
	var row := HBoxContainer.new()
	box.add_child(row)
	var expr := UIKit.field(row, "Dé libre", UIKit.line_edit("d20", "d20, 2d6+1…")) as LineEdit
	var diff := UIKit.field(row, "Difficulté (DD)", UIKit.spin(14, 0, 100)) as SpinBox
	var public := CheckBox.new()
	public.text = "Résultat visible par tout le groupe"
	public.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	public.button_pressed = true
	box.add_child(public)
	_dialog("Demander un jet à %s" % player_name, box, func():
		var err := Net.server.mj_request_roll(player_id, expr.text, label.text, int(diff.value), public.button_pressed, String(skill.get_item_metadata(skill.selected)))
		if err != "":
			_feed.add_notice(err, Palette.DANGER))


func _dialog_npc_packs() -> void:
	var server := Net.server
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 420)
	box.add_child(UIKit.label("Cochez les personnages à ajouter à la campagne. Vous pourrez ensuite les modifier et les placer sur la carte.", "MutedLabel", true))
	var list := UIKit.vscroll(box)
	var checks: Array = []
	for pack in NpcLibrary.packs(server.session.universe):
		var h := UIKit.label(String(pack.name), "HeadingLabel", true)
		h.add_theme_font_size_override("font_size", 17)
		list.add_child(h)
		list.add_child(UIKit.label(String(pack.get("description", "")), "MutedLabel", true))
		var all := CheckBox.new()
		all.text = "Tout le pack (%d)" % pack.npcs.size()
		list.add_child(all)
		var pack_checks: Array = []
		for entry in pack.npcs:
			var c := CheckBox.new()
			c.text = "%s — %s" % [entry.get("name", "?"), entry.get("concept", "")]
			c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.set_meta("entry", entry)
			list.add_child(c)
			checks.append(c)
			pack_checks.append(c)
		all.toggled.connect(func(on):
			for c in pack_checks:
				c.button_pressed = on)
	_dialog("Packs de PNJ", box, func():
		var chosen: Array = []
		for c in checks:
			if c.button_pressed:
				chosen.append(c.get_meta("entry"))
		var n := server.mj_import_npcs(chosen)
		if n > 0:
			_feed.add_notice("%d PNJ ajoutés à la campagne." % n, Palette.OK))


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
	(_pending_box.get_parent() as Control).custom_minimum_size.y = 0 if pending.is_empty() else 240
	(_pending_box.get_parent() as Control).visible = not pending.is_empty()
	if pending.is_empty():
		_pending_title.text = "Aucune action en attente : les joueurs déclarent leurs actions depuis le Récit (mode « Action »)."
		_pending_title.add_theme_font_size_override("font_size", 15)
		return
	_pending_title.remove_theme_font_size_override("font_size")
	for m in pending:
		var card := UIKit.card(_pending_box, "", "InsetPanel")
		card.add_child(UIKit.label("%s  ·  %s%s" % [m.from_name, Protocol.format_time(m.ts), "  · privé" if m.to != Protocol.TO_ALL else ""], "MutedLabel", true))
		card.add_child(UIKit.label(String(m.text), "", true))
		card.add_child(_feed.resolve_form(String(m.id), String(m.text)))


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


## Zone basse, à droite : journal des actions récentes (combat, système,
## récompenses, connexions), une ligne chacune, la plus récente en bas.
func _build_journal() -> Control:
	var body := GameUI.section(null, "Journal des actions", "hourglass", "InsetPanel")
	var panel := body.get_parent() as Control
	panel.custom_minimum_size.x = 190
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_list = UIKit.vscroll(body)
	_journal_list.add_theme_constant_override("separation", 2)
	UIKit.follow_bottom(_journal_list)
	for m in Net.server.messages.slice(maxi(0, Net.server.messages.size() - 40)):
		_journal_message(m)
	return panel


func _journal_add(text: String, color: Color) -> void:
	if _journal_list == null or text.strip_edges() == "":
		return
	# Une ligne par entrée (pas de retour à la ligne : la zone se redimensionne).
	var l := UIKit.label("%s  %s" % [Protocol.format_time(Protocol.now()), text], "MutedLabel")
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.tooltip_text = text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	_journal_list.add_child(l)
	if _journal_list.get_child_count() > 200:
		_journal_list.get_child(0).queue_free()


func _journal_message(m: Dictionary) -> void:
	var kind := String(m.get("kind", ""))
	var first := String(m.get("text", "")).get_slice("\n", 0)
	match kind:
		Protocol.KIND_COMBAT:
			_journal_add("Combat : " + first, Palette.HP.lightened(0.3))
		Protocol.KIND_SYSTEM:
			_journal_add(first, Palette.MUTED)
		Protocol.KIND_REWARD:
			_journal_add("Récompense : " + first, Palette.ULT)
		Protocol.KIND_ACTION:
			_journal_add("%s propose : %s" % [m.get("from_name", "?"), first], Palette.GOLD)
		Protocol.KIND_ROLL:
			var r: Dictionary = m.get("roll", {})
			_journal_add("%s lance %s → %s" % [m.get("from_name", "?"), r.get("expr", "?"), r.get("total", "?")], Palette.VIOLET.lightened(0.4))


## Raccourcis clavier du MJ (PC).
const SHORTCUTS := [
	["Ctrl + S", "Sauvegarder"], ["F1 / F2", "Carte / Récit"], ["F5", "Tour suivant (combat)"],
	["Ctrl + E", "Événement rapide"], ["Ctrl + Q", "Nouvelle quête"], ["Ctrl + N", "Écrire au groupe"], ["Ctrl + Z", "Annuler la dernière retouche de carte"],
	["Échap", "Fermer un panneau"],
]


func _unhandled_key_input(event: InputEvent) -> void:
	if Net.server == null or _tabs == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	var handled := true
	if k.ctrl_pressed and k.keycode == KEY_S:
		Net.server.save()
		_notifier.push("Campagne sauvegardée.", "success")
	elif k.keycode == KEY_F1:
		_show("table")
	elif k.keycode == KEY_F2:
		_show("story")
	elif k.keycode == KEY_F5 and Net.server.phase.get("type", "") == "combat":
		Net.server.mj_next_turn()
	elif k.ctrl_pressed and k.keycode == KEY_E and _events_menu != null:
		_events_menu.show_popup()
	elif k.ctrl_pressed and k.keycode == KEY_Q:
		_open_quest_editor({})
	elif k.ctrl_pressed and k.keycode == KEY_N:
		_composer.focus_text()
	elif k.ctrl_pressed and k.keycode == KEY_Z:
		Net.server.mj_undo(_edit_map)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _add_log(entry: Dictionary) -> void:
	_journal_add(String(entry.get("text", "")), {"ok": Palette.OK, "warn": Palette.WARN, "ask": Palette.GOLD}.get(entry.get("kind", ""), Palette.MUTED))
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
	ConfirmBox.ask(self, "Confirmation", text, "Confirmer", on_ok, true)


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
