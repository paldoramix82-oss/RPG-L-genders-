extends Node
## Style — construit le thème visuel commun au PC et à Android, et adapte
## l'échelle de l'interface à la densité de l'écran des téléphones.

const FONT_PIXEL := preload("res://assets/fonts/PixelifySans.ttf")
## Repli pour les symboles absents de la police pixel (◆ ◇ ▲ ▼ ✦…).
const FONT_FALLBACK := preload("res://assets/fonts/AlegreyaSans-Regular.ttf")
const UI_DIR := "res://assets/ui/"

var theme: Theme
var font_display: FontVariation
var FONT_BODY: FontVariation
var FONT_BOLD: FontVariation


func _ready() -> void:
	var pixel: FontFile = FONT_PIXEL
	pixel.fallbacks = [FONT_FALLBACK]
	FONT_BODY = _weight(450)
	FONT_BOLD = _weight(650)
	font_display = _weight(700)
	theme = _build_theme()
	get_tree().root.theme = theme
	if App.is_mobile():
		get_window().size_changed.connect(_apply_mobile_scale)
		_apply_mobile_scale()
		apply_orientation()
	else:
		apply_ui_scale()


## Taille du texte et des boutons choisie dans les réglages (0,85 à 1,4).
func ui_scale() -> float:
	return clampf(float(App.get_setting("display", "ui_scale", 1.0)), 0.75, 1.5)


func apply_ui_scale() -> void:
	if App.is_mobile():
		_apply_mobile_scale()
	else:
		get_window().content_scale_factor = ui_scale()


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
	var k := logical_short / short_side / ui_scale()
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


## Police pixel (Pixelify Sans) à une graisse donnée.
func _weight(w: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = FONT_PIXEL
	f.variation_opentype = {"wght": w}
	return f


## Cadre pixel en 9-patch (assets/ui, généré par tools/make_ui.py).
func tex_box(name: String, margin: float = 14.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(UI_DIR + name + ".png")
	sb.set_texture_margin_all(8)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.75
	sb.content_margin_bottom = margin * 0.75
	return sb


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_BODY
	t.default_font_size = 17

	# --- Textes ---
	t.set_color("font_color", "Label", Palette.TEXT)
	_variation(t, "TitleLabel", "Label")
	t.set_font("font", "TitleLabel", font_display)
	t.set_font_size("font_size", "TitleLabel", 44)
	t.set_color("font_color", "TitleLabel", Palette.GOLD)
	t.set_color("font_outline_color", "TitleLabel", Color("2a1260"))
	t.set_constant("outline_size", "TitleLabel", 8)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "TitleLabel", 0)
	t.set_constant("shadow_offset_y", "TitleLabel", 3)
	_variation(t, "HeadingLabel", "Label")
	t.set_font("font", "HeadingLabel", font_display)
	t.set_font_size("font_size", "HeadingLabel", 20)
	t.set_color("font_color", "HeadingLabel", Palette.TEXT)
	t.set_color("font_shadow_color", "HeadingLabel", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_y", "HeadingLabel", 2)
	_variation(t, "StrongLabel", "Label")
	t.set_font("font", "StrongLabel", FONT_BOLD)
	_variation(t, "MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", Palette.MUTED)
	t.set_font_size("font_size", "MutedLabel", 15)
	_variation(t, "CodeLabel", "Label")
	t.set_font("font", "CodeLabel", font_display)
	t.set_font_size("font_size", "CodeLabel", 40)
	t.set_color("font_color", "CodeLabel", Palette.GOLD)
	_variation(t, "OnGoldLabel", "Label")
	t.set_font("font", "OnGoldLabel", FONT_BOLD)
	t.set_color("font_color", "OnGoldLabel", Palette.ON_GOLD)

	t.set_color("default_color", "RichTextLabel", Palette.TEXT)
	t.set_font("normal_font", "RichTextLabel", FONT_BODY)
	t.set_font("bold_font", "RichTextLabel", FONT_BOLD)
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_font_size("bold_font_size", "RichTextLabel", 17)

	# --- Panneaux : cadres pixel ---
	var card := tex_box("panel", 16)
	t.set_stylebox("panel", "PanelContainer", card)
	_variation(t, "CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", card)
	_variation(t, "InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", tex_box("panel_inset", 12))
	_variation(t, "HighlightPanel", "PanelContainer")
	t.set_stylebox("panel", "HighlightPanel", tex_box("panel_gold", 16))
	_variation(t, "MagicPanel", "PanelContainer")
	t.set_stylebox("panel", "MagicPanel", tex_box("panel_magic", 16))
	_variation(t, "DangerPanel", "PanelContainer")
	t.set_stylebox("panel", "DangerPanel", tex_box("panel_danger", 16))
	_variation(t, "GoldBanner", "PanelContainer")
	t.set_stylebox("panel", "GoldBanner", tex_box("banner_gold", 14))
	_variation(t, "NameTag", "PanelContainer")
	t.set_stylebox("panel", "NameTag", tex_box("name_tag", 10))
	_variation(t, "SlotPanel", "PanelContainer")
	t.set_stylebox("panel", "SlotPanel", tex_box("slot", 4))
	_variation(t, "SlotSelected", "PanelContainer")
	t.set_stylebox("panel", "SlotSelected", tex_box("slot_selected", 4))
	_variation(t, "BarPanel", "PanelContainer")
	t.set_stylebox("panel", "BarPanel", tex_box("bar", 12))
	_variation(t, "NavPanel", "PanelContainer")
	t.set_stylebox("panel", "NavPanel", tex_box("bar", 8))
	_variation(t, "BubbleMine", "PanelContainer")
	t.set_stylebox("panel", "BubbleMine", tex_box("panel_magic", 12))
	_variation(t, "BubbleOther", "PanelContainer")
	t.set_stylebox("panel", "BubbleOther", tex_box("panel_inset", 12))
	_variation(t, "BubbleMJ", "PanelContainer")
	t.set_stylebox("panel", "BubbleMJ", tex_box("panel_gold", 12))
	_variation(t, "BubblePrivate", "PanelContainer")
	t.set_stylebox("panel", "BubblePrivate", tex_box("panel_magic", 12))

	# --- Boutons : indigo, et or pour le choix en cours ---
	_tex_buttons(t, "Button", "button", "button_hover", Palette.TEXT)
	_variation(t, "PrimaryButton", "Button")
	_tex_buttons(t, "PrimaryButton", "button_gold", "button_gold_hover", Palette.ON_GOLD)
	t.set_font("font", "PrimaryButton", FONT_BOLD)
	_variation(t, "DangerButton", "Button")
	_tex_buttons(t, "DangerButton", "button_danger", "button_danger", Color("ffd0d6"))
	_variation(t, "NavButton", "Button")
	var none := StyleBoxEmpty.new()
	none.content_margin_left = 12
	none.content_margin_right = 12
	none.content_margin_top = 8
	none.content_margin_bottom = 8
	_tex_buttons(t, "NavButton", "", "button", Palette.MUTED)
	t.set_stylebox("normal", "NavButton", none)
	t.set_font_size("font_size", "NavButton", 16)
	# Menu en liste (Menu principal) : ligne transparente, dorée quand choisie.
	_variation(t, "MenuItem", "Button")
	_tex_buttons(t, "MenuItem", "", "button", Palette.TEXT)
	t.set_stylebox("normal", "MenuItem", none)
	t.set_font_size("font_size", "MenuItem", 19)

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
		t.set_stylebox("normal", type, tex_box("field", 12))
		t.set_stylebox("focus", type, tex_box("field_focus", 12))
		t.set_stylebox("read_only", type, tex_box("panel_inset", 12))
		t.set_color("font_color", type, Palette.TEXT)
		t.set_color("font_placeholder_color", type, Palette.FAINT)
		t.set_color("caret_color", type, Palette.GOLD)
		t.set_color("selection_color", type, Palette.VIOLET_DIM)
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		t.set_stylebox(s, "OptionButton", tex_box({"hover": "button_hover", "disabled": "button_disabled"}.get(s, "button"), 12))
	t.set_stylebox("up", "SpinBox", StyleBoxEmpty.new())

	# --- Listes déroulantes et menus ---
	t.set_stylebox("panel", "PopupMenu", tex_box("panel", 10))
	t.set_stylebox("hover", "PopupMenu", tex_box("button_gold", 6))
	t.set_color("font_color", "PopupMenu", Palette.TEXT)
	t.set_color("font_hover_color", "PopupMenu", Palette.ON_GOLD)
	t.set_constant("v_separation", "PopupMenu", 12)
	t.set_stylebox("panel", "PopupPanel", tex_box("panel", 10))

	# --- Barres de défilement ---
	var bar_margin := 8.0 if App.is_mobile() else 3.0
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 2, bar_margin))
		t.set_stylebox("grabber", type, _box(Palette.VIOLET_DIM, Color(0, 0, 0, 0), 0, 2, bar_margin))
		t.set_stylebox("grabber_highlight", type, _box(Palette.VIOLET, Color(0, 0, 0, 0), 0, 2, bar_margin))
		t.set_stylebox("grabber_pressed", type, _box(Palette.GOLD, Color(0, 0, 0, 0), 0, 2, bar_margin))

	t.set_stylebox("separator", "HSeparator", _line(Palette.BORDER))
	t.set_constant("separation", "HSeparator", 12)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_stylebox("panel", "TooltipPanel", tex_box("panel_inset", 8))
	t.set_color("font_color", "TooltipLabel", Palette.TEXT)
	t.set_stylebox("panel", "Window", tex_box("panel", 12))
	t.set_stylebox("embedded_border", "Window", tex_box("panel", 12))
	t.set_stylebox("panel", "AcceptDialog", tex_box("panel", 14))
	return t


## Boutons à cadre pixel : normal / survol, or quand enfoncé (choix en cours).
func _tex_buttons(t: Theme, type: String, normal: String, hover: String, fg: Color) -> void:
	if normal != "":
		t.set_stylebox("normal", type, tex_box(normal, 14))
	t.set_stylebox("hover", type, tex_box(hover, 14))
	t.set_stylebox("pressed", type, tex_box("button_gold_pressed", 14))
	t.set_stylebox("hover_pressed", type, tex_box("button_gold", 14))
	t.set_stylebox("disabled", type, tex_box("button_disabled", 14))
	var focus := StyleBoxEmpty.new()
	t.set_stylebox("focus", type, focus)
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg.lightened(0.15) if fg != Palette.ON_GOLD else fg)
	t.set_color("font_pressed_color", type, Palette.ON_GOLD)
	t.set_color("font_hover_pressed_color", type, Palette.ON_GOLD)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_disabled_color", type, Palette.FAINT)
	t.set_color("icon_pressed_color", type, Palette.ON_GOLD)


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
