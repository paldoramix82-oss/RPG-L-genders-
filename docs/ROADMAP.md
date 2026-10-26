# Feuille de route

## Fait

**Réseau (phase 1)** — hôte autoritaire ENet/UDP, code de partie, validation par le MJ, anti-force brute, reconnexion automatique avec conservation du joueur, file d'envoi sans doublon, découverte facultative sur le Wi-Fi, fin de session propre. **N'importe quel appareil peut héberger** (PC ou Android).

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
- Bande originale de 14 morceaux composés pour le jeu, synchronisée sur les téléphones, musique de combat automatique.

## À valider par vous

L'application n'a été exécutée que sous Linux (tests réseau entre processus, captures d'écran). **Il faut l'essayer sur un vrai PC Windows et de vrais téléphones Android** : [TEST_PHASE1.md](TEST_PHASE1.md).

## Pistes suivantes (non commencées)

- Inventaire avancé côté MJ : bibliothèque d'objets, transfert d'objets entre personnages, économie.
- Factions et réputations ; variables persistantes du monde (porte ouverte, pont détruit…).
- Événements programmés (déclenchement différé), notes du MJ dans le journal, marquage « important ».
- Brouillard de guerre / zones révélées progressivement sur la carte.
- Images de fond pour les cartes (photos ou dessins importés).
- Enregistrer ses propres PNJ dans un pack réutilisable d'une campagne à l'autre.
- Importer ses propres musiques (MP3/OGG) depuis l'appareil de l'hôte.
- Mode « écran partagé » : un affichage TV/projecteur de la carte pour la table.
