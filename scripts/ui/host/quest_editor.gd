class_name QuestEditor
extends VBoxContainer
## Formulaire d'une quête : titre, principale / secondaire, donneur, description,
## objectifs, joueurs concernés (aucun coché = tout le groupe), récompenses.

## give : true pour la donner tout de suite aux joueurs.
signal saved(data: Dictionary, give: bool)
signal cancelled
## Le MJ veut créer un objet sur mesure comme récompense.
signal create_item_requested

var quest := {}
var _title: LineEdit
var _kind: OptionButton
var _giver: LineEdit
var _desc: TextEdit
var _objectives: VBoxContainer
var _players := {}
var _xp: SpinBox
var _offer: CheckBox
var _auto: CheckBox
var _gold: SpinBox
var _items: VBoxContainer
var _custom_items: Array = []


func _init(data: Dictionary) -> void:
	quest = data.duplicate(true)
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var server := Net.server
	var main := UIKit.card(self, "La quête")
	_title = UIKit.line_edit(String(quest.get("title", "")), "Ex. : Les loups de Valombre")
	UIKit.field(main, "Titre", _title)
	_kind = OptionButton.new()
	_kind.add_item("Quête principale")
	_kind.add_item("Quête secondaire")
	_kind.select(0 if quest.get("kind", "side") == "main" else 1)
	UIKit.field(main, "Type", _kind)
	_giver = UIKit.line_edit(String(quest.get("giver", "")), "Ex. : le maire de Valombre")
	UIKit.field(main, "Confiée par (facultatif)", _giver)
	_desc = TextEdit.new()
	_desc.text = String(quest.get("description", ""))
	_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_desc.custom_minimum_size.y = 90
	UIKit.field(main, "Description", _desc)
	var obj := UIKit.card(self, "Objectifs")
	_objectives = VBoxContainer.new()
	obj.add_child(_objectives)
	for o in quest.get("objectives", []):
		_add_objective(o)
	obj.add_child(UIKit.button("+ Ajouter un objectif", "", func(): _add_objective({})))
	obj.add_child(UIKit.label("Un objectif automatique se coche tout seul : monstres vaincus, lieu atteint, objet obtenu, PNJ à qui l'on a parlé.", "MutedLabel", true))
	_auto = CheckBox.new()
	_auto.text = "Terminer la quête toute seule quand tout est fait (récompenses données)"
	_auto.button_pressed = bool(quest.get("auto", true))
	obj.add_child(_auto)
	_offer = CheckBox.new()
	_offer.text = "Le PNJ qui la confie la propose aux joueurs qui lui parlent"
	_offer.button_pressed = bool(quest.get("offer", true))
	obj.add_child(_offer)
	var who := UIKit.card(self, "Pour qui ?")
	who.add_child(UIKit.label("Aucun joueur coché : la quête est pour tout le groupe.", "MutedLabel", true))
	for p in server.players.values():
		if p.status != Protocol.STATUS_ACCEPTED:
			continue
		var c := CheckBox.new()
		var sheet: Dictionary = server.characters.get(p.id, {})
		c.text = String(p.name) + (("  —  " + String(sheet.name)) if not sheet.is_empty() else "")
		c.button_pressed = (quest.get("assigned", []) as Array).has(p.id)
		who.add_child(c)
		_players[p.id] = c
	var rw: Dictionary = quest.get("rewards", {})
	var rcard := UIKit.card(self, "Récompenses")
	var row := HBoxContainer.new()
	rcard.add_child(row)
	_xp = UIKit.spin(int(rw.get("xp", 0)), 0, 999999)
	UIKit.field(row, "XP (pour chacun)", _xp)
	_gold = UIKit.spin(int(rw.get("gold", 0)), 0, 999999)
	UIKit.field(row, "Or (pour chacun)", _gold)
	rcard.add_child(UIKit.label("Objets (dans le coffre du groupe, ou directement au joueur s'il est seul) :", "MutedLabel", true))
	_items = VBoxContainer.new()
	rcard.add_child(_items)
	for it in rw.get("items", []):
		if it.has("def"):
			_custom_items.append(it)
		else:
			_add_item(String(it.get("item", "")), int(it.get("qty", 1)))
	_refresh_custom()
	var ir := HFlowContainer.new()
	ir.add_theme_constant_override("h_separation", 6)
	rcard.add_child(ir)
	ir.add_child(UIKit.button("+ Objet du catalogue", "", func(): _add_item("", 1)))
	ir.add_child(UIKit.button("+ Créer un objet sur mesure…", "", func(): create_item_requested.emit()))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	add_child(actions)
	actions.add_child(UIKit.button("Annuler", "", func(): cancelled.emit()))
	actions.add_child(UIKit.button("Enregistrer", "", func(): saved.emit(collect(), false)))
	if String(quest.get("status", "draft")) == "draft":
		actions.add_child(UIKit.button("Enregistrer et donner", "PrimaryButton", func(): saved.emit(collect(), true)))


## Ajoute un objet créé sur mesure (définition complète) aux récompenses.
func add_custom_item(def: Dictionary) -> void:
	_custom_items.append({"def": def, "qty": 1})
	_refresh_custom()


func _refresh_custom() -> void:
	for c in _items.get_children():
		if c.has_meta("custom"):
			c.queue_free()
	for i in _custom_items.size():
		var row := HBoxContainer.new()
		row.set_meta("custom", true)
		var l := UIKit.label("%s (sur mesure)" % _custom_items[i].def.get("name", "Objet"), "StrongLabel", true)
		l.add_theme_color_override("font_color", Content.rarity_color(String(_custom_items[i].def.get("rarity", "commun"))))
		row.add_child(l)
		var idx := i
		row.add_child(UIKit.button("×", "DangerButton", func():
			_custom_items.remove_at(idx)
			_refresh_custom()))
		_items.add_child(row)


func _add_objective(o: Dictionary) -> void:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	box.add_child(row)
	var kind := OptionButton.new()
	for k in SessionServer.OBJECTIVE_KINDS:
		kind.add_item(String(SessionServer.OBJECTIVE_NAMES[k]))
		kind.set_item_metadata(kind.item_count - 1, k)
		if k == String(o.get("kind", "manual")):
			kind.select(kind.item_count - 1)
	row.add_child(kind)
	var e := UIKit.line_edit(String(o.get("text", "")), "Ex. : Trouver la tanière")
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	row.add_child(UIKit.button("×", "DangerButton", func(): box.queue_free()))
	var params := HFlowContainer.new()
	params.add_theme_constant_override("h_separation", 8)
	box.add_child(params)
	var target := UIKit.line_edit(String(o.get("target", "")), "Nom du monstre, de l'objet ou du PNJ")
	target.custom_minimum_size.x = 220
	var target_f: Control = UIKit.field(params, "Cible", target).get_parent()
	var count := UIKit.spin(int(o.get("count", 1)), 1, 99)
	var count_f: Control = UIKit.field(params, "Nombre", count).get_parent()
	var x := UIKit.spin(int(o.get("x", 0)), 0, 999)
	var y := UIKit.spin(int(o.get("y", 0)), 0, 999)
	var rad := UIKit.spin(int(o.get("radius", 2)), 0, 20)
	var place: Array = [UIKit.field(params, "Case X", x).get_parent(), UIKit.field(params, "Case Y", y).get_parent(), UIKit.field(params, "Rayon", rad).get_parent()]
	var update := func() -> void:
		var k := String(kind.get_item_metadata(kind.selected))
		params.visible = k != "manual"
		target_f.visible = k in ["kill", "item", "talk"]
		count_f.visible = k in ["kill", "item"]
		for f: Control in place:
			f.visible = k == "reach"
	kind.item_selected.connect(func(_i): update.call())
	update.call()
	var done := bool(o.get("done", false))
	var progress := int(o.get("progress", 0))
	box.set_meta("get", func(): return {"text": e.text, "done": done, "kind": String(kind.get_item_metadata(kind.selected)),
		"target": target.text, "count": int(count.value), "progress": progress, "x": int(x.value), "y": int(y.value), "radius": int(rad.value)})
	_objectives.add_child(box)


func _add_item(id: String, qty: int) -> void:
	var row := HBoxContainer.new()
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.fit_to_longest_item = false
	for e in Content.list(Net.server.content, "items"):
		o.add_item("%s (%s)" % [e.name, GameUI.rarity_name(e)])
		o.set_item_metadata(o.item_count - 1, String(e.id))
		if String(e.id) == id:
			o.select(o.item_count - 1)
	row.add_child(o)
	var s := UIKit.spin(qty, 1, 99)
	s.prefix = "×"
	row.add_child(s)
	row.add_child(UIKit.button("×", "DangerButton", func(): row.queue_free()))
	row.set_meta("get", func(): return {"item": String(o.get_item_metadata(o.selected)) if o.selected >= 0 else "", "qty": int(s.value)})
	_items.add_child(row)


func collect() -> Dictionary:
	var objectives: Array = []
	for row in _objectives.get_children():
		if not row.is_queued_for_deletion() and row.has_meta("get"):
			var o: Dictionary = row.get_meta("get").call()
			if String(o.text).strip_edges() != "":
				objectives.append(o)
	var assigned: Array = []
	for pid in _players:
		if _players[pid].button_pressed:
			assigned.append(pid)
	var items: Array = []
	for row in _items.get_children():
		if not row.is_queued_for_deletion() and row.has_meta("get"):
			var it: Dictionary = row.get_meta("get").call()
			if String(it.item) != "":
				items.append(it)
	items.append_array(_custom_items)
	return {"id": String(quest.get("id", "")), "title": _title.text, "kind": "main" if _kind.selected == 0 else "side",
		"giver": _giver.text, "description": _desc.text, "objectives": objectives, "auto": _auto.button_pressed, "offer": _offer.button_pressed, "assigned": assigned,
		"rewards": {"xp": int(_xp.value), "gold": int(_gold.value), "items": items}}
