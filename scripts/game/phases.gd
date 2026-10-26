class_name Phases
extends RefCounted
## Phases de jeu choisies par le MJ. Chacune a ses règles, affichées à tous et
## appliquées par l'hôte (qui joue, combien de cases, combien d'actions).
##
## turns : tour par tour ; who : « players » (pions des joueurs) ou « all »
## (tous les pions visibles, ordre d'initiative) ; move : « free », « limit »
## (vitesse en cases par tour) ou « none » ; action : une action par tour.

const LIST := ["libre", "exploration", "dialogue", "combat", "repos"]

const DEFS := {
	"libre": {
		"name": "Récit libre", "turns": false, "who": "", "move": "free", "action": false,
		"rules": "Tout le monde peut parler, agir et se déplacer librement. Le MJ raconte et tranche.",
	},
	"exploration": {
		"name": "Exploration", "turns": true, "who": "players", "move": "limit", "action": true,
		"rules": "Chacun son tour : déplacez-vous (jusqu'à votre vitesse), décrivez ce que vous faites (fouiller, examiner, parler…) ou utilisez une capacité, puis « Terminer mon tour ».",
	},
	"dialogue": {
		"name": "Dialogue", "turns": true, "who": "players", "move": "none", "action": true,
		"rules": "Tour de parole : à votre tour, parlez ou agissez, puis passez la parole avec « Terminer mon tour ». Pas de déplacement.",
	},
	"combat": {
		"name": "Combat", "turns": true, "who": "all", "move": "limit", "action": true,
		"rules": "Ordre d'initiative (d20 + Dextérité). À votre tour : 2 points d'action (PA). Se déplacer, attaque rapide, se défendre, objet : 1 PA ; attaque puissante : 2 PA ; capacités : selon leur coût. Parler est gratuit. Le MJ joue les adversaires. À 0 PV, on est hors de combat.",
	},
	"repos": {
		"name": "Repos", "turns": false, "who": "", "move": "none", "action": false,
		"rules": "Le groupe se repose : pas de déplacement. À la fin du repos, chacun récupère la moitié de ses PV et toute sa ressource (mana…).",
	},
}


static func def(type: String) -> Dictionary:
	return DEFS.get(type, DEFS["libre"])
