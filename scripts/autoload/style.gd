extends Node
## Style — construit le thème visuel commun au PC et à Android, et adapte
## l'échelle de l'interface à la densité de l'écran des téléphones.

const FONT_BODY := preload("res://assets/fonts/AlegreyaSans-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/AlegreyaSans-Bold.ttf")
const FONT_DISPLAY_FILE := preload("res://assets/fonts/Cinzel.ttf")

var theme: Theme
var font_display: FontVariation


func _ready() -> void:
	font_display = FontVariation.new()
	font_display.base_font = FONT_DISPLAY_FILE
	font_display.variation_opentype = {"wght": 600}
	theme = _build_theme()
	get_tree().root.theme = theme
	if App.is_mobile():
		get_window().size_changed.connect(_apply_mobile_scale)
		_apply_mobile_scale()
		apply_orientation()


## Sur téléphone : le petit côté de l'écran fait environ 400 unités, quelle que
## soit la résolution et l'orientation (portrait ou paysage), pour des textes
## lisibles et des boutons assez grands pour les doigts.
func _apply_mobile_scale() -> void:
	var size := DisplayServer.window_get_size()
	if size.x <= 0 or size.y <= 0:
		return
	var dpi := float(DisplayServer.screen_get_dpi())
	var density := clampf(dpi / 160.0, 1.0, 4.0)
	var short_side := float(mini(size.x, size.y))
	var logical_short := clampf(short_side / density, 360.0, 560.0)
	var k := logical_short / short_side
	get_window().content_scale_size = Vector2i(int(size.x * k), int(size.y * k))


## Orientation choisie par le joueur : « auto » (selon le capteur), « portrait »
## ou « paysage ». Réglage local à l'appareil.
func apply_orientation() -> void:
	if not OS.has_feature("mobile"):
		return
	match String(App.get_setting("display", "orientation", "auto")):
		"portrait":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
		"landscape":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
		_:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_BODY
	t.default_font_size = 19

	# --- Textes ---
	t.set_color("font_color", "Label", Palette.TEXT)
	_variation(t, "TitleLabel", "Label")
	t.set_font("font", "TitleLabel", font_display)
	t.set_font_size("font_size", "TitleLabel", 44)
	t.set_color("font_color", "TitleLabel", Palette.GOLD)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.65))
	t.set_constant("shadow_offset_x", "TitleLabel", 0)
	t.set_constant("shadow_offset_y", "TitleLabel", 2)
	_variation(t, "HeadingLabel", "Label")
	t.set_font("font", "HeadingLabel", font_display)
	t.set_font_size("font_size", "HeadingLabel", 21)
	t.set_color("font_color", "HeadingLabel", Palette.GOLD)
	_variation(t, "StrongLabel", "Label")
	t.set_font("font", "StrongLabel", FONT_BOLD)
	_variation(t, "MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", Palette.MUTED)
	t.set_font_size("font_size", "MutedLabel", 16)
	_variation(t, "CodeLabel", "Label")
	t.set_font("font", "CodeLabel", font_display)
	t.set_font_size("font_size", "CodeLabel", 40)
	t.set_color("font_color", "CodeLabel", Palette.TEXT)

	t.set_color("default_color", "RichTextLabel", Palette.TEXT)
	t.set_font("normal_font", "RichTextLabel", FONT_BODY)
	t.set_font("bold_font", "RichTextLabel", FONT_BOLD)
	t.set_font_size("normal_font_size", "RichTextLabel", 19)
	t.set_font_size("bold_font_size", "RichTextLabel", 19)

	# --- Panneaux ---
	# Cartes : coins biseautés, dégradé discret, équerres dorées.
	var card := OrnateStyle.make(Palette.PANEL.lightened(0.04), Palette.PANEL.darkened(0.18), Palette.BORDER, Color(Palette.GOLD_DIM, 0.85), 8, 18)
	card.inner_line = true
	t.set_stylebox("panel", "PanelContainer", card)
	_variation(t, "CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", card)
	_variation(t, "InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", OrnateStyle.make(Palette.BG_DEEP.lightened(0.02), Palette.BG_DEEP, Palette.BORDER.darkened(0.15), Color(0, 0, 0, 0), 5, 12))
	_variation(t, "HighlightPanel", "PanelContainer")
	var hl := OrnateStyle.make(Palette.GOLD_DEEP.lightened(0.06), Palette.GOLD_DEEP.darkened(0.45), Palette.GOLD_DIM, Palette.GOLD, 8, 16)
	hl.inner_line = true
	t.set_stylebox("panel", "HighlightPanel", hl)
	_variation(t, "MagicPanel", "PanelContainer")
	var mg := OrnateStyle.make(Palette.VIOLET_DEEP.lightened(0.05), Palette.VIOLET_DEEP.darkened(0.4), Palette.VIOLET_DIM, Palette.VIOLET.lightened(0.3), 8, 16)
	mg.inner_line = true
	t.set_stylebox("panel", "MagicPanel", mg)
	_variation(t, "DangerPanel", "PanelContainer")
	t.set_stylebox("panel", "DangerPanel", OrnateStyle.make(Color("3a2023"), Color("221416"), Palette.DANGER.darkened(0.3), Palette.DANGER, 8, 16))
	_variation(t, "BarPanel", "PanelContainer")
	var bar := _box(Palette.BG_DEEP, Color(Palette.GOLD_DIM, 0.5), 0, 0, 12)
	bar.border_width_bottom = 1
	t.set_stylebox("panel", "BarPanel", bar)
	_variation(t, "NavPanel", "PanelContainer")
	var nav := _box(Palette.BG_DEEP, Color(Palette.GOLD_DIM, 0.6), 0, 0, 6)
	nav.border_width_top = 1
	nav.shadow_color = Color(0, 0, 0, 0.45)
	nav.shadow_size = 10
	t.set_stylebox("panel", "NavPanel", nav)
	_variation(t, "BubbleMine", "PanelContainer")
	t.set_stylebox("panel", "BubbleMine", _box(Palette.VIOLET_DEEP, Palette.VIOLET_DIM, 1, 8, 10))
	_variation(t, "BubbleOther", "PanelContainer")
	t.set_stylebox("panel", "BubbleOther", _box(Palette.PANEL_ALT, Palette.BORDER, 1, 8, 10))
	_variation(t, "BubbleMJ", "PanelContainer")
	t.set_stylebox("panel", "BubbleMJ", _box(Palette.GOLD_DEEP, Palette.GOLD_DIM, 1, 8, 10))
	_variation(t, "BubblePrivate", "PanelContainer")
	t.set_stylebox("panel", "BubblePrivate", _box(Color("2a2338"), Palette.PRIVATE.darkened(0.35), 1, 8, 10))

	# --- Boutons ---
	_button_styles(t, "Button", Palette.PANEL_ALT, Palette.BORDER, Palette.TEXT)
	_variation(t, "PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", Palette.GOLD_DEEP, Palette.GOLD_DIM, Palette.GOLD)
	t.set_font("font", "PrimaryButton", FONT_BOLD)
	_variation(t, "DangerButton", "Button")
	_button_styles(t, "DangerButton", Color("3a2425"), Palette.DANGER.darkened(0.35), Palette.DANGER.lightened(0.2))
	_variation(t, "NavButton", "Button")
	_button_styles(t, "NavButton", Color(0, 0, 0, 0), Color(0, 0, 0, 0), Palette.MUTED)
	var nav_on := OrnateStyle.make(Palette.VIOLET_DEEP.lightened(0.05), Palette.VIOLET_DEEP.darkened(0.2), Palette.GOLD_DIM, Color(0, 0, 0, 0), 5, 10)
	t.set_stylebox("pressed", "NavButton", nav_on)
	t.set_stylebox("hover_pressed", "NavButton", nav_on)
	t.set_color("font_pressed_color", "NavButton", Palette.GOLD)
	t.set_font_size("font_size", "NavButton", 17)

	t.set_color("font_color", "CheckBox", Palette.TEXT)
	t.set_color("font_hover_color", "CheckBox", Palette.GOLD)
	t.set_color("font_pressed_color", "CheckBox", Palette.TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", Palette.GOLD)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 4
	empty.content_margin_top = 8
	empty.content_margin_bottom = 8
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(s, "CheckBox", empty)

	# --- Champs de saisie ---
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, OrnateStyle.make(Palette.BG_DEEP, Palette.BG_DEEP.lightened(0.03), Palette.BORDER, Color(0, 0, 0, 0), 5, 12))
		var focus_edit := OrnateStyle.make(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Palette.GOLD_DIM, Color(0, 0, 0, 0), 5, 12)
		t.set_stylebox("focus", type, focus_edit)
		t.set_stylebox("read_only", type, OrnateStyle.make(Palette.BG, Palette.BG, Palette.BORDER, Color(0, 0, 0, 0), 5, 12))
		t.set_color("font_color", type, Palette.TEXT)
		t.set_color("font_placeholder_color", type, Palette.FAINT)
		t.set_color("caret_color", type, Palette.GOLD)
		t.set_color("selection_color", type, Palette.VIOLET_DIM)

	# --- Listes déroulantes et menus ---
	t.set_stylebox("panel", "PopupMenu", OrnateStyle.make(Palette.PANEL_ALT, Palette.PANEL, Palette.GOLD_DIM, Color(0, 0, 0, 0), 6, 8))
	t.set_stylebox("hover", "PopupMenu", _box(Palette.VIOLET_DIM, Color(0, 0, 0, 0), 0, 4, 6))
	t.set_color("font_color", "PopupMenu", Palette.TEXT)
	t.set_color("font_hover_color", "PopupMenu", Palette.GOLD)
	t.set_constant("v_separation", "PopupMenu", 12)

	# --- Barres de défilement fines ---
	# Sur téléphone, barres plus larges pour être attrapées au doigt.
	var bar_margin := 8.0 if App.is_mobile() else 3.0
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 6, bar_margin))
		t.set_stylebox("grabber", type, _box(Palette.VIOLET_DIM, Color(0, 0, 0, 0), 0, 6, bar_margin))
		t.set_stylebox("grabber_highlight", type, _box(Palette.VIOLET, Color(0, 0, 0, 0), 0, 6, bar_margin))
		t.set_stylebox("grabber_pressed", type, _box(Palette.GOLD_DIM, Color(0, 0, 0, 0), 0, 6, bar_margin))

	t.set_stylebox("separator", "HSeparator", _line(Palette.BORDER))
	t.set_constant("separation", "HSeparator", 12)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_stylebox("panel", "TooltipPanel", OrnateStyle.make(Palette.PANEL_ALT, Palette.PANEL, Palette.GOLD_DIM, Color(0, 0, 0, 0), 5, 8))
	t.set_color("font_color", "TooltipLabel", Palette.TEXT)
	return t


func _variation(t: Theme, name: StringName, base: StringName) -> void:
	t.set_type_variation(name, base)


## Boutons biseautés avec léger dégradé et reflet en haut.
func _button_styles(t: Theme, type: String, bg: Color, border: Color, fg: Color) -> void:
	t.set_stylebox("normal", type, _btn(bg.lightened(0.05), bg.darkened(0.12), border))
	t.set_stylebox("hover", type, _btn(bg.lightened(0.12), bg.darkened(0.02), border.lightened(0.3) if border.a > 0 else Color(Palette.GOLD_DIM, 0.5)))
	t.set_stylebox("pressed", type, _btn(bg.darkened(0.25), bg.darkened(0.1), Palette.GOLD_DIM))
	t.set_stylebox("hover_pressed", type, _btn(bg.darkened(0.15), bg, Palette.GOLD_DIM))
	var off := _btn(Color(bg.darkened(0.35), bg.a * 0.7), Color(bg.darkened(0.45), bg.a * 0.7), Color(border.darkened(0.35), border.a * 0.6))
	off.top_glint = false
	t.set_stylebox("disabled", type, off)
	var focus := OrnateStyle.make(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Palette.GOLD_DIM, Color(0, 0, 0, 0), 5, 12)
	t.set_stylebox("focus", type, focus)
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg.lightened(0.15))
	t.set_color("font_pressed_color", type, fg)
	t.set_color("font_hover_pressed_color", type, fg)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_disabled_color", type, Palette.FAINT)


func _btn(top: Color, bottom: Color, border: Color) -> OrnateStyle:
	var sb := OrnateStyle.make(top, bottom, border, Color(0, 0, 0, 0), 5, 12)
	sb.top_glint = top.a > 0
	return sb


func _box(bg: Color, border: Color, border_width: int, radius: int, margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.7
	sb.content_margin_bottom = margin * 0.7
	sb.anti_aliasing = true
	return sb


func _line(color: Color) -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = color
	sb.thickness = 1
	return sb
