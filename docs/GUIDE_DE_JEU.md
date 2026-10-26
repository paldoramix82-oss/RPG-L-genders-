# Guide de jeu

## Lancer une partie

1. **L'hôte** (le MJ) ouvre l'application sur un PC Windows **ou un téléphone Android**, puis *Héberger une partie*.
2. Il crée une **nouvelle campagne** (nom, univers) ou **reprend** une campagne sauvegardée.
3. Le tableau de bord affiche **l'adresse IP, le port et le code**.
4. Chaque joueur : *Rejoindre une partie* → nom, adresse IP, port, code. Le MJ accepte la demande (sauf si l'acceptation automatique est cochée).

Tout le monde doit être sur **le même Wi-Fi** (box, routeur ou partage de connexion d'un téléphone).
Un téléphone hôte doit garder l'application **ouverte et l'écran allumé** : si Android met l'application en arrière-plan, les joueurs perdent la connexion jusqu'à son retour.

## Les grandes cartes

| Carte | Taille | Contenu |
|---|---|---|
| Kurtzuma — carte du monde | 120 × 80 | Le continent, ses nations (Pik, RAC, Trèfle, Karoh, Keurd…), les mers, les îles et les quatre cicatrices des Légenders |
| Région de Valombre | 96 × 64 | La ville, ses champs, la rivière et le pont, la forêt des Cendres, le lac, les hameaux, les ruines, la grotte, les montagnes |
| Shima — la capitale | 96 × 64 | Le QG de la magie au centre, les treize divisions en cercle, le port |
| Forêt-Monde — la lisière | 96 × 72 | Campement scientifique, villages de monstres, racines géantes, veines d'AEC |

Sur ces cartes, utilisez *Recentrer*, la molette ou deux doigts pour zoomer. Les pions et les noms s'affichent mieux en zoomant.

## Les univers

À la création de la campagne, le MJ choisit un univers :

| Univers | Contenu |
|---|---|
| **Légenders** | Codex complet (les dix Légenders, l'AEC et ses couleurs, l'éveil, les 10 catégories magiques, Gardiens, mutants, anti-magie, maîtrise des bases, rangs B → L, mages d'État, Kurtzuma et ses nations, monstres, Ombrés, démons, esprits). Suggestions de création : espèces, origines (nations), catégories et origines de magie, rangs. Cartes en plus : Shima – Division de l'Encre, Île du test de survie, Grande Caldeira. |
| **Fantasy classique** | Le cadre de démonstration « Les Cendres de Valombre » (ville, forêt, ruines, secrets pour le MJ). |
| **Univers libre** | Rien d'imposé. |

Les entrées du codex marquées « MJ » (secrets) **ne sont jamais envoyées aux joueurs**.
Les univers sont de simples fichiers JSON dans `data/universes/` : on peut en ajouter un en copiant `libre.json`.

## Côté joueur (5 onglets)

- **Aventure** — le fil de l'histoire. En bas, trois modes :
  - *Message* : au groupe ou au MJ en privé ;
  - *Action* : décrivez librement ce que vous tentez. L'action reste « En attente du MJ » jusqu'à ce qu'il la résolve ou la refuse (avec éventuellement un jet de dés et une conséquence) ;
  - *Dés* : d4 à d100, plusieurs dés, modificateur, ou formule libre (`2d6+3`, `d20-1`, `1d20+1d4`). Jet visible par tous ou secret (vous et le MJ). Un **plateau de dés animé** s'affiche : les dés roulent puis s'arrêtent sur le résultat (le tirage est fait par l'hôte, pour que personne ne puisse tricher).
  - Quand le MJ **demande un jet** (pour une action ou une épreuve, avec éventuellement une difficulté), un bouton **« Lancer le dé »** apparaît : c'est vous qui lancez, et le jeu affiche « Réussite » ou « Échec ».
- **Carte** — la carte affichée par le MJ, avec les pions. Votre pion est déjà sélectionné : **touchez une case** pour l'y envoyer, ou faites-le glisser. Deux doigts : zoom ; *Recentrer* revient sur votre pion. Des boutons de dés rapides (d20, d12, d10, d8, d6, d4) sont sous la carte. Pendant un combat, l'ordre des tours s'affiche et vous ne pouvez bouger que pendant votre tour.
- **Fiche** — votre personnage, **entièrement libre** : nom, concept, espèce, origine, apparence, couleur et initiales du pion, magie (catégorie, nom, origine, effets, limites — avec suggestions de l'univers), capacités et techniques (coût, portée, limites), caractéristiques et compétences (ajoutez celles que vous voulez), PV, énergie (AEC, mana…), niveau, expérience, rang, inventaire, personnalité, objectifs, histoire, relations, notes et un **secret** visible seulement par vous et le MJ.
- **Groupe** — réglage de la **musique** sur votre téléphone (activer / couper, volume), puis les autres joueurs et la partie publique de leur fiche (nom, espèce, apparence, nom de la magie si le joueur l'accepte).
- **Codex** — le lore de l'univers, avec recherche.

## Côté MJ

- **Joueurs** : accepter / refuser, écrire en privé, ouvrir une fiche, déconnecter, retirer (la fiche devient un PNJ).
- **Table** — la carte interactive :
  - **Ambiance musicale** : 14 morceaux classés par ambiance (Épique, Combat rock, Aventure, Tension, Taverne, Ville, Exploration, Mystère, Repos) ; *Lecture*, *Suivant* (même ambiance), *Stop* ; option « jouer aussi sur les téléphones » ; option « musique de combat automatique » (un morceau rock démarre avec le combat, l'ambiance précédente revient à la fin) ;
  - choisir une carte, la **montrer aux joueurs**, en créer une (vierge ou à partir d'un modèle), la dupliquer, la renommer, la redimensionner (jusqu'à 128 × 128) ;
  - outils : **Déplacer** (n'importe quel pion), **Peindre** le terrain (29 terrains : herbe, prairie fleurie, champs, forêt, eau, montagne, rochers, sable, neige, glace, routes, pavés, toits, bâtiments, murs, grotte, lave, cendres, cristal AEC…, pinceau réglable), **Pion** (PNJ, monstre ou objet : nom, couleur, PV, caché), **Étiquette** (visible ou secrète), **Gomme**, **Départ** (case où arrivent les joueurs) ;
  - **Sélection** : renommer un pion, PV (−5, −1, +1, +5), cacher / révéler, couleur, note secrète, ouvrir sa fiche ;
  - **Combat** : initiative d20 tirée automatiquement, ordre modifiable (▲ ▼), tour suivant, ajout / retrait de combattants. Le pion dont c'est le tour est mis en évidence chez tout le monde.
  - Autoriser ou non les joueurs à déplacer leur pion.
- **Personnages** — toutes les fiches (joueurs et PNJ). Le MJ peut tout modifier, créer des PNJ, **importer des packs de PNJ** (bouton *Packs de PNJ…* : mages de Shima, gens et créatures de Kurtzuma, habitants de Valombre, bestiaire), les placer sur la carte (cachés par défaut, monstres avec le pion à cornes) et verrouiller les fiches des joueurs.
- **Récit** — le fil complet (y compris les messages privés), les **actions en attente** : résoudre (résultat + jet facultatif), refuser, ou **« Le joueur lance »** (le joueur lance lui-même le dé indiqué, avec une difficulté facultative, puis vous concluez). Messages au groupe ou privés, jets publics, secrets ou montrés à un seul joueur.
- Bouton **Jet** sur chaque joueur : lui demander un jet (ex. « Perception, d20, difficulté 12 »), visible par tout le groupe ou seulement par vous et lui.
- **Codex** — y compris les entrées réservées au MJ.
- **Réseau** — état, adresses, journal des connexions.

**Sauvegarde** : automatique toutes les minutes et à la fin de la session, plus le bouton *Sauver*. Tout est conservé : joueurs, fiches, cartes, pions, messages. À la reprise, le code de la partie est le même et chaque joueur retrouve sa place et son personnage en se reconnectant depuis le même téléphone.

## Monstres et créatures

Il n'y a volontairement **pas de bestiaire imposé** : le MJ crée ses monstres comme des pions (nom, couleur, PV) et, s'il le souhaite, une fiche de PNJ complète (capacités, magie, inventaire…) qu'il place sur la carte. Le codex Légenders décrit les familles de créatures pour l'inspiration.
