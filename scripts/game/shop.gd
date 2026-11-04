class_name Shop
extends RefCounted
## Commerce : boutiques des PNJ marchands et boutique du MJ.
## Une boutique : {"items": [{"item", "price", "stock"}], "buy_pct": 50}
##   stock -1 = illimité ; buy_pct = part du prix que le marchand rend quand
##   on lui vend un objet (0 = il n'achète rien).

const RARITY_PRICE := {"commun": 10, "peu_commun": 35, "rare": 110, "epique": 320, "legendaire": 900}

## Ce que vend chaque métier, par catégories d'objets du catalogue.
const ROLE_GOODS := {
	"marchand": ["consommable", "potion", "outil", "accessoire", "materiau"],
	"forgeron": ["arme", "armure"],
	"herboriste": ["potion", "consommable", "materiau"],
	"aubergiste": ["consommable"],
	"mage": ["livre", "potion", "accessoire"],
	"noble": ["accessoire"],
	"chasseur": ["materiau", "arme"],
	"fermier": ["consommable", "materiau"],
}


static func is_merchant_role(role: String) -> bool:
	return ROLE_GOODS.has(role)


## Prix d'achat d'un objet du catalogue.
static func price_of(content: Dictionary, item_id: String) -> int:
	var def := Content.get_entry(content, "items", item_id)
	if def.is_empty():
		return 0
	if int(def.get("value", 0)) > 0:
		return int(def.value)
	return int(RARITY_PRICE.get(String(def.get("rarity", "commun")), 10))


## Prix de rachat d'un objet du sac.
static func sell_price(content: Dictionary, inst: Dictionary, buy_pct: int) -> int:
	var base := int(inst.get("value", 0))
	if base <= 0:
		base = price_of(content, String(inst.get("item_id", "")))
	return maxi(1, base * clampi(buy_pct, 0, 100) / 100) if buy_pct > 0 else 0


## Stock de départ d'un marchand selon son métier (objets non uniques, pas de quête).
static func default_stock(content: Dictionary, role: String, rng: RandomNumberGenerator, count: int = 8) -> Dictionary:
	var cats: Array = ROLE_GOODS.get(role, ROLE_GOODS.marchand)
	var pool: Array = []
	for e in Content.list(content, "items"):
		if String(e.get("category", "")) in cats and not e.get("unique", false) and String(e.get("rarity", "commun")) in ["commun", "peu_commun", "rare"]:
			pool.append(e)
	pool.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var items: Array = []
	while not pool.is_empty() and items.size() < count:
		var e: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var rare := String(e.get("rarity", "commun")) == "rare"
		items.append({"item": String(e.id), "price": price_of(content, String(e.id)), "stock": rng.randi_range(1, 2) if rare else -1})
	return {"items": items, "buy_pct": 50}


static func sanitize(raw: Variant, content: Dictionary) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var items: Array = []
	for it in raw.get("items", []):
		if it is Dictionary and items.size() < 40 and not Content.get_entry(content, "items", String(it.get("item", ""))).is_empty():
			items.append({"item": String(it.item), "price": clampi(int(it.get("price", price_of(content, String(it.item)))), 0, 9999999),
				"stock": clampi(int(it.get("stock", -1)), -1, 9999)})
	return {"items": items, "buy_pct": clampi(int(raw.get("buy_pct", 50)), 0, 100), "open": bool(raw.get("open", true))}
