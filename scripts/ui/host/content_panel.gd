class_name ContentPanel
extends VBoxContainer
## Catalogue de la campagne côté MJ : objets, capacités, effets, monstres, classes,
## tables de butin, et règles. Tout se crée et se modifie en pleine partie.

signal edit_requested(kind: String, entry: Dictionary)
## Afficher un résultat (ex. butin tiré) : titre et contenu.
signal show_requested(title: String, content: Control)

const KIND_LABELS := {"items": "Objets", "abilities": "Capacités", "statuses": "Effets", "monsters": "Monstres",
	"classes": "Classes", "loot": "Butin", "rules": "Règles"}

var _kind := "items"
var _filter := ""
var _list: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rebuild()


func rebuild() -> void:
	UIKit.clear(self)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	add_child(tabs)
	for k in KIND_LABELS:
		var b := UIKit.button(KIND_LABELS[k], "PrimaryButton" if k == _kind else "", func():
			_kind = k
			_filter = ""
			rebuild())
		b.custom_minimum_size.y = 36
		b.add_theme_font_size_override("font_size", 15)
		tabs.add_child(b)
	if _kind == "rules":
		_rules()
		return
	var top := HBoxContainer.new()
	add_child(top)
	var search := UIKit.line_edit(_filter, "Rechercher…")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(t):
		_filter = t
		_fill())
	top.add_child(search)
	top.add_child(UIKit.button("+ Nouveau", "PrimaryButton", func(): edit_requested.emit(_kind, _blank())))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	add_child(_list)
	_fill()


func _blank() -> Dictionary:
	match _kind:
		"items":
			return {"name": "Nouvel objet", "category": "arme", "rarity": "commun", "icon": "sword", "weapon": {"damage": "1d6", "stat": "Force", "crit": 20, "range": 1}}
		"abilities":
			return {"name": "Nouvelle capacité", "icon": "star", "cost": 3, "ap": 1, "range": 1, "target": "enemy", "roll": "attack", "stat": "Force",
				"effects": [{"type": "damage", "dice": "1d8"}]}
		"statuses":
			return {"name": "Nouvel effet", "icon": "sparkle", "kind": "debuff", "color": "#a07cc9"}
		"monsters":
			return {"name": "Nouveau monstre", "hp": 20, "xp": 20, "weapon": {"damage": "1d6", "stat": "Force", "range": 1}}
		"classes":
			return {"name": "Nouvelle classe", "hp_base": 14, "speed": 5, "resource": {"name": "Mana", "stat": "Esprit", "base": 8}}
		"loot":
			return {"name": "Nouveau butin", "gold": [0, 10], "entries": []}
	return {}


func _fill() -> void:
	UIKit.clear(_list)
	var server := Net.server
	var entries := Content.list(server.content, _kind)
	var f := _filter.strip_edges().to_lower()
	var shown := 0
	for e in entries:
		if f != "" and not String(e.get("name", "")).to_lower().contains(f):
			continue
		shown += 1
		if shown > 80:
			_list.add_child(UIKit.label("… affinez la recherche pour voir la suite.", "MutedLabel", true))
			break
		_list.add_child(_row(e))
	if shown == 0:
		_list.add_child(UIKit.label("Rien ici pour l'instant.", "MutedLabel", true))


func _row(e: Dictionary) -> Control:
	var server := Net.server
	var card := UIKit.card(null, "", "InsetPanel")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	card.add_child(head)
	var icon := String(e.get("icon", e.get("emblem", "star")))
	var col := Palette.GOLD
	if _kind == "items":
		col = Content.rarity_color(String(e.get("rarity", "commun")))
	elif e.has("color"):
		col = Color(String(e.color))
	head.add_child(GameUI.icon_badge(icon, col, 30))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	var n := UIKit.label(String(e.get("name", e.id)), "StrongLabel", true)
	if _kind == "items":
		n.add_theme_color_override("font_color", col.lightened(0.15))
	info.add_child(n)
	info.add_child(UIKit.label(_summary(e), "MutedLabel", true))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 4)
	actions.add_theme_constant_override("v_separation", 4)
	card.add_child(actions)
	var id := String(e.id)
	actions.add_child(_small("Modifier", "", func(): edit_requested.emit(_kind, e)))
	actions.add_child(_small("Dupliquer", "", func():
		var copy: Dictionary = e.duplicate(true)
		copy.erase("id")
		copy.name = String(e.get("name", "")) + " (copie)"
		server.mj_content_save(_kind, copy)
		_fill()))
	match _kind:
		"items":
			actions.add_child(_give_menu(id))
			actions.add_child(_small("Au coffre du groupe", "", func():
				server.add_loot(Content.item_instance(server.content, id), "Donné par le MJ")))
		"monsters":
			actions.add_child(_small("Placer (caché)", "PrimaryButton", func(): _spawn(id, true)))
			actions.add_child(_small("Placer (visible)", "", func(): _spawn(id, false)))
		"loot":
			actions.add_child(_small("Tirer", "PrimaryButton", func(): _roll(id)))
		"abilities":
			actions.add_child(_small("Mettre à jour chez les personnages", "", func():
				var count := server.mj_push_ability_update(id)
				show_requested.emit("Capacité mise à jour", UIKit.label("%d personnage%s mis à jour." % [count, "s" if count > 1 else ""], "", true))))
	actions.add_child(_small("Supprimer", "DangerButton", func():
		server.mj_content_delete(_kind, id)
		_fill()))
	return card.get_parent()


func _summary(e: Dictionary) -> String:
	var content := Net.server.content
	match _kind:
		"items":
			return "%s · %s · %s" % [GameUI.rarity_name(e), Content.CATEGORY_NAMES.get(String(e.get("category", "")), ""), Inventory.describe(e, content)]
		"abilities":
			return "%s — %s" % [Effects.ability_costs(e), Effects.describe_list(e.get("effects", []), content, String(e.get("stat", "")))]
		"statuses":
			return String(e.get("description", ""))
		"monsters":
			return "%d PV · %s · %d XP%s" % [int(e.get("hp", 0)), e.get("weapon", {}).get("damage", "?"), int(e.get("xp", 0)), " · BOSS" if e.get("boss", false) else ""]
		"classes":
			return "%s · %d PV · passif : %s" % [e.get("role", ""), int(e.get("hp_base", 0)), e.get("passive", {}).get("name", "—")]
		"loot":
			var g: Array = e.get("gold", [0, 0])
			return "%d–%d or · %d objets possibles" % [int(g[0]), int(g[1]), (e.get("entries", []) as Array).size()]
	return ""


func _give_menu(item_id: String) -> MenuButton:
	var server := Net.server
	var menu := MenuButton.new()
	menu.text = "Donner à…"
	menu.flat = false
	menu.theme_type_variation = "PrimaryButton"
	menu.custom_minimum_size.y = 36
	var targets: Array = []
	for cid in server.characters:
		if server.players.has(cid):
			targets.append(cid)
			menu.get_popup().add_item(String(server.characters[cid].name))
	menu.get_popup().index_pressed.connect(func(i): server.mj_give_item(String(targets[i]), item_id, 1))
	if targets.is_empty():
		menu.disabled = true
	return menu


func _spawn(monster_id: String, hidden: bool) -> void:
	var server := Net.server
	var map: Dictionary = server.maps.get(server.active_map, {})
	var t := server.mj_spawn_monster(monster_id, int(map.get("spawn", {}).get("x", 0)) + 3, int(map.get("spawn", {}).get("y", 0)), hidden)
	if t.is_empty():
		show_requested.emit("Impossible", UIKit.label("Aucune carte affichée ou carte pleine.", "", true))


func _roll(table_id: String) -> void:
	var server := Net.server
	var drop := server.mj_roll_loot(table_id)
	var box := VBoxContainer.new()
	box.add_child(UIKit.label("Or : %d" % int(drop.gold), "StrongLabel"))
	for it in drop.items:
		box.add_child(GameUI.item_card(it, server.content))
	if (drop.items as Array).is_empty():
		box.add_child(UIKit.label("Aucun objet cette fois.", "MutedLabel", true))
	box.add_child(UIKit.button("Tout mettre dans le coffre du groupe (et partager l'or)", "PrimaryButton", func():
		for it in drop.items:
			server.add_loot(it, String(Content.get_entry(server.content, "loot", table_id).get("name", "Butin")))
		if int(drop.gold) > 0:
			server.mj_event("group_reward", {"gold": int(drop.gold) / maxi(1, server.players.size()), "text": "Le groupe se partage %d pièces d'or." % int(drop.gold)})
		show_requested.emit("Butin distribué", UIKit.label("Le butin est dans le coffre du groupe.", "", true))))
	show_requested.emit("Butin tiré", box)


func _rules() -> void:
	var server := Net.server
	var rules := Content.rules(server.content)
	add_child(GameUI.hint("Les règles s'appliquent immédiatement à toute la campagne (fiches recalculées)."))
	var card := UIKit.card(self, "Règles de la campagne")
	var spins := {}
	for spec in Content.RULE_FIELDS:
		var s := UIKit.spin(int(rules.get(spec[0], 0)), int(spec[2]), int(spec[3]))
		UIKit.field(card, spec[1], s)
		spins[spec[0]] = s
	var swap := CheckBox.new()
	swap.text = "Autoriser à changer de capacités équipées pendant un combat"
	swap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	swap.button_pressed = bool(rules.get("swap_in_combat", false))
	card.add_child(swap)
	var shared := CheckBox.new()
	shared.text = "Vision partagée : chaque joueur voit ce que voit tout le groupe (sinon, seulement autour de son personnage)"
	shared.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shared.button_pressed = bool(rules.get("shared_vision", false))
	card.add_child(shared)
	card.add_child(UIKit.button("Appliquer les règles", "PrimaryButton", func():
		var values := {"swap_in_combat": swap.button_pressed, "shared_vision": shared.button_pressed}
		for k in spins:
			values[k] = int(spins[k].value)
		server.mj_set_rules(values)
		show_requested.emit("Règles", UIKit.label("Règles appliquées.", "", true))))


func _small(text: String, variation: String, cb: Callable) -> Button:
	var b := UIKit.button(text, variation, cb)
	b.custom_minimum_size.y = 36
	b.add_theme_font_size_override("font_size", 14)
	return b
