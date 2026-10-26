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
- [ ] G1. Un joueur crée son personnage avec l'assistant en 5 étapes (nom et portrait, classe, 15 points, arme, récapitulatif) : il arrive dans le salon « Vous êtes prêt ! », son pion apparaît sur la carte. Le MJ voit « Préparation : 1/1 » et appuie sur « La partie commence ! ».
- [ ] G2. Le joueur déplace son pion en touchant une case : le mouvement apparaît chez le MJ et les autres joueurs.
- [ ] G3. Le MJ pose un monstre caché : les joueurs ne le voient pas ; il le révèle : il apparaît.
- [ ] G4. Exploration : chacun son tour, déplacement limité à la vitesse, « Terminer mon tour ». Combat : « C'est votre tour ! », 2 PA, Attaque rapide → toucher la cible entourée de rouge → jet automatique, chiffres de dégâts au-dessus du pion ; le MJ fait jouer ses monstres (ou « Jouer automatiquement ») ; Repos rend des PV.
- [ ] G5. Action déclarée par un joueur → le MJ la résout avec un jet → résultat reçu.
- [ ] G6. Jet de dés secret d'un joueur : visible du MJ seulement.
- [ ] G7. Terminer la session, puis *Reprendre* la campagne : fiches, cartes et pions sont restaurés ; les joueurs se reconnectent avec la même adresse IP.
- [ ] G8. Héberger depuis un téléphone Android (optionnel) et rejoindre depuis les autres.

### H. Règles, progression, butin (nouvelle version)
- [ ] H1. Barre du bas : PV, mana et capacités visibles en permanence ; la jauge de PV s'anime quand on est touché.
- [ ] H2. Toucher une capacité : le panneau explique coût, portée, effets, et pourquoi elle est indisponible (mana, recharge, ultime pas chargé, pas son tour).
- [ ] H3. Un effet (poison, étourdi…) s'affiche au-dessus du pion, dans la frise et sur la fiche ; un étourdi perd son tour.
- [ ] H4. Victoire : bandeau « Victoire ! », XP et or distribués, butin dans le coffre du groupe ; deux joueurs qui touchent « Prendre » en même temps : un seul obtient l'objet.
- [ ] H5. Niveau 2 (le MJ donne 100 XP) : « + » doré sur le portrait, point de caractéristique placé, capacité apprise ou améliorée.
- [ ] H6. Sac : équiper une armure montre « Défense x → y » avant de confirmer ; utiliser une potion ; lire un livre de compétence.
- [ ] H7. Quête : le MJ la prépare, la donne → elle apparaît dans le journal et en haut de l'écran ; « Réussie : distribuer » donne XP / or / objet une seule fois.
- [ ] H8. Le MJ crée un objet en pleine partie et le donne à un joueur : il apparaît dans son sac avec la bonne rareté.
- [ ] H9. Reprendre une campagne sauvegardée avec l'ancienne version : les fiches sont converties, rien n'est perdu (copie `.json.v1` à côté).

### I. Outils du MJ
- [ ] I1. Fiche et outils d'un joueur : ± PV, donner de l'XP, appliquer un effet, apprendre une capacité ; chaque intervention apparaît dans le journal du MJ (invisible des joueurs).
- [ ] I2. Créer › Monstres › Placer, puis Combat : le monstre joue avec ses capacités.
- [ ] I3. Événement rapide › Embuscade : monstres placés et combat lancé.
- [ ] I4. Créer › Règles : passer à 3 PA par tour → effectif au tour suivant.
- [ ] I5. Tableau du MJ : déplacer les séparateurs entre les zones ; le journal des actions (en bas) se remplit pendant un combat ; raccourcis Ctrl + S, F1 / F2, F5, Ctrl + E.

### J. Refonte visuelle, paysage, musique, brouillard
- [ ] J1. Musique : le thème principal joue sur l'accueil, l'écran « Rejoindre » et le salon, sur le PC et les téléphones ; le bouton *Musique* de l'accueil le coupe ; il s'arrête quand la partie commence (ou cède la place au morceau du MJ).
- [ ] J2. Paysage : tourner le téléphone pendant la partie → colonne personnage à droite, panneau du tour à côté de la carte ; retour en portrait sans rien perdre (récit, panneau ouvert). *Journal › Réglages › Affichage* bloque l'orientation.
- [ ] J3. Encoche et barre de navigation : rien de caché sous elles, en portrait comme en paysage.
- [ ] J4. Clavier virtuel : en écrivant un message (portrait et paysage), le champ reste visible.
- [ ] J5. Brouillard : un joueur ne voit que les cases autour de lui ; un monstre derrière un mur ou une forêt dense n'apparaît pas ; en s'approchant, il apparaît ; les zones déjà vues restent assombries ; deux joueurs éloignés ne se voient pas (sauf *vision partagée*).
- [ ] J6. MJ : *Voir le brouillard des joueurs*, *Oublier l'exploration*, brouillard coupé sur une carte → tout redevient visible.
- [ ] J7. Bouton *Discuter* pendant un combat : messages échangés sans dépenser de PA ; pastille de non-lus quand on est sur la carte.
- [ ] J8. Capacité hors de portée : grisée, « Aucun ennemi à portée » au toucher ; seule une cible à portée est entourée de rouge.
- [ ] J9. Notifications : soin reçu, objet obtenu, ultime disponible, action refusée — courtes, en haut, sans bloquer.
- [ ] J10. Inventaire : filtres par catégorie ; utiliser une potion commune sans confirmation, un objet rare avec confirmation ; jeter demande confirmation.

## Rapport

Merci d'indiquer, pour chaque ligne en échec : modèle de téléphone, version d'Android, type de réseau (box / partage de connexion de quel téléphone), et le message affiché. Ces informations permettent de corriger avant la phase 2.
