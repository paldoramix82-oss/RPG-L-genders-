#!/usr/bin/env python3
"""Génère les classes de personnage (data/classes/*.json).

Chaque classe : bonus de caractéristiques, PV et énergie de base, vitesse
(cases par tour), bonus d'attaque / de critique / de défense, compétences,
capacités utilisables en jeu (attaque, soin, effet), équipement fixe et
choix d'équipement (ex. trois dagues au choix pour l'assassin).
Usage : python3 tools/make_classes.py
"""
import json
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "classes")


def weapon(name, damage, stat, crit=20, range_=1, desc="", effect=""):
    return {"name": name, "category": "arme", "damage": damage, "stat": stat, "crit": crit, "range": range_,
            "description": desc, "effect": effect, "qty": 1, "equipped": True}


def armor(name, defense, desc="", category="armure"):
    return {"name": name, "category": category, "defense": defense, "description": desc, "qty": 1, "equipped": True}


def potion(name, heal, qty=2, desc=""):
    return {"name": name, "category": "consommable", "heal": heal, "description": desc, "qty": qty, "equipped": False}


def item(name, desc, qty=1):
    return {"name": name, "category": "objet", "description": desc, "qty": qty, "equipped": False}


def attack(name, damage, stat, cost, range_=1, desc=""):
    return {"name": name, "kind": "attack", "damage": damage, "stat": stat, "res_cost": cost, "range": range_, "description": desc}


def heal(name, dice, stat, cost, range_=4, desc=""):
    return {"name": name, "kind": "heal", "heal": dice, "stat": stat, "res_cost": cost, "range": range_, "description": desc}


def effect(name, cost, desc, range_=1):
    return {"name": name, "kind": "effect", "res_cost": cost, "range": range_, "description": desc}


def cls(id_, name, tagline, role, color, emblem, bonus, hp, res, res_stat, speed, abilities, kit, choices,
        skills=(), attack_bonus=0, crit_bonus=0, defense_bonus=0, magic=None, recommended=None, description=""):
    return {
        "id": id_, "name": name, "tagline": tagline, "role": role, "color": color, "emblem": emblem,
        "description": description or tagline, "bonus": bonus, "hp_base": hp, "hp_per_level": max(4, hp // 3),
        "res_base": res, "res_stat": res_stat, "speed": speed, "attack_bonus": attack_bonus, "crit_bonus": crit_bonus,
        "defense_bonus": defense_bonus, "skills": [{"name": s, "value": v} for s, v in skills],
        "abilities": abilities, "kit": kit, "choices": choices, "magic": magic or {},
        "recommended": recommended or {},
    }


LEGENDERS = [
    cls("briseur", "Briseur", "Renforcement : se couvre d'une énergie qui décuple ses coups.", "Combattant au contact", "#b0605a", "fist",
        {"Force": 2, "Endurance": 1}, 18, 8, "Endurance", 5,
        [attack("Poing élémentaire", "2d6", "Force", 3, 1, "Un coup chargé de son vecteur (flammes, foudre, son…)."),
         effect("Surcharge", 2, "Jusqu'à la fin du tour suivant : +2 aux dégâts et +1 à la défense.")],
        [potion("Ration de combat", "1d6", 2, "Rend un peu de vigueur.")],
        [{"title": "Votre arme", "options": [
            weapon("Gantelets en AEC rouge", "1d8", "Force", 20, 1, "Frappent fort, chauffent au rouge."),
            weapon("Lame large", "1d10", "Force", 20, 1, "Lourde mais dévastatrice."),
            weapon("Bâton renforcé", "1d6", "Force", 19, 2, "Allonge de 2 cases, coups précis.")]},
         {"title": "Votre protection", "options": [
            armor("Veste renforcée", 2, "Cuir doublé de plaques souples."),
            armor("Bouclier d'énergie", 2, "Un champ AEC jaune portatif.", "bouclier")]}],
        skills=[("Combat", 3), ("Intimidation", 1)], attack_bonus=1,
        magic={"category": "Renforcement", "name": "Renforcement", "description": "Se recouvre de son vecteur pour gagner en résistance, vitesse et dégâts."},
        recommended={"Force": 4, "Endurance": 3, "Agilité": 2, "Perception": 1, "Intelligence": 1, "Charisme": 1}),
    cls("ombre", "Ombre", "Assassin des Faucheurs : silence, apnée, coups critiques.", "Assassin", "#4a4358", "dagger",
        {"Agilité": 2, "Perception": 1}, 13, 10, "Agilité", 6,
        [attack("Frappe dans l'ombre", "2d6", "Agilité", 3, 1, "Attaque surprise : +2 à la touche si la cible ne vous a pas vu."),
         effect("Apnée spectrale", 4, "Devient intangible jusqu'à son prochain tour : les attaques le traversent.")],
        [item("Fumigène", "Masque une zone de 3 cases pendant un tour.", 2), item("Crochets de serrurier", "Ouvrir une serrure en silence.")],
        [{"title": "Votre dague", "options": [
            weapon("Dague courbe", "1d4", "Agilité", 18, 1, "Critique sur 18-20 : la favorite des Faucheurs."),
            weapon("Kunai jumeaux", "1d6", "Agilité", 19, 3, "Se lancent jusqu'à 3 cases."),
            weapon("Lame d'apnée", "1d6", "Agilité", 19, 1, "Ignore 1 point de défense.", "ignore_defense_1")]},
         {"title": "Votre tenue", "options": [
            armor("Cape sombre", 1, "Discrète : avantage pour se cacher."),
            armor("Cuir souple", 2, "Protège sans bruit.")]}],
        skills=[("Discrétion", 3), ("Maîtrise des bases (AEC)", 2)], crit_bonus=1,
        magic={"category": "Spéciale", "name": "Intangibilité", "description": "Intangible tant qu'il retient son souffle."},
        recommended={"Agilité": 5, "Perception": 3, "Endurance": 2, "Force": 1, "Intelligence": 1}),
    cls("invocateur", "Invocateur", "Appelle des esprits liés par contrat.", "Soutien / attaque à distance", "#6f9fc9", "spirit",
        {"Charisme": 2, "Intelligence": 1}, 12, 14, "Charisme", 5,
        [attack("Appel d'esprit", "2d6", "Charisme", 3, 6, "Un esprit lié frappe une cible jusqu'à 6 cases."),
         effect("Gardien spirituel", 3, "Un esprit protège un allié : +2 défense jusqu'à son prochain tour.", 4)],
        [item("Registre des contrats", "Les noms des esprits liés."), potion("Fiole d'AEC vert", "2d4", 1)],
        [{"title": "Votre focus", "options": [
            weapon("Bâton de contrat", "1d6", "Charisme", 20, 2, "Gravé des sceaux de vos contrats."),
            weapon("Cristal d'appel", "1d4", "Charisme", 19, 5, "Projette un éclat d'esprit jusqu'à 5 cases."),
            weapon("Clochette spirituelle", "1d6", "Charisme", 20, 3, "Son tintement blesse les esprits hostiles.")]}],
        skills=[("Magie", 3), ("Négociation", 1)],
        magic={"category": "Invocation", "name": "Contrats spirituels", "description": "Invoque des entités qui ont accepté un contrat."},
        recommended={"Charisme": 5, "Intelligence": 3, "Perception": 2, "Endurance": 2}),
    cls("createur", "Créateur élémentaire", "Génère tornades, flammes ou vagues à partir de rien.", "Mage d'attaque à distance", "#d1a15e", "flame",
        {"Intelligence": 2, "Perception": 1}, 11, 15, "Intelligence", 5,
        [attack("Trait élémentaire", "2d8", "Intelligence", 3, 7, "Une décharge (vent, feu, eau…) jusqu'à 7 cases."),
         attack("Déferlement", "3d6", "Intelligence", 6, 4, "Frappe fort à 4 cases ; épuisant."),
         effect("Mur élémentaire", 3, "Bloque une ligne de 3 cases jusqu'à votre prochain tour.", 5)],
        [potion("Fiole d'AEC vert", "2d4", 1)],
        [{"title": "Votre catalyseur", "options": [
            weapon("Catalyseur en AEC jaune", "1d6", "Intelligence", 20, 6, "Projette l'énergie à 6 cases."),
            weapon("Gant de focalisation", "1d8", "Intelligence", 20, 3, "Plus puissant, portée 3."),
            weapon("Orbe instable", "1d10", "Intelligence", 19, 4, "Puissant mais capricieux.")]}],
        skills=[("Magie", 3), ("Investigation", 1)],
        magic={"category": "Création", "name": "Création élémentaire", "description": "Crée un élément de zéro ; ne contrôle pas ce qui existe déjà."},
        recommended={"Intelligence": 5, "Perception": 3, "Agilité": 2, "Endurance": 2}),
    cls("metamorphe", "Métamorphe", "Prend la forme d'une bête pour combattre ou fuir.", "Combattant polyvalent", "#7b5a3a", "paw",
        {"Force": 1, "Agilité": 1, "Endurance": 1}, 16, 10, "Endurance", 6,
        [effect("Forme bestiale", 3, "Jusqu'à la fin du combat : +2 Force, griffes 1d8, vitesse +1."),
         attack("Charge", "2d6", "Force", 2, 1, "Fonce sur une cible.")],
        [potion("Viande séchée", "1d6", 3)],
        [{"title": "Votre forme favorite", "options": [
            weapon("Griffes de fauve", "1d6", "Agilité", 19, 1, "Rapides et précises."),
            weapon("Mâchoires d'ours", "1d8", "Force", 20, 1, "Puissantes."),
            weapon("Bec de rapace", "1d6", "Perception", 20, 1, "Vise les points faibles.")]}],
        skills=[("Survie", 2), ("Pistage", 2)],
        magic={"category": "Métamorphose", "name": "Formes animales", "description": "Polymorphe : forme animale ou hybride ; plus massive = plus épuisante."},
        recommended={"Force": 3, "Agilité": 3, "Endurance": 3, "Perception": 2, "Intelligence": 1}),
    cls("psychique", "Psychique", "Agit par l'esprit : perception, manipulation, télékinésie.", "Contrôle", "#a07cc9", "eye",
        {"Intelligence": 1, "Perception": 1, "Charisme": 1}, 12, 14, "Intelligence", 5,
        [attack("Onde mentale", "2d6", "Intelligence", 3, 6, "Une douleur pure dans l'esprit de la cible."),
         effect("Carte mentale", 2, "Révèle au MJ tout ce qui est caché dans un rayon de 8 cases."),
         effect("Emprise", 5, "La cible perd son prochain tour (le MJ peut demander un jet de résistance).", 4)],
        [item("Carnet d'observations", "Ce que vous avez lu dans les esprits.")],
        [{"title": "Votre outil", "options": [
            weapon("Télékinésie", "1d6", "Intelligence", 20, 5, "Projette des objets jusqu'à 5 cases."),
            weapon("Lame psychique", "1d8", "Intelligence", 19, 1, "Une lame faite de pensée."),
            weapon("Pendule d'AEC", "1d4", "Perception", 18, 4, "Trouve les failles.")]}],
        skills=[("Investigation", 2), ("Négociation", 2)],
        magic={"category": "Psychique", "name": "Esprit", "description": "Agit sur le plan mental : perception, influence, télékinésie."},
        recommended={"Intelligence": 4, "Perception": 3, "Charisme": 3, "Endurance": 2}),
    cls("soigneur", "Soigneur", "Feux follets et énergie verte : garde le groupe debout.", "Soin", "#8fb28a", "heart",
        {"Charisme": 1, "Intelligence": 1, "Endurance": 1}, 13, 14, "Charisme", 5,
        [heal("Feux follets", "2d6", "Charisme", 3, 5, "Soigne un allié jusqu'à 5 cases."),
         heal("Vague de soin", "1d8", "Charisme", 5, 3, "Soigne (à appliquer à chaque allié proche, au jugé du MJ)."),
         effect("Purification", 2, "Retire un effet (poison, peur, brûlure…).", 3)],
        [potion("Potion de soin", "2d4", 3), item("Trousse de soins", "Avantage aux jets de Médecine.")],
        [{"title": "Votre arme", "options": [
            weapon("Bâton de vie", "1d6", "Force", 20, 2, "Simple et solide."),
            weapon("Fronde", "1d4", "Agilité", 20, 6, "Pour rester à distance.")]}],
        skills=[("Médecine", 3), ("Alchimie", 1)],
        magic={"category": "Invocation", "name": "Feux follets guérisseurs", "description": "Invoque des feux follets qui soignent."},
        recommended={"Charisme": 4, "Intelligence": 3, "Endurance": 3, "Perception": 2}),
    cls("tacticien", "Tacticien de Karoh", "Sans magie, mais avec la technologie la plus redoutée du monde.", "Tireur / anti-mage", "#5c6470", "gear",
        {"Perception": 2, "Intelligence": 1}, 14, 8, "Intelligence", 5,
        [effect("Brouilleur anti-magie", 3, "La cible ne peut pas utiliser de capacité magique à son prochain tour (sauf mutants et Gardiens puissants).", 5),
         attack("Tir ajusté", "2d8", "Perception", 3, 8, "Un tir précis jusqu'à 8 cases.")],
        [item("Brouilleur portatif", "Coupe la résonance d'un mage."), item("Munitions", "Pour l'arme à feu.", 20)],
        [{"title": "Votre arme", "options": [
            weapon("Pistolet compact", "1d8", "Perception", 20, 8, "Portée 8 cases."),
            weapon("Arbalète de poing", "1d6", "Perception", 19, 6, "Silencieuse."),
            weapon("Matraque à choc", "1d6", "Force", 20, 1, "Étourdit.")]},
         {"title": "Votre protection", "options": [
            armor("Gilet de Karoh", 3, "Fibres techniques."),
            armor("Manteau à capteurs", 1, "+1 Initiative (au jugé du MJ).")]}],
        skills=[("Technologie", 3), ("Investigation", 1)],
        magic={"category": "Aucune (sans-magie)", "name": "", "description": ""},
        recommended={"Perception": 5, "Intelligence": 3, "Agilité": 2, "Endurance": 2}),
    cls("mutant", "Mutant", "AEC et ADN animal : insensible à l'anti-magie.", "Tank / combattant", "#4f7a3a", "claw",
        {"Endurance": 2, "Force": 1}, 20, 6, "Endurance", 5,
        [heal("Régénération", "1d8", "Endurance", 2, 0, "Se soigne soi-même."),
         attack("Assaut sauvage", "2d8", "Force", 4, 1, "Un déchaînement de coups.")],
        [potion("Ration", "1d6", 2)],
        [{"title": "Votre mutation offensive", "options": [
            weapon("Griffes rétractiles", "1d8", "Force", 19, 1, "Toujours prêtes."),
            weapon("Queue écailleuse", "1d6", "Agilité", 20, 2, "Allonge de 2 cases."),
            weapon("Crocs venimeux", "1d6", "Force", 20, 1, "Poison : 1d4 au tour suivant.", "poison")]}],
        skills=[("Combat", 2), ("Survie", 2)], defense_bonus=1,
        magic={"category": "Mutation", "name": "Physiologie modifiée", "description": "Pas d'antenne AEC : l'anti-magie n'a aucun effet."},
        recommended={"Endurance": 4, "Force": 4, "Agilité": 2, "Perception": 2}),
]

FANTASY = [
    cls("guerrier", "Guerrier", "Lame, bouclier et courage.", "Combattant au contact", "#b0605a", "sword",
        {"Force": 2, "Endurance": 1}, 18, 6, "Endurance", 5,
        [attack("Coup puissant", "2d8", "Force", 3, 1, "Un coup de toutes ses forces."),
         effect("Provocation", 2, "Les ennemis proches doivent l'attaquer à leur prochain tour.")],
        [potion("Potion de soin", "2d4", 1)],
        [{"title": "Votre arme", "options": [
            weapon("Épée longue", "1d8", "Force", 20, 1, "L'arme classique."),
            weapon("Hache de guerre", "1d10", "Force", 20, 1, "Lourde."),
            weapon("Lance", "1d8", "Force", 20, 2, "Allonge de 2 cases.")]},
         {"title": "Votre protection", "options": [
            armor("Cotte de mailles", 3, "Solide."), armor("Bouclier rond", 2, "Se combine avec la vitesse.", "bouclier")]}],
        skills=[("Combat", 3), ("Intimidation", 1)], attack_bonus=1,
        recommended={"Force": 4, "Endurance": 4, "Agilité": 2, "Perception": 2}),
    cls("assassin", "Assassin", "Frapper vite, frapper juste, disparaître.", "Assassin", "#4a4358", "dagger",
        {"Agilité": 2, "Perception": 1}, 13, 10, "Agilité", 6,
        [attack("Attaque sournoise", "2d6", "Agilité", 3, 1, "+2 à la touche si la cible est prise par surprise."),
         effect("Disparition", 3, "Se cache instantanément ; ne peut pas être ciblé jusqu'à son prochain tour.")],
        [item("Crochets", "Ouvrir les serrures."), potion("Fiole de poison", "0", 1, "À appliquer sur une lame : +1d4 au prochain coup.")],
        [{"title": "Votre dague", "options": [
            weapon("Dague effilée", "1d4", "Agilité", 18, 1, "Critique sur 18-20."),
            weapon("Dagues de lancer", "1d4", "Agilité", 19, 4, "Se lancent à 4 cases."),
            weapon("Stylet empoisonné", "1d6", "Agilité", 19, 1, "Poison : 1d4 au tour suivant.", "poison")]}],
        skills=[("Discrétion", 3), ("Pistage", 1)], crit_bonus=1,
        recommended={"Agilité": 5, "Perception": 3, "Endurance": 2, "Charisme": 2}),
    cls("mage", "Mage", "Les arcanes au bout des doigts.", "Mage d'attaque à distance", "#6f9fc9", "staff",
        {"Intelligence": 2, "Perception": 1}, 10, 16, "Intelligence", 5,
        [attack("Projectile arcanique", "2d6", "Intelligence", 2, 7, "Ne rate presque jamais (portée 7)."),
         attack("Boule de feu", "3d6", "Intelligence", 6, 6, "Explose à 6 cases."),
         effect("Bouclier arcanique", 2, "+3 défense jusqu'à son prochain tour.")],
        [item("Grimoire", "Vos sorts notés."), potion("Potion de mana", "0", 1, "Rend 1d6 énergie (au jugé du MJ).")],
        [{"title": "Votre focalisateur", "options": [
            weapon("Bâton runique", "1d6", "Intelligence", 20, 2, "Simple et fiable."),
            weapon("Baguette d'ébène", "1d4", "Intelligence", 19, 6, "Tire à 6 cases."),
            weapon("Orbe de cristal", "1d8", "Intelligence", 20, 4, "Puissant.")]}],
        skills=[("Magie", 3), ("Investigation", 1)],
        recommended={"Intelligence": 5, "Perception": 3, "Endurance": 2, "Agilité": 2}),
    cls("pretre", "Prêtre", "La foi qui soigne et protège.", "Soin", "#e0e0d0", "heart",
        {"Charisme": 2, "Endurance": 1}, 14, 14, "Charisme", 5,
        [heal("Soins", "2d6", "Charisme", 3, 4, "Soigne un allié à 4 cases."),
         attack("Flamme sacrée", "2d6", "Charisme", 3, 5, "Brûle les créatures impies."),
         effect("Bénédiction", 2, "+1 à tous les jets d'un allié pendant 2 tours.", 4)],
        [potion("Eau bénite", "1d8", 2), item("Symbole sacré", "Focalise la foi.")],
        [{"title": "Votre arme", "options": [
            weapon("Masse d'armes", "1d6", "Force", 20, 1, "Solide."), weapon("Bâton de pèlerin", "1d6", "Force", 20, 2, "Allonge 2.")]}],
        skills=[("Médecine", 3), ("Négociation", 1)],
        recommended={"Charisme": 5, "Endurance": 3, "Intelligence": 2, "Perception": 2}),
    cls("rodeur", "Rôdeur", "Archer et pisteur des terres sauvages.", "Tireur", "#8fb28a", "bow",
        {"Perception": 2, "Agilité": 1}, 15, 8, "Perception", 6,
        [attack("Tir précis", "2d8", "Perception", 3, 10, "Vise un point faible (portée 10)."),
         effect("Marque du chasseur", 2, "+2 aux dégâts contre la cible marquée jusqu'à la fin du combat.", 10)],
        [item("Corde (15 m)", "Toujours utile."), potion("Baies revigorantes", "1d6", 3)],
        [{"title": "Votre arme", "options": [
            weapon("Arc long", "1d8", "Perception", 20, 10, "Portée 10."), weapon("Arc court", "1d6", "Agilité", 19, 7, "Rapide."),
            weapon("Deux épées courtes", "1d6", "Agilité", 19, 1, "Au contact.")]}],
        skills=[("Survie", 2), ("Pistage", 2)],
        recommended={"Perception": 5, "Agilité": 3, "Endurance": 2, "Force": 2}),
    cls("barde", "Barde", "Charme, musique et répliques cinglantes.", "Soutien / social", "#d27aa0", "lute",
        {"Charisme": 2, "Agilité": 1}, 12, 12, "Charisme", 5,
        [effect("Chant inspirant", 2, "Un allié relance son prochain dé raté.", 6),
         attack("Moquerie cinglante", "1d8", "Charisme", 2, 6, "Blesse l'ego… et le corps."),
         heal("Mélodie apaisante", "1d8", "Charisme", 3, 4, "Soigne un allié.")],
        [item("Luth", "Pour les tavernes et les combats."), potion("Vin épicé", "1d4", 2)],
        [{"title": "Votre arme", "options": [
            weapon("Rapière", "1d8", "Agilité", 19, 1, "Élégante."), weapon("Arbalète légère", "1d6", "Agilité", 20, 6, "Portée 6.")]}],
        skills=[("Négociation", 3), ("Marchandage", 1)],
        recommended={"Charisme": 5, "Agilité": 3, "Perception": 2, "Intelligence": 2}),
]

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for uid, classes in (("legenders", LEGENDERS), ("fantasy", FANTASY)):
        with open(os.path.join(OUT, uid + ".json"), "w", encoding="utf-8") as f:
            json.dump(classes, f, ensure_ascii=False, indent=1)
    print(len(LEGENDERS), "classes Légenders,", len(FANTASY), "classes fantasy")
