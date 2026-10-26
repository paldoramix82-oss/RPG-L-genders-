class_name Sprites
extends RefCounted
## Sprites pixel art du jeu (générés par tools/make_sprites.py, voir
## assets/sprites). Chargés à la demande et gardés en mémoire.
##   items   objets en couleurs        glyphs  symboles teintés en jeu
##   nature  arbres, rochers, fleurs   props   mobilier et décors
##   units   personnages et monstres

const DIR := "res://assets/sprites/"

## Icônes du jeu dessinées par un sprite d'objet sous un autre nom.
const ITEM_ALIASES := {"leather": "leather", "music": "", "crystal": "crystal", "flask": "flask"}

static var _cache := {}


static func tex(group: String, name: String) -> Texture2D:
	var key := group + "/" + name
	if _cache.has(key):
		return _cache[key]
	var path := DIR + key + ".png"
	var t: Texture2D = load(path) if name != "" and ResourceLoader.exists(path) else null
	_cache[key] = t
	return t


static func item(name: String) -> Texture2D:
	return tex("items", String(ITEM_ALIASES.get(name, name)))


static func glyph(name: String) -> Texture2D:
	return tex("glyphs", name)


## Taille d'affichage nette : plus grand multiple entier de la taille du sprite
## qui tient dans « avail » (ou une réduction si la place manque).
static func crisp_size(t: Texture2D, avail: float) -> Vector2:
	var base := maxf(t.get_width(), t.get_height())
	var k := floorf(avail / base)
	if k < 1.0:
		return Vector2(t.get_width(), t.get_height()) * (avail / base)
	return Vector2(t.get_width(), t.get_height()) * k


## Dessine un sprite centré dans un rectangle, à une échelle entière si possible.
static func draw_centered(ci: CanvasItem, t: Texture2D, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	var sz := crisp_size(t, minf(rect.size.x, rect.size.y))
	var pos := (rect.get_center() - sz * 0.5).round()
	ci.draw_texture_rect(t, Rect2(pos, sz), false, modulate)
