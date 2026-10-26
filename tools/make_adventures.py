#!/usr/bin/env python3
"""Génère les aventures prêtes à jouer (data/adventures/<id>.json).

Une aventure = une carte modèle + des PNJ placés (tirés des packs data/npcs) +
des monstres (souvent cachés, à révéler) + des coffres (table de butin) + des
étiquettes + des quêtes en brouillon + des scènes à raconter, avec des conseils
pour le MJ. Le MJ la charge en un clic et la modifie librement ensuite.
Usage : python3 tools/make_adventures.py
"""
import json
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "adventures")


def npc(pack, name, x, y, hidden=False, note=""):
    return {"pack": pack, "name": name, "x": x, "y": y, "hidden": hidden, "note": note}


def mon(id_, x, y, hidden=True):
    return {"id": id_, "x": x, "y": y, "hidden": hidden}


def chest(name, x, y, loot, hidden=False, items=()):
    c = {"name": name, "x": x, "y": y, "loot": loot, "hidden": hidden}
    if items:
        c["items"] = [{"item": i, "qty": q} for i, q in items]
    return c


# Objectifs : texte seul = coché par le MJ ; sinon suivis automatiquement par l'hôte.
def talk(text, name):
    return {"text": text, "kind": "talk", "target": name}


def reach(text, x, y, radius=2):
    return {"text": text, "kind": "reach", "x": x, "y": y, "radius": radius}


def kill(text, target, count=1):
    return {"text": text, "kind": "kill", "target": target, "count": count}


def get(text, item_id, count=1):
    return {"text": text, "kind": "item", "target": item_id, "count": count}


def quest(title, kind, giver, desc, objectives, xp=0, gold=0, items=()):
    return {"title": title, "kind": kind, "giver": giver, "description": desc,
            "objectives": [o if isinstance(o, dict) else {"text": o} for o in objectives],
            "rewards": {"xp": xp, "gold": gold, "items": [{"item": i, "qty": q} for i, q in items]}}


def scene(title, narration, tips, action=None):
    s = {"title": title, "narration": narration, "tips": tips}
    if action:
        s["action"] = action
    return s


ADVENTURES = [
    {
        "id": "cloches_valombre", "universe": "fantasy", "map": "valombre_ville", "music": "taverne",
        "name": "Les cloches de Valombre", "length": "1 à 2 séances · 2 à 5 joueurs · niveau 1",
        "tagline": "Chaque nuit, à minuit, les cloches du temple sonnent toutes seules.",
        "description": "Une petite ville tranquille, une prêtresse inquiète, un champ brûlé sans flammes et une crypte qu'on n'ouvre plus. Idéal pour une première partie : discussions, enquête, un peu d'exploration et un combat final.",
        "npcs": [npc("fantasy_valombre", "Bertrand", 6, 9), npc("fantasy_valombre", "Sœur Aveline", 14, 9),
                 npc("fantasy_valombre", "Dorn", 7, 15), npc("fantasy_valombre", "Bourgmestre Hallis", 14, 15),
                 npc("fantasy_valombre", "Mirelle", 27, 14), npc("fantasy_valombre", "Capitaine Roderic", 11, 11),
                 npc("fantasy_valombre", "Le Voyageur encapuchonné", 5, 7, note="Sait ce qui se cache sous le temple ; ne parle que si on lui offre à boire.")],
        "monsters": [mon("squelette", 13, 6), mon("squelette", 15, 6), mon("ombre_errante", 14, 5), mon("ombre_errante", 28, 5)],
        "chests": [chest("Coffre du sonneur", 16, 6, "coffre", True), chest("Caisse abandonnée", 29, 16, "brigand", items=[("minerai_fer", 2)]),
                   chest("Touffes d'herbes", 27, 16, "", items=[("herbes_medicinales", 3)]), chest("Sac oublié", 4, 9, "", items=[("lettre_scellee", 1)])],
        "labels": [{"x": 14, "y": 6, "text": "Crypte (entrée sous l'autel)", "hidden": True}],
        "quests": [
            quest("Les cloches de minuit", "main", "Sœur Aveline",
                  "Les cloches sonnent seules chaque nuit depuis l'incendie du champ. Sœur Aveline craint que quelque chose se soit réveillé sous le temple.",
                  [talk("Écouter Sœur Aveline", "Sœur Aveline"), reach("Examiner le champ calciné", 28, 6), reach("Trouver l'entrée de la crypte (sous l'autel)", 14, 6, 1),
                   kill("Faire taire les ombres qui sonnent les cloches", "ombre_errante", 2)],
                  300, 60, [("amulette_vie", 1)]),
            quest("Le minerai de Dorn", "side", "Dorn", "Le forgeron manque de fer depuis que la route de la forêt n'est plus sûre. Une caisse aurait été abandonnée près du marais.",
                  [get("Trouver 2 minerais de fer", "minerai_fer", 2)], 100, 25, [("marteau_armes", 1)]),
            quest("Les herbes du marais", "side", "Mirelle", "L'herboriste n'ose plus aller cueillir au marais : des lueurs y dansent la nuit.",
                  [reach("Aller au marais", 28, 15), get("Cueillir 3 herbes médicinales", "herbes_medicinales", 3)], 80, 10, [("potion_soin", 2)]),
            quest("Une ardoise bien chargée", "side", "Bertrand", "Un client est parti sans payer… en laissant un sac près de l'entrée de la taverne.",
                  [get("Retrouver le sac (la lettre scellée)", "lettre_scellee", 1), talk("Interroger le Voyageur encapuchonné", "Le Voyageur encapuchonné")], 60, 15),
        ],
        "scenes": [
            scene("Arrivée à Valombre", "La route de la forêt débouche enfin sur Valombre. Les toits fument, un garde bâille à l'entrée, et la taverne du Corbeau Rieur promet une soupe chaude. Au loin, le clocher du temple domine la place.",
                  "Laissez chaque joueur présenter son personnage à Bertrand le tavernier. Personne ne parle des cloches tant qu'on ne pose pas la question."),
            scene("Minuit", "À minuit pile, les cloches du temple se mettent à sonner. Douze coups. Puis un treizième. Dans la taverne, plus personne ne parle.",
                  "Sœur Aveline arrive essoufflée et demande de l'aide : donnez la quête « Les cloches de minuit ».", {"type": "give_quest", "quest": 0}),
            scene("Le champ calciné", "L'herbe est noire sur un cercle parfait. Les cendres sont encore tièdes, alors que personne n'a vu de flammes. Au centre, la terre semble avoir été poussée de l'intérieur.",
                  "Épreuve d'Esprit (difficulté 13) : ceux qui réussissent sentent une magie froide qui « tire » vers le temple. Une ombre errante rôde ici (cachée).",
                  {"type": "group_check", "stat": "Esprit", "difficulty": 13, "title": "Que ressentez-vous ?"}),
            scene("La crypte", "Sous l'autel fendu, un escalier descend dans le noir. L'air sent la cire froide. Quelque chose cliquette en bas… comme des os qui s'entrechoquent au rythme des cloches.",
                  "Les monstres cachés près du temple sont révélés : ils attaquent quiconque entre dans leur périmètre (combat local, automatique). Le coffre du sonneur est dans la crypte.", {"type": "reveal_combat"}),
            scene("Le silence", "La dernière ombre se dissipe. Pour la première fois depuis des semaines, minuit passe sans un seul coup de cloche. Sœur Aveline pleure de soulagement.",
                  "Cochez les objectifs puis « Réussie : distribuer ». Le Voyageur encapuchonné laisse entendre que ce n'était que le début…"),
        ],
    },
    {
        "id": "meute_cendres", "universe": "fantasy", "map": "foret_cendres", "music": "foret_monde",
        "name": "La meute des Cendres", "length": "1 séance · 2 à 4 joueurs · niveau 1-2",
        "tagline": "Des loups au pelage gris de cendre attaquent les voyageurs.",
        "description": "Une chasse en forêt : suivre des traces, choisir sa route, affronter la meute et son alpha dans la clairière. Beaucoup de combat, un mystère en bonus.",
        "npcs": [npc("bestiaire", "Garde", 2, 15, note="Survivant de la dernière attaque, blessé.")],
        "monsters": [mon("loup", 21, 12), mon("loup", 24, 16), mon("loup_alpha", 16, 9), mon("araignee", 27, 3)],
        "chests": [chest("Sac d'un chasseur disparu", 9, 18, "coffre"), chest("Nid de l'araignée", 28, 2, "bete", True)],
        "labels": [{"x": 8, "y": 17, "text": "Traces de lutte", "hidden": False}],
        "quests": [
            quest("La meute des Cendres", "main", "Garde", "Trois voyageurs ont disparu sur la route. Les survivants parlent de loups gris comme la cendre.",
                  [reach("Suivre les traces jusqu'à la clairière", 16, 9, 3), kill("Vaincre 2 loups", "loup", 2), kill("Vaincre le loup alpha", "loup_alpha")], 250, 40, [("bottes_vent", 1)]),
            quest("Le cristal noirci", "side", "Garde", "Une pierre levée porte un cristal noirci. Est-ce lui qui rend les loups si féroces ?",
                  [reach("Examiner la pierre levée", 16, 11, 1), "Rapporter un fragment à un érudit (le MJ coche)"], 120, 0, [("gemme_brute", 1)]),
        ],
        "scenes": [
            scene("La lisière", "Les arbres sont gris, l'air sent la fumée froide. Sur le sentier, des traces de pattes, beaucoup trop grandes, et une besace déchirée.",
                  "Laissez les joueurs fouiller (sac du chasseur au sud-ouest). Épreuve de Dextérité 12 pour suivre les traces sans bruit.",
                  {"type": "group_check", "stat": "Dextérité", "difficulty": 12, "title": "Suivre les traces"}),
            scene("Hurlements", "Un hurlement, puis un autre, tout proches. Des silhouettes grises glissent entre les troncs.",
                  "Les loups sont révélés : ils attaquent dès qu'un personnage entre dans leur périmètre.", {"type": "reveal_combat"}),
            scene("La clairière", "Au centre de la clairière, une pierre levée porte un cristal noirci. Devant elle, un loup énorme vous fixe sans bouger.",
                  "Le loup alpha garde la pierre. S'il tombe, les autres fuient (à vous de voir)."),
        ],
    },
    {
        "id": "ruines_temple", "universe": "fantasy", "map": "ruines_temple", "music": "valombre",
        "name": "Les ruines du temple oublié", "length": "1 à 2 séances · 3 à 5 joueurs · niveau 2-3",
        "tagline": "Un temple effondré, un gardien de pierre et un culte qui prie en secret.",
        "description": "Exploration de donjon : salles, pièges racontés, cultistes et golem. Parfait pour montrer le brouillard de guerre (la vision limitée rend chaque couloir inquiétant).",
        "npcs": [],
        "monsters": [mon("cultiste", 10, 9), mon("cultiste", 18, 9), mon("squelette", 12, 14), mon("squelette", 16, 15)],
        "chests": [chest("Reliquaire de l'autel", 15, 6, "magique"), chest("Trésor de la crypte", 14, 17, "boss", True)],
        "labels": [],
        "quests": [
            quest("Le cœur du temple", "main", "", "On dit qu'une relique dort sous l'autel. Des cultistes pensent la même chose.",
                  [reach("Franchir le portail effondré", 14, 3), kill("Chasser les cultistes", "cultiste", 2), kill("Vaincre le gardien de pierre", "Gardien de pierre"),
                   reach("Trouver la relique (au fond de la crypte)", 14, 17)], 400, 80, [("lame_runique", 1)]),
        ],
        "scenes": [
            scene("Le portail", "Le portail du temple s'est effondré il y a des siècles. Entre les pierres, une lueur de torche… quelqu'un est déjà là.",
                  "Brouillard : les joueurs ne voient que leur zone. Faites-les avancer pièce par pièce."),
            scene("Les cultistes", "Des silhouettes en robe psalmodient devant l'autel fendu. L'une d'elles se retourne : « Vous n'auriez pas dû venir. »",
                  "Les cultistes et squelettes sont révélés : ils attaquent ceux qui s'approchent.", {"type": "reveal_combat"}),
            scene("La crypte", "L'escalier de la crypte descend dans une salle où dort un gardien de pierre. Ses yeux s'allument.",
                  "Le Gardien de pierre est déjà sur la carte. Le trésor de la crypte est caché derrière lui."),
        ],
    },
    {
        "id": "nuit_corbeau", "universe": "fantasy", "map": "taverne_corbeau", "music": "taverne",
        "name": "Une nuit au Corbeau Rieur", "length": "1 courte séance · 2 à 5 joueurs · niveau 1",
        "tagline": "Une soirée à la taverne qui tourne mal.",
        "description": "Une aventure très courte pour apprendre : parler aux PNJ, déclarer des actions libres, lancer des dés, puis une petite bagarre à la cave.",
        "npcs": [],
        "monsters": [mon("bandit", 16, 12), mon("bandit", 18, 13), mon("chef_bandit", 19, 11)],
        "chests": [chest("Butin des contrebandiers", 20, 13, "brigand", True)],
        "labels": [],
        "quests": [
            quest("La trappe sous le tonneau", "main", "Bertrand le tavernier", "Des bruits montent de la cave chaque nuit. Bertrand jure qu'il n'y a que des tonneaux en bas.",
                  [talk("Écouter Bertrand", "Bertrand le tavernier"), reach("Descendre à la cave", 17, 13), kill("Chasser les contrebandiers", "bandit", 2), kill("Vaincre leur chef", "chef_bandit")],
                  150, 30, [("potion_soin", 2)]),
            quest("Le message du voyageur", "side", "Voyageur encapuchonné", "Le voyageur vous confie une lettre scellée à porter au temple de Valombre. Il insiste : ne l'ouvrez pas.",
                  [talk("Remettre la lettre à Sœur Aveline (à Valombre)", "Sœur Aveline")], 60, 20, [("lettre_scellee", 1)]),
        ],
        "scenes": [
            scene("Une soirée ordinaire", "Le feu crépite, un barde joue faux, et Bertrand essuie le même verre depuis dix minutes. Dans un coin, un voyageur encapuchonné ne touche pas à sa bière.",
                  "Faites parler les joueurs : c'est le moment d'essayer « Parler à… », « Examiner », les messages privés au MJ."),
            scene("Des bruits dans la cave", "Un choc sourd sous le plancher. Puis un autre. Bertrand pâlit : « Encore… »",
                  "Donnez la quête principale. Épreuve d'Esprit 12 pour repérer la trappe sous le tonneau.",
                  {"type": "group_check", "stat": "Esprit", "difficulty": 12, "title": "Fouiller la cave"}),
            scene("Les contrebandiers", "Sous la trappe, trois hommes déchargent des caisses à la lueur d'une lanterne. Leur chef dégaine : « Mauvaise soirée pour être curieux. »",
                  "Les bandits sont révélés : ils attaquent ceux qui descendent à la cave.", {"type": "reveal_combat"}),
        ],
    },
    {
        "id": "test_magie", "universe": "legenders", "map": "ile_test", "music": "test_de_la_magie",
        "name": "Le test de la magie", "length": "1 à 2 séances · 2 à 5 joueurs · niveau 1",
        "tagline": "Dix jours sur une île pour devenir mage d'État.",
        "description": "Les candidats sont téléportés au hasard sur une île sauvage. Il faut survivre, retrouver les autres et rejoindre le point de rendez-vous. Exploration (avec le brouillard), rencontres et combat.",
        "npcs": [npc("legenders_monde", "Examinateur Dorrow", 9, 11, note="Observe tout, n'aide personne… officiellement."),
                 npc("legenders_monde", "Nib", 14, 15, True)],
        "monsters": [mon("loup", 18, 8), mon("loup", 19, 9), mon("ours", 25, 14), mon("araignee", 6, 19)],
        "chests": [chest("Ravitaillement largué", 20, 10, "coffre"), chest("Cache d'un ancien candidat", 26, 16, "magique", True)],
        "labels": [],
        "quests": [
            quest("Survivre dix jours", "main", "Examinateur Dorrow", "Atteindre le point de rendez-vous avant la fin du test.",
                  ["Trouver de l'eau douce (le MJ coche)", reach("Rejoindre le pic central", 20, 9), kill("Survivre aux loups de l'île", "loup", 2),
                   reach("Atteindre le point de rendez-vous", 25, 15)], 300, 50, [("amulette_vie", 1)]),
            quest("Le candidat disparu", "side", "Examinateur Dorrow", "Mako, un candidat, n'a pas répondu à l'appel du deuxième jour. Il aurait laissé une cache près du rendez-vous.",
                  [reach("Trouver la cache de Mako", 26, 16, 1)], 80),
            quest("Le chapardeur", "side", "", "Quelqu'un vole les provisions la nuit. Des petites traces de pas, et une odeur d'ombre.",
                  [talk("Prendre le voleur sur le fait (parler à Nib)", "Nib"), "Décider de son sort (le MJ coche)"], 60, 0, [("bombe_fumee", 2)]),
        ],
        "scenes": [
            scene("La téléportation", "Une lumière blanche, un bruit de verre brisé… et le sable. Vous êtes seul, sur une plage inconnue. Dans votre poche, une carte qui indique un seul point : le rendez-vous, dans dix jours.",
                  "Donnez la quête principale. Chacun commence seul : la vision ne montre que les environs immédiats."),
            scene("Les loups de l'île", "Des yeux brillent dans les fourrés. L'île n'est pas déserte.",
                  "Les bêtes de l'île sont révélées : elles attaquent quiconque s'approche.", {"type": "reveal_combat"}),
            scene("La nuit", "Le feu crépite. Au matin, la moitié des provisions a disparu, et de petites traces s'éloignent vers la forêt.",
                  "Quête « Le chapardeur » : Nib est caché près d'ici.", {"type": "give_quest", "quest": 2}),
        ],
    },
    {
        "id": "division_encre", "universe": "legenders", "map": "shima_encre", "music": "shima",
        "name": "Premier jour à la Division de l'Encre", "length": "1 séance · 2 à 5 joueurs · niveau 1",
        "tagline": "Nouvelles recrues, premier entraînement… et un trafic d'AEC noir.",
        "description": "Rencontres avec des mages d'État, entraînement contre un golem, puis une petite enquête sur de l'AEC noir qui circule dans la division.",
        "npcs": [npc("legenders_shima", "Youri", 15, 13), npc("legenders_shima", "Midori", 26, 12), npc("legenders_shima", "Kenji", 14, 15),
                 npc("legenders_monde", "Sabbas", 30, 18, True, "Contrebandier d'AEC noir caché près du terrain.")],
        "monsters": [mon("golem", 27, 14, False), mon("cultiste", 31, 17), mon("cultiste", 29, 19)],
        "chests": [chest("Caisse d'AEC noir", 31, 19, "magique", True)],
        "labels": [{"x": 30, "y": 18, "text": "Odeur de cristal brûlé", "hidden": True}],
        "quests": [
            quest("Bienvenue à la Division de l'Encre", "main", "Youri", "Youri accueille les recrues : présentations, puis entraînement contre le golem.",
                  [talk("Se présenter à Youri", "Youri"), kill("Battre le golem d'entraînement", "golem")], 200, 40, [("talisman_garde", 1)]),
            quest("L'AEC noir", "side", "Midori", "Des cristaux d'AEC noir circulent dans la division. Midori veut savoir qui les fait entrer.",
                  [talk("Interroger Kenji", "Kenji"), reach("Trouver la cachette derrière le terrain", 30, 18), kill("Arrêter le contrebandier", "Sabbas")], 180, 60),
        ],
        "scenes": [
            scene("L'appel", "Le QG de la magie bourdonne. Un homme aux cheveux en bataille vous attend, un carnet couvert d'encre à la main : « Bienvenue à la Division de l'Encre. Ici, on écrit notre légende. »",
                  "Youri donne la quête principale.", {"type": "give_quest", "quest": 0}),
            scene("Le golem", "Sur le terrain d'entraînement, un golem de pierre se redresse. Midori sourit : « Ne vous inquiétez pas. Il ne tape qu'à moitié. »",
                  "Combat d'entraînement : le golem attaque ceux qui approchent (ou un joueur l'engage en le touchant).", {"type": "start_combat"}),
            scene("L'odeur du cristal brûlé", "Derrière le terrain, une odeur âcre. Des éclats de cristal noir traînent entre les rochers.",
                  "Les complices de Sabbas sont révélés et attaquent ceux qui s'approchent. Sabbas lui-même est un PNJ : on l'arrête en l'engageant (le toucher › Attaquer).", {"type": "reveal_combat"}),
        ],
    },
]


def main():
    os.makedirs(OUT, exist_ok=True)
    for adv in ADVENTURES:
        with open(os.path.join(OUT, adv["id"] + ".json"), "w", encoding="utf-8") as f:
            json.dump(adv, f, ensure_ascii=False, indent=1)
        print(adv["id"], len(adv["quests"]), "quêtes,", len(adv["npcs"]), "PNJ,", len(adv["monsters"]), "monstres,", len(adv["scenes"]), "scènes")


if __name__ == "__main__":
    main()
