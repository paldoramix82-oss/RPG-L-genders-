class_name Trade
extends RefCounted
## Commerce côté hôte : achats et ventes chez les PNJ marchands et à la
## boutique du MJ (séparé de SessionServer pour garder ce fichier lisible).
## Les prix et stocks par défaut sont dans Shop.

## Boutique visée par un joueur : celle d'un PNJ proche, ou celle du MJ si elle est ouverte.
static func _shop_for(s: SessionServer, player: Dictionary, shop_id: String) -> Dictionary:
	if shop_id == "mj":
		var mj: Dictionary = s.session.get("mj_shop", {})
		return {"shop": mj, "name": "Boutique du MJ"} if not mj.is_empty() and mj.get("open", false) else {"error": "La boutique du MJ est fermée."}
	var map: Dictionary = s.maps.get(s.active_map, {})
	var t := MapData.token(map, shop_id)
	var me := MapData.token(map, s._pawn_id(player.id))
	if t.is_empty() or t.get("hidden", false) or not t.get("shop") is Dictionary:
		return {"error": "Ce marchand n'est pas là."}
	if s.combat.side(t) == "enemies":
		return {"error": "%s ne veut pas commercer avec vous." % t.name}
	if me.is_empty() or Rules.distance(Vector2i(int(me.x), int(me.y)), Vector2i(int(t.x), int(t.y))) > 2:
		return {"error": "Approchez-vous de %s pour commercer." % t.name}
	if not s.encounter_of(String(me.id)).is_empty():
		return {"error": "Pas de commerce en plein combat."}
	return {"shop": t.shop, "name": String(t.name), "token": t}


static func buy(s: SessionServer, player: Dictionary, payload: Dictionary) -> String:
	var c: Dictionary = s.characters.get(player.id, {})
	if c.is_empty():
		return "Créez d'abord votre personnage."
	var found := _shop_for(s, player, String(payload.get("shop", "")))
	if found.has("error"):
		return String(found.error)
	var item_id := String(payload.get("item", ""))
	var qty := clampi(int(payload.get("qty", 1)), 1, 99)
	var line := {}
	for it in found.shop.get("items", []):
		if String(it.item) == item_id:
			line = it
	if line.is_empty():
		return "Cet objet n'est pas en vente."
	if int(line.stock) >= 0 and int(line.stock) < qty:
		return "Il n'en reste que %d." % int(line.stock)
	var cost := int(line.price) * qty
	if int(c.get("gold", 0)) < cost:
		return "Pas assez d'or : il faut %d pièces (vous en avez %d)." % [cost, int(c.get("gold", 0))]
	var inst := Content.item_instance(s.content, item_id, qty)
	if inst.is_empty() or Inventory.add(c, inst).is_empty():
		return "Votre sac est plein."
	c.gold = int(c.get("gold", 0)) - cost
	if int(line.stock) > 0:
		line.stock = int(line.stock) - qty
	_trade_message(s, player, c, "achète %s ×%d à %s pour %d or." % [inst.name, qty, found.name, cost])
	return ""


static func sell(s: SessionServer, player: Dictionary, payload: Dictionary) -> String:
	var c: Dictionary = s.characters.get(player.id, {})
	if c.is_empty():
		return "Créez d'abord votre personnage."
	var found := _shop_for(s, player, String(payload.get("shop", "")))
	if found.has("error"):
		return String(found.error)
	var pct := int(found.shop.get("buy_pct", 50))
	if pct <= 0:
		return "%s n'achète rien." % found.name
	var uid := String(payload.get("uid", ""))
	var inst := {}
	for it in c.get("inventory", []):
		if String(it.get("uid", "")) == uid:
			inst = it
	if inst.is_empty():
		return "Objet introuvable dans votre sac."
	if inst.get("equipped", false):
		return "Retirez d'abord cet objet (il est équipé)."
	if String(inst.get("category", "")) == "quete":
		return "On ne vend pas un objet de quête."
	var qty := clampi(int(payload.get("qty", 1)), 1, int(inst.get("qty", 1)))
	var gain := Shop.sell_price(s.content, inst, pct) * qty
	inst.qty = int(inst.get("qty", 1)) - qty
	if int(inst.qty) <= 0:
		(c.inventory as Array).erase(inst)
	c.gold = int(c.get("gold", 0)) + gain
	_trade_message(s, player, c, "vend %s ×%d à %s pour %d or." % [inst.name, qty, found.name, gain])
	return ""


static func _trade_message(s: SessionServer, player: Dictionary, c: Dictionary, text: String) -> void:
	s._add_message({"kind": Protocol.KIND_SYSTEM, "from": Protocol.MJ_ID, "from_name": "Commerce", "to": String(player.id), "text": "%s %s" % [c.name, text]})
	s._mj_log("Commerce : %s %s" % [c.name, text])
	s._mark("characters")
	s._mark("tokens")
	if s.session.get("mj_shop", {}).get("open", false):
		s._broadcast_settings()
	s._unsaved = true
	s.characters_changed.emit()
	s.maps_changed.emit()


## MJ : boutique d'un PNJ (vide = n'est plus marchand).
static func set_npc_shop(s: SessionServer, map_id: String, token_id: String, shop: Dictionary) -> void:
	var map: Dictionary = s.maps.get(map_id, {})
	var t := MapData.token(map, token_id)
	if t.is_empty():
		return
	var clean := Shop.sanitize(shop, s.content)
	if clean.is_empty() or (clean.items as Array).is_empty() and not shop.get("keep", false):
		t.erase("shop")
	else:
		t.shop = clean
	s.map_changed(map_id, true)


## MJ : stock par défaut selon le métier (ou « marchand »).
static func default_for_role(s: SessionServer, role: String) -> Dictionary:
	return Shop.default_stock(s.content, role if Shop.is_merchant_role(role) else "marchand", s._rng)


## MJ : sa propre boutique, ouverte à tous les joueurs où qu'ils soient.
static func set_mj_shop(s: SessionServer, shop: Dictionary) -> void:
	s.session.mj_shop = Shop.sanitize(shop, s.content)
	s._mj_log("Boutique du MJ %s (%d objets)." % ["ouverte" if s.session.mj_shop.get("open", false) else "fermée", (s.session.mj_shop.get("items", []) as Array).size()])
	s._broadcast_settings()
	s._unsaved = true


