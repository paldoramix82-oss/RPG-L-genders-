class_name EffectList
extends VBoxContainer
## Liste d'effets composables (éditeur du MJ) : chaque ligne choisit un type
## d'effet et ses réglages. « Si… alors… » contient deux sous-listes.

var content := {}
var _rows: VBoxContainer
var _depth := 0


func _init(effects: Array, content_data: Dictionary, depth: int = 0) -> void:
	content = content_data
	_depth = depth
	add_theme_constant_override("separation", 6)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	add_child(_rows)
	for e in effects:
		if e is Dictionary:
			_add(e)
	var add := HBoxContainer.new()
	add_child(add)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in Content.EFFECT_TYPES:
		if t == "if" and _depth > 0:
			continue
		o.add_item(String(Content.EFFECT_NAMES.get(t, t)))
		o.set_item_metadata(o.item_count - 1, t)
	add.add_child(o)
	add.add_child(UIKit.button("+ Ajouter l'effet", "", func(): _add({"type": String(o.get_item_metadata(o.selected))})))


func collect() -> Array:
	var out: Array = []
	for row in _rows.get_children():
		if not row.is_queued_for_deletion() and row.has_meta("get"):
			out.append(row.get_meta("get").call())
	return out


func _add(e: Dictionary) -> void:
	var type := String(e.get("type", "damage"))
	var panel := PanelContainer.new()
	panel.theme_type_variation = "CardPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UIKit.label(String(Content.EFFECT_NAMES.get(type, type)), "StrongLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := UIKit.button("Retirer", "DangerButton", func(): panel.queue_free())
	x.custom_minimum_size.y = 34
	head.add_child(x)
	var getters := {}
	var spin := func(key: String, caption: String, lo: int, hi: int, fallback: int):
		var s := UIKit.spin(int(e.get(key, fallback)), lo, hi)
		UIKit.field(col, caption, s)
		getters[key] = func(): return int(s.value)
	var text := func(key: String, caption: String, fallback: String):
		var l := UIKit.line_edit(String(e.get(key, fallback)))
		UIKit.field(col, caption, l)
		getters[key] = func(): return l.text
	var pick := func(key: String, caption: String, options: Dictionary, fallback: String):
		var o := OptionButton.new()
		for k in options:
			o.add_item(String(options[k]))
			o.set_item_metadata(o.item_count - 1, k)
			if String(k) == String(e.get(key, fallback)):
				o.select(o.item_count - 1)
		UIKit.field(col, caption, o)
		getters[key] = func(): return String(o.get_item_metadata(o.selected)) if o.selected >= 0 else fallback
	var on_opts := {"target": "La cible", "self": "Soi-même", "allies": "Les alliés proches"}
	match type:
		"damage":
			text.call("dice", "Dés de dégâts", "1d6")
			spin.call("bonus", "Bonus fixe", -99, 999, 0)
			pick.call("element", "Nature", {"physique": "Physique", "magique": "Magique"}, "physique")
		"heal":
			text.call("dice", "Dés de soin (vide = montant fixe)", "1d8")
			spin.call("amount", "Montant fixe", 0, 999, 0)
			pick.call("on", "Sur", on_opts, "target")
		"restore":
			pick.call("resource", "Ressource", {"res": "Mana / ressource", "hp": "PV"}, "res")
			spin.call("amount", "Quantité (négatif = retire)", -999, 999, 4)
			pick.call("on", "Sur", on_opts, "self")
		"status":
			var statuses := {}
			for s in Content.list(content, "statuses"):
				statuses[String(s.id)] = String(s.name)
			pick.call("status", "Effet", statuses, "etourdi")
			spin.call("turns", "Durée (tours)", 0, 99, 2)
			spin.call("chance", "Chance (%)", 0, 100, 100)
			spin.call("value", "Valeur (bouclier, dégâts en plus…)", 0, 999, 0)
			pick.call("on", "Sur", on_opts, "target")
		"cleanse":
			spin.call("count", "Nombre d'effets négatifs retirés", 1, 10, 1)
			pick.call("on", "Sur", on_opts, "target")
		"push", "pull":
			spin.call("cells", "Cases", 1, 6, 1)
		"ap":
			spin.call("amount", "Points d'action (+/−)", -4, 4, 1)
			pick.call("on", "Sur", on_opts, "target")
		"stat":
			pick.call("stat", "Caractéristique", {"Force": "Force", "Dextérité": "Dextérité", "Constitution": "Constitution", "Intelligence": "Intelligence", "Esprit": "Esprit", "Charisme": "Charisme"}, "Force")
			spin.call("amount", "Modification", -10, 10, 2)
			spin.call("turns", "Durée (tours)", 1, 99, 2)
			pick.call("on", "Sur", on_opts, "target")
		"drain":
			spin.call("pct", "Pourcentage des dégâts rendu en PV", 1, 100, 30)
		"summon":
			text.call("name", "Nom de l'invocation", "Esprit")
			spin.call("hp", "PV", 1, 999, 10)
			text.call("attack", "Dégâts", "1d6")
			spin.call("defense", "Défense", 0, 40, 10)
		"narrate":
			text.call("text", "Texte affiché", "")
		"if":
			var cond: Dictionary = e.get("cond", {})
			var cond_spins := {}
			for spec in [["target_hp_below", "Si la cible est sous X % de PV (0 = ignorer)"], ["self_hp_below", "Si vous êtes sous X % de PV"], ["chance", "Avec X % de chances"]]:
				var s := UIKit.spin(int(cond.get(spec[0], 0)), 0, 100)
				UIKit.field(col, spec[1], s)
				cond_spins[spec[0]] = s
			var debuffed := CheckBox.new()
			debuffed.text = "Si la cible subit un effet négatif"
			debuffed.button_pressed = bool(cond.get("target_debuffed", false))
			col.add_child(debuffed)
			col.add_child(UIKit.label("Alors :", "StrongLabel"))
			var then_list := EffectList.new(e.get("then", []), content, _depth + 1)
			col.add_child(then_list)
			col.add_child(UIKit.label("Sinon :", "StrongLabel"))
			var else_list := EffectList.new(e.get("else", []), content, _depth + 1)
			col.add_child(else_list)
			getters["cond"] = func():
				var c := {}
				for k in cond_spins:
					if int(cond_spins[k].value) > 0:
						c[k] = int(cond_spins[k].value)
				if debuffed.button_pressed:
					c["target_debuffed"] = true
				return c
			getters["then"] = func(): return then_list.collect()
			getters["else"] = func(): return else_list.collect()
	panel.set_meta("get", func():
		var out := {"type": type}
		for k in getters:
			out[k] = getters[k].call()
		return out)
	_rows.add_child(panel)
