class_name CharacterTools
extends VBoxContainer
## Outils du MJ sur un personnage (joueur, PNJ ou monstre), sans passer par des
## menus : PV, ressource, ultime, XP, or, caractéristiques, objets, capacités,
## effets de statut, inventaire. Chaque modification est journalisée par l'hôte.

signal edit_requested(char_id: String)
signal create_item_requested(char_id: String)
signal place_requested(char_id: String)
signal deleted

var cid := ""


func _init(char_id: String) -> void:
	cid = char_id
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rebuild()


func _server() -> SessionServer:
	return Net.server


func rebuild() -> void:
	UIKit.clear(self)
	var server := _server()
	var sheet: Dictionary = server.characters.get(cid, {})
	if sheet.is_empty():
		add_child(UIKit.label("Cette fiche n'existe plus.", "MutedLabel", true))
		return
	var content := server.content
	var is_player := server.players.has(cid)
	# --- Actions rapides ---
	var quick := UIKit.card(self, "Actions rapides", "HighlightPanel")
	quick.add_child(_delta_row("PV", Palette.HP, func(d): server.mj_adjust(cid, "hp", d), [-10, -5, -1, 1, 5, 10]))
	var heal := HFlowContainer.new()
	heal.add_theme_constant_override("h_separation", 6)
	quick.add_child(heal)
	heal.add_child(_small("Soigner complètement", "", func(): server.mj_adjust(cid, "hp", int(sheet.hp_max))))
	heal.add_child(_small("Mettre hors de combat", "DangerButton", func(): server.mj_adjust(cid, "hp", -int(sheet.hp))))
	if int(sheet.get("res_max", 0)) > 0:
		quick.add_child(_delta_row(String(sheet.get("res_name", "Ressource")), Palette.MANA, func(d): server.mj_adjust(cid, "res", d), [-5, -1, 1, 5, 99]))
	if (sheet.get("abilities", []) as Array).any(func(a): return a.get("ultimate", false)):
		var ult := HFlowContainer.new()
		ult.add_theme_constant_override("h_separation", 6)
		quick.add_child(ult)
		ult.add_child(UIKit.label("Ultime %d %%" % int(sheet.get("ult", 0)), "StrongLabel"))
		ult.add_child(_small("Charger", "", func(): server.mj_adjust(cid, "ult", 100)))
		ult.add_child(_small("Vider", "", func(): server.mj_adjust(cid, "ult", -100)))
	# XP et or.
	var gain := HFlowContainer.new()
	gain.add_theme_constant_override("h_separation", 6)
	gain.add_theme_constant_override("v_separation", 6)
	quick.add_child(gain)
	var xp := UIKit.spin(50, 1, 99999)
	xp.prefix = "XP"
	gain.add_child(xp)
	gain.add_child(_small("Donner l'XP", "PrimaryButton", func(): server.mj_give_xp(cid, int(xp.value))))
	var gold := UIKit.spin(10, 1, 999999)
	gold.prefix = "Or"
	gain.add_child(gold)
	gain.add_child(_small("Donner", "", func(): server.mj_give_gold(cid, int(gold.value))))
	gain.add_child(_small("Retirer", "DangerButton", func(): server.mj_give_gold(cid, -int(gold.value))))
	# --- Caractéristiques ---
	var stats := UIKit.card(self, "Caractéristiques")
	for s in Content.stat_names(content):
		var st := String(s)
		var row := HBoxContainer.new()
		stats.add_child(row)
		var l := UIKit.label("%s  %d" % [st, Rules.base_stat(sheet, st)], "")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_small("−", "", func(): server.mj_set_stat(cid, st, -1)))
		row.add_child(_small("+", "PrimaryButton", func(): server.mj_set_stat(cid, st, 1)))
	# --- Objets ---
	var items := UIKit.card(self, "Donner un objet")
	var item_pick := _picker(content, "items")
	items.add_child(item_pick)
	var qty := UIKit.spin(1, 1, 99)
	qty.prefix = "×"
	var irow := HFlowContainer.new()
	irow.add_theme_constant_override("h_separation", 6)
	items.add_child(irow)
	irow.add_child(qty)
	irow.add_child(_small("Donner", "PrimaryButton", func():
		if item_pick.selected >= 0:
			server.mj_give_item(cid, String(item_pick.get_item_metadata(item_pick.selected)), int(qty.value))))
	irow.add_child(_small("Créer un objet et le donner…", "", func(): create_item_requested.emit(cid)))
	# --- Capacités ---
	var abil := UIKit.card(self, "Capacités")
	var ab_pick := _picker(content, "abilities")
	abil.add_child(ab_pick)
	abil.add_child(_small("Apprendre cette capacité", "PrimaryButton", func():
		if ab_pick.selected >= 0:
			server.mj_teach(cid, String(ab_pick.get_item_metadata(ab_pick.selected)))))
	for a in sheet.get("abilities", []):
		var id := String(a.get("id", ""))
		var row := HBoxContainer.new()
		abil.add_child(row)
		var l := UIKit.label("%s%s%s" % [a.name, "  (ultime)" if a.get("ultimate", false) else "", "  · équipée" if a.get("equipped", false) else ""], "")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var eq := bool(a.get("equipped", false))
		row.add_child(_small("Retirer de la barre" if eq else "Équiper", "", func(): server.set_ability_equipped(cid, id, not eq)))
		row.add_child(_small("Oublier", "DangerButton", func(): server.mj_forget(cid, id)))
	# --- Effets ---
	var fx := UIKit.card(self, "Effets de statut")
	var token := _token()
	if token.is_empty():
		fx.add_child(UIKit.label("Placez ce personnage sur la carte affichée pour lui appliquer des effets.", "MutedLabel", true))
	else:
		var st_pick := _picker(content, "statuses")
		fx.add_child(st_pick)
		var frow := HFlowContainer.new()
		frow.add_theme_constant_override("h_separation", 6)
		fx.add_child(frow)
		var turns := UIKit.spin(2, 0, 99)
		turns.prefix = "tours"
		frow.add_child(turns)
		var value := UIKit.spin(0, 0, 999)
		value.prefix = "valeur"
		frow.add_child(value)
		var tid := String(token.id)
		frow.add_child(_small("Appliquer", "PrimaryButton", func():
			if st_pick.selected >= 0:
				server.mj_apply_status(tid, String(st_pick.get_item_metadata(st_pick.selected)), int(turns.value), int(value.value))))
		var effects: Array = sheet.get("effects", [])
		for i in effects.size():
			var e: Dictionary = effects[i]
			var row := HBoxContainer.new()
			fx.add_child(row)
			row.add_child(GameUI.icon_badge(String(e.get("icon", "sparkle")), Color(String(e.get("color", "#a07cc9"))), 26))
			var l := UIKit.label("%s%s" % [e.name, (" (%d tours)" % int(e.turns)) if int(e.get("turns", 0)) > 0 else ""], "")
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var idx := i
			row.add_child(_small("×", "DangerButton", func(): server.mj_remove_status(tid, idx)))
	# --- Inventaire ---
	var inv := UIKit.card(self, "Inventaire (%d objets, %d or)" % [(sheet.get("inventory", []) as Array).size(), int(sheet.get("gold", 0))])
	inv.add_child(InventoryView.new(sheet, content, {"mj": true, "act": _on_inventory_act}))
	# --- Fiche ---
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 6)
	row2.add_theme_constant_override("v_separation", 6)
	add_child(row2)
	row2.add_child(UIKit.button("Modifier l'histoire et les valeurs", "", func(): edit_requested.emit(cid)))
	if not is_player:
		row2.add_child(UIKit.button("Placer sur la carte affichée", "", func(): place_requested.emit(cid)))
		row2.add_child(UIKit.button("Supprimer la fiche", "DangerButton", func():
			server.mj_delete_character(cid)
			deleted.emit()))
	add_child(CharacterSheet.new(sheet, content, {"mj": true, "act": _on_sheet_act}))


func _on_inventory_act(action: String, data: Dictionary) -> void:
	if action == "remove_item":
		_server().mj_remove_item(cid, String(data.uid))


func _on_sheet_act(action: String, data: Dictionary) -> void:
	if action == "equip_ability":
		_server().set_ability_equipped(cid, String(data.id), bool(data.equipped))
	elif action == "edit_story":
		edit_requested.emit(cid)


func _token() -> Dictionary:
	var map: Dictionary = _server().maps.get(_server().active_map, {})
	for t in map.get("tokens", []):
		if String(t.get("char_id", "")) == cid or String(t.get("owner", "")) == cid:
			return t
	return {}


func _picker(content: Dictionary, kind: String) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size.y = UIKit.TOUCH_HEIGHT
	o.fit_to_longest_item = false
	for e in Content.list(content, kind):
		var label := String(e.get("name", e.id))
		if kind == "items":
			label += "  (%s)" % GameUI.rarity_name(e)
		o.add_item(label)
		o.set_item_metadata(o.item_count - 1, String(e.id))
	return o


func _delta_row(caption: String, color: Color, apply: Callable, deltas: Array) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	var l := UIKit.label(caption, "StrongLabel")
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size.x = 80
	row.add_child(l)
	for d in deltas:
		var dd := int(d)
		row.add_child(_small(("%+d" % dd) if absi(dd) < 99 else "Max", "DangerButton" if dd < 0 else "", func(): apply.call(dd)))
	return row


func _small(text: String, variation: String, cb: Callable) -> Button:
	var b := UIKit.button(text, variation, cb)
	b.custom_minimum_size.y = 38
	b.add_theme_font_size_override("font_size", 15)
	return b
