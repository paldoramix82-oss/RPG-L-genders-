class_name CharacterSheet
extends VBoxContainer
## Fiche de personnage organisée par catégories : identité et progression,
## ressources, caractéristiques et valeurs de combat, effets en cours, passif,
## capacités (équipées / connues), montée de niveau, équipement, histoire.
## Vue complète (propriétaire, MJ) ou publique (autres joueurs).
##
## options : {mine: bool, mj: bool, act: Callable(action: String, data: Dictionary)}
##   actions : level ({stat}|{learn}|{upgrade}), equip_ability ({id, equipped}), edit_story

var sheet := {}
var content := {}
var mine := false
var mj := false
var act := Callable()


func _init(sheet_data: Dictionary, content_data: Dictionary, options: Dictionary = {}) -> void:
	sheet = sheet_data
	content = content_data
	mine = bool(options.get("mine", false))
	mj = bool(options.get("mj", false))
	act = options.get("act", Callable())
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


func _emit(action: String, data: Dictionary = {}) -> void:
	if act.is_valid():
		act.call(action, data)


func _build() -> void:
	var c := sheet
	var public := bool(c.get("public", false))
	var d := Rules.derived(c, content) if not public else {}
	var cls := Rules.get_class_def(content, String(c.get("class_id", "")))
	# --- En-tête ---
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
	if not public:
		var lp := Rules.level_progress(c, content)
		var xp := ResourceBar.new("XP", Palette.XP, 16)
		xp.show_text = false
		xp.set_values(int(lp.xp) - int(lp.from), maxi(1, int(lp.to) - int(lp.from)), false)
		titles.add_child(xp)
		titles.add_child(UIKit.label("%d / %d XP pour le niveau %d" % [int(lp.xp), int(lp.to), int(lp.level) + 1], "MutedLabel"))
		var money := HBoxContainer.new()
		money.add_child(Icons.new("coin", Palette.GOLD, 22))
		money.add_child(UIKit.label("%d pièces d'or" % int(c.get("gold", 0)), "StrongLabel"))
		titles.add_child(money)
	# --- Ressources ---
	var bars := UIKit.card(self, "")
	var hp := ResourceBar.new("PV", Palette.HP, 26)
	hp.set_values(int(c.get("hp", 0)), int(c.get("hp_max", 1)), false)
	bars.add_child(hp)
	if int(c.get("res_max", 0)) > 0:
		var res := ResourceBar.new(String(c.get("res_name", d.get("res_name", "Énergie"))), Palette.MANA, 22)
		res.set_values(int(c.get("res", 0)), int(c.res_max), false)
		bars.add_child(res)
	if not public and _has_ultimate():
		var ult := ResourceBar.new("Ultime", Palette.ULT, 16)
		ult.set_values(int(c.get("ult", 0)), 100, false)
		bars.add_child(ult)
		bars.add_child(UIKit.label("La jauge d'ultime se remplit en combat (coups donnés et reçus, chaque tour).", "MutedLabel", true))
	# --- Montée de niveau ---
	if mine and not public:
		_level_up()
	# --- Effets en cours ---
	var effects: Array = c.get("effects", [])
	if not effects.is_empty():
		var ec := UIKit.card(self, "Effets en cours")
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
	if public:
		_story(c)
		add_child(UIKit.label("Vous voyez la partie publique de cette fiche.", "MutedLabel", true))
		return
	# --- Caractéristiques et combat ---
	var sc := UIKit.card(self, "Caractéristiques")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	sc.add_child(flow)
	for s in Content.stat_names(content):
		var base := Rules.base_stat(c, s)
		var eff := Rules.stat(c, s, content, d.mods)
		flow.add_child(GameUI.stat_tile(s, eff, content, eff - base))
	sc.add_child(UIKit.label("En vert : bonus d'équipement ou d'effet ; en rouge : malus.", "MutedLabel", true))
	sc.add_child(explain_stats(content))
	var fc := UIKit.card(self, "Au combat")
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	fc.add_child(grid)
	var w: Dictionary = Rules.weapons(c)[0]
	var p := Rules.attack_profile(c, content, w)
	for spec in [["Défense", str(d.defense), "Score à atteindre au d20 pour vous toucher."], ["Initiative", "%+d" % int(d.initiative), "Ajoutée au d20 pour l'ordre de jeu."],
			["Vitesse", "%d cases" % int(d.speed), "Cases parcourues par déplacement."], ["Points d'action", str(d.ap), "Actions par tour de combat."],
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
	# --- Passif ---
	var passive: Dictionary = c.get("passive", {})
	if not passive.is_empty() and String(passive.get("name", "")) != "":
		var pc := UIKit.card(self, "Passif de classe")
		pc.add_child(GameUI.passive_card(passive, content))
	# --- Capacités ---
	var res_name := String(d.res_name)
	var ac := UIKit.card(self, "Capacités")
	var equipped := Rules.equipped_abilities(c)
	ac.add_child(UIKit.label("Barre rapide : %d / %d capacités de base + ultime." % [equipped.filter(func(a): return not a.get("ultimate", false)).size(), int(Content.rule(content, "slots_basic"))], "MutedLabel", true))
	for a in c.get("abilities", []):
		var holder := VBoxContainer.new()
		holder.add_theme_constant_override("separation", 4)
		ac.add_child(holder)
		var note := "" if a.get("equipped", false) else "Connue, pas équipée."
		holder.add_child(GameUI.ability_card(a, content, res_name, note))
		if mine or mj:
			var id := String(a.get("id", ""))
			var eq := bool(a.get("equipped", false))
			holder.add_child(UIKit.button("Retirer de la barre rapide" if eq else "Équiper dans la barre rapide", "" if eq else "PrimaryButton", func():
				_emit("equip_ability", {"id": id, "equipped": not eq})))
	for item in Rules.equipped(c):
		for g in item.get("grants", []):
			var a := Content.ability_copy(content, String(g), true)
			if not a.is_empty():
				ac.add_child(GameUI.ability_card(a, content, res_name, "Accordée par %s." % item.name))
	# --- Équipement ---
	var eqc := UIKit.card(self, "Équipement porté")
	var any := false
	for item in Rules.equipped(c):
		eqc.add_child(GameUI.item_card(item, content))
		any = true
	if not any:
		eqc.add_child(UIKit.label("Rien d'équipé. Ouvrez l'inventaire pour vous équiper.", "MutedLabel", true))
	_story(c)
	if mine or mj:
		add_child(UIKit.button("Modifier l'histoire et l'apparence", "", func(): _emit("edit_story")))


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
	var card := UIKit.card(self, "Niveau supérieur !", "HighlightPanel")
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
		var m := UIKit.card(self, "Magie")
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
			story = UIKit.card(self, "Histoire et personnalité")
		_para(story, spec[1], c[spec[0]])


func _para(parent: Node, caption: String, text: Variant) -> void:
	if String(text) == "":
		return
	if caption != "":
		var c := UIKit.label(caption, "MutedLabel")
		c.add_theme_color_override("font_color", Palette.GOLD_DIM)
		parent.add_child(c)
	parent.add_child(UIKit.label(String(text), "", true))
