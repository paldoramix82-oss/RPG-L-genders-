class_name BrickPalette
extends VBoxContainer
## Briques : blocs prêts à combiner pour fabriquer une capacité ou un passif
## sans rien régler à la main. Chaque brique ajoute un ou plusieurs effets
## (« effects ») et peut fixer quelques réglages (« fields » : cible, zone,
## déclencheur…). On empile les briques, puis on ajuste si on veut.
##   mode "ability" : formes de ciblage + effets
##   mode "passive" : déclencheurs + effets + particularités

signal picked(brick: Dictionary)

const EFFECT_GROUPS := [
	["Frapper", "sword", [
		{"label": "Coup", "icon": "sword", "effects": [{"type": "damage", "dice": "1d8", "element": "physique"}], "fields": {"element": "physique", "roll": "attack", "stat": "Force"}},
		{"label": "Gros coup", "icon": "hammer", "effects": [{"type": "damage", "dice": "2d10", "element": "physique"}], "fields": {"element": "physique", "roll": "attack", "stat": "Force"}},
		{"label": "Sort", "icon": "sparkle", "effects": [{"type": "damage", "dice": "2d6", "element": "magique"}], "fields": {"element": "magique", "roll": "none", "stat": "Intelligence"}},
		{"label": "Feu", "icon": "fire", "effects": [{"type": "damage", "dice": "1d6", "element": "magique"}, {"type": "status", "status": "brulure", "turns": 2, "chance": 100, "value": 2}], "fields": {"element": "magique"}},
		{"label": "Glace", "icon": "ice", "effects": [{"type": "damage", "dice": "1d6", "element": "magique"}, {"type": "status", "status": "gel", "turns": 1, "chance": 60}], "fields": {"element": "magique"}},
		{"label": "Poison", "icon": "drop", "effects": [{"type": "status", "status": "poison", "turns": 3, "chance": 100, "value": 2}]},
		{"label": "Saignement", "icon": "dagger", "effects": [{"type": "status", "status": "saignement", "turns": 3, "chance": 100, "value": 2}]},
		{"label": "Vol de vie", "icon": "heart", "effects": [{"type": "drain", "pct": 40}]},
	]],
	["Soigner et protéger", "heart", [
		{"label": "Soin", "icon": "heart", "effects": [{"type": "heal", "dice": "2d4", "on": "target"}], "fields": {"element": "soin", "roll": "none", "stat": "Esprit"}},
		{"label": "Se soigner", "icon": "cross", "effects": [{"type": "heal", "dice": "1d8", "on": "self"}]},
		{"label": "Soin des alliés", "icon": "sun", "effects": [{"type": "heal", "dice": "1d6", "on": "allies"}]},
		{"label": "Bouclier", "icon": "shield", "effects": [{"type": "status", "status": "bouclier", "turns": 2, "chance": 100, "value": 8, "on": "target"}]},
		{"label": "Purifier", "icon": "wave", "effects": [{"type": "cleanse", "count": 2, "on": "target"}]},
		{"label": "Régénération", "icon": "leaf", "effects": [{"type": "status", "status": "regeneration", "turns": 3, "chance": 100, "value": 3, "on": "target"}]},
		{"label": "Mana +4", "icon": "crystal", "effects": [{"type": "restore", "resource": "res", "amount": 4, "on": "self"}]},
	]],
	["Contrôler", "chain", [
		{"label": "Étourdir", "icon": "star", "effects": [{"type": "status", "status": "etourdi", "turns": 1, "chance": 50}]},
		{"label": "Immobiliser", "icon": "chain", "effects": [{"type": "status", "status": "immobilise", "turns": 2, "chance": 100}]},
		{"label": "Silence", "icon": "mask", "effects": [{"type": "status", "status": "silence", "turns": 2, "chance": 75}]},
		{"label": "Aveugler", "icon": "eye", "effects": [{"type": "status", "status": "aveugle", "turns": 2, "chance": 75}]},
		{"label": "Effrayer", "icon": "skull", "effects": [{"type": "status", "status": "effraye", "turns": 2, "chance": 60}]},
		{"label": "Affaiblir", "icon": "spiral", "effects": [{"type": "stat", "stat": "Force", "amount": -2, "turns": 2, "on": "target"}]},
		{"label": "Repousser", "icon": "wind", "effects": [{"type": "push", "cells": 2}]},
		{"label": "Attirer", "icon": "arrow", "effects": [{"type": "pull", "cells": 2}]},
		{"label": "Voler 1 PA", "icon": "hourglass", "effects": [{"type": "ap", "amount": -1, "on": "target"}]},
	]],
	["Renforcer", "bolt", [
		{"label": "Force +2", "icon": "fist", "effects": [{"type": "stat", "stat": "Force", "amount": 2, "turns": 3, "on": "self"}]},
		{"label": "Hâte", "icon": "boots", "effects": [{"type": "status", "status": "hate", "turns": 2, "chance": 100, "on": "self"}]},
		{"label": "Rage", "icon": "fire", "effects": [{"type": "status", "status": "rage", "turns": 2, "chance": 100, "on": "self"}]},
		{"label": "Bénédiction", "icon": "sun", "effects": [{"type": "status", "status": "beni", "turns": 3, "chance": 100, "on": "allies"}]},
		{"label": "+1 PA", "icon": "hourglass", "effects": [{"type": "ap", "amount": 1, "on": "self"}]},
		{"label": "Invisible", "icon": "spirit", "effects": [{"type": "status", "status": "invisible", "turns": 2, "chance": 100, "on": "self"}]},
	]],
	["Invoquer", "spirit", [
		{"label": "Squelette", "icon": "skull", "effects": [{"type": "summon", "name": "Squelette", "hp": 12, "attack": "1d6", "defense": 11, "color": "#d8d2bf"}]},
		{"label": "Esprit", "icon": "spirit", "effects": [{"type": "summon", "name": "Esprit", "hp": 8, "attack": "1d8", "defense": 13, "color": "#9fc3d4"}]},
		{"label": "Loup", "icon": "paw", "effects": [{"type": "summon", "name": "Loup", "hp": 14, "attack": "1d6", "defense": 12, "color": "#8a7d6b"}]},
		{"label": "Golem", "icon": "castle", "effects": [{"type": "summon", "name": "Golem", "hp": 30, "attack": "1d10", "defense": 14, "color": "#7d7468"}]},
	]],
	["Conditions", "target", [
		{"label": "Achever (cible blessée : +2d6)", "icon": "skull", "effects": [{"type": "if", "cond": {"target_weak": true}, "then": [{"type": "damage", "dice": "2d6", "element": "physique"}]}]},
		{"label": "Désespoir (moi < 50 % PV : soin)", "icon": "heart", "effects": [{"type": "if", "cond": {"self_hp_below": 50}, "then": [{"type": "heal", "dice": "2d6", "on": "self"}]}]},
		{"label": "Chance 30 % : étourdir", "icon": "star", "effects": [{"type": "if", "cond": {"chance": 30}, "then": [{"type": "status", "status": "etourdi", "turns": 1, "chance": 100}]}]},
		{"label": "Cible affaiblie : poison", "icon": "drop", "effects": [{"type": "if", "cond": {"target_debuffed": true}, "then": [{"type": "status", "status": "poison", "turns": 3, "chance": 100, "value": 3}]}]},
		{"label": "Message", "icon": "scroll", "effects": [{"type": "narrate", "text": "Une aura étrange entoure le lanceur…"}]},
	]],
]

const SHAPES := ["Forme (qui est visé)", "target", [
	{"label": "Un ennemi au contact", "icon": "sword", "fields": {"target": "enemy", "range": 1, "radius": 0}},
	{"label": "Un ennemi à distance", "icon": "bow", "fields": {"target": "enemy", "range": 6, "radius": 0}},
	{"label": "Un allié", "icon": "heart", "fields": {"target": "ally", "range": 5, "radius": 0}},
	{"label": "Soi-même", "icon": "person", "fields": {"target": "self", "range": 0, "radius": 0}},
	{"label": "Zone autour de soi", "icon": "wave", "fields": {"target": "area_enemy", "range": 0, "radius": 2}},
	{"label": "Zone à distance", "icon": "meteor", "fields": {"target": "area_enemy", "range": 6, "radius": 1}},
	{"label": "Aura pour les alliés", "icon": "sun", "fields": {"target": "area_ally", "range": 0, "radius": 2}},
]]

const COSTS := ["Coût", "crystal", [
	{"label": "Gratuit, 1 PA", "icon": "hourglass", "fields": {"cost": 0, "ap": 1, "cooldown": 0}},
	{"label": "Petit sort (3 mana)", "icon": "crystal", "fields": {"cost": 3, "ap": 1, "cooldown": 0}},
	{"label": "Gros sort (6 mana, 2 PA)", "icon": "gem", "fields": {"cost": 6, "ap": 2, "cooldown": 1}},
	{"label": "Une fois par combat", "icon": "moon", "fields": {"cost": 0, "ap": 2, "cooldown": 99}},
]]

const TRIGGER_BRICKS := ["Quand ça se déclenche", "hourglass", [
	{"label": "Toujours", "icon": "sun", "fields": {"trigger": "always"}},
	{"label": "Début de tour", "icon": "hourglass", "fields": {"trigger": "turn_start"}},
	{"label": "Quand il touche", "icon": "sword", "fields": {"trigger": "on_hit"}},
	{"label": "Quand il achève", "icon": "skull", "fields": {"trigger": "on_kill"}},
	{"label": "Quand il est blessé", "icon": "drop", "fields": {"trigger": "on_damaged"}},
	{"label": "Quand il soigne", "icon": "heart", "fields": {"trigger": "on_heal"}},
	{"label": "Garde un allié proche (−3 dégâts)", "icon": "shield", "fields": {"trigger": "ally_damaged", "reduce": 3, "range": 1}},
]]

const PASSIVE_BONUS := ["Bonus permanents", "star", [
	{"label": "+2 Défense", "icon": "shield", "mods": {"defense": 2}},
	{"label": "+2 dégâts", "icon": "sword", "mods": {"damage": 2}},
	{"label": "+1 au toucher", "icon": "target", "mods": {"to_hit": 1}},
	{"label": "+10 PV max", "icon": "heart", "mods": {"hp_max": 10}},
	{"label": "+1 vitesse", "icon": "boots", "mods": {"speed": 1}},
	{"label": "+1 PA", "icon": "hourglass", "mods": {"ap": 1}},
	{"label": "Sait nager", "icon": "wave", "mods": {"nage": 1}},
	{"label": "Insensible à la magie ciblée", "icon": "mask", "traits": ["anti_magie"]},
]]

var mode := "ability"
var last_group := ""


func _init(for_mode: String = "ability", open_group: String = "") -> void:
	mode = for_mode
	add_theme_constant_override("separation", 6)
	add_child(UIKit.label("Touchez des briques pour les ajouter : elles s'empilent. Vous pouvez ensuite ajuster chaque effet plus bas.", "MutedLabel", true))
	var groups: Array = []
	if mode == "ability":
		groups = [SHAPES, COSTS] + EFFECT_GROUPS
	else:
		groups = [TRIGGER_BRICKS, PASSIVE_BONUS] + EFFECT_GROUPS
	for g in groups:
		# Ouvert : le dernier groupe utilisé, sinon le premier (forme / déclencheur) et « Frapper ».
		var title := String(g[0])
		var open: bool = title == open_group if open_group != "" else (g == groups[0] or title == "Frapper")
		var box := UIKit.fold(self, title, open, "InsetPanel")
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		box.add_child(flow)
		for brick in g[2]:
			var b := UIKit.button(String(brick.label), "", func():
				last_group = title
				picked.emit(brick))
			b.custom_minimum_size = Vector2(0, 40)
			var tex := Sprites.glyph(String(brick.get("icon", "")))
			if tex != null:
				b.icon = tex
				b.expand_icon = false
			b.tooltip_text = describe(brick)
			flow.add_child(b)


## Ce que fait une brique, en clair.
static func describe(brick: Dictionary) -> String:
	var parts: Array = []
	if brick.has("effects"):
		parts.append(Effects.describe_list(brick.effects, {}))
	for k in brick.get("fields", {}):
		parts.append("%s = %s" % [k, brick.fields[k]])
	for k in brick.get("mods", {}):
		parts.append("%s %+d" % [k, int(brick.mods[k])])
	return " · ".join(PackedStringArray(parts))


## Nom proposé à partir des briques posées (« Feu + Zone »…).
static func suggest_name(labels: Array) -> String:
	if labels.is_empty():
		return ""
	return " ".join(PackedStringArray(labels.slice(0, 2)))
