class_name Prefabs
extends RefCounted
## Bâtiments prêts à poser sur une carte : le MJ choisit, touche la carte, et la
## maison, l'auberge, la forge… apparaissent avec leurs murs, leur porte, leurs
## meubles, leur nom et leur habitant (un PNJ avec un rôle, qui propose des
## quêtes dès qu'on lui parle).
##
## Plans : un caractère par case. Codes de terrain (voir MapData.TERRAINS), plus :
##   +  porte (sol du bâtiment)        @  place de l'habitant (sol)
##   $  coffre (sol)                   M  monstre caché (sol)
##   (espace)  case laissée telle quelle

const LIST := {
	"maison": {"name": "Maison", "label": false, "floor": "d", "role": "habitant", "icon": "castle", "rows": [
		"######",
		"#td@t#",
		"#dddd#",
		"#tddd#",
		"##++##"]},
	"grande_maison": {"name": "Grande maison", "label": false, "floor": "d", "role": "habitant", "icon": "castle", "rows": [
		"########",
		"#tdd#dt#",
		"#ddd+dd#",
		"#d@d#dd#",
		"#ddd#t$#",
		"###++###"]},
	"auberge": {"name": "Auberge", "floor": "d", "role": "aubergiste", "icon": "food", "rows": [
		"##########",
		"#tdtddtt@#",
		"#ddddddtd#",
		"#tdtddddd#",
		"#ddddddtd#",
		"#tdtddd$d#",
		"####++####"]},
	"forge": {"name": "Forge", "floor": "d", "role": "forgeron", "icon": "hammer", "rows": [
		"#######",
		"#cct@d#",
		"#ccdddd",
		"#tdd$dd",
		"###++##"]},
	"echoppe": {"name": "Échoppe", "floor": "d", "role": "marchand", "icon": "coin", "rows": [
		"######",
		"#tt@t#",
		"#dddd#",
		"#t$dt#",
		"##++##"]},
	"temple": {"name": "Temple", "floor": "o", "role": "pretre", "icon": "sun", "rows": [
		"#########",
		"#ooaaaoo#",
		"#ooo@ooo#",
		"#t#ooo#t#",
		"#ooooooo#",
		"#t#ooo#t#",
		"#ooooooo#",
		"#oo$oooo#",
		"####+####"]},
	"tour_garde": {"name": "Tour de garde", "floor": "o", "role": "garde", "icon": "shield", "rows": [
		"#####",
		"#o@o#",
		"#ooo#",
		"#o$o#",
		"##+##"]},
	"caserne": {"name": "Caserne", "floor": "d", "role": "capitaine", "icon": "crown", "rows": [
		"##########",
		"#tdtdtdt@#",
		"#dddddddd#",
		"#tdtdtd$d#",
		"#dddddddd#",
		"####++####"]},
	"ferme": {"name": "Ferme et champs", "floor": "d", "role": "fermier", "icon": "food", "rows": [
		"zzzzz######",
		"zzzzz#td@t#",
		"zzzzz#dddd#",
		"zzzzz#tddd#",
		"zzzzz##++##",
		"zzzzz  rr  ",
		"zzzzz  rr  ",
		"zzzzz  rr  "]},
	"grange": {"name": "Grange", "floor": "d", "role": "", "icon": "bag", "rows": [
		"########",
		"#tdddtt#",
		"#dddddd+",
		"#tt$ddt#",
		"########"]},
	"marche": {"name": "Place du marché", "floor": "p", "role": "marchand", "icon": "coin", "rows": [
		"ppppppppp",
		"ptt@pttpp",
		"ppppppppp",
		"ppppwpppp",
		"ppppppppp",
		"pttppttpp",
		"ppppppppp"]},
	"puits": {"name": "Puits", "label": false, "floor": "p", "role": "", "icon": "drop", "rows": [
		"ppp",
		"pwp",
		"ppp"]},
	"campement": {"name": "Campement", "floor": ".", "role": "chasseur", "icon": "fire", "rows": [
		" yyyyy ",
		"yb.b.by",
		"y.....y",
		"y..c@.y",
		"y.....y",
		"yb.$.by",
		" yyyyy "]},
	"maison_mage": {"name": "Tour du mage", "floor": "o", "role": "mage", "icon": "spiral", "rows": [
		"#######",
		"#tatat#",
		"#ooooo#",
		"#oo@oo#",
		"#t$oot#",
		"#ooooo#",
		"###+###"]},
	"herboristerie": {"name": "Herboristerie et jardin", "floor": "d", "role": "herboriste", "icon": "drop", "rows": [
		"######yyy",
		"#tt@t#yfy",
		"#dddd+yyy",
		"#t$dd#yfy",
		"######yyy"]},
	"manoir": {"name": "Manoir", "floor": "d", "role": "noble", "icon": "ring", "rows": [
		"yy##########yy",
		"yy#tdddddtd#yy",
		"yy#dddtdddd#yy",
		"yy#td@ddddt#yy",
		"yy####+#####yy",
		"yy#tdddddt$#yy",
		"yy#dddddddd#yy",
		"yy#####++###yy",
		"yyyyyyyppyyyyy"]},
	"ruine": {"name": "Ruine", "floor": "o", "role": "", "icon": "skull", "rows": [
		"##x#x###",
		"#xoox.ox",
		"x.oMoxo#",
		"#oxo$oo#",
		"#o.xooxx",
		"###x#x##"]},
	"crypte": {"name": "Entrée de crypte", "floor": "o", "role": "", "icon": "skull", "monster": "squelette", "rows": [
		"#######",
		"#ooMoo#",
		"#o#o#o#",
		"#oo$oo#",
		"#ooooo#",
		"###+###"]},
}

## Habitants à placer seuls (sans bâtiment), dans l'ordre de la palette.
const ROLE_ORDER := ["habitant", "aubergiste", "forgeron", "marchand", "pretre", "garde", "capitaine", "fermier", "chasseur", "herboriste", "mage", "noble"]


static func get_def(id: String) -> Dictionary:
	return LIST.get(id, {})


static func size_of(id: String) -> Vector2i:
	var rows: Array = get_def(id).get("rows", [])
	var w := 0
	for r in rows:
		w = maxi(w, String(r).length())
	return Vector2i(w, rows.size())


## Coin haut-gauche pour un bâtiment centré sur la case touchée (dans la carte).
static func anchor(map: Dictionary, id: String, x: int, y: int) -> Vector2i:
	var s := size_of(id)
	return Vector2i(clampi(x - s.x / 2, 0, maxi(0, int(map.w) - s.x)), clampi(y - s.y / 2, 0, maxi(0, int(map.h) - s.y)))


## Pose le bâtiment (terrain seulement). Renvoie {rect, npc: [cases], chest: [cases],
## monster: [cases], door: [cases]}.
static func stamp(map: Dictionary, id: String, x: int, y: int) -> Dictionary:
	var def := get_def(id)
	var out := {"rect": Rect2i(), "npc": [], "chest": [], "monster": [], "door": []}
	if def.is_empty():
		return out
	var a := anchor(map, id, x, y)
	var floor_code := String(def.get("floor", "d"))
	var rows: Array = def.rows
	out.rect = Rect2i(a, size_of(id))
	for j in rows.size():
		var row := String(rows[j])
		for i in row.length():
			var ch := row[i]
			var p := a + Vector2i(i, j)
			if ch == " " or not MapData.in_bounds(map, p.x, p.y):
				continue
			var code := ch
			match ch:
				"+":
					code = floor_code
					out.door.append(p)
				"@":
					code = floor_code
					out.npc.append(p)
				"$":
					code = floor_code
					out.chest.append(p)
				"M":
					code = floor_code
					out.monster.append(p)
			if MapData.TERRAINS.has(code):
				MapData.set_cell(map, p.x, p.y, code)
	return out
