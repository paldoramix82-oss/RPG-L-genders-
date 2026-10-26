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

Voir la fin du document (rempli au fil des phases).
