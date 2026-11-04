class_name MjTrash
extends RefCounted
## Corbeille du MJ (côté hôte) : rétablir un pion, une fiche, une création,
## un objet retiré, ou reprendre un don d'or ou d'objet fait par erreur.
## Les entrées sont ajoutées par SessionServer._to_trash.

## Rétablit une entrée de la corbeille (la plus récente si id vide).
static func restore(s: SessionServer, trash_id: String = "") -> String:
	if s.trash.is_empty():
		return "La corbeille est vide."
	var idx := s.trash.size() - 1
	if trash_id != "":
		idx = -1
		for i in s.trash.size():
			if String(s.trash[i].id) == trash_id:
				idx = i
		if idx < 0:
			return "Déjà rétabli."
	var e: Dictionary = s.trash[idx]
	s.trash.remove_at(idx)
	var d: Dictionary = e.data
	match String(e.kind):
		"token":
			var map: Dictionary = s.maps.get(String(d.map), {})
			if map.is_empty():
				return "La carte n'existe plus."
			var t: Dictionary = d.token
			var p := MapData.free_cell_near(map, int(t.x), int(t.y))
			t.x = p.x
			t.y = p.y
			map.tokens.append(t)
			s.map_changed(String(d.map), true)
		"character":
			var sheet: Dictionary = d.sheet
			s.characters[String(sheet.id)] = sheet
			for l in d.get("links", []):
				var t := MapData.token(s.maps.get(String(l[0]), {}), String(l[1]))
				if not t.is_empty():
					t.char_id = String(sheet.id)
			s._mark("characters")
			s.characters_changed.emit()
		"content":
			s.content[String(d.kind)][String(d.entry.id)] = d.entry
			if String(d.kind) in Content.PLAYER_KINDS:
				s._mark("content")
			s.content_changed.emit()
		"item":
			var c: Dictionary = s.characters.get(String(d.char), {})
			if c.is_empty():
				return "Le personnage n'existe plus."
			Inventory.add(c, d.item)
			Rules.refresh(c, s.content)
			s._mark("characters")
			s.characters_changed.emit()
		"given_item":
			var c: Dictionary = s.characters.get(String(d.char), {})
			var it := Inventory.find(c, String(d.uid)) if not c.is_empty() else {}
			if it.is_empty():
				# L'objet a pu être regroupé : on retire par identifiant de catalogue.
				return "Objet introuvable (déjà utilisé ou vendu ?)."
			Inventory.consume(c, String(d.uid), mini(int(d.qty), int(it.get("qty", 1))))
			Rules.refresh(c, s.content)
			s._mark("characters")
			s.characters_changed.emit()
		"given_gold":
			var c: Dictionary = s.characters.get(String(d.char), {})
			if c.is_empty():
				return "Le personnage n'existe plus."
			c.gold = maxi(0, int(c.get("gold", 0)) - int(d.amount))
			s._mark("characters")
			s.characters_changed.emit()
	s._mj_log("Rétabli : %s." % e.title)
	s._unsaved = true
	s.trash_changed.emit()
	return ""


