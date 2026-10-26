# Guide de jeu

## Lancer une partie

1. **L'hôte** (le MJ) ouvre l'application sur un PC Windows **ou un téléphone Android**, puis *Héberger une partie*.
2. Il crée une **nouvelle campagne** (nom, univers) ou **reprend** une campagne sauvegardée.
3. Le tableau de bord affiche **l'adresse IP** en grand. Il n'y a **pas de code**.
4. Chaque joueur : *Rejoindre une partie* → son nom et l'adresse IP (pavé numérique intégré, avec la touche « . »). Les parties détectées sur le Wi-Fi se rejoignent d'un seul toucher. Le port reste caché dans *Options avancées*. Les joueurs entrent directement (le MJ peut cocher « Valider moi-même chaque nouveau joueur »).
5. Chaque joueur crée son personnage avec l'**assistant** (voir ci-dessous) puis attend dans le salon (« Vous êtes prêt ! »).
6. Quand tout le monde est prêt, le MJ appuie sur **« La partie commence ! »** : la partie démarre en phase *Exploration* sur la carte affichée.

Tout le monde doit être sur **le même Wi-Fi** (box, routeur ou partage de connexion d'un téléphone).
Un téléphone hôte doit garder l'application **ouverte et l'écran allumé** : si Android met l'application en arrière-plan, les joueurs perdent la connexion jusqu'à son retour.

## Créer son personnage (assistant en 4 étapes)

1. **Classe** — chaque classe arrive avec ses capacités, ses bonus, ses PV de base, sa vitesse, son bonus d'attaque et son **niveau de critique** (ex. l'Ombre / l'Assassin critique plus souvent). Légenders : Briseur, Ombre, Invocateur, Créateur, Métamorphe, Psychique, Soigneur, Tacticien, Mutant. Fantasy : Guerrier, Assassin, Mage, Prêtre, Rôdeur, Barde.
2. **Points** — chaque caractéristique (Force, Agilité, Endurance, Intelligence, Perception, Charisme) part de 10. Vous avez **12 points** à répartir avec − / + (de −4 à +6 par caractéristique : baisser une caractéristique rend des points). Bouton *Répartition conseillée*. Les valeurs calculées s'affichent en direct.
3. **Équipement** — le kit de la classe, plus un choix propre à la classe (ex. l'Assassin choisit parmi trois dagues : dégâts, critique et portée différents).
4. **Identité** — nom, espèce, couleur du pion, description.

Tout est calculé automatiquement par l'hôte :
- **PV** = PV de la classe + 3 × modificateur d'Endurance (+ PV par niveau) ;
- **Énergie** = base de la classe + 2 × modificateur de la caractéristique magique ;
- **Défense** = 10 + modificateur d'Agilité + armure + bonus de classe ;
- **Initiative** = modificateurs d'Agilité + Perception ; **Vitesse** = cases par tour (classe).

Le modificateur vaut (valeur − 10) / 2 arrondi en dessous. Tout reste modifiable ensuite (*Modifier en détail*, ou décocher « Calcul automatique » pour une fiche entièrement libre). La *Création libre (avancée)* reste disponible.

## Les phases de jeu (tour par tour)

Le MJ choisit la phase dans la carte **Phase de jeu** (en haut de la colonne de droite) :

| Phase | Tours | Déplacement | Action |
|---|---|---|---|
| **Récit libre** | non | libre | actions libres résolues par le MJ |
| **Exploration** | joueurs, chacun son tour | jusqu'à sa vitesse | une action, puis « Fin du tour » |
| **Dialogue** | joueurs, chacun son tour | aucun | parler / agir |
| **Combat** | tous les combattants, ordre d'initiative | jusqu'à sa vitesse | **une** action : Attaquer, Capacité ou Objet |
| **Repos** | non | aucun | à la fin du repos : moitié des PV et toute l'énergie récupérées |

À votre tour, le téléphone vibre et affiche **« C'est votre tour ! »**. Les cases atteignables brillent sur la carte. *Attaquer* : choisissez une arme puis touchez la cible ; le jet est automatique : d20 + modificateur + bonus contre la Défense de la cible ; 20 naturel = toujours touché, 1 naturel = toujours raté ; au niveau de critique de l'arme (amélioré par la classe), les dés de dégâts sont doublés. Un pion à 0 PV est hors de combat (grisé). *Fin du tour* passe au suivant. Le MJ joue les PNJ et monstres depuis la même carte (attaque, capacité, cible), peut changer l'ordre (▲ ▼ ×) et forcer « Tour suivant ». En combat, la musique rock démarre automatiquement.

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
- **Carte** — la carte affichée par le MJ, avec les pions. Votre pion est déjà sélectionné : **touchez une case** pour l'y envoyer, ou faites-le glisser. Deux doigts : zoom ; *Recentrer* revient sur votre pion. Des boutons de dés rapides (d20, d12, d10, d8, d6, d4) sont sous la carte. Pendant une phase au tour par tour, l'ordre s'affiche au-dessus de la carte, vous ne bougez qu'à votre tour (dans la limite de votre vitesse) et le panneau de tour (Attaquer, Capacité, Objet, Fin du tour) apparaît sous la carte.
- **Fiche** — votre personnage, avec la carte « Au combat » (Défense, Initiative, Vitesse, attaques avec dégâts et critique). *Refaire avec l'assistant* ou *Modifier en détail* : nom, concept, espèce, origine, apparence, couleur et initiales du pion, magie (catégorie, nom, origine, effets, limites — avec suggestions de l'univers), capacités et techniques (coût, portée, limites), caractéristiques et compétences (ajoutez celles que vous voulez), PV, énergie (AEC, mana…), niveau, expérience, rang, inventaire, personnalité, objectifs, histoire, relations, notes et un **secret** visible seulement par vous et le MJ.
- **Groupe** — réglage de la **musique** sur votre téléphone (activer / couper, volume), puis les autres joueurs et la partie publique de leur fiche (nom, espèce, apparence, nom de la magie si le joueur l'accepte).
- **Codex** — le lore de l'univers, avec recherche.

## Côté MJ

- **Joueurs** : accepter / refuser, écrire en privé, ouvrir une fiche, déconnecter, retirer (la fiche devient un PNJ).
- **Table** — la carte interactive :
  - **Ambiance musicale** : 14 morceaux classés par ambiance (Épique, Combat rock, Aventure, Tension, Taverne, Ville, Exploration, Mystère, Repos) ; *Lecture*, *Suivant* (même ambiance), *Stop* ; option « jouer aussi sur les téléphones » ; option « musique de combat automatique » (un morceau rock démarre avec le combat, l'ambiance précédente revient à la fin) ;
  - choisir une carte, la **montrer aux joueurs**, en créer une (vierge ou à partir d'un modèle), la dupliquer, la renommer, la redimensionner (jusqu'à 128 × 128) ;
  - outils : **Déplacer** (n'importe quel pion), **Peindre** le terrain (29 terrains : herbe, prairie fleurie, champs, forêt, eau, montagne, rochers, sable, neige, glace, routes, pavés, toits, bâtiments, murs, grotte, lave, cendres, cristal AEC…, pinceau réglable), **Pion** (PNJ, monstre ou objet : nom, couleur, PV, caché), **Étiquette** (visible ou secrète), **Gomme**, **Départ** (case où arrivent les joueurs) ;
  - **Sélection** : renommer un pion, PV (−5, −1, +1, +5), cacher / révéler, couleur, note secrète, ouvrir sa fiche ;
  - **Phase de jeu** (en haut) : Récit libre, Exploration, Dialogue, Combat, Repos ; initiative tirée automatiquement, ordre modifiable (▲ ▼ ×), commandes des PNJ et monstres à leur tour, *Tour suivant*. Le pion dont c'est le tour est mis en évidence chez tout le monde. Avant le début : barre « Préparation : X/Y joueurs prêts » et bouton **« La partie commence ! »**.
  - Autoriser ou non les joueurs à déplacer leur pion.
- **Personnages** — toutes les fiches (joueurs et PNJ). Le MJ peut tout modifier, créer des PNJ, **importer des packs de PNJ** (bouton *Packs de PNJ…* : mages de Shima, gens et créatures de Kurtzuma, habitants de Valombre, bestiaire), les placer sur la carte (cachés par défaut, monstres avec le pion à cornes) et verrouiller les fiches des joueurs.
- **Récit** — le fil complet (y compris les messages privés), les **actions en attente** : résoudre (résultat + jet facultatif), refuser, ou **« Le joueur lance »** (le joueur lance lui-même le dé indiqué, avec une difficulté facultative, puis vous concluez). Messages au groupe ou privés, jets publics, secrets ou montrés à un seul joueur.
- Bouton **Jet** sur chaque joueur : lui demander un jet (ex. « Perception, d20, difficulté 12 »), visible par tout le groupe ou seulement par vous et lui.
- **Codex** — y compris les entrées réservées au MJ.
- **Réseau** — état, adresses, journal des connexions.

**Sauvegarde** : automatique toutes les minutes et à la fin de la session, plus le bouton *Sauver*. Tout est conservé : joueurs, fiches, cartes, pions, messages. À la reprise, chaque joueur retrouve sa place et son personnage en se reconnectant depuis le même téléphone.

## Monstres et créatures

Il n'y a volontairement **pas de bestiaire imposé** : le MJ crée ses monstres comme des pions (nom, couleur, PV) et, s'il le souhaite, une fiche de PNJ complète (capacités, magie, inventaire…) qu'il place sur la carte. Le codex Légenders décrit les familles de créatures pour l'inspiration.
