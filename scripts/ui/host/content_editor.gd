class_name ContentEditor
extends VBoxContainer
## Formulaire de création / modification d'une entrée du catalogue (MJ) :
## objet, capacité, effet de statut, monstre, classe, table de butin.
## Les effets se composent librement (dégâts + étourdissement + soin…),
## sans programmation. Les données sont validées par l'hôte (Content.sanitize).

signal saved(kind: String, data: Dictionary)
signal cancelled

const ICONS := ["sword", "axe", "hammer", "spear", "dagger", "bow", "crossbow", "gun", "staff", "wand", "lute", "claw", "fist",
	"armor", "robe", "cloak", "shield", "ward", "castle", "ring", "amulet", "crown", "boots", "eye", "book", "scroll", "map",
	"potion", "flask", "food", "bomb", "leather", "scale", "fang", "herb", "leaf", "ore", "gem", "crystal", "key", "coin", "bag",
	"chest", "fire", "meteor", "ice", "bolt", "heart", "cross", "phoenix", "horn", "spiral", "wave", "wind", "mask", "drop",
	"sun", "moon", "star", "sparkle", "target", "arrow", "chain", "paw", "hand", "gear", "skull", "spirit", "dragon", "music", "hourglass"]
const STAT_FIELDS := ["Force", "Dextérité", "Constitution", "Intelligence", "Esprit", "Charisme"]
const TRIGGERS := {"always": "Toujours actif (bonus permanent ou sous condition)", "turn_start": "Au début de son tour",
	"on_hit": "Quand il touche avec une attaque", "on_kill": "Quand il met un ennemi hors de combat",
	"on_damaged": "Quand il subit des dégâts", "ally_damaged": "Quand un allié proche subit des dégâts", "on_heal": "Quand il soigne"}

var kind := ""
var data := {}
var content := {}
var _get := {}  # clé -> Callable() renvoyant la valeur


func _init(entry_kind: String, entry: Dictionary, content_data: Dictionary) -> void:
	kind = entry_kind
	data = entry.duplicate(true)
	content = content_data
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match kind:
		"items":
			_build_item()
		"abilities":
			_build_ability()
		"statuses":
			_build_status()
		"monsters":
			_build_monster()
		"classes":
			_build_class()
		"loot":
			_build_loot()
		"species":
			_build_species()
	var actions := HBoxContainer.new()
	add_child(actions)
	actions.add_child(UIKit.button("Annuler", "", func(): cancelled.emit()))
	actions.add_child(UIKit.spacer(false))
	actions.add_child(UIKit.button("Aperçu", "", show_preview))
	var save := UIKit.button("Enregistrer", "PrimaryButton", func(): saved.emit(kind, collect()))
	save.custom_minimum_size.x = 180
	actions.add_child(save)


## Aperçu : la carte telle que les joueurs la verront, après validation par les
## mêmes règles que l'enregistrement (Content.sanitize), dans une fenêtre.
func show_preview() -> void:
	var _preview := VBoxContainer.new()
	_preview.add_theme_constant_override("separation", 8)
	var entry := Content.sanitize(kind, collect(), content)
	match kind:
		"items":
			_preview.add_child(GameUI.item_card(entry, content))
			var use := Effects.describe_list(entry.get("use", []), content)
			if use != "":
				_preview.add_child(UIKit.label("À l'utilisation : " + use, "MutedLabel", true))
		"abilities":
			_preview.add_child(GameUI.ability_card(entry, content, "Mana"))
		"statuses":
			var row := HBoxContainer.new()
			row.add_child(GameUI.icon_badge(String(entry.get("icon", "sparkle")), Color(String(entry.get("color", "#a07cc9"))), 34))
			row.add_child(UIKit.label("%s — %s" % [entry.get("name", "?"), entry.get("description", "")], "", true))
			_preview.add_child(row)
		"classes":
			_preview.add_child(UIKit.label(String(entry.get("name", "?")), "HeadingLabel", true))
			if not (entry.get("passive", {}) as Dictionary).is_empty():
				_preview.add_child(GameUI.passive_card(entry.passive, content))
			for id in entry.get("abilities", []) + [entry.get("ultimate", "")]:
				var a := Content.get_entry(content, "abilities", String(id))
				if not a.is_empty():
					_preview.add_child(GameUI.ability_card(a, content, String(entry.get("resource", {}).get("name", "Mana"))))
		"species":
			var sy := {}
			for cid in entry.get("synergies", {}):
				if String(entry.synergies[cid].get("name", "")) != "":
					sy = entry.synergies[cid]
					break
			_preview.add_child(GameUI.species_card(entry, sy, content))
		"monsters":
			_preview.add_child(UIKit.label("%s%s — %d PV, arme %s, %d XP" % [entry.get("name", "?"), " (boss)" if entry.get("boss", false) else "", int(entry.get("hp", 0)), entry.get("weapon", {}).get("damage", "?"), int(entry.get("xp", 0))], "StrongLabel", true))
			for id in entry.get("abilities", []):
				var a := Content.get_entry(content, "abilities", String(id))
				if not a.is_empty():
					_preview.add_child(GameUI.ability_card(a, content, "Énergie"))
		_:
			_preview.add_child(UIKit.label(String(entry.get("name", "?")), "StrongLabel", true))
	ConfirmBox.show_content(get_tree().current_scene, "Aperçu", _preview)


func collect() -> Dictionary:
	var out := data.duplicate(true)
	for key in _get:
		var v: Variant = _get[key].call()
		_set_path(out, key, v)
	return out


static func _set_path(d: Dictionary, path: String, v: Variant) -> void:
	var parts := path.split("/")
	var cur := d
	for i in parts.size() - 1:
		if not cur.get(parts[i]) is Dictionary:
			cur[parts[i]] = {}
		cur = cur[parts[i]]
	cur[parts[-1]] = v


func _value(path: String, fallback: Variant = null) -> Variant:
	var cur: Variant = data
	for p in path.split("/"):
		if not cur is Dictionary or not (cur as Dictionary).has(p):
			return fallback
		cur = cur[p]
	return cur


# ---------------------------------------------------------------------------
# Champs
# ---------------------------------------------------------------------------

func _text(parent: Node, path: String, caption: String, placeholder: String = "") -> void:
	var e := UIKit.line_edit(String(_value(path, "")), placeholder)
	UIKit.field(parent, caption, e)
	_get[path] = func(): return e.text


func _long(parent: Node, path: String, caption: String) -> void:
	var t := TextEdit.new()
	t.text = String(_value(path, ""))
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.custom_minimum_size.y = 70
	UIKit.field(parent, caption, t)
	_get[path] = func(): return t.text


func _int(parent: Node, path: String, caption: String, lo: int, hi: int, fallback: int = 0) -> void:
	var s := UIKit.spin(int(_value(path, fallback)), lo, hi)
	UIKit.field(parent, caption, s)
	_get[path] = func(): return int(s.value)


func _bool(parent: Node, path: String, caption: String) -> void:
	var c := CheckBox.new()
	c.text = caption
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.button_pressed = bool(_value(path, false))
	parent.add_child(c)
	_get[path] = func(): return c.button_pressed


func _enum(parent: Node, path: String, caption: String, options: Variant, fallback: String = "") -> OptionButton:
	var o := OptionButton.new()
	var current := String(_value(path, fallback))
	var pairs: Array = []
	if options is Dictionary:
		for k in options:
			pairs.append([String(k), String(options[k])])
	else:
		for k in options:
			pairs.append([String(k), String(k)])
	for p in pairs:
		o.add_item(p[1])
		o.set_item_metadata(o.item_count - 1, p[0])
		if p[0] == current:
			o.select(o.item_count - 1)
	UIKit.field(parent, caption, o)
	_get[path] = func(): return String(o.get_item_metadata(o.selected)) if o.selected >= 0 else ""
	return o


func _ref(parent: Node, path: String, caption: String, ref_kind: String, allow_empty: bool = true) -> void:
	var opts := {}
	if allow_empty:
		opts[""] = "(aucun)"
	for e in Content.list(content, ref_kind):
		opts[String(e.id)] = String(e.get("name", e.id))
	_enum(parent, path, caption, opts)


func _icon(parent: Node, path: String) -> void:
	var row := HBoxContainer.new()
	var preview := Icons.new(String(_value(path, "star")), Palette.GOLD, 36)
	row.add_child(preview)
	var o := _enum(row, path, "Icône", ICONS, "star")
	o.item_selected.connect(func(i): preview.set_icon(String(o.get_item_metadata(i))))
	parent.add_child(row)


func _color(parent: Node, path: String, caption: String) -> void:
	var picker := ColorPickerButton.new()
	picker.color = Color(String(_value(path, "#8a8f9a")))
	picker.custom_minimum_size = Vector2(80, 40)
	UIKit.field(parent, caption, picker)
	_get[path] = func(): return "#" + picker.color.to_html(false)


func _dice(parent: Node, path: String, caption: String, fallback: String = "1d6") -> void:
	_text(parent, path, caption, "1d6, 2d8+1…")
	if String(_value(path, "")) == "":
		_set_path(data, path, fallback)


## Bonus / malus : liste de lignes « Défense +2 ».
func _mods(parent: Node, path: String, caption: String) -> void:
	var card := UIKit.card(parent, caption, "InsetPanel")
	var rows := VBoxContainer.new()
	card.add_child(rows)
	var add_row := func(key: String, value: int):
		var row := HBoxContainer.new()
		var o := OptionButton.new()
		for k in Content.MOD_KEYS:
			o.add_item(String(Content.MOD_NAMES.get(k, k)))
			o.set_item_metadata(o.item_count - 1, k)
			if k == key:
				o.select(o.item_count - 1)
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(o)
		var s := UIKit.spin(value, -99, 999)
		row.add_child(s)
		var x := UIKit.button("×", "DangerButton", func(): row.queue_free())
		x.custom_minimum_size.x = 40
		row.add_child(x)
		row.set_meta("get", func(): return [String(o.get_item_metadata(o.selected)), int(s.value)])
		rows.add_child(row)
	var mods: Dictionary = _value(path, {}) if _value(path, {}) is Dictionary else {}
	for k in mods:
		if mods[k] is int or mods[k] is float:
			add_row.call(String(k), int(mods[k]))
	card.add_child(UIKit.button("+ Ajouter un bonus / malus", "", func(): add_row.call("defense", 1)))
	_get[path] = func():
		var out := {}
		for row in rows.get_children():
			if row.is_queued_for_deletion() or not row.has_meta("get"):
				continue
			var kv: Array = row.get_meta("get").call()
			if int(kv[1]) != 0:
				out[kv[0]] = int(kv[1])
		var keep: Dictionary = _value(path, {}) if _value(path, {}) is Dictionary else {}
		if keep.has("damage_dice"):
			out["damage_dice"] = keep.damage_dice
		return out


## Liste de références (capacités d'un monstre, accordées par un objet…).
func _ref_list(parent: Node, path: String, caption: String, ref_kind: String) -> void:
	var card := UIKit.card(parent, caption, "InsetPanel")
	var rows := VBoxContainer.new()
	card.add_child(rows)
	var add_row := func(id: String):
		var row := HBoxContainer.new()
		var o := OptionButton.new()
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for e in Content.list(content, ref_kind):
			o.add_item(String(e.get("name", e.id)))
			o.set_item_metadata(o.item_count - 1, String(e.id))
			if String(e.id) == id:
				o.select(o.item_count - 1)
		row.add_child(o)
		var x := UIKit.button("×", "DangerButton", func(): row.queue_free())
		x.custom_minimum_size.x = 40
		row.add_child(x)
		row.set_meta("get", func(): return String(o.get_item_metadata(o.selected)) if o.selected >= 0 else "")
		rows.add_child(row)
	var current: Variant = _value(path, [])
	if current is Array:
		for id in current:
			add_row.call(String(id))
	card.add_child(UIKit.button("+ Ajouter", "", func(): add_row.call("")))
	_get[path] = func():
		var out: Array = []
		for row in rows.get_children():
			if not row.is_queued_for_deletion() and row.has_meta("get"):
				var id := String(row.get_meta("get").call())
				if id != "":
					out.append(id)
		return out


## Composeur d'effets : chaque ligne est un effet (type + réglages).
func _effects(parent: Node, path: String, caption: String, hint: String = "") -> void:
	var card := UIKit.card(parent, caption, "InsetPanel")
	if hint != "":
		card.add_child(UIKit.label(hint, "MutedLabel", true))
	var list := EffectList.new(_value(path, []) if _value(path, []) is Array else [], content)
	card.add_child(list)
	_get[path] = func(): return list.collect()


# ---------------------------------------------------------------------------
# Formulaires par type
# ---------------------------------------------------------------------------

func _build_item() -> void:
	var main := UIKit.card(self, "Objet")
	_text(main, "name", "Nom", "Ex. : Lame de lune")
	_icon(main, "icon")
	_enum(main, "category", "Catégorie", Content.CATEGORY_NAMES, "arme")
	_enum(main, "rarity", "Rareté", Content.RARITY_NAMES, "commun")
	_long(main, "description", "Description")
	_int(main, "value", "Valeur (or)", 0, 999999)
	_bool(main, "unique", "Objet unique (un seul exemplaire dans la campagne)")
	var w := UIKit.card(self, "Arme (si c'est une arme)")
	_dice(w, "weapon/damage", "Dégâts", "1d6")
	_enum(w, "weapon/stat", "Caractéristique utilisée", STAT_FIELDS, "Force")
	_int(w, "weapon/crit", "Critique à partir de (20 = seulement sur 20)", 2, 20, 20)
	_int(w, "weapon/range", "Portée (cases)", 1, 30, 1)
	_enum(w, "weapon/element", "Type de dégâts", {"physique": "Physique", "magique": "Magique"}, "physique")
	_mods(self, "mods", "Bonus quand l'objet est équipé")
	_effects(self, "use", "Effets à l'utilisation (potions, consommables)", "Laissez vide si l'objet ne s'utilise pas.")
	_effects(self, "on_hit", "Effets quand l'arme touche", "Ex. : 25 % d'empoisonner, vol de vie…")
	_ref_list(self, "grants", "Capacités accordées tant que l'objet est équipé", "abilities")
	var book := UIKit.card(self, "Livre de compétence")
	_ref(book, "teaches", "Apprend la capacité (à la lecture)", "abilities")


func _build_ability() -> void:
	var main := UIKit.card(self, "Capacité")
	_text(main, "name", "Nom", "Ex. : Lance de glace")
	_text(main, "short", "Nom court (barre rapide)", "14 lettres max.")
	_icon(main, "icon")
	_long(main, "description", "Description")
	_bool(main, "ultimate", "Ultime (utilisable quand la jauge est pleine)")
	var costs := UIKit.card(self, "Coûts et portée")
	_int(costs, "cost", "Coût en ressource (mana…)", 0, 999)
	_int(costs, "ap", "Coût en points d'action", 0, 6, 1)
	_int(costs, "cooldown", "Recharge (tours, 0 = aucune)", 0, 99)
	_int(costs, "range", "Portée (cases, 0 = soi / autour de soi)", 0, 30, 1)
	_enum(costs, "target", "Cible", Content.TARGET_NAMES, "enemy")
	_int(costs, "radius", "Rayon de la zone (si zone)", 0, 6)
	_enum(costs, "roll", "Jet", {"attack": "Jet d'attaque contre la Défense", "none": "Touche automatiquement"}, "attack")
	_enum(costs, "stat", "Caractéristique utilisée", STAT_FIELDS, "Force")
	_enum(costs, "element", "Nature", {"physique": "Physique", "magique": "Magique", "soin": "Soin"}, "physique")
	_int(costs, "conditions/self_hp_below", "Condition : utilisable sous X % de PV (0 = toujours)", 0, 100)
	_effects(self, "effects", "Effets (dans l'ordre)", "Combinez librement : dégâts, soins, effets de statut, repousser, invoquer…")


func _build_status() -> void:
	var main := UIKit.card(self, "Effet de statut")
	_text(main, "name", "Nom", "Ex. : Gelé")
	_icon(main, "icon")
	_color(main, "color", "Couleur")
	_enum(main, "kind", "Type", {"buff": "Bénéfique", "debuff": "Néfaste"}, "debuff")
	_long(main, "description", "Description (affichée aux joueurs)")
	_mods(self, "mods", "Bonus / malus tant que l'effet dure")
	var flags := UIKit.card(self, "Particularités")
	var current: Array = data.get("flags", [])
	var checks := {}
	for spec in [["stun", "Perd son tour (étourdi)"], ["root", "Ne peut pas se déplacer"], ["silence", "Ne peut pas utiliser de capacité"],
			["shield", "Bouclier : absorbe des dégâts (valeur)"], ["untargetable", "Impossible à cibler"], ["break_on_attack", "Prend fin quand il attaque"]]:
		var c := CheckBox.new()
		c.text = spec[1]
		c.button_pressed = current.has(spec[0])
		flags.add_child(c)
		checks[spec[0]] = c
	_get["flags"] = func():
		var out: Array = []
		for k in checks:
			if checks[k].button_pressed:
				out.append(k)
		return out
	var tick := UIKit.card(self, "Au début de chaque tour (facultatif)")
	_enum(tick, "tick/type", "Effet", {"": "Rien", "damage": "Dégâts", "heal": "Soin"}, "")
	_dice(tick, "tick/dice", "Dés", "1d4")


func _build_monster() -> void:
	var main := UIKit.card(self, "Monstre")
	_text(main, "name", "Nom", "Ex. : Loup des neiges")
	_icon(main, "icon")
	_color(main, "color", "Couleur du pion")
	_long(main, "description", "Description")
	_bool(main, "boss", "Boss")
	var stats := UIKit.card(self, "Caractéristiques (1 à 10, 5 = moyen)")
	var grid := GridContainer.new()
	grid.columns = 3
	stats.add_child(grid)
	for s in STAT_FIELDS:
		_int(grid, "stats/" + s, s, 1, 30, 5)
	var fight := UIKit.card(self, "Combat")
	_int(fight, "hp", "Points de vie", 1, 99999, 20)
	_int(fight, "defense_bonus", "Bonus de Défense", -10, 30)
	_int(fight, "power", "Puissance (bonus de dégâts)", 0, 99, 2)
	_int(fight, "speed", "Vitesse (cases)", 1, 20, 5)
	_int(fight, "aggro", "Périmètre d'attaque (cases, 0 = règle de la campagne)", 0, 20, 0)
	_int(fight, "res", "Ressource (pour ses capacités)", 0, 999, 10)
	_dice(fight, "weapon/damage", "Dégâts de son attaque", "1d6")
	_enum(fight, "weapon/stat", "Caractéristique de l'attaque", STAT_FIELDS, "Force")
	_int(fight, "weapon/range", "Portée de l'attaque", 1, 30, 1)
	_enum(fight, "weapon/element", "Type de dégâts", {"physique": "Physique", "magique": "Magique"}, "physique")
	_ref_list(self, "abilities", "Capacités", "abilities")
	var rw := UIKit.card(self, "Récompenses")
	_int(rw, "xp", "XP rapportée", 0, 999999, 20)
	_ref(rw, "loot", "Table de butin", "loot")


## Peuple : bonus, trait, capacités innées ; les synergies avec chaque classe se
## règlent ci-dessous (une ligne par classe).
func _build_species() -> void:
	var main := UIKit.card(self, "Peuple")
	_text(main, "name", "Nom", "Ex. : Elfe des neiges")
	_icon(main, "icon")
	_long(main, "description", "Description")
	var stats := UIKit.card(self, "Bonus de caractéristiques (−5 à +5)")
	var grid := GridContainer.new()
	grid.columns = 3
	stats.add_child(grid)
	for s in STAT_FIELDS:
		_int(grid, "stats/" + s, s, -5, 5, 0)
	_mods(self, "mods", "Bonus de jeu (PV, mana, vision, résistances…)")
	var tr := UIKit.card(self, "Trait")
	_text(tr, "trait/name", "Nom du trait", "Ex. : Sang ancien")
	_long(tr, "trait/description", "Ce qu'il fait, en une phrase")
	_ref_list(self, "abilities", "Capacités de peuple (toujours disponibles)", "abilities")
	var syn := UIKit.card(self, "Synergies avec les classes (facultatif)")
	syn.add_child(GameUI.hint("Ex. : un demi-orc druide gagne « Appel de la horde ». Laissez vide pour aucune synergie."))
	for cls in Content.list(content, "classes"):
		var cid := String(cls.id)
		var box := UIKit.card(syn, String(cls.get("name", cid)), "InsetPanel")
		_text(box, "synergies/%s/name" % cid, "Nom de la synergie", "")
		_text(box, "synergies/%s/description" % cid, "Effet (texte)", "")
		_mods(box, "synergies/%s/mods" % cid, "Bonus")
		_ref_list(box, "synergies/%s/abilities" % cid, "Capacités accordées", "abilities")


func _build_class() -> void:
	var main := UIKit.card(self, "Classe")
	_text(main, "name", "Nom", "Ex. : Nécromancien")
	_text(main, "tagline", "Accroche", "Une phrase")
	_text(main, "role", "Rôle", "Ex. : Soutien, tank…")
	_long(main, "description", "Description")
	_color(main, "color", "Couleur")
	_enum(main, "emblem", "Emblème", ["sword", "dagger", "fist", "claw", "flame", "spirit", "eye", "heart", "paw", "gear", "staff", "bow", "lute"], "sword")
	_int(main, "difficulty", "Difficulté (1 à 3)", 1, 3, 1)
	var stats := UIKit.card(self, "Bonus de caractéristiques")
	var grid := GridContainer.new()
	grid.columns = 3
	stats.add_child(grid)
	for s in STAT_FIELDS:
		_int(grid, "bonus/" + s, s, -5, 5, 0)
	var vals := UIKit.card(self, "Valeurs de base")
	_int(vals, "hp_base", "PV de base", 1, 999, 14)
	_int(vals, "hp_per_level", "PV gagnés par niveau", 0, 99, 5)
	_text(vals, "resource/name", "Nom de la ressource", "Mana, Vigueur, AEC…")
	_enum(vals, "resource/stat", "Caractéristique de la ressource", STAT_FIELDS, "Esprit")
	_int(vals, "resource/base", "Ressource de base", 0, 999, 8)
	_int(vals, "speed", "Vitesse (cases)", 1, 20, 5)
	_int(vals, "crit_bonus", "Bonus de critique", 0, 10)
	_int(vals, "defense_bonus", "Bonus de Défense", -5, 20)
	_int(vals, "attack_bonus", "Bonus au toucher", -5, 20)
	var p := UIKit.card(self, "Passif")
	_text(p, "passive/name", "Nom du passif")
	_long(p, "passive/description", "Description (ce que voient les joueurs)")
	_icon(p, "passive/icon")
	_enum(p, "passive/trigger", "Se déclenche", TRIGGERS, "always")
	_int(p, "passive/cond/self_hp_below", "Condition : PV du personnage sous X % (0 = sans)", 0, 100)
	_int(p, "passive/cond/distance_min", "Condition : cible à X cases ou plus (0 = sans)", 0, 30)
	_bool(p, "passive/cond/target_weak", "Condition : cible blessée ou affaiblie")
	_int(p, "passive/reduce", "Protection d'un allié : dégâts réduits de", 0, 99)
	_int(p, "passive/range", "Portée de la protection (cases)", 0, 10)
	_mods(p, "passive/mods", "Bonus du passif")
	_effects(p, "passive/effects", "Effets du passif quand il se déclenche")
	var kit := UIKit.card(self, "Capacités de départ")
	for i in 3:
		var path := "abilities"
		var current: Array = data.get("abilities", [])
		var o := OptionButton.new()
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for e in Content.list(content, "abilities"):
			o.add_item(String(e.name))
			o.set_item_metadata(o.item_count - 1, String(e.id))
			if i < current.size() and String(e.id) == String(current[i]):
				o.select(o.item_count - 1)
		UIKit.field(kit, "Capacité de base %d" % (i + 1), o)
		kit.set_meta("ab%d" % i, o)
	_get["abilities"] = func():
		var out: Array = []
		for i in 3:
			var o: OptionButton = kit.get_meta("ab%d" % i)
			if o.selected >= 0:
				out.append(String(o.get_item_metadata(o.selected)))
		return out
	_ref(kit, "ultimate", "Ultime", "abilities", false)
	_learnables()
	_kit_rows()


func _learnables() -> void:
	var card := UIKit.card(self, "Capacités à apprendre en montant de niveau", "InsetPanel")
	var rows := VBoxContainer.new()
	card.add_child(rows)
	var add := func(id: String, level: int):
		var row := HBoxContainer.new()
		var o := OptionButton.new()
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for e in Content.list(content, "abilities"):
			o.add_item(String(e.name))
			o.set_item_metadata(o.item_count - 1, String(e.id))
			if String(e.id) == id:
				o.select(o.item_count - 1)
		row.add_child(o)
		var s := UIKit.spin(level, 1, 99)
		s.prefix = "niv."
		row.add_child(s)
		row.add_child(UIKit.button("×", "DangerButton", func(): row.queue_free()))
		row.set_meta("get", func(): return {"ability": String(o.get_item_metadata(o.selected)) if o.selected >= 0 else "", "level": int(s.value)})
		rows.add_child(row)
	for l in data.get("learnable", []):
		add.call(String(l.get("ability", "")), int(l.get("level", 2)))
	card.add_child(UIKit.button("+ Ajouter", "", func(): add.call("", 2)))
	_get["learnable"] = func():
		var out: Array = []
		for row in rows.get_children():
			if not row.is_queued_for_deletion() and row.has_meta("get"):
				var v: Dictionary = row.get_meta("get").call()
				if String(v.ability) != "":
					out.append(v)
		return out


func _kit_rows() -> void:
	var card := UIKit.card(self, "Équipement de départ", "InsetPanel")
	var rows := VBoxContainer.new()
	card.add_child(rows)
	var add := func(id: String, qty: int, equip: bool):
		var row := HBoxContainer.new()
		var o := OptionButton.new()
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for e in Content.list(content, "items"):
			o.add_item(String(e.name))
			o.set_item_metadata(o.item_count - 1, String(e.id))
			if String(e.id) == id:
				o.select(o.item_count - 1)
		row.add_child(o)
		var s := UIKit.spin(qty, 1, 99)
		row.add_child(s)
		var c := CheckBox.new()
		c.text = "équipé"
		c.button_pressed = equip
		row.add_child(c)
		row.add_child(UIKit.button("×", "DangerButton", func(): row.queue_free()))
		row.set_meta("get", func(): return {"item": String(o.get_item_metadata(o.selected)) if o.selected >= 0 else "", "qty": int(s.value), "equip": c.button_pressed})
		rows.add_child(row)
	for k in data.get("kit", []):
		add.call(String(k.get("item", "")), int(k.get("qty", 1)), bool(k.get("equip", false)))
	card.add_child(UIKit.button("+ Ajouter un objet", "", func(): add.call("", 1, false)))
	_get["kit"] = func():
		var out: Array = []
		for row in rows.get_children():
			if not row.is_queued_for_deletion() and row.has_meta("get"):
				var v: Dictionary = row.get_meta("get").call()
				if String(v.item) != "":
					out.append(v)
		return out
	card.add_child(UIKit.label("Les choix d'équipement de la classe (ex. trois dagues au choix) sont conservés tels quels.", "MutedLabel", true))


func _build_loot() -> void:
	var main := UIKit.card(self, "Table de butin")
	_text(main, "name", "Nom", "Ex. : Repaire des brigands")
	var g := HBoxContainer.new()
	main.add_child(g)
	var gold: Array = data.get("gold", [0, 0])
	var lo := UIKit.spin(int(gold[0]) if gold.size() > 0 else 0, 0, 999999)
	var hi := UIKit.spin(int(gold[1]) if gold.size() > 1 else 0, 0, 999999)
	UIKit.field(g, "Or minimum", lo)
	UIKit.field(g, "Or maximum", hi)
	_get["gold"] = func(): return [int(lo.value), int(hi.value)]
	for spec in [["entries", "Objets possibles (chance en %)", true], ["guaranteed", "Objets garantis", false]]:
		var card := UIKit.card(self, spec[1], "InsetPanel")
		var rows := VBoxContainer.new()
		card.add_child(rows)
		var chance_mode: bool = spec[2]
		var add := func(e: Dictionary):
			var row := HBoxContainer.new()
			var o := OptionButton.new()
			o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for it in Content.list(content, "items"):
				o.add_item(String(it.name))
				o.set_item_metadata(o.item_count - 1, String(it.id))
				if String(it.id) == String(e.get("item", "")):
					o.select(o.item_count - 1)
			row.add_child(o)
			var c := UIKit.spin(int(e.get("chance", 50)), 0, 100)
			c.suffix = "%"
			c.visible = chance_mode
			row.add_child(c)
			var q := UIKit.spin(int(e.get("min", e.get("qty", 1))), 1, 999)
			q.prefix = "×"
			row.add_child(q)
			row.add_child(UIKit.button("×", "DangerButton", func(): row.queue_free()))
			row.set_meta("get", func():
				var item := String(o.get_item_metadata(o.selected)) if o.selected >= 0 else ""
				return {"item": item, "chance": int(c.value), "min": int(q.value), "max": int(q.value)} if chance_mode else {"item": item, "qty": int(q.value)})
			rows.add_child(row)
		for e in data.get(spec[0], []):
			add.call(e)
		card.add_child(UIKit.button("+ Ajouter", "", func(): add.call({})))
		var key: String = spec[0]
		_get[key] = func():
			var out: Array = []
			for row in rows.get_children():
				if not row.is_queued_for_deletion() and row.has_meta("get"):
					var v: Dictionary = row.get_meta("get").call()
					if String(v.item) != "":
						out.append(v)
			return out
