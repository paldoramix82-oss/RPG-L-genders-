#!/usr/bin/env python3
"""Génère les packs de PNJ (data/npcs/*.json).

Les fichiers JSON sont la vraie source utilisée par le jeu : on peut aussi les
modifier à la main. Ce script sert à (re)créer les packs fournis.
Usage : python3 tools/make_npc_packs.py
"""
import json
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "npcs")
STATS = ["Force", "Agilité", "Endurance", "Intelligence", "Perception", "Charisme"]


def npc(name, concept, species, origin, kind="npc", hp=15, res=10, rank="", magic=None, abilities=(), stats=None,
        skills=(), appearance="", personality="", goals="", secret="", inventory=(), color="#9a9a9a", symbol="", relations=""):
    st = dict(zip(STATS, stats or [10] * 6))
    base_magic = {"category": "", "name": "", "origin": "", "description": "", "limits": "", "public": True}
    base_magic.update(magic or {})
    return {
        "name": name, "concept": concept, "species": species, "origin": origin, "kind": kind,
        "hp": hp, "hp_max": hp, "res": res, "res_max": res, "rank": rank, "magic": base_magic,
        "abilities": [{"name": a[0], "description": a[1], "cost": a[2] if len(a) > 2 else "", "range": a[3] if len(a) > 3 else "",
                       "limits": a[4] if len(a) > 4 else ""} for a in abilities],
        "stats": [{"name": k, "value": v} for k, v in st.items()],
        "skills": [{"name": s[0], "value": s[1]} for s in skills],
        "appearance": appearance, "personality": personality, "goals": goals, "secret": secret, "relations": relations,
        "inventory": [{"name": i[0], "qty": i[1], "description": i[2] if len(i) > 2 else ""} for i in inventory],
        "pawn": {"color": color, "symbol": symbol},
    }


def M(cat, name, desc, origin="Personnalité et environnement", limits=""):
    return {"category": cat, "name": name, "description": desc, "origin": origin, "limits": limits}


# --- Légenders : mages de Shima et figures citées dans les documents de l'univers ---
SHIMA = [
    npc("Youri", "Mage d'État de rang L — Division de l'Encre", "Humain", "RAC (Shima)", hp=60, res=40, rank="L",
        magic=M("Création", "Tornades", "Crée des tornades de toutes tailles et de toutes forces. Ne peut pas contrôler une tornade naturelle : seulement en créer une nouvelle."),
        abilities=[("Tornade", "Une colonne de vent qui balaie tout sur son passage.", "variable", "Zone"), ("Maîtrise des bases", "Connaît les fondamentaux, sans plus.")],
        stats=[13, 15, 14, 14, 15, 13], skills=[("Combat", 6), ("Magie", 8), ("Survie", 4)],
        personality="Calme et sûr de lui, vitrine de Shima. Son rang est public et son salaire astronomique.", goals="Garder la Division de l'Encre soudée.",
        secret="Il sait qu'il est très loin du niveau des L+.", color="#6f9fc9", symbol="YL"),
    npc("Midori", "Mage d'État de rang I (Immortel)", "Humaine", "RAC (Shima)", hp=50, res=35, rank="I",
        stats=[11, 14, 13, 15, 15, 14], skills=[("Magie", 7), ("Investigation", 4)],
        personality="Exigeante, d'une efficacité redoutable. Comme Youri, elle n'a que les bases de la maîtrise.", color="#8fb28a", symbol="MI"),
    npc("Shiro", "Métamorphe surpuissant (SS+)", "Humain", "RAC", hp=45, res=30, rank="SS+",
        magic=M("Métamorphose", "Formes animales", "Polymorphe : peut prendre n'importe quelle forme animale ou hybride. Les formes plus massives l'épuisent davantage."),
        stats=[16, 14, 15, 7, 11, 10], skills=[("Combat", 6)],
        personality="Une puissance brute, freinée par sa bêtise et son manque de stratégie.", color="#e0e0d0", symbol="SH"),
    npc("Lisz", "Faucheuse, rang S", "Humaine", "Clan des Faucheurs", hp=32, res=25, rank="S",
        magic=M("Spéciale", "Spectre (intangibilité par apnée)", "Devient intangible tant qu'elle retient sa respiration.", "Croyance collective", "Limitée par son souffle."),
        stats=[11, 16, 13, 13, 15, 10], skills=[("Discrétion", 6), ("Maîtrise des bases (AEC)", 7), ("Combat", 5)],
        personality="Froide et professionnelle : maîtriser les fondamentaux était une question de survie dès l'enfance.", color="#2a2733", symbol="LZ"),
    npc("Kojiro", "Mutant, rang S (évalué au combat pur)", "Mutant", "Lidaknie", hp=40, res=0, rank="S",
        magic=M("Mutation", "Physiologie modifiée", "AEC + ADN animal : pas d'antenne AEC, insensible à la technologie anti-magie de Karoh.", "Mutation", "N'a accès à aucune technique universelle de maîtrise."),
        stats=[16, 15, 16, 10, 13, 9], skills=[("Combat", 7), ("Pistage", 4)], color="#7b5a3a", symbol="KJ"),
    npc("Benjamin Tennyson", "Invocateur des bêtes mythiques", "Humain", "RAC", hp=24, res=30,
        magic=M("Invocation", "Bêtes mythiques", "Dix contrats remplis : il appelle des esprits qui existaient déjà dans le monde spirituel."),
        abilities=[("Monkey", "Capucin, esprit de la foudre."), ("Bunny", "Lapin transcendé par un fruit millénaire."),
                   ("Minette", "Esprit des plantes ; peut devenir une tigresse géante."), ("Wolf", "Croc d'argent, esprit de glace."),
                   ("Kitsune", "Renarde à cinq queues, sans doute la plus ancienne.")],
        appearance="19 ans, cheveux blancs.", color="#d9dee4", symbol="BT"),
    npc("Imelda", "Gardienne de la Foudre", "Humaine", "RAC", hp=30, res=25,
        magic=M("Renforcement", "Foudre de Fulminis", "Se renforce par la foudre et peut l'appeler.", "Imposition par un Légender (Gardien)"),
        personality="Une décharge d'énergie permanente.", color="#d1a15e", symbol="IM"),
    npc("Kenji", "Soigneur", "Humain", "RAC", hp=18, res=20,
        magic=M("Invocation", "Feux follets guérisseurs", "Invoque des feux follets qui soignent."), skills=[("Médecine", 5)],
        personality="Son premier élan est toujours de prendre soin des autres.", color="#8fb28a", symbol="KE"),
    npc("Trenya", "Éclaireuse psychique", "Humaine", "RAC", hp=18, res=20,
        magic=M("Psychique", "Carte mentale", "Perçoit en temps réel une carte mentale de son environnement."),
        skills=[("Perception", 6), ("Investigation", 4)], color="#a07cc9", symbol="TR"),
    npc("Ryo", "Mage à la magie inclassable", "Humain", "RAC", hp=22, res=25,
        magic=M("Spéciale", "Vitesse en pourcentage", "Accélère ou ralentit tout ce qu'il veut, en pourcentage."), color="#5fb3a8", symbol="RY"),
    npc("Kefha", "L'homme d'acier", "Humain", "RAC", hp=34, res=15,
        magic=M("Assimilation", "Acier", "Assimile du métal et devient un homme d'acier ; la source est détruite.", limits="Sans métal disponible, il est à sec."),
        stats=[15, 9, 16, 9, 10, 9], color="#9a9a9a", symbol="KF"),
    npc("Queen", "Transformatrice", "Humaine", "RAC", hp=20, res=20,
        magic=M("Transformation", "Boue", "Transforme les solides en boue (jamais elle-même)."), color="#7b5a3a", symbol="QN"),
    npc("Lax", "Corps élastique", "Humain", "RAC", hp=28, res=10,
        magic=M("Déformation", "Élasticité", "Son corps EST élastique, sans activation : c'est sa nature."), color="#d27aa0", symbol="LX"),
    npc("Olivia", "Beauté envoûtante", "Humaine", "RAC", hp=16, res=20,
        magic=M("Psychique", "Admiration", "Sa beauté provoque une soumission par admiration.", limits="L'utiliser contre la liberté d'autrui est illégal."),
        skills=[("Négociation", 6)], color="#d27aa0", symbol="OL"),
]

# --- Légenders : PNJ originaux et créatures ---
MONDE = [
    npc("Nib", "Ombré guide et chapardeur", "Ombré", "Forêts de Kurtzuma", hp=8, res=12,
        magic=M("Psychique", "Voix des bêtes et illusion", "Parle à tous les animaux et monstres ; prend l'apparence de n'importe quelle créature, sans ses capacités."),
        skills=[("Discrétion", 6), ("Survie", 5), ("Artisanat", 4)], appearance="Petit rongeur humanoïde tout noir, aux yeux brillants.",
        personality="Méfiant puis loyal ; adore les objets mécaniques.", goals="Être payé en bricoles intéressantes.",
        secret="Il a volé les provisions de la moitié des candidats du test.", color="#2a2733", symbol="NB"),
    npc("Agente Vex", "Agente des services de Karoh", "Humaine sans-magie", "Karoh", hp=22, res=0,
        abilities=[("Brouilleur anti-magie", "Empêche la résonance d'un mage avec le champ terrestre.", "1 charge", "10 m", "Inutile contre les mutants et les Gardiens de haut niveau.")],
        skills=[("Discrétion", 5), ("Investigation", 5), ("Combat", 4)], inventory=[("Brouilleur portatif", 1), ("Pistolet compact", 1)],
        personality="Polie, glaciale, toujours deux coups d'avance.", goals="Évaluer les nouveaux mages d'État.", secret="Karoh cherche le Lac Retourné.",
        color="#5c6470", symbol="VX"),
    npc("Orsino Valdecœur", "Marchand de cristaux de Trèfle", "Humain", "Trèfle", hp=12, res=5,
        skills=[("Marchandage", 7), ("Négociation", 5)],
        inventory=[("AEC jaune (sous licence)", 12), ("AEC vert", 3), ("Bijou en AEC", 2, "Dissimule peut-être un fragment illégal.")],
        personality="Jovial, flatteur, compte tout.", secret="Trafique de l'AEC synthétique par les Îles Flottantes.", color="#c9a96e", symbol="OV"),
    npc("Dame Hrafna", "Chevalière mage de Pik", "Humaine", "Pik", hp=36, res=20, rank="S-",
        magic=M("Renforcement", "Armure de roc", "Se couvre de pierre pour encaisser et frapper."), stats=[15, 11, 15, 11, 12, 12],
        skills=[("Combat", 6), ("Intimidation", 4)], personality="Honneur et discipline, héritière de la culture de Fury.", color="#6e655b", symbol="HR"),
    npc("Comte Aldric", "Noble diplomate de Keurd", "Humain", "Keurd", hp=14, res=10, skills=[("Négociation", 6), ("Intimidation", 4)],
        personality="Courtois ; une rancune millénaire bien cachée.", goals="Affaiblir l'influence de la RAC sans guerre ouverte.", color="#7a2f3a", symbol="AK"),
    npc("Professeure Ilse Marrow", "Volcanologue de Volcano", "Humaine", "Grande Caldeira", hp=12, res=10,
        skills=[("Investigation", 6), ("Alchimie", 4), ("Survie", 3)], personality="Passionnée jusqu'à l'imprudence.",
        goals="Mesurer l'esprit né de la cicatrice de Sol'fyr.", color="#b4472a", symbol="IL"),
    npc("Sabbas", "Contrebandier d'AEC noir", "Humain", "Lima", hp=20, res=5, skills=[("Discrétion", 5), ("Marchandage", 5)],
        inventory=[("Fiole scellée d'AEC noir", 1, "Quelques grammes : de quoi raser un quartier.")],
        secret="Travaille pour quelqu'un de très haut placé.", color="#28252e", symbol="SB"),
    npc("Examinateur Dorrow", "Mage d'État chargé du test", "Humain", "RAC (Shima)", hp=40, res=30, rank="SS-",
        magic=M("Manipulation", "Densité de l'air", "Durcit l'air pour lui donner forme : murs, entraves, plates-formes."),
        skills=[("Combat", 6), ("Investigation", 4)], personality="Impartial ; note tout : maîtrise, stratégie, survie, utilité…", color="#4a4358", symbol="DO"),
    npc("Envie", "Démon mineur de la jalousie", "Démon", "Monde de Nhar'Zhul", kind="monster", hp=18, res=20,
        abilities=[("Se nourrir", "Grandit avec la jalousie autour de lui… et l'amplifie.")], personality="Murmure ce que les autres ont et que tu n'as pas.",
        color="#5fb36a", symbol="EN"),
    npc("L'Esprit de la rivière", "Esprit de lieu", "Esprit", "Kurtzuma", hp=30, res=40,
        abilities=[("Crue", "Fait monter les eaux."), ("Invisible", "Invisible sauf s'il décide de se montrer.")], personality="Ancien, lent, susceptible.",
        color="#30536f", symbol="ER"),
    npc("Croc blanc", "Monstre du Désert de Cristal", "Monstre", "Désert de Cristal", kind="monster", hp=28, res=0,
        abilities=[("Morsure glacée", "Les blessures gèlent."), ("Meute", "Rarement seul.")], stats=[15, 14, 14, 4, 14, 3], color="#d9dee4", symbol="CB"),
    npc("Guerrier homme-lézard", "D'une micro-civilisation de la Forêt-Monde", "Homme-lézard", "Forêt-Monde", kind="monster", hp=26, res=10,
        abilities=[("Lance-artefact", "Arme à base d'artefacts magiques.")], personality="Intelligent, parle, défend son territoire.", color="#4f7a3a", symbol="HL"),
]

VALOMBRE = [
    npc("Bertrand", "Tavernier du Corbeau Rieur", "Humain", "Valombre", hp=12, skills=[("Marchandage", 4), ("Négociation", 3)],
        personality="Bonhomme et bavard, mais évite certains sujets.", secret="Membre à contrecœur du Cercle de la Braise ; spirale brûlée sur la main.",
        color="#a77d4c", symbol="BE"),
    npc("Sœur Aveline", "Prêtresse du temple aux cloches", "Humaine", "Valombre", hp=14, res=15,
        magic=M("Divine", "Lumière apaisante", "Soigne et calme les esprits."), skills=[("Médecine", 5)],
        personality="Douce, inquiète depuis que les cloches se sont tues.", goals="Comprendre pourquoi les cloches ne sonnent plus.", color="#e0e0d0", symbol="AV"),
    npc("Dorn", "Maître-forgeron", "Nain", "Montagnes du nord", hp=22, stats=[15, 9, 15, 10, 11, 8], skills=[("Artisanat", 7)],
        inventory=[("Épée bien équilibrée", 2), ("Bouclier cerclé", 1)], personality="Bourru et honnête.", color="#6e655b", symbol="DN"),
    npc("Bourgmestre Hallis", "Dirigeant de Valombre", "Humain", "Valombre", hp=10, skills=[("Négociation", 5)],
        personality="Soucieux des apparences.", secret="Sait que le Cercle de la Braise existe et le laisse faire.", color="#5b4637", symbol="HA"),
    npc("Mirelle", "Herboriste de la lisière", "Demi-elfe", "Forêts profondes", hp=12, res=10,
        magic=M("Nature", "Murmure des plantes", "Parle aux plantes et en connaît les secrets."), skills=[("Alchimie", 6), ("Survie", 4)],
        inventory=[("Potion de soin", 3), ("Herbes de sommeil", 2)], color="#8fb28a", symbol="MR"),
    npc("Capitaine Roderic", "Capitaine de la garde", "Humain", "Valombre", hp=24, stats=[14, 12, 13, 10, 12, 11],
        skills=[("Combat", 5), ("Intimidation", 4)], color="#6f7f9a", symbol="RO"),
    npc("Le Voyageur encapuchonné", "Émissaire du Cercle de la Braise", "Humain ?", "Inconnue", hp=26, res=20,
        magic=M("Ombre", "Braise noire", "Des flammes sans lumière qui brûlent sans fumée."), personality="Parle peu, observe beaucoup.",
        secret="Prépare le réveil de ce qui dort sous les ruines.", color="#55506a", symbol="VE"),
]

BESTIAIRE = [
    npc("Loup cendré", "Bête de la forêt", "Monstre", "Forêts", kind="monster", hp=11, res=0,
        abilities=[("Morsure", "1d6+2"), ("Meute", "+2 au toucher si un autre loup est au contact.")], stats=[13, 15, 12, 3, 14, 6], color="#8a4a3c", symbol="LC"),
    npc("Bandit de grand chemin", "Détrousseur", "Humain", "Routes", hp=12, res=0,
        abilities=[("Coup de dague", "1d4+2"), ("Fuite", "Disparaît s'il se retrouve seul.")], skills=[("Discrétion", 3)], color="#7a6a5a", symbol="BA"),
    npc("Chef bandit", "Meneur cruel", "Humain", "Routes", hp=24, res=0,
        abilities=[("Épée longue", "1d8+3"), ("Ordre", "Un allié rejoue immédiatement.")], color="#5a3a2a", symbol="CH"),
    npc("Gobelin", "Petit pillard", "Gobelin", "Collines", kind="monster", hp=7, res=0,
        abilities=[("Fronde", "1d4, portée 15 m"), ("Esquive sournoise", "Se cache après avoir tiré.")], color="#6b8f3a", symbol="GO"),
    npc("Ogre", "Brute affamée", "Ogre", "Montagnes", kind="monster", hp=45, res=0,
        abilities=[("Massue", "2d8+4"), ("Lancer de rocher", "1d10+4, portée 20 m")], stats=[19, 8, 17, 5, 8, 6], color="#8a7a50", symbol="OG"),
    npc("Squelette", "Mort-vivant", "Mort-vivant", "Cryptes", kind="monster", hp=13, res=0,
        abilities=[("Lame rouillée", "1d6+1"), ("Insensible", "Ignore la peur et le poison.")], color="#d9d4c4", symbol="SQ"),
    npc("Spectre", "Âme tourmentée", "Esprit", "Ruines", kind="monster", hp=20, res=20,
        abilities=[("Toucher glacial", "1d8 et affaiblit"), ("Intangible", "Traverse murs et portes.")], color="#9fc3d4", symbol="SP"),
    npc("Araignée géante", "Prédatrice des grottes", "Monstre", "Grottes", kind="monster", hp=26, res=0,
        abilities=[("Morsure venimeuse", "1d8 + poison"), ("Toile", "Immobilise une cible.")], color="#3f3a33", symbol="AR"),
    npc("Golem de pierre", "Gardien animé", "Construction", "Ruines", kind="monster", hp=50, res=0,
        abilities=[("Poing de pierre", "2d10"), ("Lent", "Agit en dernier.")], stats=[20, 6, 20, 3, 8, 1], color="#7d7a70", symbol="GP"),
    npc("Dragonnet", "Jeune dragon", "Dragon", "Pics", kind="monster", hp=38, res=20,
        abilities=[("Souffle de feu", "3d6 en cône", "recharge 5-6"), ("Griffes", "1d10+3")], color="#b0605a", symbol="DR"),
    npc("Slime acide", "Masse gluante", "Monstre", "Égouts", kind="monster", hp=22, res=0,
        abilities=[("Engloutir", "1d6 d'acide par tour"), ("Division", "Se divise quand on le tranche.")], color="#5fb36a", symbol="SL"),
    npc("Élémentaire de cendre", "Esprit de feu éteint", "Élémentaire", "Champs calcinés", kind="monster", hp=30, res=20,
        abilities=[("Nuée de cendres", "Aveugle dans un rayon de 3 cases."), ("Braise", "1d10 de feu")], color="#4a4543", symbol="EC"),
    npc("Garde", "Soldat d'une faction", "Humain", "Ville", hp=14, res=0, abilities=[("Hallebarde", "1d10+1, allonge")], color="#6f7f9a", symbol="GA"),
    npc("Ours des cavernes", "Bête énorme", "Animal", "Forêts", kind="monster", hp=34, res=0,
        abilities=[("Étreinte", "2d6+4 et saisie")], stats=[18, 10, 16, 2, 12, 6], color="#6b4a2a", symbol="OU"),
]

PACKS = [
    ("legenders_shima", "Légenders — Mages de Shima", "legenders", "Mages d'État et figures citées dans les documents de l'univers.", SHIMA),
    ("legenders_monde", "Légenders — Gens et créatures de Kurtzuma", "legenders", "PNJ originaux : Ombré, agente de Karoh, marchand de Trèfle, chevalière de Pik, démon, esprit, monstres…", MONDE),
    ("fantasy_valombre", "Les Cendres de Valombre", "fantasy", "Les habitants de Valombre et le Cercle de la Braise.", VALOMBRE),
    ("bestiaire", "Bestiaire et adversaires", "*", "Monstres et adversaires génériques, pour tous les univers.", BESTIAIRE),
]

def add_weapons(entry):
    """Les capacités décrites par des dés (« 1d6+2 ») deviennent des armes utilisables en combat."""
    import re
    for a in entry["abilities"]:
        m = re.match(r"^(\d*d\d+(?:[+-]\d+)?)", a["description"].replace(" ", ""))
        if m:
            reach = re.search(r"portée (\d+)", a["description"])
            entry["inventory"].insert(0, {"name": a["name"], "category": "arme", "damage": m.group(1), "stat": "", "crit": 20,
                                          "range": max(1, int(reach.group(1)) // 2) if reach else 1, "qty": 1, "equipped": True,
                                          "description": a["description"]})
    return entry


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for _, _, _, _, npcs in PACKS:
        for e in npcs:
            add_weapons(e)
    for pid, name, universe, desc, npcs in PACKS:
        with open(os.path.join(OUT, pid + ".json"), "w", encoding="utf-8") as f:
            json.dump({"id": pid, "name": name, "universe": universe, "description": desc, "npcs": npcs}, f, ensure_ascii=False, indent=1)
    print(sum(len(p[4]) for p in PACKS), "PNJ dans", len(PACKS), "packs")
