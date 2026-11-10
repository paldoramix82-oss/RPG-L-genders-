class_name CommandEntries
extends RefCounted
## Entrées de la recherche rapide du MJ (Ctrl + K) : actions, onglets, outils,
## terrains, monstres, objets, bâtiments, fiches, cartes, quêtes, musiques.
## Séparé de l'écran du MJ pour le garder lisible.


static func build(h: Node) -> Array:
	var server := Net.server
	var e: Array = []
	var add := func(title: String, kind: String, f: Callable): e.append({"title": title, "kind": kind, "run": f})
	# Actions courantes.
	add.call("Générer une carte", "action", h._dialog_generate_map)
	add.call("Nouvelle carte vide", "action", h._dialog_new_map)
	add.call("Nouvelle quête", "action", func(): h._open_quest_editor({}))
	add.call("Boutique du MJ", "action", h._open_mj_shop)
	add.call("Annuler la dernière suppression ou le dernier don", "action", func():
		var err := server.mj_restore()
		h._notifier.push(err if err != "" else "Rétabli.", "warning" if err != "" else "success"))
	add.call("Exporter vers la bibliothèque", "action", h._dialog_export_library)
	if not App.is_mobile():
		add.call("Essai solo : ouvrir une fenêtre joueur", "action", h._open_test_player)
	add.call("Importer une bibliothèque", "action", h._dialog_import_library)
	add.call("Sauvegarder la campagne", "action", func(): server.save())
	add.call("Montrer cette carte aux joueurs", "action", func(): server.mj_set_active_map(h._edit_map))
	add.call("Épreuve de groupe", "événement", h._event_check)
	add.call("Dégâts ou soins de groupe", "événement", h._event_group_hp)
	add.call("Récompense de groupe", "événement", h._event_reward)
	add.call("Embuscade", "événement", h._event_ambush)
	add.call("Afficher / masquer les performances", "réglage", func():
		Perf.set_enabled(not Perf.enabled())
		App.save_settings())
	add.call("Texte plus grand", "réglage", func(): h._scale_ui(0.15))
	add.call("Texte plus petit", "réglage", func(): h._scale_ui(-0.15))
	# Onglets et outils.
	for spec in [["combat", "Combat"], ["world", "Monde"], ["quests", "Quêtes"], ["create", "Créer"], ["chars", "Fiches"], ["codex", "Codex"], ["net", "Réseau"], ["adventure", "Aventure"]]:
		add.call(spec[1], "onglet", h._show.bind(spec[0]))
	for spec in h.MAP_TOOLS:
		add.call(spec[1], "outil de carte", func():
			h._show("table")
			h._set_tool(spec[0]))
	for code in MapData.TERRAINS:
		add.call("Peindre : %s" % MapData.TERRAINS[code][0], "terrain", func():
			h._paint_code = code
			h._show("table")
			h._set_tool("paint"))
	# Placer en un geste.
	var place := func(spec: Dictionary, title: String, tab: String):
		h._place_spec = spec
		h._place_title = title
		h._place_tab = tab
		h._show("table")
		h._set_tool("place")
		h._notifier.push("Touchez la carte pour poser : %s." % title, "info")
	for m in Content.list(server.content, "monsters"):
		add.call("Placer : %s" % m.name, "monstre", place.bind({"type": "monster", "id": String(m.id)}, String(m.name), "monster"))
		add.call("Modifier le monstre %s" % m.name, "catalogue", h._open_content_editor.bind("monsters", m))
	for rid in Prefabs.ROLE_ORDER:
		var title := String(QuestLibrary.role(rid).get("title", rid)).capitalize()
		add.call("Placer : %s" % title, "habitant", place.bind({"type": "npc_role", "role": rid}, title, "npc_role"))
	for it in Content.list(server.content, "items"):
		add.call("Placer : %s" % it.name, "objet", place.bind({"type": "item", "id": String(it.id)}, String(it.name), "item"))
		add.call("Modifier l'objet %s" % it.name, "catalogue", h._open_content_editor.bind("items", it))
	for a in Content.list(server.content, "abilities"):
		add.call("Modifier la capacité %s" % a.name, "catalogue", h._open_content_editor.bind("abilities", a))
	for look in SessionServer.PASSAGE_LOOKS:
		add.call("Placer : %s" % SessionServer.PASSAGE_LOOKS[look], "passage", place.bind({"type": "passage", "look": look}, String(SessionServer.PASSAGE_LOOKS[look]), "passage"))
	add.call("Placer : coffre", "coffre", place.bind({"type": "chest", "name": "Coffre"}, "Coffre", "chest"))
	for id in Prefabs.LIST:
		add.call("Bâtir : %s" % Prefabs.get_def(String(id)).name, "bâtiment", func():
			h._prefab_id = String(id)
			h._show("table")
			h._set_tool("prefab"))
	# Personnages, cartes, quêtes.
	for c in server.characters.values():
		add.call("Fiche : %s" % c.name, "personnage" if String(c.get("owner", "")) != "" else "PNJ", h._open_char_tools.bind(String(c.id)))
	for id in server.map_order:
		add.call("Carte : %s" % server.maps[id].name, "carte", func():
			h._edit_map = String(id)
			h._refresh_map_select()
			h._load_edit_map()
			h._show("table"))
	for q in server.quests:
		add.call("Quête : %s" % q.title, "quête", h._open_quest_editor.bind(q))
	for t in MusicLibrary.tracks():
		add.call("Musique : %s — %s" % [t.mood, t.title], "musique", func(): server.mj_music(String(t.id), true))
	return e
