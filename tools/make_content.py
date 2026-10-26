#!/usr/bin/env python3
"""Génère le contenu de jeu par défaut (data/content/<univers>.json).

Un fichier par univers : règles, caractéristiques, classes (passif, trois
capacités de base, ultime, capacités à apprendre, équipement), capacités,
effets de statut, objets, tables de butin et monstres. Le MJ en reçoit une
copie dans chaque campagne et peut tout modifier en cours de partie.

Toutes les capacités, objets et statuts utilisent la même liste d'effets
composables (voir scripts/game/effects.gd).
Usage : python3 tools/make_content.py
"""
import json
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "content")

STATS = [
    {"name": "Force", "short": "FOR", "description": "Puissance physique : dégâts au corps à corps, attaques puissantes, porter, enfoncer."},
    {"name": "Dextérité", "short": "DEX", "description": "Précision et agilité : toucher, esquive (Défense), initiative, discrétion, tir, et vision (jusqu'où l'on voit sur la carte)."},
    {"name": "Constitution", "short": "CON", "description": "Résistance physique : points de vie, résistance aux coups et au poison."},
    {"name": "Intelligence", "short": "INT", "description": "Savoir et analyse : puissance des sorts arcaniques, énigmes, connaissances."},
    {"name": "Esprit", "short": "ESP", "description": "Volonté et concentration : mana, résistance mentale et magique, puissance des soins."},
    {"name": "Charisme", "short": "CHA", "description": "Influence : persuader, intimider, et renforcer les capacités de soutien (bonus aux alliés)."},
]

RULES = {
    "stat_base": 5, "stat_pool": 15, "stat_min": 1, "stat_max": 10, "stat_cap": 14,
    "ap_per_turn": 2, "move_ap": 1, "quick_attack_ap": 1, "power_attack_ap": 2, "defend_ap": 1, "item_ap": 1,
    "defense_base": 8, "hp_per_con": 2, "res_per_stat": 2, "res_regen_turn": 1,
    "ult_gain_deal": 15, "ult_gain_taken": 10, "ult_gain_turn": 10,
    "xp_base": 100, "level_max": 20, "stat_points_per_level": 1, "pick_every_levels": 1,
    "slots_basic": 3, "slots_ultimate": 1, "swap_in_combat": False,
    "rest_hp_pct": 50, "start_gold": 20, "max_ability_rank": 3,
}

# --- Effets composables -------------------------------------------------------

def dmg(dice, bonus=0, element=None, stat=None):
    e = {"type": "damage", "dice": dice}
    if bonus: e["bonus"] = bonus
    if element: e["element"] = element
    if stat: e["stat"] = stat
    return e

def heal(dice, bonus=0, on="target"):
    e = {"type": "heal", "dice": dice, "on": on}
    if bonus: e["bonus"] = bonus
    return e

def st(status, turns, chance=100, value=0, on="target"):
    e = {"type": "status", "status": status, "turns": turns}
    if chance != 100: e["chance"] = chance
    if value: e["value"] = value
    if on != "target": e["on"] = on
    return e

def shield(amount, turns=2, on="target"):
    return {"type": "status", "status": "bouclier", "turns": turns, "value": amount, "on": on}

def restore(resource, amount, on="self"):
    return {"type": "restore", "resource": resource, "amount": amount, "on": on}

def cleanse(count=1, on="target"):
    return {"type": "cleanse", "count": count, "on": on}

def push(cells):
    return {"type": "push", "cells": cells}

def pull(cells):
    return {"type": "pull", "cells": cells}

def ap(amount, on="target"):
    return {"type": "ap", "amount": amount, "on": on}

def statmod(stat, amount, turns, on="target"):
    return {"type": "stat", "stat": stat, "amount": amount, "turns": turns, "on": on}

def iff(cond, then, else_=None):
    e = {"type": "if", "cond": cond, "then": then}
    if else_: e["else"] = else_
    return e

def drain(pct):
    return {"type": "drain", "pct": pct}

def summon(name, hp, attack="1d6", defense=10, color="#9fc3d4"):
    return {"type": "summon", "name": name, "hp": hp, "attack": attack, "defense": defense, "color": color}

def narrate(text):
    return {"type": "narrate", "text": text}


ABILITIES = {}


def ab(id_, name, icon, desc, cost, ap_, rng, target, effects, stat, cooldown=0, roll=None, element="physique",
       radius=0, ultimate=False, cond=None, short=""):
    if roll is None:
        roll = "attack" if target in ("enemy", "area_enemy") and any(e["type"] == "damage" for e in effects) else "none"
    a = {"id": id_, "name": name, "short": short or name, "icon": icon, "description": desc,
         "cost": cost, "ap": ap_, "range": rng, "cooldown": cooldown, "target": target, "radius": radius,
         "roll": roll, "stat": stat, "element": element, "effects": effects, "ultimate": ultimate}
    if cond:
        a["conditions"] = cond
    ABILITIES[id_] = a
    return id_


# --- Effets de statut ---------------------------------------------------------

STATUSES = [
    {"id": "etourdi", "name": "Étourdi", "icon": "spiral", "color": "#e0c35a", "kind": "debuff",
     "description": "Perd son prochain tour.", "flags": ["stun"]},
    {"id": "immobilise", "name": "Immobilisé", "icon": "chain", "color": "#9a8f7a", "kind": "debuff",
     "description": "Ne peut pas se déplacer.", "flags": ["root"]},
    {"id": "silence", "name": "Réduit au silence", "icon": "mask", "color": "#8a7fa8", "kind": "debuff",
     "description": "Ne peut pas utiliser de capacité.", "flags": ["silence"]},
    {"id": "poison", "name": "Empoisonné", "icon": "drop", "color": "#7fb05a", "kind": "debuff",
     "description": "Perd 1d4 PV au début de chaque tour (+ valeur).", "tick": {"type": "damage", "dice": "1d4"}},
    {"id": "saignement", "name": "Saignement", "icon": "drop", "color": "#c25050", "kind": "debuff",
     "description": "Perd 1d6 PV au début de chaque tour.", "tick": {"type": "damage", "dice": "1d6"}},
    {"id": "brulure", "name": "Brûlure", "icon": "fire", "color": "#e07a3a", "kind": "debuff",
     "description": "Perd 1d6 PV au début de chaque tour.", "tick": {"type": "damage", "dice": "1d6"}},
    {"id": "gel", "name": "Gelé", "icon": "ice", "color": "#9fc3d4", "kind": "debuff",
     "description": "−2 vitesse et −1 PA.", "mods": {"speed": -2, "ap": -1}},
    {"id": "affaibli", "name": "Affaibli", "icon": "fist", "color": "#8a7a6a", "kind": "debuff",
     "description": "−2 aux dégâts infligés.", "mods": {"damage": -2}},
    {"id": "vulnerable", "name": "Vulnérable", "icon": "target", "color": "#d27a6a", "kind": "debuff",
     "description": "−2 Défense et subit +2 dégâts.", "mods": {"defense": -2, "damage_taken": 2}},
    {"id": "marque", "name": "Marqué", "icon": "target", "color": "#c9a96e", "kind": "debuff",
     "description": "Subit +3 dégâts des attaques.", "mods": {"damage_taken": 3}},
    {"id": "aveugle", "name": "Aveuglé", "icon": "eye", "color": "#6a6a6a", "kind": "debuff",
     "description": "−4 au toucher.", "mods": {"to_hit": -4}},
    {"id": "effraye", "name": "Effrayé", "icon": "skull", "color": "#7a6a8a", "kind": "debuff",
     "description": "−2 au toucher et −1 Défense.", "mods": {"to_hit": -2, "defense": -1}},
    {"id": "bouclier", "name": "Bouclier", "icon": "ward", "color": "#7fa8d4", "kind": "buff",
     "description": "Absorbe des dégâts (valeur) avant les PV.", "flags": ["shield"]},
    {"id": "protege", "name": "En garde", "icon": "shield", "color": "#c9a96e", "kind": "buff",
     "description": "+3 Défense.", "mods": {"defense": 3}},
    {"id": "renforce", "name": "Renforcé", "icon": "fist", "color": "#d1a15e", "kind": "buff",
     "description": "+2 aux dégâts.", "mods": {"damage": 2}},
    {"id": "beni", "name": "Béni", "icon": "star", "color": "#f0d78c", "kind": "buff",
     "description": "+1 au toucher et +1 aux dégâts.", "mods": {"to_hit": 1, "damage": 1}},
    {"id": "concentre", "name": "Concentré", "icon": "eye", "color": "#a07cc9", "kind": "buff",
     "description": "+2 au toucher.", "mods": {"to_hit": 2}},
    {"id": "hate", "name": "Hâte", "icon": "wind", "color": "#8fd4c0", "kind": "buff",
     "description": "+1 PA et +2 vitesse.", "mods": {"ap": 1, "speed": 2}},
    {"id": "regeneration", "name": "Régénération", "icon": "leaf", "color": "#8fb28a", "kind": "buff",
     "description": "Récupère 1d6 PV au début de chaque tour.", "tick": {"type": "heal", "dice": "1d6"}},
    {"id": "invisible", "name": "Invisible", "icon": "mask", "color": "#5a5a7a", "kind": "buff",
     "description": "Ne peut pas être ciblé ; +2 au toucher. Prend fin en attaquant.", "flags": ["untargetable", "break_on_attack"], "mods": {"to_hit": 2}},
    {"id": "rage", "name": "Rage", "icon": "fire", "color": "#c25050", "kind": "buff",
     "description": "+3 dégâts, −2 Défense.", "mods": {"damage": 3, "defense": -2}},
    {"id": "forme_bestiale", "name": "Forme bestiale", "icon": "paw", "color": "#7b5a3a", "kind": "buff",
     "description": "+2 Force, +2 vitesse, +2 dégâts.", "mods": {"Force": 2, "speed": 2, "damage": 2}},
    {"id": "modifie", "name": "Modifié", "icon": "sparkle", "color": "#a07cc9", "kind": "buff",
     "description": "Caractéristique modifiée temporairement."},
]

# --- Objets -------------------------------------------------------------------

ITEMS = {}


def item(id_, name, icon, category, rarity, desc, value=5, slot="", weapon=None, mods=None, use=None,
         on_hit=None, grants=None, teaches="", unique=False, stack=False):
    i = {"id": id_, "name": name, "icon": icon, "category": category, "rarity": rarity, "description": desc,
         "value": value, "slot": slot, "stackable": stack or category in ("consommable", "potion", "materiau"), "unique": unique}
    if weapon: i["weapon"] = weapon
    if mods: i["mods"] = mods
    if use: i["use"] = use
    if on_hit: i["on_hit"] = on_hit
    if grants: i["grants"] = grants
    if teaches: i["teaches"] = teaches
    ITEMS[id_] = i
    return id_


def wpn(damage, stat, crit=20, rng=1, element="physique"):
    return {"damage": damage, "stat": stat, "crit": crit, "range": rng, "element": element}


def weapon(id_, name, icon, rarity, desc, w, value=10, mods=None, on_hit=None, grants=None, unique=False):
    return item(id_, name, icon, "arme", rarity, desc, value, "arme", w, mods, None, on_hit, grants, "", unique)


def armor(id_, name, icon, rarity, desc, mods, value=10, slot="armure", category="armure"):
    return item(id_, name, icon, category, rarity, desc, value, slot, None, mods)


def acc(id_, name, icon, rarity, desc, mods=None, value=15, on_hit=None, grants=None, unique=False):
    return item(id_, name, icon, "accessoire", rarity, desc, value, "accessoire", None, mods, None, on_hit, grants, "", unique)


def potion(id_, name, icon, rarity, desc, use, value=8, category="potion"):
    return item(id_, name, icon, category, rarity, desc, value, "", None, None, use)


def material(id_, name, icon, rarity, desc, value=3):
    return item(id_, name, icon, "materiau", rarity, desc, value)


# Armes communes
weapon("epee_longue", "Épée longue", "sword", "commun", "Fiable et équilibrée.", wpn("1d8", "Force", 19), 15)
weapon("hache_guerre", "Hache de guerre", "axe", "commun", "Lourde : gros dégâts.", wpn("1d12", "Force"), 15)
weapon("marteau_armes", "Marteau d'armes", "hammer", "peu_commun", "Chaque coup peut étourdir (15 %).", wpn("1d10", "Force"), 25,
       on_hit=[st("etourdi", 1, 15)])
weapon("lance", "Lance", "spear", "commun", "Frappe à 2 cases.", wpn("1d8", "Force", 20, 2), 12)
weapon("dague", "Dague", "dagger", "commun", "Légère et précise.", wpn("1d4", "Dextérité", 19), 6)
weapon("dague_courbe", "Dague courbe", "dagger", "commun", "Critique sur 17-20.", wpn("1d4", "Dextérité", 17), 15)
weapon("kunai_jumeaux", "Kunai jumeaux", "dagger", "commun", "Se lancent jusqu'à 3 cases.", wpn("1d6", "Dextérité", 19, 3), 15)
weapon("stylet_empoisonne", "Stylet empoisonné", "dagger", "peu_commun", "25 % d'empoisonner la cible (3 tours).", wpn("1d4", "Dextérité", 19), 25,
       on_hit=[st("poison", 3, 25)])
weapon("arc_long", "Arc long", "bow", "commun", "Portée 8.", wpn("1d8", "Dextérité", 20, 8), 15)
weapon("arbalete", "Arbalète", "crossbow", "commun", "Portée 6, critique 19-20.", wpn("1d10", "Dextérité", 19, 6), 18)
weapon("arc_court", "Arc court", "bow", "commun", "Portée 6, léger.", wpn("1d6", "Dextérité", 19, 6), 10)
weapon("baton_chene", "Bâton de chêne", "staff", "commun", "Augmente la réserve de mana (+4).", wpn("1d6", "Force", 20, 1), 10, {"res_max": 4})
weapon("baguette_braise", "Baguette de braise", "wand", "commun", "Projette des braises (portée 5, magique).", wpn("1d6", "Intelligence", 20, 5, "magique"), 15)
weapon("masse_benie", "Masse bénie", "hammer", "commun", "+10 % aux soins prodigués.", wpn("1d6", "Force"), 12, {"heal_pct": 10})
weapon("rapiere", "Rapière", "sword", "commun", "Fine et rapide.", wpn("1d6", "Dextérité", 18), 14)
weapon("luth_lame", "Luth à lame", "lute", "peu_commun", "Instrument… et arme (+1 Charisme).", wpn("1d6", "Dextérité"), 25, {"Charisme": 1})
weapon("griffes_acier", "Griffes d'acier", "claw", "commun", "Deux attaques rapides.", wpn("1d6", "Force", 19), 12)
# Armes rares et plus
weapon("lame_runique", "Lame runique", "sword", "rare", "+1 au toucher, dégâts magiques.", wpn("1d10", "Force", 19, 1, "magique"), 80, {"to_hit": 1})
weapon("arc_du_vent", "Arc du vent", "bow", "rare", "Portée 10, +1 vitesse.", wpn("1d10", "Dextérité", 19, 10), 80, {"speed": 1})
weapon("croc_vampirique", "Croc vampirique", "dagger", "epique", "Rend 30 % des dégâts infligés en PV.", wpn("1d6", "Dextérité", 18), 150,
       on_hit=[drain(30)])
weapon("baton_tempete", "Bâton des tempêtes", "staff", "epique", "Accorde la capacité « Éclair en chaîne ».", wpn("1d8", "Intelligence", 20, 5, "magique"), 160,
       {"res_max": 6}, grants=["eclair_chaine"])
weapon("brise_monde", "Brise-Monde", "hammer", "legendaire", "Marteau d'un héros oublié. 30 % d'étourdir, +2 Force.", wpn("2d8", "Force", 19), 500,
       {"Force": 2}, on_hit=[st("etourdi", 1, 30)], unique=True)

# Armures et accessoires
armor("armure_cuir", "Armure de cuir", "armor", "commun", "Légère.", {"defense": 1, "resist_phys": 1}, 10)
armor("cotte_mailles", "Cotte de mailles", "armor", "commun", "Bonne protection, −1 vitesse.", {"defense": 3, "resist_phys": 2, "speed": -1}, 25)
armor("harnois", "Harnois", "armor", "peu_commun", "Plates complètes, −1 vitesse.", {"defense": 4, "resist_phys": 3, "speed": -1}, 60)
armor("robe_mage", "Robe d'apprenti", "robe", "commun", "+4 mana, résistance magique +1.", {"res_max": 4, "resist_mag": 1}, 10)
armor("robe_archimage", "Robe d'archimage", "robe", "rare", "+8 mana, +2 résistance magique.", {"res_max": 8, "resist_mag": 2, "defense": 1}, 90)
armor("cape_ombre", "Cape d'ombre", "cloak", "peu_commun", "+1 Défense, +1 Dextérité.", {"defense": 1, "Dextérité": 1}, 35)
armor("bouclier_bois", "Bouclier de bois", "shield", "commun", "+2 Défense.", {"defense": 2}, 8, "accessoire", "armure")
armor("pavois", "Pavois", "shield", "peu_commun", "+3 Défense, +1 résistance physique.", {"defense": 3, "resist_phys": 1}, 30, "accessoire", "armure")
acc("anneau_force", "Anneau de force", "ring", "peu_commun", "+1 Force.", {"Force": 1}, 40)
acc("anneau_esprit", "Anneau de clarté", "ring", "peu_commun", "+1 Esprit.", {"Esprit": 1}, 40)
acc("amulette_vie", "Amulette de vie", "amulet", "rare", "+10 PV max.", {"hp_max": 10}, 90)
acc("talisman_garde", "Talisman de garde", "amulet", "peu_commun", "+1 résistance physique et magique.", {"resist_phys": 1, "resist_mag": 1}, 45)
acc("bottes_vent", "Bottes de vent", "boots", "rare", "+2 vitesse.", {"speed": 2}, 70)
acc("oeil_faucon", "Œil de faucon", "eye", "rare", "+2 au toucher à distance (et partout).", {"to_hit": 2}, 90)
acc("grimoire_poche", "Grimoire de poche", "book", "commun", "+4 mana.", {"res_max": 4}, 20)
acc("couronne_epines", "Couronne d'épines", "crown", "epique", "+3 dégâts mais −5 PV max.", {"damage": 3, "hp_max": -5}, 150)
acc("pendentif_phenix", "Pendentif du phénix", "amulet", "legendaire", "Une fois par combat, accorde « Renaissance ».", {"hp_max": 5}, 400,
    grants=["renaissance"], unique=True)

# Outils et lumière (équipement de départ, voir STARTER_KIT)
acc("torche", "Torche", "fire", "commun", "Éclaire autour de vous : +2 cases de vision (accessoire).", {"vision": 2}, 2)
acc("lanterne", "Lanterne sourde", "sun", "peu_commun", "Lumière stable : +3 cases de vision (accessoire).", {"vision": 3}, 25)
item("corde", "Corde (15 m)", "chain", "outil", "commun", "Pour grimper, attacher, descendre dans un puits… Le MJ décide de ce qu'elle permet.", 2)
item("crochets", "Outils de crochetage", "key", "outil", "commun", "Ouvrir serrures et coffres (épreuve de Dextérité, au choix du MJ).", 10)
item("sac_couchage", "Sac de couchage", "bag", "outil", "commun", "Repos plus confortable en pleine nature.", 2)
potion("trousse_soins", "Trousse de soins", "cross", "commun", "Bandages et onguents : rend 1d4 + 3 PV.", [heal("1d4", 3, "self")], 5, "consommable")

# Consommables
potion("potion_soin", "Potion de soin", "potion", "commun", "Rend 2d6+2 PV.", [heal("2d6", 2, "self")], 10)
potion("potion_soin_sup", "Potion de soin supérieure", "potion", "peu_commun", "Rend 4d6+4 PV.", [heal("4d6", 4, "self")], 30)
potion("potion_mana", "Potion de mana", "flask", "commun", "Rend 8 points de ressource.", [restore("res", 8, "self")], 12)
potion("elixir_force", "Élixir de force", "flask", "peu_commun", "+2 Force pendant 3 tours.", [statmod("Force", 2, 3, "self")], 25)
potion("elixir_hate", "Élixir de hâte", "flask", "rare", "Hâte pendant 2 tours (+1 PA).", [st("hate", 2, on="self")], 60)
potion("antidote", "Antidote", "flask", "commun", "Retire poison et saignement.", [cleanse(2, "self")], 8)
potion("ration", "Ration de voyage", "food", "commun", "Rend 1d6 PV.", [heal("1d6", 0, "self")], 2, "consommable")
potion("bombe_fumee", "Bombe fumigène", "bomb", "commun", "Invisible pendant 1 tour.", [st("invisible", 1, on="self")], 15, "consommable")
potion("parchemin_feu", "Parchemin de feu", "scroll", "peu_commun", "Brûle tous ceux qui vous entourent (2d6).", [narrate("Le parchemin s'embrase !")], 30, "consommable")
# Matériaux, quête, livres, uniques
material("cuir_brut", "Cuir brut", "leather", "commun", "À vendre ou à travailler.")
material("croc_loup", "Croc de loup", "fang", "commun", "Trophée de chasse.")
material("herbes_medicinales", "Herbes médicinales", "herb", "commun", "Un soigneur saura en faire quelque chose.")
material("minerai_fer", "Minerai de fer", "ore", "commun", "Pour un forgeron.")
material("gemme_brute", "Gemme brute", "gem", "peu_commun", "Se vend bien.", 25)
material("ecaille_dragon", "Écaille de dragon", "scale", "epique", "Matériau légendaire pour une armure.", 120)
item("cle_rouillee", "Clé rouillée", "key", "quete", "commun", "Ouvre quelque chose, quelque part…", 0)
item("lettre_scellee", "Lettre scellée", "scroll", "quete", "peu_commun", "Le sceau n'est pas brisé.", 0)
item("carte_tresor", "Carte au trésor", "map", "quete", "rare", "Une croix rouge sur une île inconnue.", 0)
item("livre_boule_feu", "Grimoire : Boule de feu", "book", "livre", "rare", "Apprend la capacité « Boule de feu ».", 120, teaches="boule_de_feu")
item("livre_second_souffle", "Manuel : Second souffle", "book", "livre", "peu_commun", "Apprend la capacité « Second souffle ».", 60, teaches="second_souffle")
item("livre_premiers_soins", "Traité : Premiers soins", "book", "livre", "commun", "Apprend la capacité « Premiers soins ».", 30, teaches="premiers_soins")

# Capacités communes (apprenables par tous via livres, MJ, entraînement)
ab("boule_de_feu", "Boule de feu", "fire", "Explose sur une zone (rayon 1) : 3d6 dégâts magiques, brûlure possible.", 6, 2, 6, "area_enemy",
   [dmg("3d6", element="magique"), st("brulure", 2, 30)], "Intelligence", 2, element="magique", radius=1)
ab("second_souffle", "Second souffle", "heart", "Récupère 1d10 + Constitution PV.", 3, 1, 0, "self", [heal("1d10", 0, "self")], "Constitution", 3)
ab("premiers_soins", "Premiers soins", "cross", "Soigne un allié au contact (1d8 + Esprit).", 2, 1, 1, "ally", [heal("1d8")], "Esprit", 1)
ab("eclair_chaine", "Éclair en chaîne", "bolt", "Frappe une zone (rayon 1) : 2d8 dégâts magiques.", 6, 2, 6, "area_enemy", [dmg("2d8", element="magique")],
   "Intelligence", 2, element="magique", radius=1)
ab("renaissance", "Renaissance", "phoenix", "Une fois par combat : rend 50 % des PV et retire tous les effets négatifs.", 0, 1, 0, "self",
   [heal("6d6", 0, "self"), cleanse(5, "self")], "Constitution", 99)

# --- Classes ------------------------------------------------------------------

def passive(name, desc, trigger, icon="star", cond=None, mods=None, effects=None, reduce=0, rng=0):
    p = {"name": name, "description": desc, "trigger": trigger, "icon": icon}
    if cond: p["cond"] = cond
    if mods: p["mods"] = mods
    if effects: p["effects"] = effects
    if reduce: p["reduce"] = reduce
    if rng: p["range"] = rng
    return p


def klass(id_, name, tagline, role, color, emblem, description, bonus, hp, hp_lvl, res_name, res_stat, res_base, speed,
          passive_, abilities, ultimate, learnable, kit, choices, recommended, crit_bonus=0, defense_bonus=0, attack_bonus=0,
          magic=None, difficulty=1):
    assert sum(recommended.values()) == RULES["stat_pool"], (id_, sum(recommended.values()))
    return {
        "id": id_, "name": name, "tagline": tagline, "role": role, "color": color, "emblem": emblem,
        "description": description, "difficulty": difficulty, "bonus": bonus, "hp_base": hp, "hp_per_level": hp_lvl,
        "resource": {"name": res_name, "stat": res_stat, "base": res_base}, "speed": speed,
        "crit_bonus": crit_bonus, "defense_bonus": defense_bonus, "attack_bonus": attack_bonus,
        "passive": passive_, "abilities": abilities, "ultimate": ultimate, "learnable": learnable,
        "kit": kit, "choices": choices, "recommended": recommended, "magic": magic or {},
    }


def rec(**kw):
    out = {s["name"]: 0 for s in STATS}
    names = {"FOR": "Force", "DEX": "Dextérité", "CON": "Constitution", "INT": "Intelligence", "ESP": "Esprit", "CHA": "Charisme"}
    for k, v in kw.items():
        out[names[k]] = v
    return out


def kit(*pairs):
    return [{"item": i, "qty": q, "equip": e} for i, q, e in pairs]


def choice(title, *ids):
    return {"title": title, "options": list(ids)}


FANTASY = [
    klass("guerrier", "Guerrier", "Lame, bouclier et courage.", "Combattant au contact", "#b0605a", "sword",
          "Robuste et polyvalent, il encaisse les coups en première ligne et frappe fort. Idéal pour débuter.",
          {"Force": 1, "Constitution": 1}, 20, 6, "Vigueur", "Constitution", 6, 5,
          passive("Inébranlable", "Sous 50 % de ses PV : +2 Défense et +2 dégâts.", "always", "shield", {"self_hp_below": 50}, {"defense": 2, "damage": 2}),
          [ab("frappe_puissante", "Frappe puissante", "sword", "Un coup de toute sa force : 2d8 + Force.", 3, 1, 1, "enemy", [dmg("2d8")], "Force", short="Frappe"),
           ab("cri_guerre", "Cri de guerre", "horn", "Vous et vos alliés à 2 cases : Renforcé (+2 dégâts) pendant 2 tours.", 4, 1, 0, "area_ally",
              [st("renforce", 2)], "Charisme", 3, radius=2, short="Cri"),
           ab("charge", "Charge", "boots", "Fonce sur une cible à 4 cases : 1d8 + Force, 50 % de l'étourdir.", 4, 2, 4, "enemy",
              [dmg("1d8"), st("etourdi", 1, 50)], "Force", 2)],
          ab("tourbillon_acier", "Tourbillon d'acier", "spiral", "ULTIME : frappe tous les ennemis autour de vous (rayon 1) : 3d8 + Force.", 0, 2, 0, "area_enemy",
             [dmg("3d8")], "Force", radius=1, ultimate=True, short="Tourbillon"),
          [{"ability": ab("second_souffle_g", "Second souffle", "heart", "Récupère 1d10 + Constitution PV.", 3, 1, 0, "self", [heal("1d10", 0, "self")], "Constitution", 3), "level": 2},
           {"ability": ab("brise_armure", "Brise-armure", "hammer", "1d8 + Force et rend la cible Vulnérable 2 tours.", 3, 1, 1, "enemy", [dmg("1d8"), st("vulnerable", 2)], "Force", 2), "level": 3},
           {"ability": ab("provocation", "Défi", "shield", "Vous gagnez En garde (+3 Défense) 2 tours ; un ennemi à 3 cases est Affaibli.", 2, 1, 3, "enemy",
                          [st("affaibli", 2), st("protege", 2, on="self")], "Charisme", 2, roll="none"), "level": 4}],
          kit(("armure_cuir", 1, True), ("potion_soin", 2, False)),
          [choice("Votre arme", "epee_longue", "hache_guerre", "marteau_armes")],
          rec(FOR=4, DEX=2, CON=4, INT=0, ESP=2, CHA=3)),
    klass("mage", "Mage", "Les arcanes au bout des doigts.", "Attaque magique à distance", "#6f9fc9", "staff",
          "Fragile mais redoutable à distance : sorts de zone, contrôle et bouclier magique.",
          {"Intelligence": 2}, 10, 4, "Mana", "Intelligence", 12, 5,
          passive("Flux arcanique", "Quand un de vos sorts touche, récupère 2 mana.", "on_hit", "spiral", {"element": "magique"}, effects=[restore("res", 2, "self")]),
          [ab("trait_feu", "Trait de feu", "fire", "2d6 + Intelligence dégâts magiques à 6 cases, 30 % de brûlure.", 3, 1, 6, "enemy",
              [dmg("2d6", element="magique"), st("brulure", 2, 30)], "Intelligence", element="magique", short="Feu"),
           ab("bouclier_arcanique", "Bouclier arcanique", "ward", "Un allié à 4 cases (ou vous) gagne un bouclier de 6 + Intelligence pendant 2 tours.", 4, 1, 4, "ally",
              [{"type": "status", "status": "bouclier", "turns": 2, "value": 6, "scale": "Intelligence"}], "Intelligence", 2, element="magique", short="Bouclier"),
           ab("gel", "Étreinte du givre", "ice", "1d6 + Intelligence dégâts magiques et Immobilisé 1 tour.", 4, 1, 5, "enemy",
              [dmg("1d6", element="magique"), st("immobilise", 1)], "Intelligence", 1, element="magique", short="Givre")],
          ab("meteore", "Météore", "meteor", "ULTIME : zone de rayon 2 à 6 cases : 4d6 + Intelligence dégâts magiques et brûlure.", 0, 2, 6, "area_enemy",
             [dmg("4d6", element="magique"), st("brulure", 2)], "Intelligence", radius=2, ultimate=True, element="magique"),
          [{"ability": "boule_de_feu", "level": 2},
           {"ability": ab("teleportation", "Pas de l'ombre", "spiral", "Vous gagnez Hâte (+1 PA, +2 vitesse) pendant 1 tour.", 3, 1, 0, "self", [st("hate", 1, on="self")], "Intelligence", 3, element="magique"), "level": 3},
           {"ability": "eclair_chaine", "level": 5}],
          kit(("robe_mage", 1, True), ("potion_mana", 2, False)),
          [choice("Votre focaliseur", "baton_chene", "baguette_braise", "grimoire_poche")],
          rec(FOR=0, DEX=3, CON=3, INT=5, ESP=4, CHA=0)),
    klass("assassin", "Assassin", "Frapper vite, frapper juste, disparaître.", "Dégâts et critiques", "#4a4358", "dagger",
          "Mobile et létal : critiques fréquents, poison, et achève les cibles affaiblies.",
          {"Dextérité": 2}, 14, 4, "Concentration", "Dextérité", 8, 6,
          passive("Coup de grâce", "+1d6 dégâts contre une cible sous 50 % de ses PV ou affectée par un effet négatif.", "always", "skull",
                  {"target_weak": True}, {"damage_dice": "1d6"}),
          [ab("attaque_sournoise", "Attaque sournoise", "dagger", "2d6 + Dextérité, +2 au toucher.", 3, 1, 1, "enemy", [dmg("2d6")], "Dextérité", short="Sournoise"),
           ab("lame_empoisonnee", "Lame empoisonnée", "drop", "1d6 + Dextérité et Empoisonné 3 tours.", 3, 1, 1, "enemy", [dmg("1d6"), st("poison", 3)], "Dextérité", 1, short="Poison"),
           ab("disparition", "Disparition", "mask", "Devient Invisible 1 tour (impossible à cibler, +2 au toucher).", 4, 1, 0, "self",
              [st("invisible", 1, on="self")], "Dextérité", 3)],
          ab("danse_lames", "Danse des lames", "dagger", "ULTIME : 5d6 + Dextérité sur une cible et Saignement 3 tours.", 0, 2, 1, "enemy",
             [dmg("5d6"), st("saignement", 3)], "Dextérité", ultimate=True, short="Danse"),
          [{"ability": ab("lancer_couteaux", "Pluie de couteaux", "dagger", "Zone de rayon 1 à 4 cases : 2d4 + Dextérité.", 3, 1, 4, "area_enemy", [dmg("2d4")], "Dextérité", 2, radius=1), "level": 2},
           {"ability": ab("marque_mort", "Marque de mort", "target", "La cible est Marquée (+3 dégâts subis) pendant 3 tours.", 2, 1, 6, "enemy", [st("marque", 3)], "Dextérité", 2, roll="none"), "level": 3}],
          kit(("armure_cuir", 1, True), ("bombe_fumee", 1, False)),
          [choice("Votre dague", "dague_courbe", "kunai_jumeaux", "stylet_empoisonne")],
          rec(FOR=1, DEX=5, CON=3, INT=1, ESP=2, CHA=3), crit_bonus=1),
    klass("gardien", "Gardien", "Le bouclier du groupe.", "Protection", "#8a8f9a", "shield",
          "Protège ses alliés : boucliers, réduction des dégâts, et une défense de forteresse.",
          {"Constitution": 2}, 22, 7, "Vigueur", "Constitution", 6, 4,
          passive("Rempart", "Un allié à 1 case qui subit des dégâts en subit 3 de moins.", "ally_damaged", "shield", reduce=3, rng=1),
          [ab("coup_bouclier", "Coup de bouclier", "shield", "1d6 + Force et 60 % d'étourdir.", 3, 1, 1, "enemy", [dmg("1d6"), st("etourdi", 1, 60)], "Force", 2, short="Bouclier"),
           ab("mur_boucliers", "Mur de boucliers", "ward", "Vous et vos alliés à 1 case : bouclier de 6 pendant 2 tours.", 4, 1, 0, "area_ally",
              [shield(6, 2)], "Constitution", 2, radius=1, short="Mur"),
           ab("interposition", "Interposition", "shield", "Un allié à 4 cases gagne En garde (+3 Défense) et un bouclier de 8.", 3, 1, 4, "ally",
              [st("protege", 2), shield(8, 2)], "Constitution", 2)],
          ab("forteresse", "Forteresse", "castle", "ULTIME : tous les alliés à 2 cases : bouclier de 15 et En garde pendant 2 tours.", 0, 2, 0, "area_ally",
             [shield(15, 2), st("protege", 2)], "Constitution", radius=2, ultimate=True),
          [{"ability": ab("provoc_gardien", "Provocation", "horn", "Un ennemi à 3 cases est Affaibli 2 tours ; vous gagnez un bouclier de 5.", 2, 1, 3, "enemy",
                          [st("affaibli", 2), shield(5, 2, "self")], "Charisme", 2, roll="none"), "level": 2},
           {"ability": "second_souffle", "level": 3}],
          kit(("cotte_mailles", 1, True), ("potion_soin", 1, False)),
          [choice("Votre équipement", "pavois", "bouclier_bois", "lance")],
          rec(FOR=3, DEX=2, CON=5, INT=0, ESP=3, CHA=2), defense_bonus=1),
    klass("soigneur", "Soigneur", "Garde le groupe debout.", "Soin et soutien", "#8fb28a", "heart",
          "Soigne, purifie et protège. Indispensable dans les longs combats.",
          {"Esprit": 2}, 14, 5, "Mana", "Esprit", 12, 5,
          passive("Bénédiction", "Vos soins sont 50 % plus efficaces.", "always", "heart", None, {"heal_pct": 50}),
          [ab("soin", "Soin", "heart", "Un allié à 4 cases récupère 2d8 + Esprit PV.", 3, 1, 4, "ally", [heal("2d8")], "Esprit", element="soin"),
           ab("purification", "Purification", "sparkle", "Retire 2 effets négatifs et donne Régénération 2 tours.", 3, 1, 4, "ally",
              [cleanse(2), st("regeneration", 2)], "Esprit", 2, element="soin"),
           ab("lumiere_sacree", "Lumière sacrée", "sun", "2d6 + Esprit dégâts magiques à 5 cases, 30 % d'aveugler.", 3, 1, 5, "enemy",
              [dmg("2d6", element="magique"), st("aveugle", 1, 30)], "Esprit", element="magique", short="Lumière")],
          ab("aube", "Aube nouvelle", "sun", "ULTIME : tous les alliés à 3 cases récupèrent 3d8 + Esprit PV (même à 0 PV) et sont purifiés.", 0, 2, 0, "area_ally",
             [heal("3d8"), cleanse(3)], "Esprit", radius=3, ultimate=True, element="soin"),
          [{"ability": ab("benediction_groupe", "Bénédiction", "star", "Vous et vos alliés à 2 cases : Béni 2 tours.", 3, 1, 0, "area_ally", [st("beni", 2)], "Charisme", 2, radius=2), "level": 2},
           {"ability": ab("sanctuaire", "Sanctuaire", "ward", "Un allié gagne un bouclier de 10 et Régénération 3 tours.", 5, 2, 4, "ally", [shield(10, 2), st("regeneration", 3)], "Esprit", 3), "level": 4}],
          kit(("robe_mage", 1, True), ("herbes_medicinales", 3, False)),
          [choice("Votre arme", "masse_benie", "baton_chene", "talisman_garde")],
          rec(FOR=1, DEX=2, CON=3, INT=1, ESP=5, CHA=3)),
    klass("rodeur", "Rôdeur", "Archer et pisteur des terres sauvages.", "Tir à distance", "#7f9a5a", "bow",
          "Frappe de loin, ralentit ses proies et domine le terrain.",
          {"Dextérité": 1, "Esprit": 1}, 16, 5, "Concentration", "Dextérité", 8, 6,
          passive("Œil de faucon", "À 3 cases ou plus de sa cible : +2 au toucher et +2 dégâts.", "always", "eye", {"distance_min": 3}, {"to_hit": 2, "damage": 2}),
          [ab("tir_precis", "Tir précis", "arrow", "1d10 + Dextérité à 8 cases, +2 au toucher.", 2, 1, 8, "enemy", [dmg("1d10")], "Dextérité", short="Tir"),
           ab("fleche_entravante", "Flèche entravante", "chain", "1d6 + Dextérité et Immobilisé 1 tour.", 3, 1, 8, "enemy", [dmg("1d6"), st("immobilise", 1)], "Dextérité", 2, short="Entrave"),
           ab("marque_chasseur", "Marque du chasseur", "target", "La cible est Marquée (+3 dégâts subis) pendant 3 tours.", 2, 1, 10, "enemy",
              [st("marque", 3)], "Esprit", 2, roll="none", short="Marque")],
          ab("pluie_fleches", "Pluie de flèches", "arrow", "ULTIME : zone de rayon 2 à 8 cases : 3d6 + Dextérité.", 0, 2, 8, "area_enemy",
             [dmg("3d6")], "Dextérité", radius=2, ultimate=True, short="Pluie"),
          [{"ability": ab("compagnon_loup", "Compagnon loup", "paw", "Appelle un loup (12 PV, 1d6) à vos côtés.", 5, 2, 1, "self",
                          [summon("Loup compagnon", 12, "1d6", 12, "#9a9a9a")], "Esprit", 5), "level": 3},
           {"ability": ab("tir_double", "Tir double", "arrow", "Deux flèches : 2 × (1d8 + Dextérité).", 4, 2, 8, "enemy", [dmg("1d8"), dmg("1d8")], "Dextérité", 2), "level": 4}],
          kit(("armure_cuir", 1, True), ("ration", 3, False)),
          [choice("Votre arme", "arc_long", "arbalete", "arc_court")],
          rec(FOR=1, DEX=5, CON=3, INT=1, ESP=4, CHA=1)),
    klass("barde", "Barde", "Charme, musique et répliques cinglantes.", "Soutien et contrôle", "#d27aa0", "lute",
          "Inspire le groupe, déstabilise les ennemis. Brille autant en combat qu'en discussion.",
          {"Charisme": 2}, 13, 4, "Inspiration", "Charisme", 10, 5,
          passive("Mélodie entraînante", "Au début de votre tour, vous et vos alliés à 2 cases êtes Bénis (1 tour).", "turn_start", "music",
                  effects=[{"type": "status", "status": "beni", "turns": 1, "on": "allies", "radius": 2}]),
          [ab("chant_courage", "Chant de courage", "music", "Vous et vos alliés à 3 cases : Renforcé 2 tours.", 3, 1, 0, "area_ally", [st("renforce", 2)], "Charisme", 2, radius=3, short="Courage"),
           ab("moquerie", "Moquerie cinglante", "mask", "1d6 + Charisme dégâts magiques et Affaibli 2 tours.", 2, 1, 5, "enemy",
              [dmg("1d6", element="magique"), st("affaibli", 2)], "Charisme", element="magique", short="Moquerie"),
           ab("berceuse", "Berceuse", "moon", "50 % d'étourdir une cible à 4 cases.", 3, 1, 4, "enemy", [st("etourdi", 1, 50)], "Charisme", 2, roll="none")],
          ab("ballade_heroique", "Ballade héroïque", "music", "ULTIME : alliés à 3 cases : 2d6 + Charisme PV, Renforcé et +1 PA.", 0, 2, 0, "area_ally",
             [heal("2d6"), st("renforce", 2), ap(1)], "Charisme", radius=3, ultimate=True, short="Ballade"),
          [{"ability": ab("dissonance", "Dissonance", "spiral", "Zone de rayon 1 à 5 cases : 1d8 dégâts magiques et Effrayé.", 4, 1, 5, "area_enemy",
                          [dmg("1d8", element="magique"), st("effraye", 2)], "Charisme", 2, radius=1, element="magique"), "level": 3}],
          kit(("armure_cuir", 1, True), ("potion_soin", 1, False)),
          [choice("Votre instrument", "luth_lame", "rapiere", "anneau_esprit")],
          rec(FOR=0, DEX=3, CON=3, INT=2, ESP=2, CHA=5)),
    klass("druide", "Druide", "Gardien des bêtes et des forêts.", "Invocateur et soutien", "#6f8f4a", "leaf",
          "Appelle des animaux à ses côtés, entrave ses ennemis avec des ronces et soigne avec la sève. Les bêtes se battent pour lui.",
          {"Esprit": 1, "Constitution": 1}, 16, 5, "Sève", "Esprit", 8, 5,
          passive("Lien sauvage", "Au début de votre tour, vous et vos alliés à 2 cases regagnez 1 PV.", "turn_start", "paw",
                  effects=[{"type": "heal", "amount": 1, "on": "allies", "radius": 2}]),
          [ab("appel_loup", "Appel du loup", "paw", "Un loup (14 PV, 1d6) surgit à vos côtés et se bat pour vous.", 4, 2, 1, "self",
              [summon("Loup", 14, "1d6", 12, "#9a9a9a")], "Esprit", 3, short="Loup"),
           ab("ronces", "Ronces", "leaf", "Des ronces jaillissent à 5 cases : 1d6 + Esprit et Immobilisé 1 tour.", 3, 1, 5, "enemy",
              [dmg("1d6", element="magique"), st("immobilise", 1)], "Esprit", 1, element="magique"),
           ab("seve_vitale", "Sève vitale", "herb", "Soigne un allié à 4 cases : 1d8 + Esprit, et Régénération 2 tours.", 3, 1, 4, "ally",
              [heal("1d8"), st("regeneration", 2)], "Esprit", 1, element="soin", short="Sève")],
          ab("fureur_sauvage", "Fureur sauvage", "dragon", "ULTIME : un ours-esprit (30 PV, 2d6) rejoint le combat ; vos alliés à 3 cases sont Renforcés.", 0, 2, 0, "self",
             [summon("Ours-esprit", 30, "2d6", 13, "#6b4a2a"), {"type": "status", "status": "renforce", "turns": 2, "on": "allies", "radius": 3}], "Esprit", ultimate=True, short="Fureur"),
          [{"ability": ab("peau_ecorce", "Peau d'écorce", "leaf", "Bouclier de 8 sur vous pendant 2 tours.", 2, 1, 0, "self", [shield(8, 2, "self")], "Constitution", 3), "level": 2},
           {"ability": ab("nuee", "Nuée d'insectes", "wind", "Zone de rayon 1 à 5 cases : 2d6 et 40 % d'empoisonner.", 4, 2, 5, "area_enemy",
                          [dmg("2d6"), st("poison", 3, 40)], "Esprit", 2, radius=1), "level": 3}],
          kit(("armure_cuir", 1, True), ("herbes_medicinales", 2, False)),
          [choice("Votre arme", "baton_chene", "lance", "arc_court")],
          rec(FOR=2, DEX=3, CON=3, INT=0, ESP=5, CHA=2), difficulty=2),
]

LEGENDERS = [
    klass("briseur", "Briseur", "Renforcement : se couvre d'une énergie qui décuple ses coups.", "Combattant au contact", "#b0605a", "fist",
          "Maître du renforcement : chaque coup est chargé de son vecteur (flammes, foudre, son…).",
          {"Force": 1, "Constitution": 1}, 20, 6, "AEC", "Constitution", 6, 5,
          passive("Surcharge", "Sous 50 % de ses PV : +3 dégâts.", "always", "fire", {"self_hp_below": 50}, {"damage": 3}),
          [ab("poing_elementaire", "Poing élémentaire", "fist", "2d8 + Force, 30 % de brûlure.", 3, 1, 1, "enemy", [dmg("2d8"), st("brulure", 2, 30)], "Force", short="Poing"),
           ab("charge_aec", "Charge d'AEC", "bolt", "Fonce à 4 cases : 1d8 + Force et 50 % d'étourdir.", 4, 2, 4, "enemy", [dmg("1d8"), st("etourdi", 1, 50)], "Force", 2, short="Charge"),
           ab("peau_renforcee", "Peau renforcée", "ward", "Bouclier de 8 + Constitution sur vous pendant 2 tours.", 3, 1, 0, "self",
              [{"type": "status", "status": "bouclier", "turns": 2, "value": 8, "scale": "Constitution", "on": "self"}], "Constitution", 2, short="Peau")],
          ab("explosion_vecteur", "Explosion de vecteur", "meteor", "ULTIME : tous les ennemis à 1 case : 3d10 + Force.", 0, 2, 0, "area_enemy",
             [dmg("3d10")], "Force", radius=1, ultimate=True, short="Explosion"),
          [{"ability": "second_souffle", "level": 2},
           {"ability": ab("rage_briseur", "Rage", "fire", "Vous entrez en Rage 3 tours (+3 dégâts, −2 Défense).", 2, 1, 0, "self", [st("rage", 3, on="self")], "Force", 4), "level": 3}],
          kit(("armure_cuir", 1, True), ("ration", 2, False)),
          [choice("Vos armes", "griffes_acier", "marteau_armes", "epee_longue")],
          rec(FOR=5, DEX=2, CON=4, INT=0, ESP=2, CHA=2),
          magic={"category": "Renforcement", "name": "Vecteur élémentaire", "description": "Se recouvre d'un élément pour décupler ses coups."}),
    klass("ombre", "Ombre", "Assassin des Faucheurs : silence, apnée, coups critiques.", "Dégâts et critiques", "#4a4358", "dagger",
          "Formée chez les Faucheurs : frappe dans le silence, devient intangible et achève les cibles affaiblies.",
          {"Dextérité": 2}, 14, 4, "AEC", "Dextérité", 8, 6,
          passive("Faucheuse", "+1d6 dégâts contre une cible sous 50 % de ses PV ou affectée par un effet négatif.", "always", "skull",
                  {"target_weak": True}, {"damage_dice": "1d6"}),
          [ab("frappe_ombre", "Frappe dans l'ombre", "dagger", "2d6 + Dextérité, +2 au toucher.", 3, 1, 1, "enemy", [dmg("2d6")], "Dextérité", short="Frappe"),
           ab("apnee_spectrale", "Apnée spectrale", "mask", "Devient Invisible 1 tour (intangible).", 4, 1, 0, "self", [st("invisible", 1, on="self")], "Dextérité", 3, short="Apnée"),
           ab("lame_silence", "Lame du silence", "drop", "1d6 + Dextérité et Réduit au silence 1 tour.", 3, 1, 1, "enemy", [dmg("1d6"), st("silence", 1)], "Dextérité", 2, short="Silence")],
          ab("moisson", "Moisson", "skull", "ULTIME : 5d6 + Dextérité sur une cible et Saignement 3 tours.", 0, 2, 1, "enemy",
             [dmg("5d6"), st("saignement", 3)], "Dextérité", ultimate=True),
          [{"ability": ab("pluie_kunai", "Pluie de kunai", "dagger", "Zone de rayon 1 à 4 cases : 2d4 + Dextérité.", 3, 1, 4, "area_enemy", [dmg("2d4")], "Dextérité", 2, radius=1), "level": 2},
           {"ability": ab("marque_faucheur", "Marque du Faucheur", "target", "La cible est Marquée 3 tours.", 2, 1, 6, "enemy", [st("marque", 3)], "Dextérité", 2, roll="none"), "level": 3}],
          kit(("cape_ombre", 1, True), ("bombe_fumee", 2, False)),
          [choice("Votre lame", "dague_courbe", "kunai_jumeaux", "stylet_empoisonne")],
          rec(FOR=1, DEX=5, CON=3, INT=1, ESP=2, CHA=3), crit_bonus=1,
          magic={"category": "Altération", "name": "Apnée spectrale", "description": "Retient son souffle pour devenir intangible."}),
    klass("invocateur", "Invocateur", "Appelle des esprits liés par contrat.", "Invocation et soutien", "#6f9fc9", "spirit",
          "Lié par contrat à des esprits : les appelle au combat et protège ses alliés.",
          {"Charisme": 1, "Esprit": 1}, 12, 4, "AEC", "Charisme", 12, 5,
          passive("Lien spirituel", "Au début de votre tour, récupère 1 AEC.", "turn_start", "spirit", effects=[restore("res", 1, "self")]),
          [ab("appel_esprit", "Appel d'esprit", "spirit", "Un esprit frappe une cible à 6 cases : 2d6 + Charisme magiques.", 3, 1, 6, "enemy",
              [dmg("2d6", element="magique")], "Charisme", element="magique", short="Esprit"),
           ab("gardien_spirituel", "Gardien spirituel", "ward", "Un allié à 4 cases : bouclier de 6 + Charisme, 2 tours.", 3, 1, 4, "ally",
              [{"type": "status", "status": "bouclier", "turns": 2, "value": 6, "scale": "Charisme"}], "Charisme", 2, short="Gardien"),
           ab("invocation", "Invocation", "spirit", "Invoque un esprit lié (15 PV, 1d8) à côté de vous.", 5, 2, 1, "self",
              [summon("Esprit lié", 15, "1d8", 12, "#9fc3d4")], "Charisme", 4)],
          ab("legion", "Légion d'esprits", "spirit", "ULTIME : zone de rayon 2 à 6 cases : 3d8 dégâts magiques et Effrayé.", 0, 2, 6, "area_enemy",
             [dmg("3d8", element="magique"), st("effraye", 2)], "Charisme", radius=2, ultimate=True, element="magique", short="Légion"),
          [{"ability": "premiers_soins", "level": 2}],
          kit(("robe_mage", 1, True), ("potion_mana", 1, False)),
          [choice("Votre catalyseur", "baguette_braise", "baton_chene", "talisman_garde")],
          rec(FOR=0, DEX=3, CON=3, INT=1, ESP=3, CHA=5),
          magic={"category": "Invocation", "name": "Contrats spirituels", "description": "Appelle des esprits liés par contrat."}),
    klass("createur", "Créateur élémentaire", "Génère tornades, flammes ou vagues à partir de rien.", "Attaque magique à distance", "#d1a15e", "flame",
          "Crée les éléments à partir de rien : énormes dégâts de zone, mais fragile.",
          {"Intelligence": 2}, 10, 4, "AEC", "Intelligence", 12, 5,
          passive("Résonance", "Quand un de vos sorts touche, récupère 2 AEC.", "on_hit", "flame", {"element": "magique"}, effects=[restore("res", 2, "self")]),
          [ab("trait_elementaire", "Trait élémentaire", "fire", "2d8 + Intelligence magiques à 7 cases.", 3, 1, 7, "enemy", [dmg("2d8", element="magique")], "Intelligence", element="magique", short="Trait"),
           ab("deferlement", "Déferlement", "wave", "Zone de rayon 1 à 4 cases : 2d6 magiques, repousse de 1 case.", 5, 1, 4, "area_enemy",
              [dmg("2d6", element="magique"), push(1)], "Intelligence", 2, radius=1, element="magique", short="Vague"),
           ab("mur_elementaire", "Mur élémentaire", "ward", "Vous et vos alliés à 1 case : bouclier de 6, 2 tours.", 3, 1, 0, "area_ally", [shield(6, 2)], "Intelligence", 2, radius=1, short="Mur")],
          ab("tempete", "Tempête primordiale", "wind", "ULTIME : zone de rayon 2 à 7 cases : 4d6 magiques et Gelé.", 0, 2, 7, "area_enemy",
             [dmg("4d6", element="magique"), st("gel", 2)], "Intelligence", radius=2, ultimate=True, element="magique", short="Tempête"),
          [{"ability": "boule_de_feu", "level": 2}, {"ability": "eclair_chaine", "level": 4}],
          kit(("robe_mage", 1, True), ("potion_mana", 2, False)),
          [choice("Votre focaliseur", "baguette_braise", "baton_chene", "grimoire_poche")],
          rec(FOR=0, DEX=3, CON=3, INT=5, ESP=4, CHA=0),
          magic={"category": "Création", "name": "Éléments primordiaux", "description": "Génère tornades, flammes ou vagues."}),
    klass("metamorphe", "Métamorphe", "Prend la forme d'une bête pour combattre ou fuir.", "Combattant polyvalent", "#7b5a3a", "paw",
          "Change de forme : bête de combat redoutable, rapide et résistante.",
          {"Force": 1, "Dextérité": 1}, 18, 6, "AEC", "Constitution", 8, 6,
          passive("Instinct animal", "Au début de votre tour, si vos PV sont sous 50 %, récupère 1d4 PV.", "turn_start", "paw",
                  {"self_hp_below": 50}, effects=[heal("1d4", 0, "self")]),
          [ab("forme_bestiale", "Forme bestiale", "paw", "Forme bestiale 4 tours : +2 Force, +2 vitesse, +2 dégâts.", 3, 1, 0, "self", [st("forme_bestiale", 4, on="self")], "Constitution", 5, short="Bête"),
           ab("griffes", "Coup de griffes", "claw", "2d6 + Force et Saignement 2 tours (50 %).", 3, 1, 1, "enemy", [dmg("2d6"), st("saignement", 2, 50)], "Force", short="Griffes"),
           ab("bond", "Bond", "boots", "Saute sur une cible à 5 cases : 1d8 + Dextérité.", 3, 1, 5, "enemy", [dmg("1d8", stat="Dextérité")], "Dextérité", 2)],
          ab("fureur_primale", "Fureur primale", "claw", "ULTIME : 4d8 + Force sur une cible, vous récupérez 30 % des dégâts.", 0, 2, 1, "enemy",
             [dmg("4d8"), drain(30)], "Force", ultimate=True, short="Fureur"),
          [{"ability": "second_souffle", "level": 2},
           {"ability": ab("hurlement", "Hurlement", "horn", "Ennemis à 2 cases : Effrayés 2 tours.", 3, 1, 0, "area_enemy", [st("effraye", 2)], "Charisme", 3, radius=2, roll="none"), "level": 3}],
          kit(("armure_cuir", 1, True), ("ration", 3, False)),
          [choice("Votre arme", "griffes_acier", "lance", "dague")],
          rec(FOR=4, DEX=4, CON=4, INT=0, ESP=2, CHA=1),
          magic={"category": "Transformation", "name": "Forme animale", "description": "Prend la forme d'une bête."}),
    klass("psychique", "Psychique", "Agit par l'esprit : perception, manipulation, télékinésie.", "Contrôle", "#a07cc9", "eye",
          "Brise la volonté des ennemis : étourdissements, peur et dégâts mentaux.",
          {"Esprit": 1, "Intelligence": 1}, 12, 4, "AEC", "Esprit", 12, 5,
          passive("Esprit acéré", "+2 au toucher contre une cible affectée par un effet négatif.", "always", "eye", {"target_debuffed": True}, {"to_hit": 2}),
          [ab("onde_mentale", "Onde mentale", "spiral", "2d6 + Esprit dégâts magiques à 6 cases.", 3, 1, 6, "enemy", [dmg("2d6", element="magique")], "Esprit", element="magique", short="Onde"),
           ab("emprise", "Emprise", "eye", "60 % d'étourdir une cible à 4 cases.", 5, 1, 4, "enemy", [st("etourdi", 1, 60)], "Esprit", 3, roll="none"),
           ab("telekinesie", "Télékinésie", "hand", "1d8 + Esprit et attire la cible de 2 cases.", 3, 1, 6, "enemy", [dmg("1d8", element="magique"), pull(2)], "Esprit", 1, element="magique", short="Télé")],
          ab("effondrement", "Effondrement mental", "skull", "ULTIME : zone de rayon 2 : 3d8 magiques, Étourdi (50 %).", 0, 2, 6, "area_enemy",
             [dmg("3d8", element="magique"), st("etourdi", 1, 50)], "Esprit", radius=2, ultimate=True, element="magique", short="Effondrement"),
          [{"ability": ab("terreur", "Terreur", "skull", "Une cible est Effrayée et Affaiblie 2 tours.", 3, 1, 5, "enemy", [st("effraye", 2), st("affaibli", 2)], "Esprit", 2, roll="none"), "level": 2}],
          kit(("robe_mage", 1, True), ("potion_mana", 1, False)),
          [choice("Votre focaliseur", "anneau_esprit", "baguette_braise", "grimoire_poche")],
          rec(FOR=0, DEX=3, CON=3, INT=3, ESP=5, CHA=1),
          magic={"category": "Psychisme", "name": "Esprit dominant", "description": "Perception, manipulation, télékinésie."}),
    klass("soigneur", "Soigneur", "Feux follets et énergie verte : garde le groupe debout.", "Soin et soutien", "#8fb28a", "heart",
          "Feux follets et énergie verte : soigne, purifie, protège.",
          {"Esprit": 2}, 14, 5, "AEC", "Esprit", 12, 5,
          passive("Énergie verte", "Vos soins sont 50 % plus efficaces.", "always", "heart", None, {"heal_pct": 50}),
          [ab("feux_follets", "Feux follets", "heart", "Un allié à 5 cases récupère 2d8 + Esprit PV.", 3, 1, 5, "ally", [heal("2d8")], "Esprit", element="soin", short="Soin"),
           ab("purification_l", "Purification", "sparkle", "Retire 2 effets négatifs et donne Régénération 2 tours.", 3, 1, 4, "ally", [cleanse(2), st("regeneration", 2)], "Esprit", 2, element="soin"),
           ab("vague_soin", "Vague de soin", "wave", "Vous et vos alliés à 2 cases : 1d8 + Esprit PV.", 5, 1, 0, "area_ally", [heal("1d8")], "Esprit", 2, radius=2, element="soin", short="Vague")],
          ab("renouveau", "Renouveau", "leaf", "ULTIME : alliés à 3 cases : 3d8 + Esprit PV (même à 0 PV) et purifiés.", 0, 2, 0, "area_ally",
             [heal("3d8"), cleanse(3)], "Esprit", radius=3, ultimate=True, element="soin"),
          [{"ability": ab("bulle_vie", "Bulle de vie", "ward", "Un allié : bouclier de 10, Régénération 3 tours.", 5, 2, 4, "ally", [shield(10, 2), st("regeneration", 3)], "Esprit", 3), "level": 3}],
          kit(("robe_mage", 1, True), ("herbes_medicinales", 3, False)),
          [choice("Votre catalyseur", "masse_benie", "baton_chene", "talisman_garde")],
          rec(FOR=1, DEX=2, CON=3, INT=1, ESP=5, CHA=3),
          magic={"category": "Soin", "name": "Feux follets", "description": "Énergie verte qui referme les plaies."}),
    klass("tacticien", "Tacticien de Karoh", "Sans magie, mais avec la technologie la plus redoutée du monde.", "Tir et anti-magie", "#5c6470", "gear",
          "Pas de magie, mais des gadgets : tirs précis, brouilleurs, pièges.",
          {"Dextérité": 1, "Intelligence": 1}, 15, 5, "Munitions", "Intelligence", 10, 5,
          passive("Calcul balistique", "À 3 cases ou plus de sa cible : +2 au toucher et +2 dégâts.", "always", "target", {"distance_min": 3}, {"to_hit": 2, "damage": 2}),
          [ab("tir_ajuste", "Tir ajusté", "gun", "2d8 + Dextérité à 8 cases.", 3, 1, 8, "enemy", [dmg("2d8")], "Dextérité", short="Tir"),
           ab("brouilleur", "Brouilleur anti-magie", "gear", "La cible est Réduite au silence 2 tours.", 3, 1, 5, "enemy", [st("silence", 2)], "Intelligence", 3, roll="none", short="Brouilleur"),
           ab("grenade", "Grenade", "bomb", "Zone de rayon 1 à 5 cases : 2d6 et repousse de 1 case.", 4, 1, 5, "area_enemy", [dmg("2d6"), push(1)], "Intelligence", 2, radius=1)],
          ab("frappe_orbitale", "Frappe d'artillerie", "meteor", "ULTIME : zone de rayon 2 à 10 cases : 4d8.", 0, 2, 10, "area_enemy",
             [dmg("4d8")], "Intelligence", radius=2, ultimate=True, short="Artillerie"),
          [{"ability": ab("tourelle", "Tourelle", "gear", "Déploie une tourelle (10 PV, 1d8).", 5, 2, 1, "self", [summon("Tourelle", 10, "1d8", 13, "#5c6470")], "Intelligence", 4), "level": 3}],
          kit(("armure_cuir", 1, True), ("potion_soin", 1, False)),
          [choice("Votre arme", "arbalete", "arc_long", "kunai_jumeaux")],
          rec(FOR=1, DEX=5, CON=3, INT=4, ESP=2, CHA=0)),
    klass("mutant", "Mutant", "AEC et ADN animal : insensible à l'anti-magie.", "Tank et combattant", "#4f7a3a", "claw",
          "Un corps transformé : régénération, résistance et force brute.",
          {"Constitution": 2}, 22, 7, "AEC", "Constitution", 6, 5,
          passive("Régénération mutante", "Au début de votre tour, récupère 2 PV.", "turn_start", "leaf", effects=[{"type": "heal", "amount": 2, "on": "self"}]),
          [ab("assaut_sauvage", "Assaut sauvage", "claw", "2d8 + Force.", 4, 1, 1, "enemy", [dmg("2d8")], "Force", short="Assaut"),
           ab("regeneration_m", "Régénération", "leaf", "Récupère 1d8 + Constitution PV.", 2, 1, 0, "self", [heal("1d8", 0, "self")], "Constitution", 2, element="soin", short="Régén"),
           ab("peau_ecailles", "Peau d'écailles", "scale", "En garde (+3 Défense) et bouclier de 6 pendant 2 tours.", 3, 1, 0, "self", [st("protege", 2, on="self"), shield(6, 2, "self")], "Constitution", 3, short="Écailles")],
          ab("transformation_totale", "Transformation totale", "claw", "ULTIME : Rage et Forme bestiale 3 tours, récupère 3d6 PV.", 0, 1, 0, "self",
             [st("rage", 3, on="self"), st("forme_bestiale", 3, on="self"), heal("3d6", 0, "self")], "Constitution", ultimate=True, short="Mutation"),
          [{"ability": "second_souffle", "level": 3}],
          kit(("cotte_mailles", 1, True), ("ration", 2, False)),
          [choice("Votre arme", "griffes_acier", "hache_guerre", "marteau_armes")],
          rec(FOR=4, DEX=2, CON=5, INT=0, ESP=2, CHA=2), defense_bonus=1,
          magic={"category": "Mutation", "name": "ADN animal", "description": "Insensible à l'anti-magie."}),
]

# --- Tables de butin et monstres ---------------------------------------------

LOOT = [
    {"id": "bete", "name": "Bête sauvage", "gold": [0, 2], "entries": [
        {"item": "cuir_brut", "chance": 70, "min": 1, "max": 2}, {"item": "croc_loup", "chance": 50, "min": 1, "max": 1},
        {"item": "ration", "chance": 20, "min": 1, "max": 1}]},
    {"id": "brigand", "name": "Brigand", "gold": [3, 12], "entries": [
        {"item": "potion_soin", "chance": 30, "min": 1, "max": 1}, {"item": "dague", "chance": 15, "min": 1, "max": 1},
        {"item": "armure_cuir", "chance": 10, "min": 1, "max": 1}, {"item": "bombe_fumee", "chance": 15, "min": 1, "max": 1}]},
    {"id": "gobelin", "name": "Gobelin", "gold": [1, 6], "entries": [
        {"item": "potion_soin", "chance": 20, "min": 1, "max": 1}, {"item": "minerai_fer", "chance": 30, "min": 1, "max": 2},
        {"item": "arc_court", "chance": 8, "min": 1, "max": 1}, {"item": "gemme_brute", "chance": 8, "min": 1, "max": 1}]},
    {"id": "mort_vivant", "name": "Mort-vivant", "gold": [0, 5], "entries": [
        {"item": "antidote", "chance": 20, "min": 1, "max": 1}, {"item": "epee_longue", "chance": 10, "min": 1, "max": 1},
        {"item": "talisman_garde", "chance": 5, "min": 1, "max": 1}]},
    {"id": "magique", "name": "Créature magique", "gold": [5, 15], "entries": [
        {"item": "potion_mana", "chance": 40, "min": 1, "max": 2}, {"item": "gemme_brute", "chance": 25, "min": 1, "max": 1},
        {"item": "anneau_esprit", "chance": 6, "min": 1, "max": 1}, {"item": "livre_boule_feu", "chance": 4, "min": 1, "max": 1}]},
    {"id": "coffre", "name": "Coffre au trésor", "gold": [15, 40], "entries": [
        {"item": "potion_soin", "chance": 60, "min": 1, "max": 2}, {"item": "potion_soin_sup", "chance": 25, "min": 1, "max": 1},
        {"item": "anneau_force", "chance": 12, "min": 1, "max": 1}, {"item": "bottes_vent", "chance": 6, "min": 1, "max": 1},
        {"item": "lame_runique", "chance": 5, "min": 1, "max": 1}, {"item": "livre_second_souffle", "chance": 10, "min": 1, "max": 1}]},
    {"id": "boss", "name": "Trésor de boss", "gold": [40, 100], "guaranteed": [{"item": "potion_soin_sup", "qty": 2}], "entries": [
        {"item": "amulette_vie", "chance": 30, "min": 1, "max": 1}, {"item": "croc_vampirique", "chance": 15, "min": 1, "max": 1},
        {"item": "baton_tempete", "chance": 15, "min": 1, "max": 1}, {"item": "robe_archimage", "chance": 20, "min": 1, "max": 1},
        {"item": "ecaille_dragon", "chance": 20, "min": 1, "max": 2}, {"item": "brise_monde", "chance": 3, "min": 1, "max": 1},
        {"item": "pendentif_phenix", "chance": 3, "min": 1, "max": 1}]},
]


# aggro : périmètre (en cases) où le monstre attaque de lui-même ; 0 = règle de la campagne.
AGGRO = {"loup": 5, "loup_alpha": 6, "araignee": 3, "golem": 2, "ours": 3, "jeune_dragon": 7, "gobelin_archer": 6, "chef_bandit": 5}


def monster(id_, name, color, desc, stats, hp, weapon_, abilities=(), xp=20, loot="", defense_bonus=0, boss=False, speed=5,
            statuses_immune=(), res=10, icon="skull", power=None):
    full = {s["name"]: 5 for s in STATS}
    full.update(stats)
    if power is None:
        power = 4 if boss else 2
    return {"id": id_, "name": name, "color": color, "description": desc, "stats": full, "hp": round(hp * 1.3), "power": power,
            "weapon": weapon_, "abilities": list(abilities), "xp": xp, "loot": loot, "defense_bonus": defense_bonus,
            "boss": boss, "speed": speed, "res": res, "icon": icon, "aggro": AGGRO.get(id_, 0)}


ab("morsure", "Morsure", "fang", "1d6 + Force, 30 % de saignement.", 0, 1, 1, "enemy", [dmg("1d6"), st("saignement", 2, 30)], "Force")
ab("hurlement_meute", "Hurlement", "horn", "Les alliés à 3 cases sont Renforcés.", 0, 1, 0, "area_ally", [st("renforce", 2)], "Charisme", 4, radius=3)
ab("toile", "Toile", "chain", "Immobilise une cible à 4 cases.", 0, 1, 4, "enemy", [st("immobilise", 2)], "Dextérité", 3)
ab("crochet_venin", "Crochets venimeux", "fang", "1d8 et Empoisonné 3 tours.", 0, 1, 1, "enemy", [dmg("1d8"), st("poison", 3)], "Dextérité", 2)
ab("tir_gobelin", "Flèche barbelée", "arrow", "1d6 à 6 cases.", 0, 1, 6, "enemy", [dmg("1d6")], "Dextérité")
ab("eclair_noir", "Éclair noir", "bolt", "2d6 magiques à 6 cases.", 3, 1, 6, "enemy", [dmg("2d6", element="magique")], "Intelligence", 1, element="magique")
ab("malediction", "Malédiction", "skull", "Une cible est Vulnérable et Affaiblie 2 tours.", 3, 1, 5, "enemy", [st("vulnerable", 2), st("affaibli", 2)], "Esprit", 3, roll="none")
ab("ecrasement", "Écrasement", "fist", "2d10 + Force, 40 % d'étourdir.", 0, 2, 1, "enemy", [dmg("2d10"), st("etourdi", 1, 40)], "Force", 2)
ab("souffle_feu", "Souffle de feu", "fire", "Zone de rayon 2 à 4 cases : 4d6 magiques et brûlure.", 0, 2, 4, "area_enemy",
   [dmg("4d6", element="magique"), st("brulure", 2)], "Constitution", 3, radius=2, element="magique")
ab("cri_chef", "Ordre de bataille", "horn", "Les alliés à 4 cases sont Renforcés et Concentrés.", 0, 1, 0, "area_ally", [st("renforce", 2), st("concentre", 2)], "Charisme", 3, radius=4)
ab("drain_ombre", "Étreinte de l'ombre", "spiral", "2d8 magiques, récupère 50 % en PV.", 4, 1, 3, "enemy", [dmg("2d8", element="magique"), drain(50)], "Esprit", 2, element="magique")

MONSTERS = [
    monster("loup", "Loup", "#9a9a9a", "Chasse en meute.", {"Force": 5, "Dextérité": 6, "Constitution": 5}, 18, wpn("1d6", "Force"), ["morsure"], 15, "bete", speed=7, icon="paw"),
    monster("loup_alpha", "Loup alpha", "#d9dee4", "Chef de meute.", {"Force": 7, "Dextérité": 6, "Constitution": 7}, 34, wpn("1d8", "Force"), ["morsure", "hurlement_meute"], 40, "bete", speed=7, icon="paw"),
    monster("gobelin", "Gobelin", "#7f9a5a", "Petit, lâche, nombreux.", {"Force": 3, "Dextérité": 6, "Constitution": 4}, 14, wpn("1d6", "Dextérité"), [], 12, "gobelin"),
    monster("gobelin_archer", "Gobelin archer", "#6f8a4a", "Tire de loin.", {"Force": 3, "Dextérité": 7, "Constitution": 4}, 12, wpn("1d6", "Dextérité", 20, 6), ["tir_gobelin"], 14, "gobelin"),
    monster("bandit", "Bandit", "#8a6a4a", "Détrousseur de grand chemin.", {"Force": 6, "Dextérité": 5, "Constitution": 5}, 22, wpn("1d8", "Force"), [], 20, "brigand", 1),
    monster("chef_bandit", "Chef bandit", "#b0605a", "Il crie plus fort que les autres.", {"Force": 8, "Dextérité": 6, "Constitution": 7, "Charisme": 7}, 48, wpn("1d10", "Force", 19),
            ["cri_chef"], 70, "brigand", 2, True),
    monster("squelette", "Squelette", "#e0e0d0", "Os animés par une volonté ancienne.", {"Force": 5, "Dextérité": 5, "Constitution": 4}, 18, wpn("1d8", "Force"), [], 18, "mort_vivant", 1, icon="skull"),
    monster("araignee", "Araignée géante", "#3a3a3a", "Huit pattes, beaucoup trop d'yeux.", {"Force": 5, "Dextérité": 7, "Constitution": 5}, 24, wpn("1d6", "Dextérité"),
            ["crochet_venin", "toile"], 30, "bete", speed=6),
    monster("ours", "Ours des cavernes", "#6b4a2a", "Massif et furieux.", {"Force": 9, "Dextérité": 3, "Constitution": 9}, 50, wpn("2d6", "Force"), ["ecrasement"], 55, "bete", speed=5, icon="paw"),
    monster("cultiste", "Cultiste", "#5a4a6a", "Murmure des noms interdits.", {"Dextérité": 5, "Intelligence": 7, "Esprit": 6}, 20, wpn("1d4", "Dextérité"),
            ["eclair_noir", "malediction"], 30, "magique"),
    monster("golem", "Golem de pierre", "#8a8f9a", "Lent et presque indestructible.", {"Force": 9, "Dextérité": 2, "Constitution": 10}, 60, wpn("2d8", "Force"), ["ecrasement"], 70, "magique", 3, speed=3),
    monster("ombre_errante", "Ombré", "#2a2a3a", "Une silhouette qui boit la lumière.", {"Dextérité": 7, "Esprit": 7, "Constitution": 5}, 28, wpn("1d8", "Dextérité", 20, 1, "magique"),
            ["drain_ombre"], 45, "magique"),
    monster("jeune_dragon", "Jeune dragon", "#c25050", "Déjà bien trop grand.", {"Force": 9, "Dextérité": 6, "Constitution": 9, "Esprit": 7}, 120, wpn("2d8", "Force", 19),
            ["souffle_feu", "ecrasement"], 250, "boss", 3, True, speed=6, icon="dragon"),
]


# --- Peuples -------------------------------------------------------------------
# Chaque peuple : bonus de caractéristiques, bonus de jeu (mods), un trait, parfois
# une capacité innée, et des synergies avec certaines classes (un elfe mage a plus
# de mana qu'un demi-orc mage ; un demi-orc druide appelle la horde…).

ab("rage_sang", "Rage du sang", "fist", "Une fois par combat : +2 Force et Renforcé pendant 2 tours.", 0, 1, 0, "self",
   [statmod("Force", 2, 2, "self"), st("renforce", 2, on="self")], "Force", 99, short="Rage")
ab("appel_horde", "Appel de la horde", "paw", "Un loup de guerre (18 PV, 1d8) rejoint le combat.", 4, 2, 1, "self",
   [summon("Loup de guerre", 18, "1d8", 13, "#7a6a5a")], "Esprit", 4, short="Horde")
ab("flammes_infernales", "Flammes infernales", "fire", "2d6 dégâts magiques à 4 cases, 30 % de brûlure.", 3, 1, 4, "enemy",
   [dmg("2d6", element="magique"), st("brulure", 2, 30)], "Charisme", 3, element="magique", short="Flammes")
ab("souffle_ancestral", "Pas du vent", "wind", "Vous devenez Invisible 1 tour (sortie de combat, embuscade).", 2, 1, 0, "self",
   [st("invisible", 1, on="self")], "Dextérité", 4, short="Vent")
ab("chant_profondeurs", "Chant des profondeurs", "music", "Une cible à 5 cases est Affaiblie 2 tours.", 3, 1, 5, "enemy",
   [st("affaibli", 2)], "Charisme", 3, roll="none", short="Chant")
ab("charge_cornue", "Charge cornue", "horn", "1d10 + Force à 3 cases et repousse de 2 cases.", 3, 1, 3, "enemy",
   [dmg("1d10"), push(2)], "Force", 3, short="Cornes")


def species(id_, name, desc, icon, stats=None, mods=None, trait="", trait_desc="", abilities=(), synergies=None):
    return {"id": id_, "name": name, "description": desc, "icon": icon, "stats": stats or {}, "mods": mods or {},
            "trait": {"name": trait, "description": trait_desc}, "abilities": list(abilities), "synergies": synergies or {}}


def syn(name, desc, mods=None, abilities=()):
    return {"name": name, "description": desc, "mods": mods or {}, "abilities": list(abilities)}


SPECIES_FANTASY = [
    species("humain", "Humain", "Ambitieux et adaptables : bons partout, excellents nulle part… au début.", "person",
            {"Charisme": 1}, {"to_hit": 1}, "Détermination", "+1 au toucher, +1 Charisme.",
            synergies={"guerrier": syn("Vétéran", "Des années de guerre : +4 PV max.", {"hp_max": 4}),
                       "soigneur": syn("Vocation", "+10 % aux soins prodigués.", {"heal_pct": 10}),
                       "barde": syn("Orateur né", "+2 Inspiration max.", {"res_max": 2})}),
    species("elfe", "Elfe", "Gracieux, anciens, liés à la magie. Fragiles mais perçants.", "leaf",
            {"Dextérité": 1, "Intelligence": 1, "Constitution": -1}, {"res_max": 4, "vision": 2}, "Sang ancien",
            "+4 de mana (ou ressource) et vision elfique (+2 cases).",
            synergies={"mage": syn("Héritage arcanique", "Un elfe mage puise plus loin : +4 mana et +1 dégât.", {"res_max": 4, "damage": 1}),
                       "rodeur": syn("Œil de l'elfe", "+1 au toucher, +1 case de vision.", {"to_hit": 1, "vision": 1}),
                       "druide": syn("Ami des forêts", "+10 % aux soins prodigués.", {"heal_pct": 10})}),
    species("nain", "Nain", "Trapus, têtus, increvables. Ils ont vu le fond des montagnes.", "hammer",
            {"Constitution": 2, "Dextérité": -1}, {"hp_max": 4, "resist_phys": 1}, "Robuste", "+4 PV max et +1 résistance physique.",
            synergies={"gardien": syn("Mur de pierre", "+1 Défense et +1 résistance physique.", {"defense": 1, "resist_phys": 1}),
                       "guerrier": syn("Forgé dans la roche", "+6 PV max.", {"hp_max": 6})}),
    species("demi_orc", "Demi-orc", "Le sang des steppes : force brute, colère froide, loyauté farouche.", "fist",
            {"Force": 2, "Intelligence": -1}, {"hp_max": 2, "damage": 1}, "Sang sauvage", "+1 dégât, +2 PV max, et la Rage du sang.",
            ["rage_sang"],
            {"druide": syn("Appel de la horde", "Un demi-orc druide parle aux loups de guerre : capacité « Appel de la horde », +2 PV max.", {"hp_max": 2}, ["appel_horde"]),
             "guerrier": syn("Brute", "+1 dégât.", {"damage": 1}),
             "rodeur": syn("Chasseur des steppes", "+1 dégât, +1 vitesse.", {"damage": 1, "speed": 1})}),
    species("halfelin", "Halfelin", "Petits, discrets, chanceux. On ne les voit jamais venir.", "boots",
            {"Dextérité": 2, "Force": -1}, {"defense": 1, "crit": 1}, "Chanceux", "+1 Défense, critique un cran plus tôt.",
            synergies={"assassin": syn("Ombre minuscule", "Critique encore un cran plus tôt.", {"crit": 1}),
                       "barde": syn("Conteur de tavernes", "+1 Charisme, +2 Inspiration.", {"Charisme": 1, "res_max": 2}),
                       "rodeur": syn("Pas léger", "+1 au toucher.", {"to_hit": 1})}),
    species("gnome", "Gnome", "Curieux, inventifs, bavards. La magie est un jouet sérieux.", "gear",
            {"Intelligence": 2, "Force": -1}, {"res_max": 2, "resist_mag": 1}, "Esprit vif", "+2 mana, +1 résistance magique.",
            synergies={"mage": syn("Bricoleur d'arcanes", "+1 dégât des sorts.", {"damage": 1}),
                       "soigneur": syn("Herboriste", "+10 % aux soins.", {"heal_pct": 10})}),
    species("tieffelin", "Tieffelin", "Une ascendance infernale : cornes, regard ardent, flammes au bout des doigts.", "fire",
            {"Charisme": 1, "Intelligence": 1}, {"resist_mag": 1}, "Héritage infernal", "+1 résistance magique et Flammes infernales.",
            ["flammes_infernales"],
            {"mage": syn("Pacte ardent", "+1 dégât.", {"damage": 1}),
             "assassin": syn("Regard infernal", "Critique un cran plus tôt.", {"crit": 1}),
             "barde": syn("Voix envoûtante", "+2 Inspiration.", {"res_max": 2})}),
]

SPECIES_LEGENDERS = [
    species("humain", "Humain", "La majorité de Kurtzuma : une affinité moyenne avec l'AEC, beaucoup de ressources.", "person",
            {"Charisme": 1}, {"res_max": 2}, "Adaptable", "+1 Charisme, +2 AEC.",
            synergies={"tacticien": syn("Stratège né", "+1 au toucher.", {"to_hit": 1})}),
    species("sans_magie", "Humain sans-magie", "Aucune AEC dans le sang… et un corps endurci pour compenser.", "fist",
            {"Force": 1, "Dextérité": 1, "Constitution": 1}, {"res_max": -6, "resist_mag": 2}, "Insensible à l'AEC",
            "+1 FOR / DEX / CON, +2 résistance magique, mais −6 AEC.",
            synergies={"briseur": syn("Poings nus", "+1 dégât.", {"damage": 1}), "tacticien": syn("Œil froid", "+1 au toucher.", {"to_hit": 1})}),
    species("mutant", "Mutant", "Le cristal a réécrit votre corps.", "spiral",
            {"Constitution": 1, "Force": 1}, {"hp_max": 4}, "Mutation", "+4 PV max.",
            synergies={"mutant": syn("Mutation stable", "+4 PV max, +1 résistance physique.", {"hp_max": 4, "resist_phys": 1}),
                       "metamorphe": syn("Chair fluide", "+1 vitesse.", {"speed": 1})}),
    species("ombre_nee", "Ombré", "Né de l'ombre, à moitié dans ce monde.", "mask",
            {"Dextérité": 2}, {"vision": 2}, "Né de l'ombre", "Voit dans le noir (+2 vision) et Pas du vent.", ["souffle_ancestral"],
            {"ombre": syn("Ombre parmi les ombres", "Critique un cran plus tôt.", {"crit": 1})}),
    species("homme_lezard", "Homme-lézard", "Écailles, sang froid, patience de chasseur.", "scale",
            {"Constitution": 1, "Dextérité": 1}, {"resist_phys": 1, "speed": 1}, "Écailles", "+1 résistance physique, +1 vitesse.",
            synergies={"briseur": syn("Carapace", "+1 Défense.", {"defense": 1})}),
    species("sirene", "Sirène", "Peuple des eaux : la voix est une arme.", "wave",
            {"Charisme": 1, "Esprit": 1}, {"res_max": 2}, "Chant des profondeurs", "+2 AEC et le Chant des profondeurs.", ["chant_profondeurs"],
            {"soigneur": syn("Marée apaisante", "+10 % aux soins.", {"heal_pct": 10}), "psychique": syn("Voix intérieure", "+2 AEC.", {"res_max": 2})}),
    species("centaure", "Centaure", "Mi-homme, mi-cheval : la plaine leur appartient.", "horn",
            {"Force": 1, "Constitution": 1}, {"speed": 2}, "Galop", "+2 vitesse.",
            synergies={"tacticien": syn("Éclaireur", "+1 vitesse, +1 vision.", {"speed": 1, "vision": 1})}),
    species("minotaure", "Minotaure", "Cornes, muscles et colère.", "horn",
            {"Force": 2, "Intelligence": -1}, {"hp_max": 4}, "Charge cornue", "+4 PV max et la Charge cornue.", ["charge_cornue"],
            {"briseur": syn("Bélier vivant", "+1 dégât.", {"damage": 1})}),
    species("esprit", "Esprit", "Une conscience faite d'AEC pure, à peine retenue par un corps.", "spirit",
            {"Esprit": 2, "Constitution": -1}, {"res_max": 4, "resist_mag": 1}, "Corps d'AEC", "+4 AEC, +1 résistance magique.",
            synergies={"invocateur": syn("Pont entre les mondes", "+4 AEC.", {"res_max": 4}), "psychique": syn("Résonance", "+1 dégât.", {"damage": 1})}),
    species("demon", "Démon", "Venu d'ailleurs, toléré, rarement aimé.", "fire",
            {"Force": 1, "Charisme": 1}, {"resist_mag": 1, "damage": 1}, "Sang infernal", "+1 dégât, +1 résistance magique, Flammes infernales.",
            ["flammes_infernales"], {"createur": syn("Forge infernale", "+1 dégât.", {"damage": 1})}),
]

# Équipement donné à tous les personnages à la création (en plus du kit de classe).
STARTER_KIT = [{"item": "potion_soin", "qty": 1}, {"item": "ration", "qty": 2}, {"item": "torche", "qty": 1},
               {"item": "corde", "qty": 1}, {"item": "trousse_soins", "qty": 1}]


def build(universe, classes):
    species_list = SPECIES_FANTASY if universe == "fantasy" else SPECIES_LEGENDERS
    used = set()
    for sp in species_list:
        used.update(sp["abilities"])
        for cid, sy in sp["synergies"].items():
            assert any(c["id"] == cid for c in classes), (universe, sp["id"], cid)
            used.update(sy["abilities"])
    for k in STARTER_KIT:
        assert k["item"] in ITEMS, k
    for c in classes:
        for a in c["abilities"] + [c["ultimate"]] + [l["ability"] for l in c["learnable"]]:
            used.add(a)
    for m in MONSTERS:
        used.update(m["abilities"])
    for i in ITEMS.values():
        used.update(i.get("grants", []))
        if i.get("teaches"):
            used.add(i["teaches"])
    used.update(["boule_de_feu", "second_souffle", "premiers_soins", "eclair_chaine", "renaissance"])
    missing = [a for a in used if a not in ABILITIES]
    assert not missing, missing
    for c in classes:
        for k in c["kit"]:
            assert k["item"] in ITEMS, k
        for ch in c["choices"]:
            for o in ch["options"]:
                assert o in ITEMS, o
    for t in LOOT:
        for e in t["entries"] + t.get("guaranteed", []):
            assert e["item"] in ITEMS, e
    return {
        "universe": universe, "version": 1, "rules": RULES, "stats": STATS,
        "classes": {c["id"]: c for c in classes},
        "abilities": {k: v for k, v in ABILITIES.items() if k in used},
        "statuses": {s["id"]: s for s in STATUSES},
        "items": ITEMS, "loot": {t["id"]: t for t in LOOT}, "monsters": {m["id"]: m for m in MONSTERS},
        "species": {s["id"]: s for s in species_list}, "starter_kit": STARTER_KIT,
    }


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, classes in (("fantasy", FANTASY), ("legenders", LEGENDERS)):
        data = build(name, classes)
        with open(os.path.join(OUT, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
        print(name, len(data["classes"]), "classes,", len(data["species"]), "peuples,", len(data["abilities"]), "capacités,", len(data["items"]), "objets,",
              len(data["monsters"]), "monstres")


if __name__ == "__main__":
    main()
