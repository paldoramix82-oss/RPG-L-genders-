class_name CreationWizard
extends VBoxContainer
## Création de personnage guidée en 5 étapes :
##   1. Identité : nom, portrait, description (histoire et personnalité facultatives),
##   2. Classe : rôle, passif, trois capacités et un ultime prêts à jouer,
##   3. Caractéristiques : 5 partout + 15 points à répartir (bornes réglées par le MJ),
##   4. Équipement : kit de classe et choix propres à la classe,
##   5. Récapitulatif : tout vérifier, revenir en arrière, puis créer.
## L'hôte reconstruit la fiche lui-même à partir de ces choix (rien n'est imposé par le téléphone).

## payload : {class_id, alloc, choices, identity}
signal finished(payload: Dictionary)
signal cancelled

const STEPS := ["Identité", "Classe", "Caractéristiques", "Équipement", "Récapitulatif"]
const TITLES := ["Qui es-tu ?", "Choisis ta classe", "Répartis tes points", "Choisis ton équipement", "Vérifie et confirme"]

var universe := {}
var content := {}
var base := {}
var step := 0
var class_id := ""
var alloc := {}
var choices: Array = []
var identity := {}
var _content: VBoxContainer
var _scroll: TouchScroll
var _title: Label
var _dots: HFlowContainer
var _back: Button
var _next: Button
var _points_label: Label
var _preview: HFlowContainer
var _value_labels := {}
var _portrait: Portrait


func _init(universe_data: Dictionary, content_data: Dictionary, base_sheet: Dictionary) -> void:
	universe = universe_data
	content = content_data
	base = base_sheet
	identity = {
		"name": String(base.get("name", "")), "species": String(base.get("species", "")), "concept": "",
		"appearance": String(base.get("appearance", "")), "background": "", "personality": "",
		"color": String(base.get("pawn", {}).get("color", CharacterData.PAWN_COLORS[0])),
		"portrait": (base.get("portrait", {}) as Dictionary).duplicate(),
	}
	_reset_alloc()
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	add_child(head)
	_title = UIKit.label("", "TitleLabel", true)
	_title.add_theme_font_size_override("font_size", 26)
	head.add_child(_title)
	_dots = HFlowContainer.new()
	_dots.add_theme_constant_override("h_separation", 4)
	head.add_child(_dots)
	_scroll = TouchScroll.new()
	add_child(_scroll)
	var column := CenteredColumn.new()
	column.max_width = 680
	column.side_margin = 0
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(column)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	column.add_child(_content)
	var nav := HBoxContainer.new()
	add_child(nav)
	_back = UIKit.button("‹  Retour", "", _go.bind(-1))
	_back.custom_minimum_size = Vector2(120, 56)
	nav.add_child(_back)
	nav.add_child(UIKit.spacer(false))
	_next = UIKit.button("Suivant  ›", "PrimaryButton", _go.bind(1))
	_next.custom_minimum_size = Vector2(170, 56)
	nav.add_child(_next)
	_show_step()


func _reset_alloc() -> void:
	alloc = {}
	for s in Content.stat_names(content):
		alloc[s] = 0


func _go(delta: int) -> void:
	if delta > 0 and step == STEPS.size() - 1:
		_finish()
		return
	if delta < 0 and step == 0:
		cancelled.emit()
		return
	step = clampi(step + delta, 0, STEPS.size() - 1)
	_show_step()


func _show_step() -> void:
	UIKit.clear(_content)
	_value_labels.clear()
	_scroll.scroll_vertical = 0
	_title.text = "Étape %d/%d — %s" % [step + 1, STEPS.size(), TITLES[step]]
	UIKit.clear(_dots)
	for i in STEPS.size():
		var chip := UIKit.chip(STEPS[i], Palette.GOLD if i == step else (Palette.OK if i < step else Palette.FAINT))
		chip.add_theme_font_size_override("font_size", 13)
		_dots.add_child(chip)
	_back.text = "‹  Retour" if step > 0 else "Annuler"
	_next.text = "Créer mon personnage" if step == STEPS.size() - 1 else "Suivant  ›"
	match step:
		0:
			_step_identity()
		1:
			_step_class()
		2:
			_step_points()
		3:
			_step_gear()
		4:
			_step_recap()
	_update_next()


func _update_next() -> void:
	match step:
		0:
			_next.disabled = String(identity.name).strip_edges() == ""
		1:
			_next.disabled = class_id == ""
		2:
			_next.disabled = not Rules.valid_alloc(alloc, content)
		_:
			_next.disabled = false


func _cls() -> Dictionary:
	return Rules.get_class_def(content, class_id)


func _preview_sheet() -> Dictionary:
	var b := base.duplicate(true)
	b.name = identity.name
	b.portrait = identity.portrait
	return Rules.build_sheet(b, content, class_id, alloc, choices)


# --- 1. Identité -------------------------------------------------------------

func _step_identity() -> void:
	var intro := UIKit.card(_content, "", "HighlightPanel")
	intro.add_child(UIKit.label("Donne un nom à ton héros et choisis son visage. Le reste (histoire, personnalité) est facultatif : tu pourras le compléter plus tard.", "", true))
	var card := UIKit.card(_content, "Nom et apparence")
	var name_edit := UIKit.line_edit(String(identity.name), "Ex. : Lina, Bran, Shin…")
	name_edit.max_length = 32
	name_edit.text_changed.connect(func(t):
		identity.name = t
		_update_next())
	UIKit.field(card, "Nom du personnage", name_edit)
	# Portrait en haut, réglages dessous : tient sur un téléphone.
	var look := HBoxContainer.new()
	look.add_theme_constant_override("separation", 14)
	card.add_child(look)
	_portrait = Portrait.new(identity.portrait, Color(String(identity.color)), 120)
	look.add_child(_portrait)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	look.add_child(side)
	side.add_child(UIKit.label("Choisissez le visage de votre héros avec les flèches, ou laissez faire le hasard.", "MutedLabel", true))
	var pickers := VBoxContainer.new()
	pickers.add_theme_constant_override("separation", 4)
	pickers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(pickers)
	for spec in [["face", "Visage", Portrait.FACE_NAMES], ["skin", "Teint", ["Clair", "Doré", "Ambré", "Mat", "Brun", "Ébène"]],
			["hair", "Coiffure", Portrait.HAIR_NAMES], ["hair_color", "Couleur", ["Noir", "Châtain", "Auburn", "Blond", "Roux", "Blanc", "Bleu nuit", "Prune"]],
			["eyes", "Yeux", Portrait.EYE_NAMES], ["beard", "Barbe", Portrait.BEARD_NAMES], ["mark", "Marque", Portrait.MARK_NAMES]]:
		pickers.add_child(_cycler(spec[0], spec[1], spec[2]))
	side.add_child(UIKit.button("Au hasard", "", func():
		for key in CharacterData.PORTRAIT_KEYS:
			identity.portrait[key] = randi() % 8
		identity.portrait.beard = randi() % 4
		identity.portrait.mark = randi() % 4
		_show_step()))
	card.add_child(UIKit.label("Couleur du pion", "MutedLabel"))
	var colors := HFlowContainer.new()
	colors.add_theme_constant_override("h_separation", 8)
	colors.add_theme_constant_override("v_separation", 8)
	card.add_child(colors)
	for col in CharacterData.PAWN_COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(48, 48)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col)
		sb.set_corner_radius_all(24)
		sb.border_color = Palette.GOLD if col == identity.color else Palette.BORDER
		sb.set_border_width_all(3 if col == identity.color else 1)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func():
			identity.color = col
			_show_step())
		colors.add_child(b)
	var species := UIKit.line_edit(String(identity.species), "Humain, elfe, mutant…")
	species.text_changed.connect(func(t): identity.species = t)
	UIKit.field(card, "Espèce (facultatif)", species)
	var more := UIKit.card(_content, "Pour aller plus loin (facultatif)")
	for spec in [["appearance", "Description", "À quoi ressemble ton personnage ?"], ["background", "Histoire", "D'où vient-il ? Que cherche-t-il ?"],
			["personality", "Personnalité", "Calme, tête brûlée, curieux…"]]:
		var e := TextEdit.new()
		e.text = String(identity.get(spec[0], ""))
		e.placeholder_text = spec[2]
		e.custom_minimum_size.y = 84
		e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		var key: String = spec[0]
		e.text_changed.connect(func(): identity[key] = e.text)
		UIKit.field(more, spec[1], e)


func _cycler(key: String, caption: String, names: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var l := UIKit.label(caption, "MutedLabel")
	l.custom_minimum_size.x = 90
	row.add_child(l)
	var value := UIKit.label("", "StrongLabel")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var refresh := func():
		value.text = String(names[int(identity.portrait.get(key, 0)) % names.size()])
		if _portrait:
			_portrait.set_data(identity.portrait, Color(String(identity.color)))
	for d in [-1, 1]:
		var b := UIKit.button("‹" if d < 0 else "›", "", func():
			identity.portrait[key] = posmod(int(identity.portrait.get(key, 0)) + d, names.size())
			refresh.call())
		b.custom_minimum_size = Vector2(48, 40)
		if d < 0:
			row.add_child(b)
			row.add_child(value)
		else:
			row.add_child(b)
	refresh.call()
	return row


# --- 2. Classe ---------------------------------------------------------------

func _step_class() -> void:
	_content.add_child(GameUI.hint("Chaque classe arrive avec un passif, trois capacités et un ultime, prêts à jouer. Touche une classe pour voir le détail."))
	for cls in Rules.classes(content):
		var selected := String(cls.id) == class_id
		var card := UIKit.card(_content, "", "HighlightPanel" if selected else "CardPanel")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var emblem := Emblem.new(String(cls.get("emblem", "sword")), Color(String(cls.get("color", "#8a8f9a"))), 60)
		emblem.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(emblem)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var name_label := UIKit.label(String(cls.name), "HeadingLabel", true)
		name_label.add_theme_font_size_override("font_size", 24)
		col.add_child(name_label)
		var stars := "◆".repeat(int(cls.get("difficulty", 1))) + "◇".repeat(3 - int(cls.get("difficulty", 1)))
		col.add_child(UIKit.chip("%s · difficulté %s" % [cls.get("role", ""), stars], Palette.VIOLET.lightened(0.3)))
		col.add_child(UIKit.label(String(cls.get("description", cls.get("tagline", ""))), "", true))
		var res: Dictionary = cls.get("resource", {})
		col.add_child(UIKit.label("PV de base %d · %s · Vitesse %d cases · Bonus : %s" % [int(cls.hp_base), res.get("name", "Énergie"), int(cls.speed), _bonus_text(cls)], "MutedLabel", true))
		if selected:
			card.add_child(GameUI.passive_card(cls.get("passive", {}), content))
			for id in cls.get("abilities", []) + [cls.get("ultimate", "")]:
				var a := Content.get_entry(content, "abilities", String(id))
				if not a.is_empty():
					var aa: Dictionary = a.duplicate()
					aa.ultimate = String(id) == String(cls.get("ultimate", ""))
					card.add_child(GameUI.ability_card(aa, content, String(res.get("name", "Énergie"))))
		var pick := UIKit.button("Classe choisie" if selected else "Choisir : %s" % cls.name, "PrimaryButton" if selected else "", func():
			if class_id != String(cls.id):
				class_id = String(cls.id)
				choices = []
				for _g in cls.get("choices", []):
					choices.append(0)
				_reset_alloc()
			_show_step())
		pick.custom_minimum_size.y = 52
		card.add_child(pick)


func _bonus_text(cls: Dictionary) -> String:
	var parts: PackedStringArray = []
	var bonus: Dictionary = cls.get("bonus", {})
	for s in bonus:
		parts.append("%s %+d" % [Content.stat_info(content, s).get("short", s), int(bonus[s])])
	return ", ".join(parts) if not parts.is_empty() else "aucun"


# --- 3. Caractéristiques -----------------------------------------------------

func _step_points() -> void:
	var rules := Content.rules(content)
	var head := UIKit.card(_content, "", "HighlightPanel")
	_points_label = UIKit.label("", "HeadingLabel")
	_points_label.add_theme_font_size_override("font_size", 26)
	head.add_child(_points_label)
	head.add_child(UIKit.label("Chaque caractéristique part de %d. Répartis %d points (entre %d et %d par caractéristique avant le bonus de classe). Plus c'est haut, mieux c'est." % [
		int(rules.stat_base), int(rules.stat_pool), int(rules.stat_min), int(rules.stat_max)], "", true))
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 8)
	tools.add_theme_constant_override("v_separation", 8)
	head.add_child(tools)
	tools.add_child(UIKit.button("Répartition conseillée", "", func():
		var rec: Dictionary = _cls().get("recommended", {})
		for s in Content.stat_names(content):
			alloc[s] = int(rec.get(s, 0))
		_refresh_points()))
	tools.add_child(UIKit.button("Réinitialiser", "", func():
		_reset_alloc()
		_refresh_points()))
	var card := UIKit.card(_content, "Caractéristiques")
	var cls := _cls()
	for s in Content.stat_names(content):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var n := UIKit.label(s, "StrongLabel")
		info.add_child(n)
		info.add_child(UIKit.label(String(Content.stat_info(content, s).get("description", "")), "MutedLabel", true))
		var minus := UIKit.button("−", "", _bump.bind(s, -1))
		minus.custom_minimum_size = Vector2(46, 50)
		row.add_child(minus)
		var v := UIKit.label("", "StrongLabel")
		v.custom_minimum_size.x = 48
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_theme_font_size_override("font_size", 24)
		row.add_child(v)
		var plus := UIKit.button("+", "PrimaryButton", _bump.bind(s, 1))
		plus.custom_minimum_size = Vector2(46, 50)
		row.add_child(plus)
		_value_labels[s] = v
		if int(cls.get("bonus", {}).get(s, 0)) != 0:
			n.text = "%s  (classe %+d)" % [s, int(cls.bonus[s])]
	var prev := UIKit.card(_content, "Ce que ça donne")
	_preview = HFlowContainer.new()
	_preview.add_theme_constant_override("h_separation", 8)
	_preview.add_theme_constant_override("v_separation", 8)
	prev.add_child(_preview)
	_refresh_points()


func _bump(stat_name: String, delta: int) -> void:
	var b := Rules.alloc_bounds(content)
	var v := int(alloc.get(stat_name, 0)) + delta
	if v < b.x or v > b.y:
		return
	if delta > 0 and Rules.points_left(alloc, content) <= 0:
		return
	alloc[stat_name] = v
	_refresh_points()


func _refresh_points() -> void:
	var values := Rules.stat_values(alloc, _cls(), content)
	var left := Rules.points_left(alloc, content)
	_points_label.text = "Points restants : %d" % left
	_points_label.add_theme_color_override("font_color", Palette.OK if left == 0 else (Palette.GOLD if left > 0 else Palette.DANGER))
	for s in _value_labels:
		_value_labels[s].text = str(values[s])
	_fill_preview()
	_update_next()


func _fill_preview() -> void:
	if _preview == null:
		return
	UIKit.clear(_preview)
	var sheet := _preview_sheet()
	var d := Rules.derived(sheet, content)
	var w: Dictionary = Rules.weapons(sheet)[0]
	var p := Rules.attack_profile(sheet, content, w)
	for spec in [["PV", str(d.hp_max), Palette.HP, "Points de vie : à 0, hors de combat."],
			[String(d.res_name), str(d.res_max), Palette.MANA, "Sert à utiliser les capacités."],
			["Défense", str(d.defense), Palette.GOLD, "Score à atteindre au d20 pour vous toucher."],
			["Initiative", "%+d" % int(d.initiative), Palette.GOLD, "Ajoutée au d20 pour l'ordre du combat."],
			["Résistance", "%d / %d" % [d.resist_phys, d.resist_mag], Palette.VIOLET.lightened(0.3), "Réduit les dégâts physiques / magiques."],
			["Attaque", "d20%+d · %s%+d" % [p.to_hit, p.damage, p.damage_bonus], Palette.HP.lightened(0.2), "Toucher et dégâts de votre arme."]]:
		var t := GameUI.value_tile(spec[0], spec[1], spec[2], spec[3])
		t.custom_minimum_size.x = 120
		t.size_flags_horizontal = Control.SIZE_FILL
		_preview.add_child(t)


# --- 4. Équipement -----------------------------------------------------------

func _step_gear() -> void:
	var cls := _cls()
	var groups: Array = cls.get("choices", [])
	_content.add_child(GameUI.hint("Ton équipement de départ. Tu en trouveras d'autres en jouant (butin, quêtes, marchands)."))
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var card := UIKit.card(_content, String(g.get("title", "Choix")))
		var options: Array = g.get("options", [])
		for oi in options.size():
			var item := Content.get_entry(content, "items", String(options[oi]))
			if item.is_empty():
				continue
			var selected := gi < choices.size() and int(choices[gi]) == oi
			var box := VBoxContainer.new()
			card.add_child(box)
			var shown := item.duplicate()
			shown.equipped = selected
			box.add_child(GameUI.item_card(shown, content))
			var b := UIKit.button("Choisi" if selected else "Prendre", "PrimaryButton" if selected else "", func():
				while choices.size() <= gi:
					choices.append(0)
				choices[gi] = oi
				_show_step())
			box.add_child(b)
	var kit: Array = cls.get("kit", [])
	if not kit.is_empty():
		var card := UIKit.card(_content, "Toujours fourni avec la classe")
		for k in kit:
			var item := Content.get_entry(content, "items", String(k.get("item", "")))
			if not item.is_empty():
				var shown := item.duplicate()
				shown.qty = int(k.get("qty", 1))
				shown.equipped = bool(k.get("equip", false))
				card.add_child(GameUI.item_card(shown, content))
	var gold := UIKit.card(_content, "")
	gold.add_child(UIKit.label("Bourse de départ : %d pièces d'or." % int(Content.rule(content, "start_gold")), "StrongLabel", true))


# --- 5. Récapitulatif ---------------------------------------------------------

func _step_recap() -> void:
	var sheet := _preview_sheet()
	var cls := _cls()
	var d := Rules.derived(sheet, content)
	var head := UIKit.card(_content, "", "HighlightPanel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	head.add_child(row)
	row.add_child(Portrait.new(identity.portrait, Color(String(cls.get("color", identity.color))), 96))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	var n := UIKit.label(String(identity.name), "TitleLabel", true)
	n.add_theme_font_size_override("font_size", 30)
	titles.add_child(n)
	titles.add_child(UIKit.label("%s%s · niveau 1" % [cls.get("name", ""), (" · " + String(identity.species)) if String(identity.species) != "" else ""], "StrongLabel", true))
	var bars := VBoxContainer.new()
	titles.add_child(bars)
	var hp := ResourceBar.new("PV", Palette.HP, 24)
	hp.set_values(int(d.hp_max), int(d.hp_max), false)
	bars.add_child(hp)
	var res := ResourceBar.new(String(d.res_name), Palette.MANA, 20)
	res.set_values(int(d.res_max), int(d.res_max), false)
	bars.add_child(res)
	var stats := UIKit.card(_content, "Caractéristiques")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	stats.add_child(flow)
	for s in Content.stat_names(content):
		flow.add_child(GameUI.stat_tile(s, Rules.base_stat(sheet, s), content))
	var vals := HFlowContainer.new()
	vals.add_theme_constant_override("h_separation", 8)
	vals.add_theme_constant_override("v_separation", 8)
	stats.add_child(vals)
	for spec in [["Défense", str(d.defense)], ["Initiative", "%+d" % int(d.initiative)], ["Vitesse", "%d cases" % int(d.speed)], ["Résistances", "%d / %d" % [d.resist_phys, d.resist_mag]]]:
		var t := GameUI.value_tile(spec[0], spec[1])
		t.custom_minimum_size.x = 120
		t.size_flags_horizontal = Control.SIZE_FILL
		vals.add_child(t)
	var kit := UIKit.card(_content, "Passif et capacités")
	kit.add_child(GameUI.passive_card(sheet.get("passive", {}), content))
	for a in Rules.equipped_abilities(sheet):
		kit.add_child(GameUI.ability_card(a, content, String(d.res_name)))
	var gear := UIKit.card(_content, "Équipement")
	for item in sheet.get("inventory", []):
		gear.add_child(GameUI.item_card(item, content))
	_content.add_child(GameUI.hint("Tu peux encore revenir en arrière. Une fois créé, ton personnage apparaît sur la carte de tout le monde."))


func _finish() -> void:
	var portrait: Dictionary = identity.portrait
	var payload := {
		"class_id": class_id, "alloc": alloc.duplicate(), "choices": choices.duplicate(),
		"identity": {
			"name": String(identity.name).strip_edges(), "species": identity.species, "appearance": identity.appearance,
			"background": identity.background, "personality": identity.personality,
			"pawn": {"color": identity.color, "symbol": ""}, "portrait": portrait,
		},
	}
	finished.emit(payload)
