class_name Notifier
extends VBoxContainer
## Notifications brèves en haut de l'écran : « Vous récupérez 12 PV »,
## « Objet obtenu : Épée du veilleur », « Mana insuffisant »… Elles ne bloquent
## rien, s'empilent (3 au plus), disparaissent seules et se ferment d'un toucher.
## Les informations importantes restent aussi dans le récit (historique).

## kind -> [couleur, icône]
const KINDS := {
	"info": [Palette.GOLD, "star"],
	"success": [Palette.HEAL, "sparkle"],
	"heal": [Palette.HEAL, "heart"],
	"damage": [Palette.HP, "fang"],
	"danger": [Palette.DANGER, "close"],
	"warning": [Palette.WARN, "hourglass"],
	"loot": [Palette.ULT, "chest"],
	"gold": [Palette.GOLD, "coin"],
	"level": [Palette.XP, "xp"],
	"magic": [Palette.PRIVATE, "spiral"],
	"ult": [Palette.ULT, "star"],
	"quest": [Palette.GOLD, "journal"],
	"chat": [Palette.PRIVATE, "chat"],
}
const MAX := 3
const DURATION := 2.8

## Largeur maximale (sur grand écran, les notifications restent centrées).
var max_width := 440.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	z_index = 40
	_place()
	get_viewport().size_changed.connect(_place)


func _place() -> void:
	var w := minf(max_width, get_viewport_rect().size.x - 24)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = 64
	offset_bottom = 64


func push(text: String, kind: String = "info", icon_name: String = "") -> void:
	var spec: Array = KINDS.get(kind, KINDS.info)
	var col: Color = spec[0]
	var panel := PanelContainer.new()
	var sb := OrnateStyle.make(Color(Palette.PANEL_ALT, 0.97), Color(Palette.BG_DEEP, 0.97), col.darkened(0.25), Color(0, 0, 0, 0), 6, 10)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var badge := GameUI.icon_badge(icon_name if icon_name != "" else String(spec[1]), col, 30)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var l := UIKit.label(text, "StrongLabel", true)
	l.add_theme_color_override("font_color", Palette.TEXT)
	l.add_theme_font_size_override("font_size", 17)
	row.add_child(l)
	# Liseré de couleur à gauche.
	var stripe := ColorRect.new()
	stripe.color = col
	stripe.custom_minimum_size = Vector2(3, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stripe)
	row.move_child(stripe, 0)
	panel.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_dismiss(panel))
	add_child(panel)
	while get_child_count() > MAX:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	panel.pivot_offset = Vector2(max_width * 0.5, 20)
	var tw := panel.create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(DURATION)
	tw.chain().tween_callback(_dismiss.bind(panel))


func _dismiss(panel: Control) -> void:
	if not is_instance_valid(panel) or panel.is_queued_for_deletion() or panel.has_meta("closing"):
		return
	panel.set_meta("closing", true)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, 0.25)
	tw.tween_callback(panel.queue_free)
