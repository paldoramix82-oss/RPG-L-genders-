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
| **Dextérité** | toucher des armes fines et de tir, Défense, initiative, discrétion, **vision** |
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
| Vision | 3 + Dextérité ÷ 2 cases (+ bonus d'objets « Vision ») |

### Vision et brouillard de guerre

Chaque joueur ne voit la carte qu'autour de **son** personnage, jusqu'à sa vision (en cases, distance réelle). Les terrains **Mur, Forêt dense, Montagne et Toits** bloquent la ligne de vue (la case elle-même reste visible). Les cases déjà vues restent connues (assombries) : c'est l'**exploration**, mémorisée par l'hôte pour chaque joueur et chaque carte, et sauvegardée.

C'est l'hôte qui filtre : un téléphone ne reçoit **que** les pions et les étiquettes qu'il voit (plus les étiquettes des zones explorées) ; le terrain est transmis mais masqué à l'affichage. Les chiffres de combat d'un pion invisible ne sont pas envoyés.

Réglages du MJ : brouillard par carte (*Monde*), *Oublier l'exploration*, *Voir le brouillard des joueurs* (aperçu), et dans *Créer › Règles* : vision de base, « +1 case tous les N points de Dextérité », **vision partagée** (chaque joueur voit ce que voit tout le groupe).

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
- **Barre du bas permanente** : portrait (ouvre la fiche, « + » doré quand une montée de niveau attend), PV, ressource, jauge d'ultime, or, indicateur de tour (« À VOUS · 2 PA »), capacités équipées, **Sac**, **Fiche**, **Journal**, **Discuter** (pastille de non-lus).
- **États des capacités** : disponible ; coût insuffisant (coût en rouge) ; en recharge (tours restants en grand) ; inutilisable (grisée, la raison s'affiche au toucher : pas votre tour, PA, mana, recharge, ultime pas chargé, aucun ennemi ou allié à portée, aucun allié blessé) ; sélectionnée en attente de cible (cadre doré, « CIBLE ? »). Le ciblage n'entoure que les pions **à portée**.
- **Panneau du tour** : « À vous ! », points d'action restants, *Attaque rapide*, *Attaque puissante*, *Se défendre*, *Objet* (ouvre le sac), chacun avec son coût en PA (grisé si impossible), et *Fin du tour* compact. Pendant qu'une action attend la réponse de l'hôte, les boutons sont bloqués et l'indicateur de connexion affiche « Envoi… ».
- **Discussion** : *Discuter* ouvre un panneau avec la conversation et la saisie par-dessus la carte ; parler ne coûte aucun PA et n'interrompt pas le combat. Les messages privés reçus déclenchent une notification.
- **Notifications** (en haut, 3 au plus, se ferment d'un toucher) : PV récupérés, objet obtenu, or reçu, compétence apprise, effet subi, ultime disponible, action refusée (avec la raison). Elles reflètent l'état confirmé par l'hôte ; tout reste aussi dans le récit.
- **Paysage** : en tournant le téléphone, la barre du bas devient une colonne à droite (bascule Récit / Carte, personnage, capacités, boutons), le panneau du tour passe à côté de la carte, et les idées d'actions tiennent dans un menu *Idées d'actions…*. Orientation automatique, ou bloquée en portrait / paysage dans *Journal › Réglages › Affichage*. Les zones système (encoche, barre de navigation) sont respectées.
- **Panneaux superposés** (fermeture par la croix, l'extérieur ou le bouton retour) :
  - *Capacité* : description, coûts, portée, cible, effets, raison si indisponible, *Utiliser* ;
  - *Fiche* : en-tête (portrait, nom, classe, niveau, XP, or, PV, ressource, ultime, effets), montée de niveau si elle attend, puis quatre onglets — *Personnage* (caractéristiques avec base + bonus, valeurs de combat dont la vision, bonus et malus, effets), *Capacités* (passif, équipées, connues, à débloquer avec leur niveau), *Équipement* (porté, contenu du sac), *Histoire* ;
  - *Sac* : emplacements (arme, armure, 2 accessoires), cases d'objets colorées par rareté avec leur nom, filtres par catégorie (seulement celles présentes), détail avec comparaison (« Défense 12 → 16 (+4) » en vert, pertes en rouge), *Équiper*, *Utiliser* (confirmation seulement pour un objet rare ou mieux), *Lire*, *Donner à…*, *Jeter* (avec confirmation) ; onglet *Coffre du groupe* ;
  - *Journal* : quêtes (principales d'abord, objectifs, récompenses), groupe, codex, réglages (musique, connexion, aide).
- Sur PC (fenêtre large), la carte et le récit s'affichent côte à côte.

## Côté MJ

L'écran est organisé en quatre zones, séparées par des **barres déplaçables** à la souris. Raccourcis : Ctrl + S sauvegarder, F1 carte, F2 récit, F5 tour suivant (combat), Ctrl + E événement rapide, Ctrl + Q nouvelle quête, Ctrl + N écrire, Échap fermer un panneau (bouton *Raccourcis* en haut).

- **Gauche — joueurs** : adresse IP, joueurs (portrait, PV, ressource, niveau, or, effets, connexion), *Écrire*, *Jet*, *Fiche et outils*, *Déconnecter*, *Retirer*.
- **Centre — Carte et Récit** : la carte interactive (pions animés, chiffres flottants) et le récit complet, avec les **actions en attente** en haut (résoudre, refuser, *Le joueur lance*).
- **Bas — journal des actions** : une ligne par événement récent (combats, récompenses, phases, propositions d'action, jets, connexions), le détail au survol.
- **Bas — saisie et événements** : *Narration* (mise en forme récit) ou message simple, au groupe ou en privé ; dés publics, secrets ou montrés à un joueur. **Événement rapide…** : épreuve de groupe (jet demandé à chacun, avec caractéristique et difficulté), dégâts ou soins de groupe, récompense de groupe (XP, or, objet au coffre), embuscade (monstres placés puis combat lancé), créer un objet, nouvelle quête.
- **Droite — outils** :
  - **Combat** : choix de la phase, ordre des tours (▲ ▼ ×), au tour d'un monstre ses commandes (*Jouer automatiquement*, attaque rapide / puissante, se défendre, capacités) avec ciblage sur la carte, *Tour suivant*, fin de combat ; pion sélectionné (nom, PV, effets à appliquer, caché, note, couleur) ; coffre du groupe (donner, retirer).
  - **Monde** : musique (14 morceaux, diffusion aux téléphones, combat automatique), cartes (montrer, créer, dupliquer, propriétés, supprimer, **brouillard de guerre**, *Voir le brouillard des joueurs*, *Oublier l'exploration*), outils de dessin (déplacer, peindre 29 terrains, pions, étiquettes secrètes, gomme, départ).
  - **Quêtes** : brouillons, en cours, terminées ; *Nouvelle quête* (principale / secondaire, donneur, description, objectifs, joueurs concernés ou tout le groupe, récompenses : XP, or, objets du catalogue ou créés sur mesure) ; *Donner aux joueurs*, objectifs à cocher, *Réussie : distribuer* (une seule fois), *Échouée*.
  - **Créer** : le catalogue de la campagne — **objets** (catégorie, rareté, icône, arme, bonus, effets à l'utilisation, effets à l'impact, capacités accordées, livre de compétence), **capacités** (coûts, portée, cible, zone, jet, recharge, ultime, effets), **effets de statut** (bonus / malus, étourdi, immobilisé, bouclier, dégâts ou soins par tour…), **monstres** et boss (caractéristiques, PV, attaque, capacités, XP, table de butin), **classes** (bonus, PV, ressource, passif, capacités, ultime, capacités à apprendre, kit), **tables de butin** (chances, quantités, objets garantis, or) et **règles** (points de création, PA, coûts, formules, XP, emplacements…). Le bouton **Aperçu** montre la carte de l'objet, de la capacité, de l'effet, du monstre ou de la classe telle que les joueurs la verront, avant d'enregistrer. Actions directes : *Donner à…*, *Au coffre du groupe*, *Placer* un monstre, *Tirer* une table de butin.
  - **Fiches** : tous les personnages, *Nouveau PNJ*, *Packs de PNJ…* (convertis automatiquement), autoriser ou non les joueurs à modifier leur histoire.
  - **Codex** (avec les secrets MJ) et **Réseau** (état, adresses, journal des connexions).
- **Fiche et outils d'un personnage** : ± PV, soigner, mettre hors de combat, ± ressource, charger l'ultime, donner XP ou or, ± caractéristiques, donner un objet (du catalogue ou créé sur le moment), apprendre / oublier une capacité, équiper / retirer, appliquer / retirer un effet, inventaire, modifier l'histoire et les valeurs (fiche libre), placer sur la carte.
- **Journal du MJ** : chaque modification manuelle (PV, objets, effets, XP, règles…) est notée dans le récit, visible du MJ seul.

## Musique

Avant le début de la partie (menus, création du personnage, salon), le **thème principal** joue en fond, sur le PC comme sur les téléphones ; le bouton *Musique* de l'accueil le coupe (réglage gardé par l'appareil). Si le MJ lance un morceau, c'est le sien qu'on entend ; quand la partie commence, le thème s'arrête et c'est le MJ qui choisit la musique.

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
