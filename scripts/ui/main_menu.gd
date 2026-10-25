extends Control
## Écran d'accueil : héberger (PC du MJ) ou rejoindre (téléphone d'un joueur).


func _ready() -> void:
	add_child(Backdrop.new())
	var column := CenteredColumn.new()
	column.max_width = 460
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	column.add_child(box)

	box.add_child(UIKit.spacer())
	var title := UIKit.label("LEGENDERS", "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var rpg := UIKit.label("R P G", "HeadingLabel")
	rpg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rpg.add_theme_color_override("font_color", Palette.VIOLET)
	box.add_child(rpg)
	var subtitle := UIKit.label("Récits partagés  ·  réseau local", "MutedLabel")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	box.add_child(_ornament())

	var host := UIKit.button("Héberger une partie", "PrimaryButton", func(): App.goto(App.SCENE_HOST))
	host.custom_minimum_size.y = 60
	host.disabled = not App.can_host()
	box.add_child(host)
	if not App.can_host():
		var note := UIKit.label("L'hébergement se fait depuis le PC du maître du jeu.", "MutedLabel", true)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(note)

	var join := UIKit.button("Rejoindre une partie", "", func(): App.goto(App.SCENE_JOIN))
	join.custom_minimum_size.y = 60
	box.add_child(join)
	if App.is_mobile():
		join.theme_type_variation = "PrimaryButton"
		join.grab_focus.call_deferred()

	box.add_child(UIKit.spacer())
	var footer := UIKit.label("v%s  ·  protocole %d%s" % [
		ProjectSettings.get_setting("application/config/version", "0"),
		Protocol.VERSION,
		"" if App.profile == "default" else "  ·  profil « %s »" % App.profile,
	], "MutedLabel")
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Palette.FAINT)
	box.add_child(footer)
	var bottom_gap := Control.new()
	bottom_gap.custom_minimum_size.y = 24
	box.add_child(bottom_gap)


func _ornament() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 28)
	c.draw.connect(func():
		var mid := c.size * 0.5
		var w := minf(c.size.x * 0.4, 160.0)
		c.draw_line(mid - Vector2(w, 0), mid - Vector2(12, 0), Palette.GOLD_DIM, 1.0, true)
		c.draw_line(mid + Vector2(12, 0), mid + Vector2(w, 0), Palette.GOLD_DIM, 1.0, true)
		var diamond := PackedVector2Array([mid + Vector2(0, -6), mid + Vector2(6, 0), mid + Vector2(0, 6), mid + Vector2(-6, 0)])
		c.draw_colored_polygon(diamond, Palette.GOLD))
	return c
