# Validation de la phase 1 sur appareils réels

Objectif du cahier des charges : **vérifier que le jeu fonctionne réellement** entre un PC Windows et de vrais téléphones Android, avant de développer la suite.

Ce qui a déjà été vérifié automatiquement (Linux, processus séparés, UDP local) : voir `tests/run_net_test.sh`. Ce qui **ne peut être vérifié que par vous** : le Wi-Fi réel, le pare-feu Windows, le comportement d'Android (mise en veille, changement de réseau), l'affichage sur vos écrans.

## Matériel

- 1 PC Windows avec `LegendersRPG.exe` (voir [COMPILATION.md](COMPILATION.md)).
- 1 à 3 téléphones Android avec `LegendersRPG.apk` (même version).
- Un Wi-Fi commun. Faire le test au moins une fois sur la box, et une fois sur le partage de connexion d'un téléphone.

## Procédure

Cocher chaque ligne et noter les remarques.

### A. Démarrage du serveur
- [ ] A1. Lancer l'exe → l'écran d'accueil s'affiche.
- [ ] A2. « Héberger une partie » → « Lancer le serveur » : la fenêtre du pare-feu apparaît, autoriser les réseaux privés.
- [ ] A3. Le tableau de bord affiche l'adresse IP en grand (192.168.x.x ou 10.x.x.x). Aucun code.

### B. Connexion d'un téléphone
- [ ] B1. Sur le téléphone : « Rejoindre une partie ». (Bouton « Héberger » grisé : normal.)
- [ ] B2. La partie apparaît-elle dans « Parties détectées » ? (oui / non — « non » n'est pas bloquant)
- [ ] B3. Saisir le nom puis l'IP au pavé numérique (vérifier que la touche « . » fonctionne après « 192.168 ») → « Rejoindre ». Le téléphone propose de créer son personnage.
- [ ] B4. (Option « Valider moi-même chaque nouveau joueur » cochée) La demande apparaît sur le PC avec Accepter / Refuser.
- [ ] B5. Le ping affiché côté PC et côté téléphone (onglet Groupe) est raisonnable (< 100 ms en général).

### C. Messages
- [ ] C1. Le MJ écrit à « Tout le groupe » → reçu par tous les téléphones.
- [ ] C2. Un joueur écrit « Au groupe » → reçu par le MJ et les autres joueurs.
- [ ] C3. Le MJ choisit « Privé : <joueur A> » → **seul** A le reçoit (vérifier sur le téléphone de B).
- [ ] C4. Un joueur écrit « Au MJ, en privé » → **seul** le MJ le reçoit (pas les autres joueurs).
- [ ] C5. Le clavier Android ne masque pas le champ de saisie.

### D. Plusieurs joueurs (critère : 3 joueurs)
- [ ] D1. Connecter 3 téléphones, tous acceptés, tous visibles dans l'onglet Groupe et côté MJ.
- [ ] D2. Un 2ᵉ appareil avec le même nom qu'un joueur existant est refusé.
- [ ] D3. Une mauvaise adresse IP affiche un message clair (« Le PC du MJ ne répond pas »).

### E. Coupures
- [ ] E1. Couper le Wi-Fi d'un téléphone 10 s puis le rallumer → « Reconnexion… » puis « Connecté », messages conservés.
- [ ] E2. Écrire un message pendant la coupure → envoyé une seule fois au retour.
- [ ] E3. Mettre le téléphone en veille 30 s, le rallumer → reconnexion automatique.
- [ ] E4. Fermer complètement l'application, la rouvrir, rejoindre avec le même nom → le joueur retrouve sa place sans nouvelle validation du MJ.
- [ ] E5. Le MJ clique « Déconnecter » sur un joueur → le téléphone revient à l'écran Rejoindre avec un message.
- [ ] E6. Le MJ clique « Terminer la session » → tous les téléphones affichent la fin de partie et ne tentent pas de se reconnecter.

### F. Ergonomie
- [ ] F1. Textes lisibles et boutons faciles à toucher sur chaque téléphone.
- [ ] F2. Aucun défilement horizontal ; on fait défiler les listes longues (assistant, fiche, codex) en glissant le doigt n'importe où, même en partant d'un bouton.
- [ ] F3. Le tableau de bord du MJ est lisible en plein écran sur le PC.

### G. Fonctions de jeu
- [ ] G1. Un joueur crée son personnage avec l'assistant (classe, 12 points, arme, nom) : il arrive dans le salon « Vous êtes prêt ! », son pion apparaît sur la carte. Le MJ voit « Préparation : 1/1 » et appuie sur « La partie commence ! ».
- [ ] G2. Le joueur déplace son pion en touchant une case : le mouvement apparaît chez le MJ et les autres joueurs.
- [ ] G3. Le MJ pose un monstre caché : les joueurs ne le voient pas ; il le révèle : il apparaît.
- [ ] G4. Exploration : chacun son tour, déplacement limité à la vitesse, « Fin du tour ». Combat : « C'est votre tour ! », Attaquer → choisir l'arme → toucher la cible → jet automatique ; le MJ fait jouer ses monstres ; Repos rend des PV.
- [ ] G5. Action déclarée par un joueur → le MJ la résout avec un jet → résultat reçu.
- [ ] G6. Jet de dés secret d'un joueur : visible du MJ seulement.
- [ ] G7. Terminer la session, puis *Reprendre* la campagne : fiches, cartes et pions sont restaurés ; les joueurs se reconnectent avec la même adresse IP.
- [ ] G8. Héberger depuis un téléphone Android (optionnel) et rejoindre depuis les autres.

## Rapport

Merci d'indiquer, pour chaque ligne en échec : modèle de téléphone, version d'Android, type de réseau (box / partage de connexion de quel téléphone), et le message affiché. Ces informations permettent de corriger avant la phase 2.
