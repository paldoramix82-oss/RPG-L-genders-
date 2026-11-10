class_name QuestPanel
extends VBoxContainer
## Quêtes du MJ : brouillons, quêtes en cours (objectifs à cocher), terminées.
## Donner une quête l'annonce aux joueurs concernés ; la réussir distribue les
## récompenses (XP, or, objets) une seule fois.

signal edit_requested(quest: Dictionary)


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rebuild()


func rebuild() -> void:
	UIKit.clear(self)
	var server := Net.server
	add_child(UIKit.button("+  Nouvelle quête", "PrimaryButton", func(): edit_requested.emit({})))
	add_child(GameUI.hint("Préparez une quête en brouillon et donnez-la au bon moment, ou donnez-la tout de suite. Elle peut concerner tout le groupe ou certains joueurs seulement."))
	if server.quests.is_empty():
		add_child(UIKit.label("Aucune quête pour l'instant.", "MutedLabel", true))
	for status in ["active", "draft", "done", "failed"]:
		var list := server.quests.filter(func(q): return q.status == status)
		if list.is_empty():
			continue
		add_child(UIKit.label({"active": "En cours", "draft": "Brouillons", "done": "Réussies", "failed": "Échouées"}[status], "HeadingLabel"))
		list.sort_custom(func(a, b): return a.kind == "main" and b.kind != "main")
		for q in list:
			add_child(_quest_card(q))


func _quest_card(q: Dictionary) -> Control:
	var server := Net.server
	var card := UIKit.card(null, "", "HighlightPanel" if q.kind == "main" and q.status == "active" else "InsetPanel")
	var head := HBoxContainer.new()
	card.add_child(head)
	head.add_child(GameUI.icon_badge("crown" if q.kind == "main" else "journal", Palette.GOLD, 28))
	head.add_child(UIKit.label(String(q.title), "StrongLabel", true))
	var who := "tout le groupe"
	if not (q.get("assigned", []) as Array).is_empty():
		var names: PackedStringArray = []
		for pid in q.assigned:
			names.append(String(server.players.get(pid, {}).get("name", "?")))
		who = ", ".join(names)
	card.add_child(UIKit.label("%s · pour %s" % ["Principale" if q.kind == "main" else "Secondaire", who], "MutedLabel", true))
	var qid := String(q.id)
	var objectives: Array = q.get("objectives", [])
	for i in objectives.size():
		var c := CheckBox.new()
		c.text = String(objectives[i].text)
		c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.button_pressed = bool(objectives[i].done)
		c.disabled = q.status != "active"
		var idx := i
		c.toggled.connect(func(on): server.mj_quest_objective(qid, idx, on))
		card.add_child(c)
	var rw: Dictionary = q.get("rewards", {})
	var parts: PackedStringArray = []
	if int(rw.get("xp", 0)) > 0:
		parts.append("%d XP" % int(rw.xp))
	if int(rw.get("gold", 0)) > 0:
		parts.append("%d or" % int(rw.gold))
	for it in rw.get("items", []):
		var name := String(it.get("def", {}).get("name", "")) if it.has("def") else String(Content.get_entry(server.content, "items", String(it.get("item", ""))).get("name", "?"))
		parts.append("%s ×%d" % [name, int(it.get("qty", 1))])
	if not parts.is_empty():
		var l := UIKit.label("Récompense : " + ", ".join(parts), "", true)
		l.add_theme_color_override("font_color", Palette.ULT)
		card.add_child(l)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	card.add_child(actions)
	match String(q.status):
		"draft":
			actions.add_child(_small("Donner aux joueurs", "PrimaryButton", func(): server.mj_quest_give(qid)))
		"active":
			actions.add_child(_small("Réussie : distribuer", "PrimaryButton", func(): server.mj_quest_complete(qid)))
			actions.add_child(_small("Échouée", "DangerButton", func(): server.mj_quest_fail(qid)))
	actions.add_child(_small("Modifier", "", func(): edit_requested.emit(q)))
	actions.add_child(_small("Supprimer", "DangerButton", func(): server.mj_quest_delete(qid)))
	return card.get_parent()


func _small(text: String, variation: String, cb: Callable) -> Button:
	var b := UIKit.button(text, variation, cb)
	b.custom_minimum_size.y = 38
	b.add_theme_font_size_override("font_size", 15)
	return b
