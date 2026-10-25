# Feuille de route

## Phase 1 — prototype réseau ✅ (code) / ⏳ (validation sur appareils réels)

| # | Étape | État |
|---|---|---|
| 1 | Projet Godot 4.4 (Windows + Android, rendu Compatibility) | ✅ |
| 2 | Écran d'accueil Héberger / Rejoindre | ✅ |
| 3 | Lancement du serveur sur le PC | ✅ |
| 4 | Affichage IP locale, port, code | ✅ |
| 5 | Connexion d'un client Android (IP + port + code) | ✅ code — ⏳ à tester sur téléphone |
| 6 | Liste des joueurs connectés (MJ et joueurs), état, ping | ✅ |
| 7 | Messages PC ⇄ Android (publics et privés) | ✅ |
| 8 | Test sur appareils réels | ⏳ **à faire** : [TEST_PHASE1.md](TEST_PHASE1.md) |

Déjà en place en plus du minimum : validation des joueurs par le MJ, refus/expulsion/retrait, anti-force brute du code, reconnexion automatique avec conservation du joueur, file d'envoi sans doublon, découverte automatique facultative, fin de session propre, test automatisé.

**Ce qui manque pour clore la phase 1** : uniquement le retour du test sur un vrai PC Windows et de vrais téléphones Android. Le code n'a pas pu être exécuté sur Windows ni sur Android depuis l'environnement de développement (il a été testé sous Linux, réseau UDP réel entre processus).

## Phase 2 — première partie jouable (après validation de la phase 1)

1. Création d'une campagne (nom, univers, règles de départ, nombre de joueurs) et chargement d'une campagne existante.
2. Rejointure avec le code (déjà fait) liée à une campagne précise.
3. Création des personnages sur le téléphone (identité, 6 caractéristiques, compétences, capacités libres).
4. Champ d'action libre (prioritaire) : identifiant, auteur, date, description, statut, visibilité, jet, difficulté, résultat, commentaire du MJ.
5. File des actions côté MJ : demander des précisions, demander un jet, fixer une difficulté, résoudre, refuser, conséquence, réponse privée.
6. Diffusion des résultats (publics au groupe, privés aux seuls concernés).
7. Journal chronologique (public / privé, notes du MJ, événements importants).
8. Messages privés (déjà fait, à relier au journal).
9. Sauvegarde JSON atomique sur le PC + reprise ; personnages conservés entre les soirées.
10. Campagne de démonstration « Les Cendres de Valombre » (ville, taverne, forêt, ruines, 3 PNJ, une faction, objets, un événement mystérieux, secrets).

## Phase 3 — outils du MJ

Lieux, PNJ, objets et inventaires, lancers de dés (D4 à D100, plusieurs dés, modificateurs, jets publics/secrets calculés sur le serveur), événements (immédiats/différés, publics/privés), modification des personnages, outils rapides accessibles sans quitter le tableau de bord.

## Phase 4 — extension du RPG

Combats au tour par tour (sans grille), factions et réputations, carte stylisée filtrée par joueur, progression configurable, variables persistantes du monde, historique avancé, finitions visuelles.

## Univers Légenders

Les documents fournis (système AEC, dix catégories magiques, Gardiens et Légenders, mutants, rangs B → L, géopolitique) pourront alimenter, à partir de la phase 2, des **modèles facultatifs** : catégories de magie proposées à la création des capacités, rangs comme système de progression optionnel, factions et lieux. Le moteur restera générique : le MJ pourra toujours créer des capacités hors catégories et modifier ou ignorer ces modèles. La campagne de démonstration demandée reste « Les Cendres de Valombre ».
