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


## Onglets du sac (comme un jeu vidéo) : catégories d'objets par onglet.
const TABS := [["bag", "Objets"], ["equip", "Équipement"], ["treasure", "Trésors"]]
const TAB_CATS := {"equip": ["arme", "armure", "accessoire"], "treasure": ["quete", "unique", "materiau", "livre"]}


func _tab_of(item: Dictionary) -> String:
	var cat := String(item.get("category", "unique"))
	for k in TAB_CATS:
		if cat in TAB_CATS[k]:
			return k
	return "bag"


func _build() -> void:
	UIKit.clear(self)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	add_child(tabs)
	var specs: Array = TABS.duplicate()
	if not mj:
		specs.append(["chest", "Coffre (%d)" % loot.size()])
	for spec in specs:
		var b := UIKit.button(spec[1], "PrimaryButton" if _tab == spec[0] else "", func():
			_tab = spec[0]
			_selected = ""
			_build())
		b.custom_minimum_size.y = 40
		tabs.add_child(b)
	if _tab == "chest" and not mj:
		_chest()
		return
	var purse := HBoxContainer.new()
	add_child(purse)
	purse.add_child(Icons.new("coin", Palette.GOLD, 22))
	var g := UIKit.label("%d pièces d'or" % int(sheet.get("gold", 0)), "StrongLabel")
	g.add_theme_color_override("font_color", Palette.GOLD)
	purse.add_child(g)
	if _tab == "equip":
		_equipped_row()
	var items: Array = (sheet.get("inventory", []) as Array).filter(func(it): return _tab_of(it) == _tab)
	# Grille de cases (4 colonnes, au moins 3 rangées : les cases vides restent visibles).
	var frame := PanelContainer.new()
	frame.theme_type_variation = "InsetPanel"
	add_child(frame)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	frame.add_child(grid)
	if _selected == "" and not items.is_empty():
		_selected = String(items[0].get("uid", ""))
	var count := maxi(12, int(ceil(items.size() / 4.0)) * 4)
	for k in count:
		grid.add_child(_cell(items[k] if k < items.size() else {}))
	# Description de l'objet choisi, en bas (comme « Potion de soin · Restaure 50 HP. »).
	var chosen := Inventory.find(sheet, _selected) if _selected != "" else {}
	var foot := PanelContainer.new()
	foot.theme_type_variation = "CardPanel"
	add_child(foot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	foot.add_child(row)
	if chosen.is_empty():
		row.add_child(UIKit.label("Rien dans cet onglet." if items.is_empty() else "Touchez un objet.", "MutedLabel", true))
		return
	var icon := TextureRect.new()
	icon.texture = Sprites.item(String(chosen.get("icon", "bag")))
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(44, 44)
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var n := UIKit.label(String(chosen.get("name", "?")), "StrongLabel", true)
	n.add_theme_color_override("font_color", Content.rarity_color(String(chosen.get("rarity", "commun"))).lightened(0.25))
	info.add_child(n)
	var desc := String(chosen.get("description", ""))
	if desc == "":
		desc = Inventory.describe(chosen, content)
	info.add_child(UIKit.label(desc, "", true))
	row.add_child(UIKit.button("Actions", "PrimaryButton", _show_detail))


## Emplacements portés : arme, armure, deux accessoires.
func _equipped_row() -> void:
	var srow := HFlowContainer.new()
	srow.add_theme_constant_override("h_separation", 10)
	srow.add_theme_constant_override("v_separation", 10)
	add_child(srow)
	for spec in [["arme", "Arme", 1], ["armure", "Armure", 1], ["accessoire", "Accessoire", 2]]:
		var items := Inventory.slot_items(sheet, spec[0])
		for i in int(spec[2]):
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 2)
			srow.add_child(box)
			box.add_child(_cell(items[i] if i < items.size() else {}, 60))
			var cap := UIKit.label(String(spec[1]), "MutedLabel")
			cap.add_theme_font_size_override("font_size", 12)
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(cap)


## Case d'inventaire : cadre pixel (doré si choisie), sprite, quantité « ×5 ».
func _cell(item: Dictionary, px: float = 64.0) -> Control:
	var uid := String(item.get("uid", ""))
	var panel := PanelContainer.new()
	panel.theme_type_variation = "SlotSelected" if uid != "" and uid == _selected else "SlotPanel"
	panel.custom_minimum_size = Vector2(px, px)
	if item.is_empty():
		return panel
	var b := Button.new()
	b.flat = true
	b.tooltip_text = String(item.get("name", ""))
	b.focus_mode = Control.FOCUS_NONE
	panel.add_child(b)
	var tex := TextureRect.new()
	tex.texture = Sprites.item(String(item.get("icon", "bag")))
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tex)
	if int(item.get("qty", 1)) > 1:
		var q := UIKit.label("×%d" % int(item.qty), "StrongLabel")
		q.add_theme_font_size_override("font_size", 13)
		q.add_theme_constant_override("outline_size", 4)
		q.add_theme_color_override("font_outline_color", Color.BLACK)
		q.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
		q.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		q.grow_vertical = Control.GROW_DIRECTION_BEGIN
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(q)
	if item.get("equipped", false):
		var e := UIKit.label("É", "StrongLabel")
		e.add_theme_font_size_override("font_size", 12)
		e.add_theme_color_override("font_color", Palette.GOLD)
		e.add_theme_constant_override("outline_size", 4)
		e.add_theme_color_override("font_outline_color", Color.BLACK)
		e.position = Vector2(4, 0)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(e)
	# Premier toucher : choisir ; second toucher : actions.
	b.pressed.connect(func():
		if _selected == uid:
			_show_detail()
		else:
			_selected = uid
			_build())
	return panel


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
