class_name QuestLibrary
extends RefCounted
## Quêtes secondaires prêtes à jouer et rôles de PNJ. Un PNJ qui a un rôle
## (aubergiste, forgeron, garde…) salue les joueurs et leur propose une quête
## tirée de cette bibliothèque dès qu'on lui parle. À l'acceptation, l'hôte place
## ce qu'il faut sur la carte (monstres, objets à ramasser, lieu à atteindre) ;
## les objectifs se cochent seuls et la quête se termine en revenant voir le PNJ.
##
## Dans les textes : {giver} = le PNJ qui confie la quête, {other} = un autre
## PNJ de la carte (livraisons), {place} = le lieu à atteindre.

const ROLES := {
	"habitant": {"title": "villageois", "color": "#9a8f7a", "icon": "person",
		"names": ["Lise", "Martin", "Odette", "Gaspard", "Maëlle", "Bastien", "Rosalie", "Firmin", "Agathe", "Thibault"],
		"greet": ["Bonjour, voyageur. On ne voit pas souvent de nouvelles têtes par ici.", "Ah, enfin quelqu'un qui a l'air capable !"],
		"quests": ["colis", "lettre", "compagnon", "loups"]},
	"aubergiste": {"title": "aubergiste", "color": "#c9a46a", "icon": "food",
		"names": ["Berthe", "Gontran", "Mireille", "Hugues", "Paulette", "Roland"],
		"greet": ["Bienvenue à l'auberge ! Une chope, un lit, et les ragots sont gratuits.", "Asseyez-vous ! Ici, on entend tout ce qui se passe dans la région."],
		"quests": ["cave", "champignons", "herbes", "colis"]},
	"forgeron": {"title": "forgeron", "color": "#b0605a", "icon": "hammer",
		"names": ["Aldric", "Brunehilde", "Torvald", "Grete", "Ulric", "Hilda"],
		"greet": ["Besoin d'une lame bien trempée ? Faudra me rendre un service d'abord.", "*clang* … Pardon. Vous disiez ?"],
		"quests": ["minerai", "outils", "golem"]},
	"marchand": {"title": "marchand", "color": "#c8b04a", "icon": "coin",
		"names": ["Ferdinand", "Yvette", "Anselme", "Clotilde", "Ismaël", "Noémie"],
		"greet": ["Approchez ! Tout se vend, tout s'achète… même les services.", "Les routes ne sont plus sûres, et mes affaires en souffrent."],
		"quests": ["brigands", "gemmes", "colis", "peaux"]},
	"pretre": {"title": "prêtre", "color": "#d8d0b0", "icon": "sun",
		"names": ["Frère Anselme", "Sœur Adèle", "Père Benoît", "Mère Hélène", "Frère Côme"],
		"greet": ["Que la lumière vous garde. Le mal rôde plus près qu'on ne le croit.", "Les morts murmurent, ces temps-ci. Je prie pour que ce ne soit qu'un rêve."],
		"quests": ["morts", "relique", "cultistes", "herbes"]},
	"garde": {"title": "garde", "color": "#6a7fa8", "icon": "shield",
		"names": ["Gérald", "Ysolde", "Arnaud", "Brigitte", "Lambert", "Solène"],
		"greet": ["Halte ! … Ah, vous êtes des aventuriers. Ça tombe bien.", "On manque de bras pour garder les routes."],
		"quests": ["loups", "brigands", "patrouille", "gobelins"]},
	"capitaine": {"title": "capitaine", "color": "#4f6a9a", "icon": "crown",
		"names": ["Capitaine Varan", "Capitaine Elsa", "Capitaine Dorn", "Capitaine Maud"],
		"greet": ["Repos. J'ai du travail pour des épées comme les vôtres.", "La garnison est débordée. Si vous cherchez de la gloire, j'ai ce qu'il faut."],
		"quests": ["chef_bandit", "gobelins", "patrouille", "cultistes"]},
	"fermier": {"title": "fermier", "color": "#8b7d45", "icon": "food",
		"names": ["Jeannot", "Margot", "Bertrand", "Colette", "Lucien", "Fanchon"],
		"greet": ["Bien le bonjour ! Faites attention où vous marchez, j'ai semé hier.", "Ah, si vous saviez les malheurs qui nous tombent dessus…"],
		"quests": ["loups", "araignees", "recolte", "ours"]},
	"chasseur": {"title": "chasseur", "color": "#5f7a4a", "icon": "bow",
		"names": ["Corentin", "Aube", "Garrick", "Ninon", "Tristan", "Séverine"],
		"greet": ["Chut… Vous entendez ? Non ? Moi si. Il y a quelque chose dans les bois.", "Les bêtes sont nerveuses cette saison."],
		"quests": ["ours", "peaux", "araignees", "loups"]},
	"herboriste": {"title": "herboriste", "color": "#7fb05a", "icon": "drop",
		"names": ["Mélisse", "Ambroise", "Capucine", "Sauge", "Valériane", "Basile"],
		"greet": ["Chaque plante a sa vertu… et son poison. Vous cherchez lequel ?", "Mes réserves s'épuisent, et les malades ne manquent pas."],
		"quests": ["herbes", "champignons", "antidote", "araignees"]},
	"mage": {"title": "mage", "color": "#8f7fd0", "icon": "spiral",
		"names": ["Maître Eldrin", "Dame Ysaure", "Maître Corvin", "Dame Liora"],
		"greet": ["Ne touchez à rien. Surtout pas à ça. Bien. Que voulez-vous ?", "L'énergie de cet endroit est… instable. Vous l'avez senti, vous aussi ?"],
		"quests": ["cristaux", "golem", "ombres", "champignons"]},
	"noble": {"title": "noble", "color": "#a05aa0", "icon": "ring",
		"names": ["Dame Aliénor", "Sire Godefroy", "Dame Isaure", "Sire Enguerrand"],
		"greet": ["Vous avez l'air… utiles. Je paie bien ceux qui le sont.", "On m'a dit que vous saviez vous battre. Prouvez-le."],
		"quests": ["relique", "chef_bandit", "lettre", "cultistes"]},
}

## Objets propres aux quêtes (ajoutés au catalogue de la campagne si besoin).
const ITEMS := {
	"herbe_lune": {"id": "herbe_lune", "name": "Herbe de lune", "icon": "herb", "category": "quete", "rarity": "commun", "description": "Une herbe argentée qui ne pousse qu'à l'ombre.", "value": 2, "slot": "", "stackable": true, "unique": false},
	"champignon_lueur": {"id": "champignon_lueur", "name": "Champignon luisant", "icon": "mushroom", "category": "quete", "rarity": "commun", "description": "Il brille faiblement dans le noir.", "value": 2, "slot": "", "stackable": true, "unique": false},
	"colis_scelle": {"id": "colis_scelle", "name": "Colis scellé", "icon": "bag", "category": "quete", "rarity": "commun", "description": "Un paquet ficelé, plus lourd qu'il n'en a l'air.", "value": 0, "slot": "", "stackable": false, "unique": false},
	"relique_sainte": {"id": "relique_sainte", "name": "Relique sainte", "icon": "relic", "category": "quete", "rarity": "rare", "description": "Un reliquaire d'argent, tiède au toucher.", "value": 0, "slot": "", "stackable": false, "unique": false},
	"outils_forge": {"id": "outils_forge", "name": "Outils de forge", "icon": "tools", "category": "quete", "rarity": "commun", "description": "Pinces, marteaux et burins, gravés au nom du forgeron.", "value": 0, "slot": "", "stackable": false, "unique": false},
	"sac_grain": {"id": "sac_grain", "name": "Sac de grain", "icon": "grain", "category": "quete", "rarity": "commun", "description": "Lourd et poussiéreux.", "value": 1, "slot": "", "stackable": true, "unique": false},
	"eclat_cristal": {"id": "eclat_cristal", "name": "Éclat de cristal", "icon": "crystal", "category": "quete", "rarity": "peu_commun", "description": "Il vibre doucement près de la magie.", "value": 5, "slot": "", "stackable": true, "unique": false},
}

## Modèles de quêtes. objectives : kind kill/item/talk/reach (+ target, count).
## spawn : monstres placés à l'acceptation (dist = distance du PNJ) ;
## pickups : objets à ramasser sur la carte ; give : objets remis au départ ;
## return : terminer en revenant voir le PNJ (les objets demandés lui sont remis).
const TEMPLATES := {
	"loups": {"title": "Les loups de la lisière", "desc": "{giver} : « Une meute rôde près d'ici. Trois bêtes de moins, et on dormira tranquilles. »",
		"objectives": [{"kind": "kill", "text": "Vaincre 3 loups", "target": "loup", "count": 3}],
		"spawn": [{"monster": "loup", "count": 3, "dist": [9, 16]}], "rewards": {"xp": 60, "gold": 15}},
	"brigands": {"title": "Brigands sur la route", "desc": "{giver} : « Des brigands détroussent les voyageurs. Chassez-les ! »",
		"objectives": [{"kind": "kill", "text": "Vaincre 3 bandits", "target": "bandit", "count": 3}],
		"spawn": [{"monster": "bandit", "count": 3, "dist": [10, 18]}], "rewards": {"xp": 80, "gold": 30}},
	"chef_bandit": {"title": "La tête du chef", "desc": "{giver} : « Leur chef se cache non loin avec ses hommes. Ramenez-moi la paix. »",
		"objectives": [{"kind": "kill", "text": "Vaincre le chef des bandits", "target": "chef_bandit", "count": 1}],
		"spawn": [{"monster": "chef_bandit", "count": 1, "dist": [14, 22]}, {"monster": "bandit", "count": 2, "dist": [14, 22], "near_previous": true}],
		"rewards": {"xp": 150, "gold": 60, "items": [{"item": "potion_soin_sup", "qty": 1}]}},
	"gobelins": {"title": "Le campement gobelin", "desc": "{giver} : « Des gobelins ont monté un camp. Dispersez-les avant qu'ils ne se multiplient. »",
		"objectives": [{"kind": "kill", "text": "Vaincre 3 gobelins", "target": "gobelin", "count": 3}],
		"spawn": [{"monster": "gobelin", "count": 3, "dist": [12, 20]}, {"monster": "gobelin_archer", "count": 1, "dist": [12, 20], "near_previous": true}],
		"rewards": {"xp": 90, "gold": 25}},
	"araignees": {"title": "Toiles et crochets", "desc": "{giver} : « Des araignées géantes ont pris leurs quartiers à côté. J'en ai des frissons. »",
		"objectives": [{"kind": "kill", "text": "Vaincre 2 araignées", "target": "araignee", "count": 2}],
		"spawn": [{"monster": "araignee", "count": 2, "dist": [8, 14]}], "rewards": {"xp": 60, "gold": 15, "items": [{"item": "antidote", "qty": 1}]}},
	"ours": {"title": "L'ours mangeur de moutons", "desc": "{giver} : « Un ours énorme décime les troupeaux. Il faut l'arrêter. »",
		"objectives": [{"kind": "kill", "text": "Vaincre l'ours", "target": "ours", "count": 1}],
		"spawn": [{"monster": "ours", "count": 1, "dist": [12, 18]}], "rewards": {"xp": 90, "gold": 20}},
	"morts": {"title": "Les morts ne dorment pas", "desc": "{giver} : « Des squelettes errent hors du cimetière. Rendez-les au repos. »",
		"objectives": [{"kind": "kill", "text": "Vaincre 3 squelettes", "target": "squelette", "count": 3}],
		"spawn": [{"monster": "squelette", "count": 3, "dist": [10, 18]}], "rewards": {"xp": 100, "gold": 20, "items": [{"item": "potion_soin", "qty": 2}]}},
	"ombres": {"title": "Ombres errantes", "desc": "{giver} : « Deux ombres rôdent, attirées par la magie. Dissipez-les. »",
		"objectives": [{"kind": "kill", "text": "Vaincre 2 ombres errantes", "target": "ombre_errante", "count": 2}],
		"spawn": [{"monster": "ombre_errante", "count": 2, "dist": [10, 18]}], "rewards": {"xp": 110, "gold": 25, "items": [{"item": "potion_mana", "qty": 1}]}},
	"golem": {"title": "Le golem déréglé", "desc": "{giver} : « Mon golem s'est enfui et détruit tout sur son passage. Arrêtez-le ! »",
		"objectives": [{"kind": "kill", "text": "Arrêter le golem", "target": "golem", "count": 1}],
		"spawn": [{"monster": "golem", "count": 1, "dist": [12, 20]}], "rewards": {"xp": 140, "gold": 40}},
	"cultistes": {"title": "Le culte caché", "desc": "{giver} : « Des cultistes tiennent des réunions la nuit. Mettez fin à leurs rituels. »",
		"objectives": [{"kind": "kill", "text": "Vaincre 2 cultistes", "target": "cultiste", "count": 2}],
		"spawn": [{"monster": "cultiste", "count": 2, "dist": [12, 20]}], "rewards": {"xp": 100, "gold": 30}},
	"cave": {"title": "La cave infestée", "desc": "{giver} : « Il y a des araignées dans ma réserve ! Personne n'ose descendre. »",
		"objectives": [{"kind": "kill", "text": "Vaincre 2 araignées", "target": "araignee", "count": 2}],
		"spawn": [{"monster": "araignee", "count": 2, "dist": [6, 10]}], "rewards": {"xp": 50, "gold": 15, "items": [{"item": "ration", "qty": 3}]}},
	"herbes": {"title": "Herbes de lune", "desc": "{giver} : « Il me faut trois brins d'herbe de lune. Ils poussent dans les coins d'ombre alentour. »",
		"objectives": [{"kind": "item", "text": "Cueillir 3 herbes de lune", "target": "herbe_lune", "count": 3}],
		"pickups": [{"item": "herbe_lune", "count": 3, "dist": [6, 14]}], "return": true, "rewards": {"xp": 50, "gold": 15, "items": [{"item": "potion_soin", "qty": 1}]}},
	"champignons": {"title": "Champignons luisants", "desc": "{giver} : « Rapportez-moi quatre champignons luisants. On les repère à leur lueur. »",
		"objectives": [{"kind": "item", "text": "Ramasser 4 champignons luisants", "target": "champignon_lueur", "count": 4}],
		"pickups": [{"item": "champignon_lueur", "count": 4, "dist": [6, 16]}], "return": true, "rewards": {"xp": 50, "gold": 20}},
	"minerai": {"title": "Du fer pour la forge", "desc": "{giver} : « Mes réserves sont vides. Trouvez-moi trois morceaux de minerai de fer. »",
		"objectives": [{"kind": "item", "text": "Trouver 3 minerais de fer", "target": "minerai_fer", "count": 3}],
		"pickups": [{"item": "minerai_fer", "count": 3, "dist": [8, 16]}], "return": true, "rewards": {"xp": 50, "gold": 20}},
	"outils": {"title": "Les outils volés", "desc": "{giver} : « Des gobelins m'ont volé mes outils ! Ils ne doivent pas être loin. »",
		"objectives": [{"kind": "item", "text": "Récupérer les outils de forge", "target": "outils_forge", "count": 1}],
		"pickups": [{"item": "outils_forge", "count": 1, "dist": [10, 18]}], "spawn": [{"monster": "gobelin", "count": 2, "near_pickup": true}],
		"return": true, "rewards": {"xp": 80, "gold": 25}},
	"recolte": {"title": "Aider à la récolte", "desc": "{giver} : « Les sacs de grain sont restés aux champs. Ramenez-en trois avant la pluie ! »",
		"objectives": [{"kind": "item", "text": "Rapporter 3 sacs de grain", "target": "sac_grain", "count": 3}],
		"pickups": [{"item": "sac_grain", "count": 3, "dist": [5, 12]}], "return": true, "rewards": {"xp": 40, "gold": 10, "items": [{"item": "ration", "qty": 2}]}},
	"cristaux": {"title": "Éclats de cristal", "desc": "{giver} : « Des éclats de cristal sont tombés non loin. Trois suffiront à mes recherches. »",
		"objectives": [{"kind": "item", "text": "Trouver 3 éclats de cristal", "target": "eclat_cristal", "count": 3}],
		"pickups": [{"item": "eclat_cristal", "count": 3, "dist": [8, 18]}], "return": true, "rewards": {"xp": 70, "gold": 20, "items": [{"item": "potion_mana", "qty": 2}]}},
	"gemmes": {"title": "Des gemmes pour le marché", "desc": "{giver} : « Des gemmes brutes affleurent dans les rochers. Deux, et je vous paie bien. »",
		"objectives": [{"kind": "item", "text": "Trouver 2 gemmes brutes", "target": "gemme_brute", "count": 2}],
		"pickups": [{"item": "gemme_brute", "count": 2, "dist": [10, 18]}], "return": true, "rewards": {"xp": 60, "gold": 35}},
	"relique": {"title": "La relique perdue", "desc": "{giver} : « Une relique sacrée a été dérobée. On la dit gardée par des morts. »",
		"objectives": [{"kind": "item", "text": "Retrouver la relique sainte", "target": "relique_sainte", "count": 1}],
		"pickups": [{"item": "relique_sainte", "count": 1, "dist": [14, 24]}], "spawn": [{"monster": "squelette", "count": 2, "near_pickup": true}],
		"return": true, "rewards": {"xp": 120, "gold": 40, "items": [{"item": "talisman_garde", "qty": 1}]}},
	"peaux": {"title": "Des peaux pour l'hiver", "desc": "{giver} : « Il me faut deux cuirs bruts. Les loups du coin en ont de belles. »",
		"objectives": [{"kind": "item", "text": "Obtenir 2 cuirs bruts", "target": "cuir_brut", "count": 2}],
		"spawn": [{"monster": "loup", "count": 3, "dist": [9, 16]}], "return": true, "rewards": {"xp": 60, "gold": 25}},
	"antidote": {"title": "Antidote pour le village", "desc": "{giver} : « Trois poignées d'herbes médicinales et je pourrai soigner les fiévreux. (Cherchez-en avec « Chasser, cueillir ».) »",
		"objectives": [{"kind": "item", "text": "Cueillir 3 herbes médicinales", "target": "herbes_medicinales", "count": 3}],
		"return": true, "rewards": {"xp": 50, "gold": 15, "items": [{"item": "antidote", "qty": 1}]}},
	"colis": {"title": "Le colis", "desc": "{giver} : « Portez ce colis à {other}. Et ne l'ouvrez pas ! »", "needs_other": true,
		"objectives": [{"kind": "talk", "text": "Remettre le colis à {other}", "target": "{other}", "count": 1}],
		"give": [{"item": "colis_scelle", "qty": 1}], "deliver": "colis_scelle", "rewards": {"xp": 40, "gold": 20}},
	"lettre": {"title": "Une lettre à remettre", "desc": "{giver} : « Cette lettre doit arriver à {other}, en main propre. »", "needs_other": true,
		"objectives": [{"kind": "talk", "text": "Remettre la lettre à {other}", "target": "{other}", "count": 1}],
		"give": [{"item": "lettre_scellee", "qty": 1}], "deliver": "lettre_scellee", "rewards": {"xp": 40, "gold": 15}},
	"patrouille": {"title": "Patrouille", "desc": "{giver} : « Allez jeter un œil du côté de {place}, puis revenez me faire votre rapport. »",
		"objectives": [{"kind": "reach", "text": "Inspecter {place}", "count": 1}],
		"place": {"name": "la vieille borne", "dist": [14, 22]}, "spawn": [{"monster": "loup", "count": 2, "near_place": true, "hidden": true}],
		"return": true, "rewards": {"xp": 50, "gold": 15}},
	"compagnon": {"title": "Le compagnon perdu", "desc": "{giver} : « Mon chien Moustache s'est sauvé vers {place}. Pouvez-vous voir s'il va bien ? »",
		"objectives": [{"kind": "reach", "text": "Retrouver Moustache vers {place}", "count": 1}],
		"place": {"name": "le vieux chêne", "dist": [10, 18]}, "return": true, "rewards": {"xp": 30, "gold": 10}},
}


static func role(role_id: String) -> Dictionary:
	return ROLES.get(role_id, {})


## Nom d'un nouveau PNJ du rôle, distinct de ceux déjà sur la carte.
static func pick_name(role_id: String, rng: RandomNumberGenerator, taken: Array) -> String:
	var r := role(role_id)
	var names: Array = r.get("names", ["Inconnu"])
	var start := rng.randi_range(0, names.size() - 1)
	for i in names.size():
		var n := "%s, %s" % [names[(start + i) % names.size()], r.get("title", "")]
		if not taken.has(n):
			return n
	return "%s, %s %d" % [names[start], r.get("title", ""), rng.randi_range(2, 99)]


static func greeting(role_id: String, rng: RandomNumberGenerator) -> String:
	var lines: Array = role(role_id).get("greet", [])
	return String(lines[rng.randi_range(0, lines.size() - 1)]) if not lines.is_empty() else ""


static func _fill(text: String, giver: String, other: String, place: String) -> String:
	return text.replace("{giver}", giver).replace("{other}", other).replace("{place}", place)


## Données de quête (pour SessionServer.mj_quest_save) tirées d'un modèle.
static func build(template_id: String, giver: String, other: String = "") -> Dictionary:
	var t: Dictionary = TEMPLATES.get(template_id, {})
	if t.is_empty():
		return {}
	var place := String(t.get("place", {}).get("name", ""))
	var objectives: Array = []
	for o in t.objectives:
		var copy: Dictionary = o.duplicate(true)
		copy.text = _fill(String(o.text), giver, other, place)
		if copy.has("target"):
			copy.target = _fill(String(o.target), giver, other, place)
		objectives.append(copy)
	if t.get("return", false):
		objectives.append({"kind": "talk", "text": "Revenir voir %s" % giver, "target": giver, "count": 1, "return": true})
	return {"title": String(t.title), "kind": "side", "giver": giver, "description": _fill(String(t.desc), giver, other, place),
		"objectives": objectives, "rewards": (t.rewards as Dictionary).duplicate(true), "offer": true, "auto": true, "template": template_id}
