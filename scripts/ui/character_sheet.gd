class_name CharacterSheet
extends VBoxContainer
## Fiche de personnage : en-tête toujours visible (portrait, nom, classe, niveau,
## expérience, ressources), montée de niveau si elle attend, puis quatre onglets :
##   Personnage (caractéristiques base + bonus, valeurs de combat, effets),
##   Capacités (passif, équipées, connues, à débloquer),
##   Équipement (objets portés), Histoire (magie, personnalité, secret).
## Vue complète (propriétaire, MJ) ou publique (autres joueurs).
##
## options : {mine: bool, mj: bool, act: Callable(action: String, data: Dictionary)}
##   actions : level ({stat}|{learn}|{upgrade}), equip_ability ({id, equipped}), edit_story

var sheet := {}
var content := {}
var mine := false
var mj := false
var act := Callable()
## Onglet affiché (conservé quand la fiche se met à jour).
static var last_tab := "stats"
var _tab := "stats"


func _init(sheet_data: Dictionary, content_data: Dictionary, options: Dictionary = {}) -> void:
	sheet = sheet_data
	content = content_data
	mine = bool(options.get("mine", false))
	mj = bool(options.get("mj", false))
	act = options.get("act", Callable())
	_tab = String(options.get("tab", last_tab))
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


func _emit(action: String, data: Dictionary = {}) -> void:
	if act.is_valid():
		act.call(action, data)


func _build() -> void:
	UIKit.clear(self)
	var c := sheet
	var public := bool(c.get("public", false))
	var d := Rules.derived(c, content) if not public else {}
	_header(c, public, d)
	if mine and not public:
		_level_up()
	if public:
		_effects(c)
		_story(c)
		add_child(UIKit.label("Vous voyez la partie publique de cette fiche.", "MutedLabel", true))
		return
	# Onglets.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	add_child(tabs)
	var group := ButtonGroup.new()
	for spec in [["stats", "Personnage", "person"], ["skills", "Capacités", "bolt"], ["gear", "Équipement", "armor"], ["story", "Histoire", "book"]]:
		var b := UIKit.button(spec[1], "NavButton")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = _tab == spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 40
		b.add_theme_font_size_override("font_size", 14)
		b.clip_text = true
		var key: String = spec[0]
		b.pressed.connect(func():
			_tab = key
			last_tab = key
			_build())
		tabs.add_child(b)
	match _tab:
		"skills":
			_skills(c, d)
		"gear":
			_gear(c)
		"story":
			_story(c)
			if String(c.get("appearance", "")) == "" and String(c.get("background", "")) == "":
				add_child(UIKit.label("Aucune histoire écrite pour l'instant.", "MutedLabel", true))
			if mine or mj:
				add_child(UIKit.button("Modifier l'histoire et l'apparence", "", func(): _emit("edit_story")))
		_:
			_stats(c, d)


func _header(c: Dictionary, public: bool, d: Dictionary) -> void:
	var cls := Rules.get_class_def(content, String(c.get("class_id", "")))
	var head := UIKit.card(self, "", "HighlightPanel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	head.add_child(row)
	var portrait := Portrait.for_sheet(c, content, 96)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(portrait)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	var name_label := UIKit.label(String(c.get("name", "Sans nom")), "TitleLabel", true)
	name_label.add_theme_font_size_override("font_size", 28)
	titles.add_child(name_label)
	var sub: PackedStringArray = []
	if not cls.is_empty():
		sub.append(String(cls.name))
	elif String(c.get("concept", "")) != "":
		sub.append(String(c.concept))
	for key in ["species", "origin"]:
		if String(c.get(key, "")) != "":
			sub.append(String(c[key]))
	sub.append("Niveau %d" % int(c.get("level", 1)))
	titles.add_child(UIKit.label("  ·  ".join(sub), "StrongLabel", true))
	if not cls.is_empty() and String(cls.get("description", "")) != "":
		titles.add_child(UIKit.label(String(cls.description), "MutedLabel", true))
	if not public:
		var lp := Rules.level_progress(c, content)
		var xp := ResourceBar.new("XP", Palette.XP, 14)
		xp.show_text = false
		xp.set_values(int(lp.xp) - int(lp.from), maxi(1, int(lp.to) - int(lp.from)), false)
		titles.add_child(xp)
		var money := HBoxContainer.new()
		money.add_theme_constant_override("separation", 6)
		var xl := UIKit.label("%d / %d XP" % [int(lp.xp), int(lp.to)], "MutedLabel")
		xl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		money.add_child(xl)
		money.add_child(Icons.new("coin", Palette.GOLD, 20))
		var gl := UIKit.label("%d or" % int(c.get("gold", 0)), "StrongLabel")
		gl.add_theme_color_override("font_color", Palette.GOLD)
		money.add_child(gl)
		titles.add_child(money)
	# Ressources.
	var hp := ResourceBar.new("PV", Palette.HP, 24)
	hp.set_values(int(c.get("hp", 0)), int(c.get("hp_max", 1)), false)
	head.add_child(hp)
	if int(c.get("res_max", 0)) > 0:
		var res := ResourceBar.new(String(c.get("res_name", d.get("res_name", "Énergie"))), Palette.MANA, 20)
		res.set_values(int(c.get("res", 0)), int(c.res_max), false)
		head.add_child(res)
	if not public and _has_ultimate():
		var ult := ResourceBar.new("Ultime", Palette.ULT, 14)
		ult.set_values(int(c.get("ult", 0)), 100, false)
		head.add_child(ult)
	var effects: Array = c.get("effects", [])
	if not effects.is_empty():
		head.add_child(GameUI.status_row(effects, 22))


func _effects(c: Dictionary) -> void:
	var effects: Array = c.get("effects", [])
	if effects.is_empty():
		return
	var ec := GameUI.section(self, "Effets en cours", "sparkle")
	for e in effects:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.add_child(GameUI.icon_badge(String(e.get("icon", "sparkle")), Color(String(e.get("color", "#a07cc9"))), 30))
		var txt := "%s%s" % [e.get("name", "?"), (" — %d tour%s" % [int(e.turns), "s" if int(e.turns) > 1 else ""]) if int(e.get("turns", 0)) > 0 else ""]
		if int(e.get("value", 0)) > 0:
			txt += " (%d)" % int(e.value)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(UIKit.label(txt, "StrongLabel", true))
		if String(e.get("description", "")) != "":
			box.add_child(UIKit.label(String(e.description), "MutedLabel", true))
		line.add_child(box)
		ec.add_child(line)


func _stats(c: Dictionary, d: Dictionary) -> void:
	var sc := GameUI.section(self, "Caractéristiques", "person")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	sc.add_child(flow)
	for s in Content.stat_names(content):
		var base := Rules.base_stat(c, s)
		var eff := Rules.stat(c, s, content, d.mods)
		flow.add_child(GameUI.stat_tile(s, eff, content, eff - base))
	sc.add_child(UIKit.label("Petit chiffre : valeur de base + bonus. En vert : bonus d'équipement ou d'effet ; en rouge : malus.", "MutedLabel", true))
	sc.add_child(explain_stats(content))
	var fc := GameUI.section(self, "Au combat", "sword")
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	fc.add_child(grid)
	var w: Dictionary = Rules.weapons(c)[0]
	var p := Rules.attack_profile(c, content, w)
	for spec in [["Défense", str(d.defense), "Score à atteindre au d20 pour vous toucher."], ["Initiative", "%+d" % int(d.initiative), "Ajoutée au d20 pour l'ordre de jeu."],
			["Vitesse", "%d cases" % int(d.speed), "Cases parcourues par déplacement."], ["Vision", "%d cases" % int(d.get("vision", 5)), "Jusqu'où vous voyez sur la carte (Dextérité)."],
			["Points d'action", str(d.ap), "Actions par tour de combat."],
			["Rés. physique", str(d.resist_phys), "Retirée aux dégâts physiques reçus."], ["Rés. magique", str(d.resist_mag), "Retirée aux dégâts magiques reçus."],
			["Toucher", "%+d" % int(p.to_hit), "Ajouté au d20 de votre attaque d'arme."], ["Dégâts", "%s%+d" % [p.damage, int(p.damage_bonus)], "Dégâts de votre arme."],
			["Critique", ("%d-20" % int(p.crit)) if int(p.crit) < 20 else "20", "Résultat du d20 qui double les dés de dégâts."]]:
		var t := GameUI.value_tile(spec[0], spec[1], Palette.GOLD, spec[2])
		t.custom_minimum_size.x = 104
		t.size_flags_horizontal = Control.SIZE_FILL
		grid.add_child(t)
	if int(d.heal_pct) != 0:
		fc.add_child(UIKit.label("Soins prodigués : %+d %%" % int(d.heal_pct), "", true))
	var mods: Dictionary = d.mods
	var mm: PackedStringArray = []
	for k in mods:
		if int(mods[k]) != 0:
			mm.append("%s %+d" % [Content.MOD_NAMES.get(k, k), int(mods[k])])
	if not mm.is_empty():
		fc.add_child(UIKit.label("Bonus et malus actuels : " + ", ".join(mm), "MutedLabel", true))
	_effects(c)


func _skills(c: Dictionary, d: Dictionary) -> void:
	var sp := Rules.get_species(content, String(c.get("species_id", "")))
	if not sp.is_empty():
		var spc := GameUI.section(self, "Peuple", String(sp.get("icon", "person")))
		spc.add_child(GameUI.species_card(sp, Rules.synergy(content, String(sp.id), String(c.get("class_id", ""))), content))
	var passive: Dictionary = c.get("passive", {})
	if not passive.is_empty() and String(passive.get("name", "")) != "":
		var pc := GameUI.section(self, "Passif de classe", "spiral")
		pc.add_child(GameUI.passive_card(passive, content))
	var res_name := String(d.res_name)
	var equipped := Rules.equipped_abilities(c)
	var ac := GameUI.section(self, "Équipées", "bolt")
	ac.add_child(UIKit.label("Barre rapide : %d / %d capacités de base + ultime (+ capacités de peuple, sans emplacement)." % [equipped.filter(func(a): return not a.get("ultimate", false) and not a.get("innate", false)).size(), int(Content.rule(content, "slots_basic"))], "MutedLabel", true))
	var known: Array = (c.get("abilities", []) as Array).filter(func(a): return not a.get("equipped", false))
	for a in c.get("abilities", []):
		if a.get("equipped", false):
			_ability_row(ac, a, res_name, "Capacité de peuple." if a.get("innate", false) else "")
	for item in Rules.equipped(c):
		for g in item.get("grants", []):
			var a := Content.ability_copy(content, String(g), true)
			if not a.is_empty():
				ac.add_child(GameUI.ability_card(a, content, res_name, "Accordée par %s." % item.name))
	if not known.is_empty():
		var kc := GameUI.section(self, "Connues", "book")
		for a in known:
			_ability_row(kc, a, res_name, "Connue, pas équipée.")
	# À débloquer : capacités de la classe pas encore apprises.
	var cls := Rules.get_class_def(content, String(c.get("class_id", "")))
	var have: Array = (c.get("abilities", []) as Array).map(func(a): return String(a.get("id", "")))
	var locked: Array = (cls.get("learnable", []) as Array).filter(func(l): return not have.has(String(l.get("ability", ""))))
	if not locked.is_empty():
		var lc := GameUI.section(self, "À débloquer", "key")
		for l in locked:
			var a := Content.get_entry(content, "abilities", String(l.get("ability", "")))
			if a.is_empty():
				continue
			var lvl := int(l.get("level", 2))
			var card := GameUI.ability_card(a, content, res_name, ("Disponible : choisissez-la à votre prochaine montée de niveau." if lvl <= int(c.get("level", 1)) else "Se débloque au niveau %d." % lvl))
			card.modulate = Color(1, 1, 1, 0.6) if lvl > int(c.get("level", 1)) else Color.WHITE
			lc.add_child(card)


func _ability_row(parent: Node, a: Dictionary, res_name: String, note: String) -> void:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 4)
	parent.add_child(holder)
	holder.add_child(GameUI.ability_card(a, content, res_name, note))
	if mine or mj:
		var id := String(a.get("id", ""))
		var eq := bool(a.get("equipped", false))
		holder.add_child(UIKit.button("Retirer de la barre rapide" if eq else "Équiper dans la barre rapide", "" if eq else "PrimaryButton", func():
			_emit("equip_ability", {"id": id, "equipped": not eq})))


func _gear(c: Dictionary) -> void:
	var eqc := GameUI.section(self, "Équipement porté", "armor")
	var any := false
	for item in Rules.equipped(c):
		eqc.add_child(GameUI.item_card(item, content))
		any = true
	if not any:
		eqc.add_child(UIKit.label("Rien d'équipé. Ouvrez l'inventaire pour vous équiper.", "MutedLabel", true))
	var bag := (c.get("inventory", []) as Array).filter(func(i): return not i.get("equipped", false))
	if not bag.is_empty():
		var bc := GameUI.section(self, "Dans le sac (%d)" % bag.size(), "bag")
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		bc.add_child(flow)
		for item in bag:
			var slot := GameUI.item_slot(item, 48)
			slot.tooltip_text = String(item.get("name", ""))
			slot.mouse_filter = Control.MOUSE_FILTER_PASS
			flow.add_child(slot)


## Bouton « À quoi servent les caractéristiques ? » qui déplie leurs descriptions.
static func explain_stats(content_data: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var details := VBoxContainer.new()
	details.visible = false
	for s in content_data.get("stats", []):
		details.add_child(UIKit.label("%s — %s" % [s.get("name", ""), s.get("description", "")], "MutedLabel", true))
	var b := UIKit.button("À quoi servent les caractéristiques ?", "", func(): details.visible = not details.visible)
	box.add_child(b)
	box.add_child(details)
	return box


func _has_ultimate() -> bool:
	for a in sheet.get("abilities", []):
		if a.get("ultimate", false):
			return true
	return false


## Montée de niveau : points de caractéristique à placer, capacité à apprendre ou améliorer.
func _level_up() -> void:
	var pending: Dictionary = sheet.get("pending", {})
	var points := int(pending.get("stat_points", 0))
	var picks := int(pending.get("picks", 0))
	if points <= 0 and picks <= 0:
		return
	var card := GameUI.section(self, "Niveau supérieur !", "xp", "HighlightPanel")
	if points > 0:
		card.add_child(UIKit.label("%d point%s de caractéristique à placer :" % [points, "s" if points > 1 else ""], "StrongLabel", true))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		card.add_child(flow)
		for s in Content.stat_names(content):
			var st := String(s)
			flow.add_child(UIKit.button("%s %d → %d" % [Content.stat_info(content, st).get("short", st), Rules.base_stat(sheet, st), Rules.base_stat(sheet, st) + 1], "", func():
				_emit("level", {"stat": st})))
	if picks > 0:
		card.add_child(UIKit.label("Choisissez : apprendre une nouvelle capacité OU améliorer une capacité connue.", "StrongLabel", true))
		var learn := Rules.learnable_now(sheet, content)
		for a in learn:
			var id := String(a.id)
			card.add_child(GameUI.ability_card(a, content, String(sheet.get("res_name", "Énergie"))))
			card.add_child(UIKit.button("Apprendre %s" % a.name, "PrimaryButton", func(): _emit("level", {"learn": id})))
		var max_rank := int(Content.rule(content, "max_ability_rank"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		card.add_child(flow)
		for a in sheet.get("abilities", []):
			if int(a.get("rank", 1)) < max_rank:
				var id := String(a.id)
				flow.add_child(UIKit.button("Améliorer %s (rang %d)" % [a.name, int(a.get("rank", 1)) + 1], "", func(): _emit("level", {"upgrade": id})))
		card.add_child(UIKit.label("Améliorer une capacité : +2 aux dégâts / soins et −1 au coût par rang.", "MutedLabel", true))


func _story(c: Dictionary) -> void:
	var magic: Dictionary = c.get("magic", {})
	if String(magic.get("name", "")) != "" or String(magic.get("category", "")) != "":
		var m := GameUI.section(self, "Magie", "wand")
		var top := String(magic.get("name", ""))
		if String(magic.get("category", "")) != "":
			top += ("  —  " if top != "" else "") + String(magic.category)
		m.add_child(UIKit.label(top, "StrongLabel", true))
		_para(m, "", magic.get("description", ""))
		_para(m, "Limites", magic.get("limits", ""))
	var fields := [["appearance", "Apparence"], ["personality", "Personnalité"], ["goals", "Objectifs"],
		["background", "Histoire"], ["relations", "Relations"], ["notes", "Notes"], ["secret", "Secret (vous et le MJ)"]]
	var story: VBoxContainer = null
	for spec in fields:
		if String(c.get(spec[0], "")) == "":
			continue
		if story == null:
			story = GameUI.section(self, "Histoire et personnalité", "book")
		_para(story, spec[1], c[spec[0]])


func _para(parent: Node, caption: String, text: Variant) -> void:
	if String(text) == "":
		return
	if caption != "":
		var c := UIKit.label(caption, "MutedLabel")
		c.add_theme_color_override("font_color", Palette.GOLD_DIM)
		parent.add_child(c)
	parent.add_child(UIKit.label(String(text), "", true))
