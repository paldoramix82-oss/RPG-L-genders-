class_name InventoryView
extends VBoxContainer
## Inventaire : objets en cases (couleur de rareté), emplacements équipés, détail
## de l'objet touché avec l'aperçu des changements (« Défense 12 → 16 ») et les
## actions possibles ; onglet « Coffre du groupe » pour se partager le butin.
##
## options : {act: Callable(action, data), loot: Array, others: Array[{id, name}], mj: bool}
##   actions : item ({action, uid, to}), take_loot ({uid}), remove_item ({uid}) [MJ]

var sheet := {}
var content := {}
var act := Callable()
var loot: Array = []
var others: Array = []
var mj := false
var _tab := "bag"
## Filtre du sac par catégorie (« all » : tout).
static var _filter := "all"
var _selected := ""
var _detail: VBoxContainer
var _grid: HFlowContainer


func _init(sheet_data: Dictionary, content_data: Dictionary, options: Dictionary = {}) -> void:
	sheet = sheet_data
	content = content_data
	act = options.get("act", Callable())
	loot = options.get("loot", [])
	others = options.get("others", [])
	mj = bool(options.get("mj", false))
	_tab = String(options.get("tab", "bag"))
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


func _emit(action: String, data: Dictionary) -> void:
	if act.is_valid():
		act.call(action, data)


func _build() -> void:
	UIKit.clear(self)
	if not mj:
		var tabs := HBoxContainer.new()
		add_child(tabs)
		for spec in [["bag", "Mon sac"], ["chest", "Coffre du groupe (%d)" % loot.size()]]:
			var b := UIKit.button(spec[1], "PrimaryButton" if _tab == spec[0] else "", func():
				_tab = spec[0]
				_selected = ""
				_build())
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tabs.add_child(b)
	if _tab == "chest" and not mj:
		_chest()
		return
	var top := HBoxContainer.new()
	add_child(top)
	top.add_child(Icons.new("coin", Palette.GOLD, 26))
	top.add_child(UIKit.label("%d pièces d'or" % int(sheet.get("gold", 0)), "StrongLabel"))
	# Emplacements équipés.
	var slots := GameUI.section(self, "Équipé", "armor")
	var srow := HFlowContainer.new()
	srow.add_theme_constant_override("h_separation", 10)
	srow.add_theme_constant_override("v_separation", 10)
	slots.add_child(srow)
	for spec in [["arme", "Arme", 1], ["armure", "Armure", 1], ["accessoire", "Accessoires", 2]]:
		var items := Inventory.slot_items(sheet, spec[0])
		for i in int(spec[2]):
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 2)
			srow.add_child(box)
			if i < items.size():
				box.add_child(_slot_button(items[i], 60))
			else:
				var empty := Control.new()
				empty.custom_minimum_size = Vector2(60, 60)
				empty.draw.connect(func():
					var sb := StyleBoxFlat.new()
					sb.bg_color = Palette.BG_DEEP
					sb.border_color = Palette.BORDER
					sb.set_border_width_all(1)
					sb.set_corner_radius_all(8)
					empty.draw_style_box(sb, Rect2(Vector2.ZERO, empty.size)))
				box.add_child(empty)
			var cap := UIKit.label(spec[1] if i == 0 else "", "MutedLabel")
			cap.add_theme_font_size_override("font_size", 12)
			box.add_child(cap)
	# Sac, filtrable par catégorie (seulement celles réellement présentes).
	var all_items: Array = sheet.get("inventory", [])
	var bag := GameUI.section(self, "Sac (%d)" % all_items.size(), "bag")
	var present: Array = []
	for item in all_items:
		var cat := String(item.get("category", "unique"))
		if not present.has(cat):
			present.append(cat)
	if present.size() > 1:
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 4)
		chips.add_theme_constant_override("v_separation", 4)
		bag.add_child(chips)
		var group := ButtonGroup.new()
		for cat in ["all"] + Content.CATEGORIES.filter(func(c): return present.has(c)):
			var key := String(cat)
			var b := UIKit.button("Tout" if key == "all" else String(Content.CATEGORY_NAMES.get(key, key)) + "s", "NavButton")
			b.toggle_mode = true
			b.button_group = group
			b.button_pressed = _filter == key
			b.custom_minimum_size.y = 34
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(func():
				_filter = key
				_build())
			chips.add_child(b)
	if _filter != "all" and not present.has(_filter):
		_filter = "all"
	_grid = HFlowContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 10)
	bag.add_child(_grid)
	if all_items.is_empty():
		bag.add_child(UIKit.label("Votre sac est vide.", "MutedLabel", true))
	for item in all_items:
		if _filter == "all" or String(item.get("category", "")) == _filter:
			_grid.add_child(_item_tile(item))
	bag.add_child(UIKit.label("Touchez un objet pour le voir en détail, l'équiper ou l'utiliser.", "MutedLabel", true))


## Case de sac : icône sur fond de rareté et nom dessous.
func _item_tile(item: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size.x = 72
	var b := _slot_button(item, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(b)
	var n := UIKit.label(String(item.get("name", "?")), "MutedLabel")
	n.add_theme_font_size_override("font_size", 12)
	n.add_theme_color_override("font_color", Content.rarity_color(String(item.get("rarity", "commun"))).lightened(0.1))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.custom_minimum_size.x = 72
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(n)
	return box


func _slot_button(item: Dictionary, px: float) -> Control:
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size = Vector2(px, px)
	b.tooltip_text = String(item.get("name", ""))
	var slot := GameUI.item_slot(item, px)
	slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(slot)
	var uid := String(item.get("uid", ""))
	b.pressed.connect(func():
		_selected = uid
		_show_detail())
	return b


## Détail d'un objet dans un panneau superposé (la liste garde sa position).
func _show_detail() -> void:
	var item := Inventory.find(sheet, _selected)
	if item.is_empty():
		return
	var panel := OverlayPanel.new(String(item.get("name", "Objet")), get_viewport_rect().size.x > 900, String(item.get("icon", "bag")))
	get_tree().current_scene.add_child(panel)
	_detail = panel.body
	var card := UIKit.card(_detail, "", "HighlightPanel")
	card.add_child(GameUI.item_card(item, content))
	# Aperçu des changements avant d'équiper.
	var preview := Inventory.preview(sheet, content, _selected)
	if not preview.is_empty():
		card.add_child(UIKit.label("Si vous %s cet objet :" % ("retirez" if item.get("equipped", false) else "équipez"), "MutedLabel", true))
		for p in preview:
			var row := HBoxContainer.new()
			var lbl := UIKit.label(String(p.label), "")
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var better := true
			var txt := ""
			if p.has("before_text"):
				txt = "%s  →  %s" % [p.before_text, p.after_text]
			else:
				txt = "%d  →  %d  (%+d)" % [int(p.before), int(p.after), int(p.after) - int(p.before)]
				better = int(p.after) >= int(p.before)
			var v := UIKit.label(txt, "StrongLabel")
			v.add_theme_color_override("font_color", Palette.HEAL if better else Palette.HP)
			row.add_child(v)
			card.add_child(row)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	card.add_child(actions)
	var uid := _selected
	# Toute action ferme le détail (l'inventaire se met à jour à la réponse de l'hôte).
	var emit_close := func(action: String, data: Dictionary):
		_emit(action, data)
		panel.close()
	if mj:
		actions.add_child(UIKit.button("Retirer cet objet", "DangerButton", func(): emit_close.call("remove_item", {"uid": uid})))
		return
	if String(item.get("slot", "")) != "":
		var eq := bool(item.get("equipped", false))
		actions.add_child(UIKit.button("Retirer" if eq else "Équiper", "" if eq else "PrimaryButton", func(): emit_close.call("item", {"action": "unequip" if eq else "equip", "uid": uid})))
	if not (item.get("use", []) as Array).is_empty():
		# Confirmation seulement pour un objet précieux (pas pour chaque potion).
		var precious := Content.RARITIES.find(String(item.get("rarity", "commun"))) >= 2
		actions.add_child(UIKit.button("Utiliser", "PrimaryButton", func():
			if precious:
				ConfirmBox.ask(get_tree().current_scene, "Utiliser %s ?" % item.get("name", ""), "Objet %s : il sera consommé." % GameUI.rarity_name(item).to_lower(), "Utiliser", func(): emit_close.call("item", {"action": "use", "uid": uid}))
			else:
				emit_close.call("item", {"action": "use", "uid": uid})))
	if String(item.get("teaches", "")) != "":
		actions.add_child(UIKit.button("Lire (apprendre)", "PrimaryButton", func(): emit_close.call("item", {"action": "read", "uid": uid})))
	for o in others:
		var to := String(o.id)
		actions.add_child(UIKit.button("Donner à %s" % o.name, "", func(): emit_close.call("item", {"action": "give", "uid": uid, "to": to})))
	if String(item.get("category", "")) != "quete":
		actions.add_child(UIKit.button("Jeter", "DangerButton", func():
			ConfirmBox.ask(get_tree().current_scene, "Jeter %s ?" % item.get("name", ""), "L'objet sera perdu définitivement.", "Jeter", func(): emit_close.call("item", {"action": "drop", "uid": uid}), true)))


func _chest() -> void:
	var card := GameUI.section(self, "Coffre du groupe", "chest")
	card.add_child(UIKit.label("Le butin des combats et certaines récompenses arrivent ici. Premier arrivé, premier servi : mettez-vous d'accord !", "MutedLabel", true))
	if loot.is_empty():
		card.add_child(UIKit.label("Le coffre est vide.", "MutedLabel", true))
	for item in loot:
		var box := VBoxContainer.new()
		card.add_child(box)
		box.add_child(GameUI.item_card(item, content))
		if String(item.get("from", "")) != "":
			box.add_child(UIKit.label("Provenance : " + String(item.from), "MutedLabel", true))
		var uid := String(item.get("uid", ""))
		box.add_child(UIKit.button("Prendre", "PrimaryButton", func(): _emit("take_loot", {"uid": uid})))
