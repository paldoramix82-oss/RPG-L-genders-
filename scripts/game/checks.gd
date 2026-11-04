class_name Checks
extends RefCounted
## Épreuves : une action (« J'escalade le mur », « Fouiller ») déclenche un jet
## d20 + caractéristique contre une difficulté (DD). L'hôte lance le dé, calcule
## l'issue et applique les conséquences (SessionServer.perform_check).
##
## Issues : critique (20 naturel), réussite (total ≥ DD), presque (DD − 3 au
## plus : échec sans pénalité), échec, échec critique (1 naturel).

const SKILLS := {
	"athletisme": {"name": "Athlétisme", "stat": "Force", "icon": "fist", "dc": 14, "range": 1,
		"verb": "tente un effort physique", "hint": "Escalader, sauter, nager, forcer une porte ou un coffre.",
		"words": ["escalad", "grimp", "saut", "nage", "nager", "forc", "enfonc", "soulev", "pouss", "défonc", "brise", "casse", "courir", "cour ", "porte "]},
	"discretion": {"name": "Discrétion", "stat": "Dextérité", "icon": "cloak", "dc": 13, "range": 0,
		"verb": "tente de se cacher", "hint": "Se cacher, se faufiler : les monstres ne vous voient plus un moment.",
		"words": ["cach", "faufil", "discr", "furtiv", "silenc", "en douce", "pas de loup", "dans l'ombre", "inaperçu", "contourn"]},
	"crochetage": {"name": "Crochetage", "stat": "Dextérité", "icon": "key", "dc": 14, "range": 1,
		"verb": "tente de crocheter", "hint": "Ouvrir un coffre verrouillé, désamorcer un piège, faire les poches.",
		"words": ["crochet", "serrure", "désamorc", "piège", "cadenas", "dérob", "vole ", "voler", "subtilis", "poche"]},
	"endurance": {"name": "Endurance", "stat": "Constitution", "icon": "heart", "dc": 13, "range": 0,
		"verb": "serre les dents", "hint": "Résister au poison, au froid, à la fatigue : chasse un effet néfaste.",
		"words": ["endur", "résist", "tenir bon", "tiens bon", "souffle", "marche forcée", "froid", "chaleur", "poison", "serre les dents"]},
	"fouille": {"name": "Fouille", "stat": "Intelligence", "icon": "bag", "dc": 12, "range": 0,
		"verb": "fouille les environs", "hint": "Trouver des objets, de l'or, des passages cachés (une fois par endroit).",
		"words": ["fouill", "cherch", "examin", "inspect", "ramass", "récupér", "explore la pièce", "sous le", "derrière le"]},
	"savoir": {"name": "Savoir", "stat": "Intelligence", "icon": "book", "dc": 13, "range": 8,
		"verb": "fait appel à ses connaissances", "hint": "Identifier un monstre (points faibles), se souvenir d'un lieu, déchiffrer.",
		"words": ["souven", "rappel", "déchiffr", "lire", "lis ", "connai", "identif", "étudi", "analys", "rune", "grimoire", "inscription"]},
	"perception": {"name": "Perception", "stat": "Esprit", "icon": "eye", "dc": 13, "range": 0,
		"verb": "observe attentivement", "hint": "Repérer les monstres cachés, les embuscades et les secrets alentour.",
		"words": ["observ", "regard", "écout", "repér", "guett", "scrut", "pist", "trace", "surveill", "attenti", "aux aguets"]},
	"soins": {"name": "Premiers soins", "stat": "Esprit", "icon": "cross", "dc": 12, "range": 1,
		"verb": "prodigue des soins", "hint": "Soigner un allié voisin (ou soi-même), une fois par minute et par blessé.",
		"words": ["soign", "pans", "bandag", "premiers soins", "guéri", "remède", "blessure"]},
	"survie": {"name": "Survie", "stat": "Esprit", "icon": "paw", "dc": 12, "range": 0,
		"verb": "cherche de quoi survivre", "hint": "Chasser, cueillir des herbes, trouver à manger (une fois par endroit).",
		"words": ["chass", "cueill", "herbe", "feu de camp", "campement", "orient", "nourriture", "manger", "baies", "champignon"]},
	"persuasion": {"name": "Persuasion", "stat": "Charisme", "icon": "chat", "dc": 13, "range": 2,
		"verb": "tente de convaincre", "hint": "Convaincre un PNJ : rumeurs, quêtes, petits services.",
		"words": ["convain", "persuad", "négoci", "marchand", "charm", "séduir", "amadou", "mentir", "bluff", "flatt", "rassur"]},
	"intimidation": {"name": "Intimidation", "stat": "Charisme", "icon": "skull", "dc": 14, "range": 4,
		"verb": "tente d'intimider", "hint": "Faire fuir un monstre (pas un boss) ou faire parler un PNJ. Raté : il attaque.",
		"words": ["intimid", "menac", "effray", "terrifi", "crie sur", "hurle sur", "rugi", "fais peur", "faire peur"]},
	"magie": {"name": "Arcanes", "stat": "Intelligence", "icon": "spiral", "dc": 13, "range": 0,
		"verb": "sonde la magie", "hint": "Détecter la magie : coffres et secrets cachés, un peu de mana.",
		"words": ["sort ", "magie", "magique", "incant", "rituel", "aec", "enchant", "dissip", "aura", "arcane"]},
}

const DC := {"facile": 10, "moyen": 14, "difficile": 18, "heroique": 22}
const DC_NAMES := {"facile": "Facile", "moyen": "Moyen", "difficile": "Difficile", "heroique": "Héroïque"}
const OUTCOMES := {"crit": "Réussite critique !", "success": "Réussite", "partial": "Presque…", "failure": "Échec", "fumble": "Échec critique"}
## Actions rapides proposées sous la carte (exploration).
const QUICK := ["fouille", "perception", "discretion", "soins", "survie"]
const QUICK_LABELS := {"fouille": "Fouiller", "perception": "Observer", "discretion": "Se cacher", "soins": "Soigner", "survie": "Chasser, cueillir",
	"athletisme": "Forcer", "crochetage": "Crocheter", "persuasion": "Convaincre", "intimidation": "Intimider", "savoir": "Identifier",
	"endurance": "Tenir bon", "magie": "Sonder la magie"}

## Tables de secours (si le catalogue de la campagne n'a pas les siennes).
const TABLES := {
	"fouille": {"id": "fouille", "name": "Fouille", "gold": [0, 6], "entries": [
		{"item": "potion_soin", "chance": 25, "min": 1, "max": 1}, {"item": "ration", "chance": 25, "min": 1, "max": 2},
		{"item": "torche", "chance": 12, "min": 1, "max": 1}, {"item": "corde", "chance": 8, "min": 1, "max": 1},
		{"item": "minerai_fer", "chance": 12, "min": 1, "max": 1}, {"item": "cle_rouillee", "chance": 6, "min": 1, "max": 1},
		{"item": "gemme_brute", "chance": 6, "min": 1, "max": 1}, {"item": "antidote", "chance": 8, "min": 1, "max": 1}]},
	"cueillette": {"id": "cueillette", "name": "Cueillette", "gold": [0, 0], "entries": [
		{"item": "herbes_medicinales", "chance": 70, "min": 1, "max": 2}, {"item": "ration", "chance": 55, "min": 1, "max": 2},
		{"item": "cuir_brut", "chance": 20, "min": 1, "max": 1}, {"item": "antidote", "chance": 8, "min": 1, "max": 1}]},
}


static func get_skill(skill_id: String) -> Dictionary:
	return SKILLS.get(skill_id, {})


## Compétence devinée d'après le texte de l'action ("" : aucune).
static func detect(text: String) -> String:
	var t := " " + text.to_lower() + " "
	var best := ""
	var best_pos := 1 << 30
	for id in SKILLS:
		for w in SKILLS[id].words:
			var p := t.find(String(w))
			if p >= 0 and p < best_pos:
				best_pos = p
				best = id
	return best


## Bonus au jet : caractéristique effective (+ bonus d'objets nommés comme la compétence).
static func bonus(sheet: Dictionary, content: Dictionary, skill_id: String) -> int:
	var skill := get_skill(skill_id)
	if skill.is_empty():
		return 0
	var m := Rules.mods(sheet, content)
	return Rules.stat(sheet, String(skill.stat), content, m) + int(m.get(String(skill.name), 0))


static func outcome(d20: int, total: int, dc: int) -> String:
	if d20 == 20:
		return "crit"
	if d20 == 1:
		return "fumble"
	if total >= dc:
		return "success"
	if total >= dc - 3:
		return "partial"
	return "failure"


static func is_success(o: String) -> bool:
	return o in ["crit", "success"]


## Nom de la difficulté la plus proche (pour l'affichage).
static func dc_name(dc: int) -> String:
	var best := "moyen"
	for k in DC:
		if absi(int(DC[k]) - dc) < absi(int(DC[best]) - dc):
			best = k
	return String(DC_NAMES[best])


## Chance de réussite (en %) pour un bonus et un DD donnés.
static func chance(bonus_value: int, dc: int) -> int:
	var need := clampi(dc - bonus_value, 2, 20)
	return (21 - need) * 5


## Phrase de récit automatique.
static func narrate(skill_id: String, o: String, who: String) -> String:
	var skill := get_skill(skill_id)
	var verb := String(skill.get("verb", "tente sa chance"))
	match o:
		"crit":
			return "%s %s… et réussit brillamment !" % [who, verb]
		"success":
			return "%s %s : c'est réussi." % [who, verb]
		"partial":
			return "%s %s : presque ! Rien ne se passe, mais rien de grave non plus." % [who, verb]
		"fumble":
			return "%s %s… et tout tourne mal !" % [who, verb]
	return "%s %s, sans succès." % [who, verb]
