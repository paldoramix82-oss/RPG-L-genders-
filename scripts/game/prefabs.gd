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
##   %  portail magique (pion à relier)  /  escalier qui descend (pion à relier)
##   (espace)  case laissée telle quelle
## « wall » : matériau des murs « # » (1 bois, 2 briques, 3 pierre, 4 haie, 5 grotte).
## et le mobilier (voir DECOR) : un terrain et un décor dessiné en pixel art.

const LIST := {
	"maison": {"name": "Maison", "label": false, "floor": "d", "role": "habitant", "icon": "castle", "rows": [
		"######",
		"#Hd@S#",
		"#dddd#",
		"#Tddd#",
		"##++##"]},
	"grande_maison": {"name": "Grande maison", "label": false, "floor": "d", "role": "habitant", "icon": "castle", "rows": [
		"########",
		"#Hdd#dS#",
		"#ddd+dd#",
		"#d@d#dd#",
		"#Tdd#O$#",
		"###++###"]},
	"auberge": {"name": "Auberge", "floor": "d", "role": "aubergiste", "icon": "food", "rows": [
		"##########",
		"#TdTddOO@#",
		"#ddddddTd#",
		"#TdTddddd#",
		"#ddddddTd#",
		"#TdTddd$d#",
		"####++####"]},
	"forge": {"name": "Forge", "floor": "d", "role": "forgeron", "icon": "hammer", "rows": [
		"#######",
		"#EEA@d#",
		"#ccdddd",
		"#Xdd$dd",
		"###++##"]},
	"echoppe": {"name": "Échoppe", "floor": "d", "role": "marchand", "icon": "coin", "rows": [
		"######",
		"#SS@X#",
		"#dddd#",
		"#T$dO#",
		"##++##"]},
	"temple": {"name": "Temple", "floor": "o", "role": "pretre", "icon": "sun", "rows": [
		"#########",
		"#ooILIoo#",
		"#ooo@ooo#",
		"#I#ooo#I#",
		"#ooooooo#",
		"#I#ooo#I#",
		"#ooooooo#",
		"#oo$oooo#",
		"####+####"]},
	"tour_garde": {"name": "Tour de garde", "floor": "o", "role": "garde", "icon": "shield", "rows": [
		"#####",
		"#X@o#",
		"#ooo#",
		"#o$o#",
		"##+##"]},
	"caserne": {"name": "Caserne", "floor": "d", "role": "capitaine", "icon": "crown", "rows": [
		"##########",
		"#HdHdHdH@#",
		"#dddddddd#",
		"#TdTdXd$d#",
		"#dddddddd#",
		"####++####"]},
	"ferme": {"name": "Ferme et champs", "floor": "d", "role": "fermier", "icon": "food", "rows": [
		"zzzzz######",
		"zzzzz#Hd@T#",
		"zzzzz#dddd#",
		"zzzzz#Yddd#",
		"zzzzz##++##",
		"zzzzz  rr  ",
		"zzzzz  rr  ",
		"zzzzz  rr  "]},
	"grange": {"name": "Grange", "floor": "d", "role": "", "icon": "bag", "rows": [
		"########",
		"#YdddYY#",
		"#dddddd+",
		"#JJ$ddX#",
		"########"]},
	"marche": {"name": "Place du marché", "floor": "p", "role": "marchand", "icon": "coin", "rows": [
		"ppppppppp",
		"pQK@pQKpp",
		"ppppppppp",
		"ppppPpppp",
		"ppppppppp",
		"pQKppQKpp",
		"ppppppppp"]},
	"puits": {"name": "Puits", "label": false, "floor": "p", "role": "", "icon": "drop", "rows": [
		"ppp",
		"pPp",
		"ppp"]},
	"campement": {"name": "Campement", "floor": ".", "role": "chasseur", "icon": "fire", "rows": [
		" yyyyy ",
		"yN.N.Ny",
		"y.....y",
		"y..C@.y",
		"y.....y",
		"yN.$.Ny",
		" yyyyy "]},
	"maison_mage": {"name": "Tour du mage", "floor": "o", "role": "mage", "icon": "spiral", "rows": [
		"#######",
		"#SaSaS#",
		"#ooooo#",
		"#oo@oo#",
		"#U$ooS#",
		"#ooooo#",
		"###+###"]},
	"herboristerie": {"name": "Herboristerie et jardin", "floor": "d", "role": "herboriste", "icon": "drop", "rows": [
		"######yyy",
		"#SU@T#yfy",
		"#dddd+yyy",
		"#J$dd#yfy",
		"######yyy"]},
	"manoir": {"name": "Manoir", "floor": "d", "role": "noble", "icon": "ring", "rows": [
		"yy##########yy",
		"yy#TdddddSd#yy",
		"yy#dddZdddd#yy",
		"yy#Hd@ddddV#yy",
		"yy####+#####yy",
		"yy#TdDdddT$#yy",
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
		"#GoooG#",
		"###+###"]},
	"bibliotheque": {"name": "Bibliothèque", "floor": "6", "wall": "2", "role": "mage", "icon": "book", "rows": [
		"#########",
		"#SSSSSSS#",
		"#6666666#",
		"#S6T6T6S#",
		"#S6D6D6S#",
		"#666@66?#",
		"#S6666$S#",
		"####++###"]},
	"boulangerie": {"name": "Boulangerie", "floor": "8", "wall": "2", "role": "marchand", "icon": "food", "rows": [
		"#######",
		"#EE*JJ#",
		"#88888#",
		"#T8@8O#",
		"#888$8#",
		"###++##"]},
	"ecurie": {"name": "Écurie", "floor": "j", "wall": "1", "role": "fermier", "icon": "paw", "rows": [
		"#########",
		"#YjjYjjY#",
		"#1j1j1j1#",
		"#jjjjjjj#",
		"#jj@jj:j#",
		"####++###"]},
	"chapelle": {"name": "Chapelle", "floor": "e", "wall": "3", "role": "pretre", "icon": "sun", "rows": [
		"#######",
		"#?eLe?#",
		"#eee@e#",
		"#=e=e=#",
		"#=e=e=#",
		"#ee$ee#",
		"###+###"]},
	"prison": {"name": "Prison", "floor": "o", "wall": "3", "role": "garde", "icon": "chain", "rows": [
		"#########",
		"#~o#~o#M#",
		"#oo#oo#o#",
		"##+##+#+#",
		"#ooooooo#",
		"#T@ooo^$#",
		"####+####"]},
	"salle_trone": {"name": "Salle du trône", "floor": "9", "wall": "3", "role": "noble", "icon": "crown", "rows": [
		"###########",
		"#!I9&@9I!$#",
		"#999777999#",
		"#I9977799I#",
		"#999777999#",
		"#I9977799I#",
		"#999777999#",
		"#####++####"]},
	"alchimiste": {"name": "Boutique d'alchimiste", "floor": "6", "wall": "2", "role": "herboriste", "icon": "potion", "rows": [
		"#######",
		"#SU*SS#",
		"#66666#",
		"#T6@6*#",
		"#66$66#",
		"###++##"]},
	"cabane": {"name": "Cabane de bûcheron", "floor": "i", "wall": "1", "role": "chasseur", "icon": "axe", "rows": [
		"######",
		"#Hi<<#",
		"#ii@i#",
		"#Ti$i#",
		"##++##"]},
	"maison_pierre": {"name": "Maison de pierre", "floor": "6", "wall": "3", "role": "habitant", "icon": "castle", "rows": [
		"#######",
		"#H6S6H#",
		"#66666#",
		"#TD@6E#",
		"#666$6#",
		"###++##"]},
	"arene": {"name": "Arène d'entraînement", "floor": "s", "wall": "1", "role": "capitaine", "icon": "sword", "rows": [
		"###########",
		"#>sssssss>#",
		"#sssssssss#",
		"#sss@sssss#",
		"#sssssssss#",
		"#^sssssss^#",
		"#####++####"]},
	"mine": {"name": "Entrée de mine", "floor": "u", "wall": "5", "monster": "gobelin", "icon": "ore", "label": true, "rows": [
		" ##### ",
		"##uuu##",
		"#XuMuO#",
		"#uu/uu#",
		"#:u$uu#",
		"##+++##"]},
	"cercle_portail": {"name": "Cercle du portail", "floor": "e", "wall": "3", "icon": "spiral", "rows": [
		"  #+#  ",
		" #eee# ",
		"#?eee?#",
		"+ee%ee+",
		"#?eee?#",
		" #eee# ",
		"  #+#  "]},
	"jardin": {"name": "Jardin à haies", "floor": "y", "wall": "4", "role": "herboriste", "icon": "leaf", "rows": [
		"#########",
		"#;yyVyy;#",
		"#y=yyy=y#",
		"#yyy@yyy#",
		"#;yyyyy;#",
		"####+####"]},
	"taverne_port": {"name": "Taverne du port", "floor": "6", "wall": "1", "role": "aubergiste", "icon": "food", "rows": [
		"##########",
		"#OOTd6T6O#",
		"#6666666J#",
		"#T6T6@6T6#",
		"#6666666$#",
		"####++####",
		"wwBBBBBBww",
		"wwwwwwwwww"]},
}

## Mobilier des plans : lettre → [terrain, décor]. « - » : case couverte par le
## décor voisin (étal sur deux cases). Variantes tirées selon la position.
const DECOR := {
	"T": ["t", "table"], "O": ["t", "barrel"], "X": ["t", "crate"], "H": ["t", "bed"], "S": ["t", "shelf"],
	"A": ["t", "anvil"], "E": ["t", "hearth"], "L": ["o", "altar"], "G": [".", "grave"], "P": ["w", "well"],
	"N": [".", "tent"], "C": ["c", "campfire"], "Q": ["p", "stall"], "K": ["t", "-"], "U": ["t", "cauldron"],
	"V": ["t", "statue"], "I": ["t", "pillar"], "J": ["t", "sacks"], "Y": ["t", "hay"], "D": ["t", "chair"], "Z": ["d", "rug"],
	"&": ["t", "throne"], "!": ["t", "banner"], "=": ["t", "bench"], "^": ["t", "weapon_rack"], "*": ["t", "jars"],
	"~": ["t", "cage"], "<": ["t", "firewood"], ">": ["t", "dummy"], "?": ["t", "candles"], ":": ["t", "cart"], ";": [".", "flowerpot"],
}
const VARIANTS := {
	"tent": ["tent_red", "tent_blue", "tent_green", "tent_beige"],
	"stall": ["stall_red", "stall_blue", "stall_green", "stall_yellow", "stall_purple"],
	"grave": ["grave", "grave_cross"],
}


## Terrain d'une case de plan.
static func cell_code(ch: String, floor_code: String, wall_code: String = "#") -> String:
	if ch in ["+", "@", "$", "M", "%", "/"]:
		return floor_code
	if ch == "#":
		return wall_code
	if DECOR.has(ch):
		return String(DECOR[ch][0])
	return ch


static func decor_id(ch: String, p: Vector2i) -> String:
	var id := String(DECOR[ch][1])
	if VARIANTS.has(id):
		var v: Array = VARIANTS[id]
		return String(v[absi(p.x * 7 + p.y * 13) % v.size()])
	return id


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
	var out := {"rect": Rect2i(), "npc": [], "chest": [], "monster": [], "door": [], "decor": []}
	if def.is_empty():
		return out
	var a := anchor(map, id, x, y)
	var floor_code := String(def.get("floor", "d"))
	var wall_code := String(def.get("wall", "#"))
	out["portal"] = []
	out["stairs"] = []
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
				"#":
					code = wall_code
				"%":
					code = floor_code
					out.portal.append(p)
				"/":
					code = floor_code
					out.stairs.append(p)
			if DECOR.has(ch):
				code = String(DECOR[ch][0])
			if MapData.TERRAINS.has(code):
				MapData.set_cell(map, p.x, p.y, code)
			MapData.set_decor(map, p.x, p.y, decor_id(ch, p) if DECOR.has(ch) else "")
	return out
