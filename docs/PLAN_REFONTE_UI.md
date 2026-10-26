# Refonte visuelle et ergonomique — audit et plan

Ce document suit la demande « Refonte visuelle et ergonomique de Legenders RPG »,
avec trois ajouts demandés en même temps : **jouer en paysage sur téléphone**,
**musique dans les menus** avant le début de la partie, et **brouillard de guerre**
(chaque joueur ne voit la carte qu'autour de lui, selon sa vision, liée à la Dextérité).

## 1. Audit de l'existant

### Architecture (inchangée)

| Couche | Fichiers | État |
|---|---|---|
| Réseau (hôte autoritaire, ENet) | `scripts/autoload/net.gd`, `scripts/net/*` | Fonctionnel, testé (3 scénarios multi-processus). Seul ajout : vue de la carte **par joueur** (brouillard). |
| Règles et moteur | `scripts/game/*` (`rules.gd`, `combat.gd`, `inventory.gd`, `effects.gd`, `content.gd`) | Fonctionnel, testé. Seul ajout : valeur dérivée `vision` et module `vision.gd`. |
| Sauvegarde | `campaign_store.gd`, format 2 | Inchangée (l'exploration est rangée dans les cartes, déjà sauvegardées). |
| Thème | `scripts/autoload/style.gd`, `scripts/ui/palette.gd` | Thème Godot unique construit en code : **refait** (habillage biseauté). |

### Composants d'interface déjà réutilisables (conservés)

`ResourceBar` (jauges animées), `Portrait` (portraits dessinés), `Icons` (≈ 70 icônes
vectorielles), `GameUI` (cartes de capacité, de passif, d'objet, cases de
caractéristique, rangées d'effets), `OverlayPanel` (panneaux superposés), `FeedView`
(récit), `MapView` (carte), `Composer` (saisie), `TabbedPages`, `TouchScroll`.

### Points faibles constatés

1. **Aspect « logiciel »** : panneaux et boutons à coins arrondis plats, fond uni ;
   peu de hiérarchie entre cartes ordinaires et importantes.
2. **Téléphone en portrait uniquement** (`window/handheld/orientation=1`) et échelle
   calculée sur la largeur : inutilisable en paysage.
3. **Pas de musique avant la partie.**
4. **Carte entièrement visible** par tous les joueurs.
5. Notifications limitées à un bandeau d'erreur rouge ; pas de retour pour les soins,
   objets reçus, ultime prêt, compétence apprise.
6. Fenêtres de confirmation système (`ConfirmationDialog`) qui détonnent.
7. Pas d'accès direct à la discussion pendant un combat (il faut quitter la carte).
8. Compétences : pas d'état « sélectionnée / en attente de cible », pas de raison
   « aucune cible à portée ».
9. Inventaire : pas de filtre par catégorie ; objets rares consommés sans confirmation.
10. Fiche : valeur de base et bonus d'équipement pas assez distingués.
11. Écran du MJ : zones de taille fixe, pas de zone basse « journal des actions /
    discussion », pas de raccourcis clavier.

## 2. Plan

| Phase | Contenu | Fichiers |
|---|---|---|
| A — Ajouts demandés | Brouillard de guerre (serveur + affichage + réglages MJ + tests) ; musique des menus ; orientation automatique et disposition paysage. | `vision.gd`, `session_server.gd`, `map_view.gd`, `music.gd`, `style.gd`, `player_screen.gd` |
| B — Système visuel | `OrnateStyle` (coins biseautés, dégradé, équerres dorées), palette noir bleuté, fond avec vignette, `Notifier` (notifications typées), `ConfirmBox` (confirmation intégrée), titres de section ornés. | `ornate_style.gd`, `style.gd`, `backdrop.gd`, `notifier.gd`, `game_ui.gd` |
| C — Écran joueur | Barre du bas : indicateur de tour et PA, bouton Discussion (pastille de non-lus), états des compétences, envoi en attente. Notifications de jeu (PV, objets, ultime, compétence). | `player_screen.gd` |
| D — Menus joueur | Fiche : base + bonus, vision ; inventaire : filtres par catégorie, nom sous les cases, confirmation des objets rares. | `character_sheet.gd`, `inventory_view.gd`, `game_ui.gd` |
| E — Combat | Frise : combattants hors de vue, éliminés barrés ; ciblage limité à la portée ; raisons précises ; bouton Objet. | `player_screen.gd`, `map_view.gd` |
| F — MJ | Zones redimensionnables (séparateurs), zone basse (discussion + journal), panneau joueurs enrichi (classe, niveau, effets, arme), raccourcis clavier. | `host_screen.gd` |
| G — Tests | Compilation, règles, réseau, captures portrait / paysage / PC. | `tests/*` |

Principe tenu partout : l'interface **demande** au serveur et **affiche** l'état qu'il
renvoie ; aucun calcul de règles n'est dupliqué dans l'interface (elle appelle
`Rules`, `Effects`, `Inventory.preview`).

## 3. Journal

| Phase | Réalisé | Vérifié |
|---|---|---|
| A — Ajouts | `vision.gd` (rayon, ligne de vue, exploration), vue de carte par joueur côté hôte, `fog` dans `EVT_MAP` / `EVT_TOKENS`, `EVT_FX` filtré ; réglages MJ (brouillard par carte, vision partagée, oubli, aperçu) ; `Music.set_menu` (thème principal avant la partie) ; orientation `sensor`, échelle sur le petit côté, réglage d'orientation ; disposition paysage. | `rules_test` : 12 vérifications de brouillard (vision 3 + DEX ÷ 2, loup proche visible / lointain caché, allié hors de vue, mur, étiquettes, exploration mémorisée, vision partagée, brouillard coupé, oubli, aperçu). `net_test` : le téléphone reçoit son brouillard. Captures paysage. |
| B — Système visuel | `OrnateStyle`, palette noir bleuté, `Backdrop` avec vignette, `Notifier`, `ConfirmBox`, `GameUI.section` / `ornament`, accueil refait (portrait et paysage, bouton Musique). | Compilation des 63 scripts ; captures. |
| C — Écran joueur | Bouton *Discuter* (panneau de discussion, non-lus, notification de message privé), indicateur de tour dans la barre, indicateur « Envoi… » (`outbox_changed`), notifications de jeu (PV, or, objets, compétences, effets, ultime), actions contextuelles (*Interagir*, *Action libre…*, *Utiliser un objet* ; menu *Idées d'actions…* en paysage), confirmation de départ intégrée. | Captures portrait 420 × 880 et paysage 900 × 420 ; pas de débordement horizontal après réglage des tailles. |
| D — Menus joueur | Fiche en en-tête + 4 onglets, base + bonus, vision, capacités à débloquer ; inventaire filtrable, noms sous les cases, comparaison avec écart, confirmations utiles. | Captures fiche et inventaire. |
| E — Combat | Ciblage limité à la portée, raisons « aucun ennemi / allié à portée », « aucun allié blessé », états de compétence (sélectionnée « CIBLE ? », coût insuffisant, recharge, ultime prêt), bouton *Objet*, *Fin du tour* compact, boutons bloqués pendant l'envoi, combattants hors de vue dans la frise. | Captures combat ; règles inchangées (les 80 vérifications précédentes passent toujours). |
| F — MJ | Zones à séparateurs, zone basse saisie + journal des actions, carte « Pour rejoindre » compacte, cartes joueurs (classe, niveau, arme), raccourcis clavier, confirmations intégrées, brouillard dans *Monde*, bouton **Aperçu** dans les créateurs (carte telle que les joueurs la verront, après la même validation que l'enregistrement). | Captures 1440 × 900 et 1280 × 720. Une boucle de mise en page (texte à retour à la ligne dans une zone redimensionnable) a été trouvée et corrigée (lignes du journal sur une seule ligne). |
| G — Tests | Compilation, `rules_test` (92 vérifications), `net_test` (3 scénarios, dont le brouillard). | **Non vérifié** : vrais téléphones Android (rotation réelle, encoche, clavier virtuel, vibrations, son), PC Windows. Voir `TEST_PHASE1.md`, sections F, I5 et J. |

### Limites connues

- Le terrain de toute la carte est transmis au téléphone (masqué à l'affichage) ; seuls les pions et étiquettes hors de vue ne sont pas envoyés.
- Pas d'illustrations : portraits, icônes et blasons sont dessinés en code, remplaçables plus tard.
- Factions : pas de système dédié ; le codex et les PNJ en tiennent lieu pour l'instant.
