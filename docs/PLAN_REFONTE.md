# Plan de refonte — LEGENDERS RPG

Ce document correspond à la **phase 1 (audit)** du cahier des charges « Refonte et amélioration ». Il décrit ce qui existe, ce qui manque, les choix techniques retenus et l'ordre de travail. Il sera mis à jour à la fin de chaque phase (section « Journal des phases » en bas).

Règle de conduite : **on améliore le projet existant, on ne repart pas de zéro**. Aucune fonctionnalité actuelle n'est supprimée ; quand un système change de forme (statistiques, capacités, inventaire), les anciennes fiches et sauvegardes sont **converties automatiquement**.

---

## 1. Audit de l'existant

### 1.1 Ce qui fonctionne (testé)

| Domaine | État | Où |
|---|---|---|
| Réseau local ENet, hôte autoritaire | Solide : authentification, version du protocole, file d'envoi avec `req_id` (pas de doublon après reconnexion), limitation du débit, reconnexion par jeton d'appareil, fin de session propre. 76 vérifications automatiques. | `scripts/net/`, `scripts/autoload/net.gd`, `tests/net_test.gd` |
| Connexion | Nom + adresse IP, pavé numérique, détection des parties sur le Wi-Fi, sans code. | `join_screen.gd` |
| Filtrage des secrets | Une seule fonction décide de ce que chaque téléphone reçoit (messages privés, pions cachés, codex MJ, fiches publiques). | `session_server.gd` (`can_see`, vues filtrées) |
| Messages et actions libres | Chat groupe / privé, actions libres « en attente du MJ », résolution, jet demandé au joueur avec difficulté. | `feed_view.gd`, `composer.gd` |
| Dés | Formules (`2d6+3`…), tirés par l'hôte, plateau animé. | `dice.gd`, `dice_tray.gd` |
| Cartes | 13 cartes, éditeur, pions, étiquettes cachées, rendu précalculé, zoom tactile. | `map_data.gd`, `map_view.gd`, `terrain_painter.gd` |
| Création assistée | 4 étapes, classes (9 Légenders, 6 Fantasy), répartition de points, choix d'équipement. | `creation_wizard.gd`, `rules.gd`, `data/classes/` (remplacé par `data/content/`) |
| Phases et tours | Récit libre, exploration, dialogue, combat, repos ; initiative ; attaque automatique ; MJ joue les PNJ. | `phases.gd`, `session_server.gd` |
| Sauvegarde | JSON avec écriture sûre (+ `.bak`), auto toutes les 60 s, reprise complète. | `campaign_store.gd` |
| Contenu | Univers Légenders (codex), 47 PNJ, 14 musiques synchronisées. | `data/` |

### 1.2 Ce qui est incomplet

- **Statistiques** : 6 caractéristiques (Force, Agilité, Endurance, Intelligence, Perception, Charisme) sur une échelle 10 ± modificateur. Le cahier des charges demande Force, **Dextérité, Constitution**, Intelligence, **Esprit**, Charisme, échelle 1–10, 5 partout + 15 points. Charisme et Intelligence n'ont presque aucun effet mécanique aujourd'hui.
- **Capacités** : 2 par classe, 3 types seulement (attaque, soin, effet « texte »). Pas d'icône, pas de recharge, pas de coût en points d'action, pas de type de cible, pas d'effets composables, **pas d'ultime ni de passif**.
- **Effets de statut** : inexistants (le champ `status` n'est qu'un texte).
- **Combat** : « déplacement + une action ». Pas de points d'action, pas d'attaque rapide / puissante, pas de défense, pas de résistances, pas d'effets en début / fin de tour, pas de condition de victoire ni de récompense.
- **Progression** : `level` et `xp` existent mais rien ne les fait évoluer ; pas de compétences connues / équipées.
- **Inventaire** : une liste de lignes (nom, dégâts, équipé). Pas de rareté, pas d'icône, pas d'identifiant d'objet, pas de comparaison, pas de tables de butin, pas d'objets à effets.
- **Journal** : pas de quêtes, pas de factions, pas d'état du monde.
- **Outils MJ** : modifications possibles mais dispersées (fiches, inspecteur de pion). Pas d'éditeur de classes, capacités, objets, effets ; modifications manuelles non journalisées.
- **Aide** : aucun tutoriel ni explication dans le jeu ; la documentation suppose que l'on connaît le jeu de rôle.

### 1.3 Ce qui doit être amélioré

- **Interface joueur** : organisée en 5 onglets (Carte, Aventure, Fiche, Groupe, Codex). PV / énergie pas visibles en permanence, capacités cachées dans un menu, pas de portrait. Le cahier des charges demande une **barre inférieure permanente** et des **panneaux superposés**.
- **Interface MJ** : `host_screen.gd` fait 1 500 lignes et empile tout dans une colonne de droite. À réorganiser en 4 zones et à découper en plusieurs panneaux.
- **Identité visuelle** : la palette (anthracite, or, violet) est en place mais il manque portraits, icônes, raretés, animations courtes, hiérarchie typographique plus marquée.
- **Synchronisation** : toutes les fiches sont renvoyées à chaque changement. C'est suffisant pour 3–6 joueurs, mais il faudra des événements plus fins (ressource modifiée, objet reçu) pour animer l'interface sans tout reconstruire.

### 1.4 Risques pour le multijoueur

| Risque | Parade |
|---|---|
| Changer le protocole oblige à mettre à jour **tous** les téléphones | Le contrôle de version existe déjà : message clair « installez la même version ». Une seule montée de version par phase livrée. |
| Récompense ou dégâts appliqués deux fois après une reconnexion | Toute commande mécanique passe par le `req_id` déjà dédoublonné ; chaque butin reçoit un identifiant et n'est distribué qu'une fois côté hôte. |
| Un téléphone qui tente d'imposer un résultat | Le téléphone n'envoie que des **intentions** (« j'utilise la capacité X sur Y »). Tous les calculs restent sur l'hôte. |
| Anciennes sauvegardes cassées | Format de sauvegarde versionné (`format` 1 → 2) avec conversion automatique, copie `.bak` avant conversion, avertissement si la sauvegarde vient d'une version plus récente. |
| Messages plus gros (catalogues de contenu) | Le catalogue (classes, capacités, objets) est envoyé une fois à la connexion, puis seulement les changements. |
| Téléphones modestes | Animations courtes en `Tween`, pas de shaders lourds, icônes dessinées (vectorielles) plutôt que de grandes textures. |

---

## 2. Choix techniques

### 2.1 Données : JSON plutôt que `Resource` Godot

Le cahier des charges suggère les ressources Godot « lorsqu'il convient ». Ici, les données doivent être **modifiées pendant la partie par le MJ**, **envoyées sur le réseau** et **sauvegardées dans la campagne**. Les `Resource` (.tres) sont faites pour être éditées dans l'éditeur Godot et se sérialisent mal sur le réseau. On garde donc des dictionnaires JSON validés (comme aujourd'hui pour les classes, cartes, PNJ), avec :

- un **catalogue par défaut** dans `data/` (livré avec le jeu) ;
- une **copie dans chaque campagne**, que le MJ modifie librement (ses créations sont sauvegardées avec la campagne) ;
- des **identifiants stables** (`ability.fireball`, `item.dague_de_l_ombre`…) pour tout ce qui est référencé.

### 2.2 Un seul moteur d'effets

Capacités, ultimes, passifs, objets utilisables et effets de statut utilisent **la même liste d'effets composables** :

```json
{"effects": [
  {"type": "damage", "dice": "2d6", "stat": "Force", "element": "physique"},
  {"type": "status", "status": "etourdi", "turns": 1, "chance": 50}
]}
```

Effets génériques prévus : dégâts, soin, restaurer une ressource, bonus, malus, modifier une caractéristique (temporaire), étourdir, immobiliser, attirer / repousser, protéger une cible (bouclier), invoquer (pion), effet conditionnel (« si la cible est blessée… »), message narratif. Un seul interpréteur côté hôte : `scripts/game/effects.gd`.

### 2.3 Organisation des fichiers (ajouts)

```
data/rulesets/<univers>/   classes, abilities, items, statuses, loot, monsters, rules.json
scripts/game/
  rules.gd        (existant, étendu) formules, caractéristiques
  content.gd      catalogue : chargement, validation, identifiants, copie campagne
  effects.gd      interpréteur d'effets composables
  combat.gd       points d'action, tours, statuts, victoire (sorti de session_server.gd)
  inventory.gd    équiper, utiliser, comparer, déposer, butin
  progression.gd  XP, niveaux, apprentissage
  migrate.gd      conversion des anciennes fiches / sauvegardes
scripts/ui/
  player/         barre inférieure, panneaux fiche / inventaire / capacités / journal
  host/           panneaux MJ (joueurs, combat, créateurs de contenu)
  widgets/        jauges animées, icônes, portraits, info-bulles, cartes d'objet
```

`session_server.gd` garde le réseau, la visibilité et la sauvegarde ; la logique de jeu en sort pour qu'il ne grossisse plus.

---

## 3. Règles proposées (modifiables par le MJ)

Toutes les valeurs ci-dessous sont dans `rules.json` de la campagne et réglables par le MJ.

### 3.1 Caractéristiques (échelle 1–10)

| Caractéristique | Sert à |
|---|---|
| **Force** | dégâts au corps à corps, attaques puissantes, épreuves de force |
| **Dextérité** | toucher, esquive (défense), initiative, discrétion, armes de jet / tir |
| **Constitution** | PV, résistance physique, résistance au poison |
| **Intelligence** | puissance des sorts de savoir, analyse, réserve de mana de certaines classes |
| **Esprit** | mana, résistance mentale et magique, puissance des soins |
| **Charisme** | persuasion / intimidation, efficacité des capacités de soutien (bonus aux alliés), prix chez les marchands |

Création : 5 partout + 15 points, entre 1 et 10. Bouton « Réinitialiser ».

### 3.2 Formules

- **Épreuve** (action libre ou compétence) : d20 + caractéristique (+ bonus) ≥ difficulté (10 facile, 15 moyen, 20 difficile). Le MJ choisit la caractéristique ; le jeu propose la plus logique.
- **Toucher** : d20 + Dextérité (armes fines, tir) ou Force (armes lourdes) + bonus ≥ **Défense** de la cible.
- **Défense** = 8 + Dextérité + armure + bonus.
- **Dégâts** = dés de l'arme ou de la capacité + moitié de la caractéristique utilisée − **résistance** de la cible (minimum 1).
- **Résistance physique** = Constitution ÷ 3 + armure ; **résistance magique** = Esprit ÷ 3 + bonus.
- **PV max** = PV de classe + Constitution × 3 (+ gain par niveau).
- **Mana max** = mana de classe + Esprit × 2 (ou Intelligence, selon la classe).
- **Initiative** = d20 + Dextérité.
- **Critique** : 20 naturel (ou plage de l'arme, améliorée par la classe) → dés doublés. 1 naturel : échec.
- **Soins** = dés du soin + moitié de l'Esprit.

### 3.3 Combat

- **2 points d'action (PA)** par tour (réglable).
- Coûts par défaut : déplacement 1 PA (jusqu'à la vitesse), attaque rapide 1 PA, attaque puissante 2 PA (+50 % de dégâts, −2 au toucher), capacité 1–2 PA (selon la capacité), objet 1 PA, **défense** 1 PA (+3 défense jusqu'au prochain tour).
- **Gratuit** : parler, chat, décrire une action narrative. Une action libre mécanique coûte ce que le MJ décide.
- Effets de statut : durée en tours, déclenchement en début ou fin de tour, icône sur le pion et dans la frise.
- Fin du combat : quand tous les ennemis (ou tous les joueurs) sont à 0 PV, ou sur décision du MJ → écran de victoire avec XP et butin.

### 3.4 Capacités

Champs : nom, icône, description, coût (mana ou autre ressource), coût en PA, portée, recharge (en tours), type de cible (soi, allié, ennemi, zone, toutes cibles), puissance, caractéristique, effets, conditions.

- 4 emplacements équipés : **3 de base + 1 ultime** (réglable).
- **Ultime** : jauge qui se remplit en infligeant ou subissant des dégâts (100 %), utilisable une fois par combat.
- **Passif** : déclencheur (début de tour, PV sous 50 %, coup critique, soin donné…) + condition + effets. Activation signalée par une petite bannière sur le pion et une ligne discrète dans le journal.

### 3.5 Classes de départ (Fantasy)

Guerrier, Mage, Assassin, **Gardien** (nouveau), Soigneur (le Prêtre actuel), Rôdeur. Le **Barde** existant est conservé comme 7ᵉ classe. Les 9 classes Légenders sont converties au même format (3 capacités + ultime + passif). Le MJ peut créer, modifier, supprimer des classes.

### 3.6 Progression

- XP par paliers (réglables). À chaque niveau : PV en plus automatiquement, **+1 point de caractéristique à placer**, et un **choix** : apprendre une nouvelle capacité (parmi 2 proposées par la classe) **ou** améliorer une capacité connue (rang 2 : plus de dégâts / moins de coût).
- Capacités **connues** et **équipées** distinctes. Changer ses capacités équipées : hors combat librement, en combat seulement si le MJ l'autorise.
- Le MJ peut à tout moment donner XP, capacité, point de caractéristique.

### 3.7 Objets et butin

- Catégories : arme, armure, accessoire, consommable, potion, matériau, quête, livre de compétence, unique.
- Raretés : commun (gris), peu commun (vert), rare (bleu), épique (violet), légendaire (or).
- Un objet = données : modificateurs (caractéristiques, PV, mana, défense, dégâts, résistances), effets à l'utilisation (même moteur d'effets), effets spéciaux (débloquer une capacité, effet en combat).
- Tables de butin : entrées avec probabilité, quantité min–max, garanties, objets uniques (une seule fois par campagne). Le MJ peut aussi donner directement.

### 3.8 Quêtes, or et créations à tout moment

- **Quêtes** données par le MJ à tout moment, à un joueur, à plusieurs ou à tout le groupe : **principales** ou **secondaires**, avec description, objectifs à cocher, état (en cours, réussie, échouée) et **récompenses** : XP, **or**, objets. Le MJ peut préparer une quête en brouillon puis la donner plus tard. À la réussite, l'hôte distribue les récompenses **une seule fois**.
- **Or** : nouvelle ressource sur chaque fiche (gagnée par quêtes, butin, dons du MJ).
- **Créations à tout moment** : le MJ peut créer un objet en pleine partie (nom, rareté, catégorie, effets…) et le donner immédiatement, ou le mettre dans le butin. Même chose pour les monstres, les effets de statut et les capacités.
- **Événements rapides du MJ** : annonce narrative, épreuve de groupe (jet demandé à tous), dégâts ou soins de groupe, récompense de groupe, embuscade (monstres placés + combat lancé).

---

## 4. Plan par phases

Chaque phase se termine par : tests automatiques, captures PC + téléphone, mise à jour du guide débutant, commit, compte rendu (changements, tests, problèmes, reste à faire).

### Phase 1 — Audit ✅ (ce document)

> **État au 26/10/2026 : phases 2 à 6 réalisées et testées automatiquement ; phase 7 en partie (reste l'essai sur vrais appareils).** Détail dans le journal ci-dessous.

### Phase 2 — Données et création de personnage
1. Catalogue de contenu (`content.gd`) : classes, capacités, objets, statuts, règles ; copie dans la campagne.
2. Nouvelles caractéristiques et formules (`rules.gd`), conversion des anciennes fiches (`migrate.gd`, format de sauvegarde 2).
3. 7 classes Fantasy + 9 Légenders au nouveau format (3 capacités, ultime, passif, kit et choix d'objets).
4. Assistant de création refait : Identité (nom, portrait, description, histoire et personnalité facultatives) → Classe → Caractéristiques (5 + 15, réinitialiser) → Équipement → **Récapitulatif** avec retour possible.
5. Portraits générés (silhouette + couleurs + emblème de classe), choix parmi plusieurs variantes.
6. Tests : création valide / invalide, conversion d'une ancienne sauvegarde, synchronisation des fiches.

### Phase 3 — Moteur de combat
1. `effects.gd` : interpréteur d'effets composables.
2. `combat.gd` : PA, coûts, attaque rapide / puissante, défense, capacités, recharges, jauge d'ultime, passifs, statuts (début / fin de tour), éliminations, victoire / défaite.
3. Commande réseau unique `combat_action` (intention), réponse = résultat calculé + raison du refus.
4. Tests automatiques sur les formules et un combat complet joueur contre monstres en réseau.

### Phase 4 — Progression et butin
1. XP, niveaux, choix à la montée de niveau, capacités connues / équipées.
2. Inventaire en données (identifiants, raretés, quantités), équiper avec aperçu « Défense 12 → 16 », utiliser, consommer, déposer, comparer.
3. Tables de butin, écran de victoire, distribution sans doublon.
4. **Quêtes** principales et secondaires (objectifs, état, récompenses XP / or / objets distribuées une seule fois), **or**, journal des quêtes côté joueur.
5. Création d'objets et dons du MJ à tout moment ; événements rapides (annonce, épreuve de groupe, dégâts / soins de groupe, récompense, embuscade).

### Phase 5 — Refonte de l'interface joueur (puis MJ)
1. Écran joueur en 3 zones : bandeau (lieu, situation, objectif), centre (récit / carte), **barre inférieure permanente** (portrait, PV, mana, 3 capacités + ultime, Inventaire, Fiche, Journal).
2. Panneaux superposés (glissent du bas sur téléphone, à droite sur PC), fermeture par geste ou bouton.
3. Jauges animées (chiffres flottants rouges / verts / bleus), frise des tours avec portraits et statuts, combattant actif mis en avant.
4. Récit : narration du MJ (parchemin), messages des joueurs (bulles), résultats mécaniques (pastilles colorées), filtre « tout / récit / combat ».
5. **Aide intégrée** : première partie guidée (bulles d'explication), bouton « ? » sur chaque panneau, info-bulles sur les caractéristiques et capacités.
6. Interface MJ en 4 zones : gauche joueurs + ressources, centre récit / carte, droite outils, bas chat + commandes rapides.

### Phase 6 — Outils du MJ
1. Personnage sélectionné → actions rapides : ± PV, ± mana, XP, donner objet, apprendre capacité, appliquer / retirer effet. Journal des modifications manuelles.
2. Créateurs : classes, passifs, capacités et ultimes (composeur d'effets), objets, statuts, monstres / boss, tables de butin, PNJ, événements.
3. Écran « Règles de la campagne » (points de création, PA, paliers d'XP, emplacements…).

### Phase 7 — Tests et stabilisation
Scénarios réseau élargis (création, combat complet, butin, montée de niveau, reconnexion en plein combat, reprise de campagne convertie), captures sur tous les écrans, liste de vérification sur vrai PC Windows et vrais téléphones, corrections.

---

## 5. Ce qui ne pourra être vérifié que par vous

L'environnement de développement est sous Linux, sans téléphone. Je teste avec plusieurs instances du jeu en réseau local simulé et des captures en résolution téléphone. **Le fonctionnement sur un vrai PC Windows et de vrais téléphones Android** (Wi-Fi, pare-feu, performances, tactile) reste à confirmer par vous avec `docs/TEST_PHASE1.md`, mis à jour à chaque phase.

---

## Journal des phases

| Phase | Date | Résumé | Tests |
|---|---|---|---|
| 1 — Audit | 2026-10-26 | Audit, choix techniques, règles proposées, plan, guide débutant. | Aucun code modifié ; 76 vérifications réseau toujours au vert. |
| 2 — Données et création | 2026-10-26 | Catalogue de campagne (`content.gd`, `data/content/`), 6 caractéristiques (5 + 15), formules (`rules.gd`), 7 + 9 classes (passif, 3 capacités, ultime, capacités à apprendre, kits), assistant en 5 étapes avec portraits, création construite par l'hôte, conversion des anciennes fiches et sauvegardes (`migrate.gd`, format 2, copie `.json.v1`). | `rules_test` : catalogue, répartition (valide / trop de points / bornes), PV et Défense, équipement choisi, triche refusée, conversion d'anciennes fiches. Captures des 5 étapes. |
| 3 — Combat | 2026-10-26 | `combat.gd` : 2 PA, attaques rapide / puissante, défense, capacités à effets composables, 23 statuts, passifs (toujours / déclenchés / protection d'allié), jauge d'ultime, recharges, invocations, victoire / défaite, jeu automatique des monstres. | `rules_test` : PA, refus faute de PA, ressource payée, recharge, ultime bloqué, statuts, étourdi qui perd son tour, monstres automatiques, victoire unique. `net_test` : attaques joueur et PNJ en réseau. |
| 4 — Progression et butin | 2026-10-26 | Niveaux et choix, capacités connues / équipées, inventaire (équiper avec aperçu, utiliser, lire, donner, jeter), raretés, tables de butin, coffre commun, or, **quêtes** (principales / secondaires, récompenses uniques), objets créés à tout moment, événements rapides. | `rules_test` : niveau 2, point placé, capacité apprise et échangée, objet créé et donné, livre, butin de boss, coffre (pas de double prise), quêtes (brouillon, assignation, récompense unique), sauvegarde et reprise. `net_test` : quête reçue, coffre en réseau. |
| 5 — Interface joueur | 2026-10-26 | Écran en 3 zones, barre du bas permanente, panneaux superposés (fiche, sac, journal, capacité, aide), frise des tours, chiffres flottants, couleurs fonctionnelles, icônes et portraits dessinés, actions contextuelles, aide intégrée, défilement tactile dans les panneaux. | Captures téléphone (420 × 880) et PC ; corrections de débordement horizontal et de hauteur. |
| 6 — Outils du MJ | 2026-10-26 | Tableau en 4 zones, outils par personnage (journalisés), créateurs (objets, capacités avec composeur d'effets, statuts, monstres, classes, butin, règles), quêtes, coffre, commandes des monstres, événements rapides. | Captures PC des panneaux ; logique testée par `rules_test` / `net_test`. |
| 7 — Stabilisation | en cours | Compilation de tous les scripts (`tests/check.sh`), tests de règles et réseau au vert. | **Reste : essai sur un vrai PC Windows et de vrais téléphones Android** (`TEST_PHASE1.md`, sections G, H, I). |

### Limites connues

- Les portraits et icônes sont dessinés en code (pas d'illustrations) ; l'icône d'un objet se choisit par son nom technique dans l'éditeur.
- Les éditeurs de classe ne modifient pas encore les « choix d'équipement » (trois dagues…) : ils sont conservés tels quels.
- Les effets « repousser / attirer » suivent la ligne entre les deux pions et s'arrêtent au premier obstacle.
- Pas encore de marchands : l'or sert aux échanges racontés par le MJ.
