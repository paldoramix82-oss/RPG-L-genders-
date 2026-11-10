# Feuille de route

## Fait

**Réseau (phase 1)** — hôte autoritaire ENet/UDP, connexion par simple adresse IP (sans code), validation facultative par le MJ, reconnexion automatique avec conservation du joueur, file d'envoi sans doublon, découverte facultative sur le Wi-Fi, fin de session propre. **N'importe quel appareil peut héberger** (PC ou Android).

**Partie jouable (phases 2 à 4, version actuelle)**
- Campagnes : création avec choix de l'univers, sauvegarde automatique (JSON, écriture sûre avec copie de secours), reprise.
- Univers : Légenders (codex tiré des documents fournis), Fantasy classique (Les Cendres de Valombre), Univers libre. Entrées secrètes réservées au MJ.
- Fiches de personnage libres (joueurs et PNJ), modifiables par le MJ, verrouillables.
- Actions libres déclarées et résolues par le MJ (résultat, jet facultatif).
- Dés génériques (d4 → d100, plusieurs dés, modificateurs, formules), jets publics, secrets ou montrés à un joueur, calculés par l'hôte.
- Messages publics et privés, fil du récit, événements automatiques (arrivée d'un personnage, changement de lieu, combat).
- Cartes interactives : 9 cartes prêtes, éditeur (terrain, pions, étiquettes, point de départ, taille), pions animés, carte affichée choisie par le MJ, pions et étiquettes cachés.
- Combat au tour par tour sur la carte (initiative, ordre modifiable, PV, tour en surbrillance, déplacement réservé au combattant actif).
- Interface responsive : colonnes sur PC, onglets sur téléphone.
- Cartes illustrées (rendu précalculé), 4 grandes cartes pour les longues campagnes, 29 terrains, pions façon jeu de plateau, mises à jour légères des pions.
- Packs de PNJ (47 fiches) importables.
- Dés lancés par les joueurs eux-mêmes (plateau animé, jets demandés par le MJ avec difficulté, réussite/échec).
- **Prise en main simplifiée** : assistant de création (classes prêtes à jouer, 12 points à répartir, équipement au choix), PV / défense / initiative calculés, salon d'attente et bouton « La partie commence ! », phases de jeu (récit libre, exploration, dialogue, combat, repos) au tour par tour avec attaques automatiques (critiques par arme et par classe), défilement tactile facile sur téléphone, saisie de l'IP au pavé numérique.
- **Refonte RPG (voir PLAN_REFONTE.md)** : six caractéristiques (5 + 15 points), classes avec passif, 3 capacités et ultime ; combat à 2 points d'action, effets de statut, passifs, jauge d'ultime, victoire et butin ; niveaux, capacités connues / équipées, inventaire à raretés, coffre du groupe, or ; quêtes principales et secondaires ; créations du MJ en pleine partie (objets, capacités, effets, monstres, classes, butin, règles) ; nouvelles interfaces joueur (barre permanente, panneaux superposés) et MJ (quatre zones) ; conversion des anciennes sauvegardes.
- Bande originale de 14 morceaux composés pour le jeu, synchronisée sur les téléphones, musique de combat automatique.

## À valider par vous

L'application n'a été exécutée que sous Linux (tests réseau entre processus, captures d'écran). **Il faut l'essayer sur un vrai PC Windows et de vrais téléphones Android** : [TEST_PHASE1.md](TEST_PHASE1.md).

## Pistes suivantes (non commencées)

- Marchands et économie (acheter / vendre avec l'or).
- Factions et réputations ; variables persistantes du monde (porte ouverte, pont détruit…).
- Illustrations : portraits et icônes dessinés par un illustrateur (les actuels sont générés en code).
- Événements programmés (déclenchement différé), notes du MJ dans le journal, marquage « important ».
- Brouillard de guerre / zones révélées progressivement sur la carte.
- Images de fond pour les cartes (photos ou dessins importés).
- Enregistrer ses propres PNJ dans un pack réutilisable d'une campagne à l'autre.
- Importer ses propres musiques (MP3/OGG) depuis l'appareil de l'hôte.
- Mode « écran partagé » : un affichage TV/projecteur de la carte pour la table.
