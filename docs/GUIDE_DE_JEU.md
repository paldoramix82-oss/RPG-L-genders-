# Guide de jeu

Référence complète des règles et des écrans. Pour une première découverte, lisez d'abord le [guide du débutant](GUIDE_DEBUTANT.md).

## Lancer une partie

1. **L'hôte** (le MJ) ouvre l'application sur un PC Windows **ou un téléphone Android**, puis *Héberger une partie*.
2. Il crée une **nouvelle campagne** (nom, univers) ou **reprend** une campagne sauvegardée.
3. Le tableau de bord affiche **l'adresse IP** en grand. Il n'y a **pas de code**.
4. Chaque joueur : *Rejoindre une partie* → son nom et l'adresse IP (pavé numérique intégré, avec la touche « . »). Les parties détectées sur le Wi-Fi se rejoignent d'un seul toucher. Le port reste caché dans *Options avancées*. Les joueurs entrent directement (le MJ peut cocher « Valider moi-même chaque nouveau joueur »).
5. Chaque joueur crée son personnage avec l'**assistant** (voir ci-dessous) puis attend dans le salon (« Vous êtes prêt ! »).
6. Quand tout le monde est prêt, le MJ appuie sur **« La partie commence ! »** : la partie démarre en phase *Exploration* sur la carte affichée.

Tout le monde doit être sur **le même Wi-Fi** (box, routeur ou partage de connexion d'un téléphone).
Un téléphone hôte doit garder l'application **ouverte et l'écran allumé** : si Android met l'application en arrière-plan, les joueurs perdent la connexion jusqu'à son retour.

## Les caractéristiques et les formules

Six caractéristiques sur une échelle de 1 à 10 (5 = moyen) :

| Caractéristique | Effets |
|---|---|
| **Force** | dégâts des armes de corps à corps et des capacités physiques, épreuves de force |
| **Dextérité** | toucher des armes fines et de tir, Défense, initiative, discrétion |
| **Constitution** | PV (×2), résistance physique (÷4), certaines ressources (Vigueur) |
| **Intelligence** | toucher et dégâts des sorts arcaniques, ressource des mages |
| **Esprit** | mana de nombreuses classes, résistance magique (÷4), puissance des soins |
| **Charisme** | capacités de soutien (boucliers renforcés), invocations, épreuves sociales |

Formules (toutes les valeurs de base sont réglables par le MJ, *Créer › Règles*) :

| Valeur | Calcul |
|---|---|
| PV max | PV de la classe + Constitution × 2 + gain par niveau + équipement |
| Ressource max (mana, AEC…) | base de la classe + caractéristique de la ressource × 2 + 2 par niveau |
| Défense | 8 + Dextérité + armure + bonus de classe et d'effets |
| Toucher | d20 + caractéristique de l'arme (ou de la capacité) + bonus ≥ Défense de la cible |
| Dégâts | dés de l'arme ou de la capacité + caractéristique ÷ 2 + bonus − résistance de la cible (minimum 1) |
| Soins | dés du soin + caractéristique ÷ 2, augmentés des bonus de soins (%) |
| Initiative | d20 + Dextérité |
| Critique | 20 naturel (ou la plage de l'arme, élargie par certaines classes) : dés de dégâts doublés |
| Épreuve | d20 + caractéristique ≥ difficulté (10 facile, 15 moyen, 20 difficile) |

## Créer son personnage (assistant en 5 étapes)

1. **Identité** — nom, portrait (visage, teint, coiffure, couleur, yeux, barbe, marque), couleur du pion ; histoire, personnalité, description facultatives.
2. **Classe** — Fantasy : Guerrier, Gardien, Soigneur, Assassin, Rôdeur, Mage, Barde. Légenders : Briseur, Ombre, Invocateur, Créateur élémentaire, Métamorphe, Psychique, Soigneur, Tacticien de Karoh, Mutant. Chaque classe a des bonus de caractéristiques, des PV de base, une ressource, une vitesse, un **passif**, **trois capacités**, un **ultime**, des capacités à apprendre, un kit et des choix d'équipement.
3. **Caractéristiques** — 5 partout + **15 points** (minimum 1, maximum 10 avant le bonus de classe). *Répartition conseillée* et *Réinitialiser*. Aperçu en direct : PV, ressource, Défense, initiative, résistances, attaque.
4. **Équipement** — choix propre à la classe (ex. trois dagues pour l'Assassin) + kit fourni + or de départ.
5. **Récapitulatif** — tout vérifier, revenir en arrière, puis créer.

La fiche est **construite par l'hôte** à partir de ces choix : un téléphone ne peut pas imposer ses statistiques. Par la suite, un joueur ne modifie lui-même que la partie « récit » de sa fiche (nom, histoire, apparence, portrait). La *Création libre (avancée)* crée un personnage « histoire seule » dont le MJ règle les valeurs.

Les anciennes fiches (versions précédentes) sont converties automatiquement : Agilité → Dextérité, Endurance → Constitution, Perception → Esprit, valeurs divisées par deux ; les fiches créées avec l'ancien assistant sont reconstruites avec leur classe (le Prêtre devient Soigneur), l'inventaire est conservé.

## Les phases de jeu

Le MJ choisit la phase (*Combat* dans la colonne d'outils) :

| Phase | Tours | Déplacement | Actions |
|---|---|---|---|
| **Récit libre** | non | libre | actions libres résolues par le MJ ; capacités et objets utilisables |
| **Exploration** | joueurs, chacun son tour | jusqu'à sa vitesse | décrire ce qu'on fait, capacités, objets ; « Terminer mon tour » |
| **Dialogue** | joueurs | aucun | parler / agir |
| **Combat** | tous les combattants visibles, par initiative | 1 PA par déplacement | **2 PA** par tour (voir ci-dessous) |
| **Repos** | non | aucun | à la fin : 50 % des PV et toute la ressource récupérés |

### Le combat

| Action | Coût |
|---|---|
| Se déplacer (jusqu'à sa vitesse ; les cases restantes peuvent servir plus tard dans le tour) | 1 PA |
| Attaque rapide (arme équipée) | 1 PA |
| Attaque puissante : −2 au toucher, +50 % de dégâts | 2 PA |
| Se défendre : « En garde » (+3 Défense) jusqu'au prochain tour | 1 PA |
| Utiliser un objet (sur soi ou un allié au contact) | 1 PA |
| Capacité | son coût en PA + son coût en ressource |
| Parler, discuter, décrire | gratuit |

- **Début de tour** : effets sur la durée (poison, brûlure, saignement, régénération), durées qui diminuent, recharges qui avancent, +1 ressource, +10 % de jauge d'ultime, passifs « au début du tour ». Un combattant **étourdi** perd son tour.
- **Jauge d'ultime** : +15 % par coup porté, +10 % par coup reçu, +10 % par tour. Pleine (100 %), l'ultime devient utilisable ; elle se vide à l'utilisation.
- **Passifs** : toujours actifs (ex. +2 Défense sous 50 % de PV), ou déclenchés (au toucher, en subissant des dégâts, en soignant, quand un allié proche est blessé…). Leur activation s'affiche discrètement sur la carte et dans le récit.
- **Hors de combat** à 0 PV (pion grisé, tour sauté). Un soin peut relever un allié.
- **Victoire** quand tous les adversaires visibles sont à terre : XP partagée, or partagé, butin des monstres dans le **coffre du groupe**. **Défaite** si tout le groupe est à terre (le MJ raconte la suite).
- À la fin du combat, les effets temporaires, les recharges et les invocations disparaissent.

### Effets de statut

Étourdi, Immobilisé, Réduit au silence, Empoisonné, Saignement, Brûlure, Gelé, Affaibli, Vulnérable, Marqué, Aveuglé, Effrayé, Bouclier, En garde, Renforcé, Béni, Concentré, Hâte, Régénération, Invisible, Rage, Forme bestiale… Leurs icônes s'affichent au-dessus des pions, dans la frise des tours et sur la fiche (avec leur description). Le MJ peut en créer d'autres.

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

## Côté joueur

- **Bandeau du haut** : lieu, situation (phase, tour, à qui de jouer), objectif de la quête principale.
- **Récit** : narration du MJ (encadrée), messages, résultats de combat en lignes colorées (rouge dégâts, vert soins, violet effets, or récompenses), jets de dés. Filtres *Tout / Récit et discussions / Combat*. Saisie : *Message* (groupe ou MJ en privé), *Action* (libre, avec des débuts de phrase proposés), *Dés*. Les jets demandés par le MJ ont un bouton **Lancer le dé**.
- **Carte** : frise des tours (portraits, PV, effets), carte avec cases atteignables dorées et cibles entourées de rouge, chiffres flottants, panneau du tour (PA, attaques, défense, fin du tour) ou rappel de la phase et dés rapides.
- **Barre du bas permanente** : portrait (ouvre la fiche, « + » doré quand une montée de niveau attend), PV, ressource, jauge d'ultime, or, capacités équipées (coût, recharge, charge de l'ultime), **Sac**, **Fiche**, **Journal**.
- **Panneaux superposés** (fermeture par la croix, l'extérieur ou le bouton retour) :
  - *Capacité* : description, coûts, portée, cible, effets, raison si indisponible, *Utiliser* ;
  - *Fiche* : identité, niveau et XP, or, ressources, montée de niveau, effets en cours, caractéristiques (bonus en vert), valeurs de combat, bonus et malus, passif, capacités (équiper / retirer), équipement porté, histoire ;
  - *Sac* : emplacements (arme, armure, 2 accessoires), cases d'objets colorées par rareté, détail avec aperçu (« Défense 12 → 16 »), *Équiper*, *Utiliser*, *Lire*, *Donner à…*, *Jeter* ; onglet *Coffre du groupe* ;
  - *Journal* : quêtes (principales d'abord, objectifs, récompenses), groupe, codex, réglages (musique, connexion, aide).
- Sur PC (fenêtre large), la carte et le récit s'affichent côte à côte.

## Côté MJ

L'écran est organisé en quatre zones.

- **Gauche — joueurs** : adresse IP, joueurs (portrait, PV, ressource, niveau, or, effets, connexion), *Écrire*, *Jet*, *Fiche et outils*, *Déconnecter*, *Retirer*.
- **Centre — Carte et Récit** : la carte interactive (pions animés, chiffres flottants) et le récit complet, avec les **actions en attente** en haut (résoudre, refuser, *Le joueur lance*).
- **Bas — saisie et événements** : *Narration* (mise en forme récit) ou message simple, au groupe ou en privé ; dés publics, secrets ou montrés à un joueur. **Événement rapide…** : épreuve de groupe (jet demandé à chacun, avec caractéristique et difficulté), dégâts ou soins de groupe, récompense de groupe (XP, or, objet au coffre), embuscade (monstres placés puis combat lancé), créer un objet, nouvelle quête.
- **Droite — outils** :
  - **Combat** : choix de la phase, ordre des tours (▲ ▼ ×), au tour d'un monstre ses commandes (*Jouer automatiquement*, attaque rapide / puissante, se défendre, capacités) avec ciblage sur la carte, *Tour suivant*, fin de combat ; pion sélectionné (nom, PV, effets à appliquer, caché, note, couleur) ; coffre du groupe (donner, retirer).
  - **Monde** : musique (14 morceaux, diffusion aux téléphones, combat automatique), cartes (montrer, créer, dupliquer, propriétés, supprimer), outils de dessin (déplacer, peindre 29 terrains, pions, étiquettes secrètes, gomme, départ).
  - **Quêtes** : brouillons, en cours, terminées ; *Nouvelle quête* (principale / secondaire, donneur, description, objectifs, joueurs concernés ou tout le groupe, récompenses : XP, or, objets du catalogue ou créés sur mesure) ; *Donner aux joueurs*, objectifs à cocher, *Réussie : distribuer* (une seule fois), *Échouée*.
  - **Créer** : le catalogue de la campagne — **objets** (catégorie, rareté, icône, arme, bonus, effets à l'utilisation, effets à l'impact, capacités accordées, livre de compétence), **capacités** (coûts, portée, cible, zone, jet, recharge, ultime, effets), **effets de statut** (bonus / malus, étourdi, immobilisé, bouclier, dégâts ou soins par tour…), **monstres** et boss (caractéristiques, PV, attaque, capacités, XP, table de butin), **classes** (bonus, PV, ressource, passif, capacités, ultime, capacités à apprendre, kit), **tables de butin** (chances, quantités, objets garantis, or) et **règles** (points de création, PA, coûts, formules, XP, emplacements…). Actions directes : *Donner à…*, *Au coffre du groupe*, *Placer* un monstre, *Tirer* une table de butin.
  - **Fiches** : tous les personnages, *Nouveau PNJ*, *Packs de PNJ…* (convertis automatiquement), autoriser ou non les joueurs à modifier leur histoire.
  - **Codex** (avec les secrets MJ) et **Réseau** (état, adresses, journal des connexions).
- **Fiche et outils d'un personnage** : ± PV, soigner, mettre hors de combat, ± ressource, charger l'ultime, donner XP ou or, ± caractéristiques, donner un objet (du catalogue ou créé sur le moment), apprendre / oublier une capacité, équiper / retirer, appliquer / retirer un effet, inventaire, modifier l'histoire et les valeurs (fiche libre), placer sur la carte.
- **Journal du MJ** : chaque modification manuelle (PV, objets, effets, XP, règles…) est notée dans le récit, visible du MJ seul.

## Progression

- **XP** par paliers : 100 pour le niveau 2, 300 pour le 3, 600 pour le 4, 1 000 pour le 5… (réglable).
- À chaque niveau : PV et ressource en plus, **1 point de caractéristique** à placer, et **un choix** : apprendre une capacité de sa classe (accessible à partir d'un certain niveau) ou améliorer une capacité connue (rang 2, 3 : +2 aux dégâts / soins et −1 au coût par rang).
- Capacités **connues** et **équipées** : 3 de base + 1 ultime équipées (réglable) ; on change hors combat (en combat seulement si le MJ l'autorise).
- On apprend aussi des capacités grâce aux **livres** (objets), aux **objets** qui en accordent tant qu'ils sont équipés, et au **MJ** à tout moment.

## Objets et butin

- Catégories : arme, armure, accessoire, consommable, potion, matériau, objet de quête, livre, objet unique.
- Raretés : commun (gris), peu commun (vert), rare (bleu), épique (violet), légendaire (or).
- Emplacements : 1 arme, 1 armure, 2 accessoires (boucliers, anneaux, amulettes, bottes…).
- Effets possibles : caractéristiques, PV, ressource, Défense, toucher, dégâts, résistances, vitesse, soins, critique, PA ; effets à l'impact (poison, étourdissement, vol de vie…) ; capacités accordées ; consommables à effets.
- **Butin** : chaque monstre a une table de butin ; la victoire la tire et met les objets dans le **coffre du groupe** (premier arrivé, premier servi). Le MJ peut aussi tirer une table à la main, donner directement, ou retirer.

## Sauvegarde

Automatique toutes les minutes et à la fin de la session, plus le bouton *Sauver*. Tout est conservé : joueurs, fiches (classes, caractéristiques, passifs, capacités connues et équipées, niveaux, XP, inventaire, or, ressources, effets), catalogue et règles de la campagne (créations du MJ comprises), quêtes, coffre du groupe, cartes, pions, messages, phase en cours. Les anciennes sauvegardes sont converties à l'ouverture (l'original est copié à côté, en `.json.v1`). Une sauvegarde venant d'une version plus récente affiche un avertissement.
