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
		"rules": "Chacun son tour : déplacez-vous (jusqu'à votre vitesse), faites UNE action (fouiller, examiner, parler, utiliser un objet…), puis « Fin du tour ».",
	},
	"dialogue": {
		"name": "Dialogue", "turns": true, "who": "players", "move": "none", "action": true,
		"rules": "Tour de parole : à votre tour, parlez ou agissez (une action), puis passez la parole avec « Fin du tour ». Pas de déplacement.",
	},
	"combat": {
		"name": "Combat", "turns": true, "who": "all", "move": "limit", "action": true,
		"rules": "Ordre d'initiative. À votre tour : déplacement (vitesse en cases) + UNE action (Attaquer, Capacité ou Objet), puis « Fin du tour ». Le MJ joue les adversaires. À 0 PV, on est hors de combat.",
	},
	"repos": {
		"name": "Repos", "turns": false, "who": "", "move": "none", "action": false,
		"rules": "Le groupe se repose : pas de déplacement. À la fin du repos, chacun récupère la moitié de ses PV et toute son énergie.",
	},
}


static func def(type: String) -> Dictionary:
	return DEFS.get(type, DEFS["libre"])
