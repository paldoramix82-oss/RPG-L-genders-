extends Control
## Écran d'accueil : héberger (PC du MJ) ou rejoindre (téléphone d'un joueur).
## Le thème principal joue en fond (bouton pour le couper). En paysage, le
## titre passe à gauche et les choix à droite.

var _music_button: Button


func _ready() -> void:
	Music.set_menu(true)
	add_child(Backdrop.new())
	var vp := get_viewport_rect().size
	var landscape := vp.x > vp.y * 1.15 and vp.y < 640
	var scroll := TouchScroll.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var column := CenteredColumn.new()
	column.max_width = 860 if landscape else 460
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size.y = vp.y - 8
	column.add_child(center)
	var layout: BoxContainer = HBoxContainer.new() if landscape else VBoxContainer.new()
	layout.add_theme_constant_override("separation", 28 if landscape else 14)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(layout)

	var head := VBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 6)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(head)
	var crest := Emblem.new("sword", Palette.VIOLET, 84 if not landscape else 72)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.add_child(crest)
	var title := UIKit.label("LEGENDERS", "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	var rpg := UIKit.label("R  P  G", "HeadingLabel")
	rpg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rpg.add_theme_color_override("font_color", Palette.VIOLET.lightened(0.25))
	head.add_child(rpg)
	head.add_child(GameUI.ornament())
	var subtitle := UIKit.label("Des histoires à vivre ensemble, autour d'une même table.", "MutedLabel", true)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(subtitle)

	var choices := VBoxContainer.new()
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 12)
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(choices)
	var host := _choice(choices, "castle", "Héberger une partie", "Sur le PC du maître du jeu : créez la partie, les joueurs la rejoignent.", func(): App.goto(App.SCENE_HOST), not App.is_mobile())
	host.disabled = not App.can_host()
	var join := _choice(choices, "person", "Rejoindre une partie", "Depuis votre téléphone, sur le même Wi-Fi que le MJ.", func(): App.goto(App.SCENE_JOIN), App.is_mobile())
	if App.is_mobile():
		join.grab_focus.call_deferred()

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 10)
	choices.add_child(bottom)
	_music_button = UIKit.button("", "NavButton", _toggle_music)
	_music_button.custom_minimum_size = Vector2(0, 40)
	_music_button.add_theme_font_size_override("font_size", 15)
	_music_button.icon = _music_icon()
	bottom.add_child(_music_button)
	_refresh_music()
	var footer := UIKit.label("v%s  ·  protocole %d%s" % [
		ProjectSettings.get_setting("application/config/version", "0"),
		Protocol.VERSION,
		"" if App.profile == "default" else "  ·  profil « %s »" % App.profile,
	], "MutedLabel")
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Palette.FAINT)
	choices.add_child(footer)

	# Entrée : le titre monte doucement, les choix apparaissent.
	head.modulate.a = 0.0
	choices.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(head, "modulate:a", 1.0, 0.5)
	tw.tween_property(choices, "modulate:a", 1.0, 0.35)


## Grand bouton de choix : icône, titre, explication en une ligne.
func _choice(parent: Node, icon_name: String, text: String, hint: String, on_pressed: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.theme_type_variation = "PrimaryButton" if primary else ""
	b.custom_minimum_size.y = 76
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var badge := GameUI.icon_badge(icon_name, Palette.GOLD if primary else Palette.TEXT, 42)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var t := UIKit.label(text, "StrongLabel")
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Palette.GOLD if primary else Palette.TEXT)
	col.add_child(t)
	var h := UIKit.label(hint, "MutedLabel", true)
	h.add_theme_font_size_override("font_size", 14)
	col.add_child(h)
	for c in [t, h]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _toggle_music() -> void:
	Music.set_enabled(not Music.enabled())
	_refresh_music()


func _refresh_music() -> void:
	_music_button.text = "  Musique : %s" % ("activée" if Music.enabled() else "coupée")


func _music_icon() -> Texture2D:
	# Petite icône de note, rendue une fois dans une image.
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(4, 18):
		img.set_pixel(15, y, Palette.GOLD)
		img.set_pixel(16, y, Palette.GOLD)
	for x in range(15, 21):
		img.set_pixel(x, 4, Palette.GOLD)
		img.set_pixel(x, 5, Palette.GOLD)
	for y in range(15, 21):
		for x in range(9, 17):
			if Vector2(x - 12.5, y - 17.5).length() < 3.6:
				img.set_pixel(x, y, Palette.GOLD)
	return ImageTexture.create_from_image(img)
