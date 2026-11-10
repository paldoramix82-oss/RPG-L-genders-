extends Control
## Écran d'accueil : héberger (PC du MJ) ou rejoindre (téléphone d'un joueur).
## Le thème principal joue en fond (bouton pour le couper). En paysage, le
## titre passe à gauche et les choix à droite.

var _music_button: Button


func _ready() -> void:
	Music.set_menu(true)
	# Fond pixel art (tools/make_title.py) : couvre l'écran, pixels nets.
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/title_bg.png")
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var vp := get_viewport_rect().size
	_fit_backdrop(bg, vp)
	resized.connect(func(): _fit_backdrop(bg, get_viewport_rect().size))
	var wide := vp.x > vp.y * 1.15
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28 if wide else 16)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/title_logo.png")
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	var lw := minf(vp.x - 40, 560.0 if wide else 420.0)
	logo.custom_minimum_size = Vector2(lw, lw * float(logo.texture.get_height()) / logo.texture.get_width())
	logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if wide else Control.SIZE_SHRINK_CENTER
	col.add_child(logo)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	# Menu : liste de boutons, le choix principal en or.
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 8)
	choices.custom_minimum_size.x = minf(vp.x - 32, 340.0)
	choices.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if wide else Control.SIZE_SHRINK_CENTER
	col.add_child(choices)
	var mobile := App.is_mobile()
	var host := _menu_button(choices, "Héberger une partie", "Sur le PC du MJ : créer ou reprendre une campagne.", func(): App.goto(App.SCENE_HOST), not mobile)
	host.disabled = not App.can_host()
	var join := _menu_button(choices, "Rejoindre une partie", "Depuis un téléphone, sur le même Wi-Fi que le MJ.", func(): App.goto(App.SCENE_JOIN), mobile)
	if mobile:
		choices.move_child(join, 0)
		join.grab_focus.call_deferred()
	else:
		host.grab_focus.call_deferred()
	_music_button = _menu_button(choices, "", "", _toggle_music, false)
	_refresh_music()
	if not mobile:
		_menu_button(choices, "Quitter", "", func(): get_tree().quit(), false)
	var footer := UIKit.label("v%s  ·  protocole %d%s" % [
		ProjectSettings.get_setting("application/config/version", "0"),
		Protocol.VERSION,
		"" if App.profile == "default" else "  ·  profil « %s »" % App.profile,
	], "MutedLabel")
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	footer.add_theme_constant_override("outline_size", 4)
	footer.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if wide else HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(footer)
	# Entrée : le logo descend, le menu apparaît.
	logo.modulate.a = 0.0
	choices.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(logo, "modulate:a", 1.0, 0.5)
	tw.tween_property(choices, "modulate:a", 1.0, 0.35)


## Fond qui couvre l'écran, centré sur le château (x = 300 sur 480) quand
## l'écran est plus étroit que l'image (téléphone en portrait).
func _fit_backdrop(bg: TextureRect, vp: Vector2) -> void:
	var tw := float(bg.texture.get_width())
	var th := float(bg.texture.get_height())
	var k := maxf(vp.x / tw, vp.y / th)
	var sz := Vector2(tw, th) * k
	var x := clampf(vp.x * 0.5 - 300.0 * k, vp.x - sz.x, 0.0)
	bg.position = Vector2(x, (vp.y - sz.y) * 0.5)
	bg.size = sz


## Bouton du menu titre : « › » devant le choix principal (doré).
func _menu_button(parent: Node, text: String, hint: String, on_pressed: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.theme_type_variation = "PrimaryButton" if primary else ""
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = ("›  " if primary else "   ") + text
	b.tooltip_text = hint
	b.custom_minimum_size.y = 52
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


func _toggle_music() -> void:
	Music.set_enabled(not Music.enabled())
	_refresh_music()


func _refresh_music() -> void:
	_music_button.text = "   Musique : %s" % ("activée" if Music.enabled() else "coupée")


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
