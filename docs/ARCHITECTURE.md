# Architecture

## Vue d'ensemble

Un seul projet Godot pour le PC et Android ; le rôle (MJ / joueur) est choisi à l'écran d'accueil. L'hébergement est désactivé sur mobile.

```
project.godot
assets/fonts/            Polices (OFL)
scenes/                  Une scène par écran (racine Control + script)
scripts/
  autoload/
    app.gd               App   : réglages locaux, profil, identifiant d'appareil, navigation
    style.gd             Style : thème visuel commun, mise à l'échelle sur téléphone
    net.gd               Net   : transport ENet, authentification, reconnexion, 2 RPC
  net/
    protocol.gd          Constantes, noms des commandes/événements, nettoyage des entrées
    session_server.gd    État officiel de la session (PC du MJ) + règles de visibilité
    session_client.gd    Vue locale d'un joueur + file d'envoi avec accusés de réception
    lan_discovery.gd     Annonce / écoute des parties sur le Wi-Fi (facultatif)
    net_utils.gd         Adresses IP locales
  ui/                    Écrans, palette, petits composants (UIKit, CenteredColumn, Backdrop)
tests/                   Test réseau multi-processus, captures d'écran
docs/
```

## Réseau

**Transport** : `ENetMultiplayerPeer` (UDP, canaux fiables), via le `SceneMultiplayer` de Godot. Le PC du MJ est le serveur (identifiant de pair 1).

**Authentification** : on utilise la phase d'authentification native de `SceneMultiplayer` (`auth_callback`). Tant qu'elle n'est pas terminée, le pair ne peut ni envoyer ni recevoir de RPC. Le téléphone envoie (en JSON) : version du protocole, code de session, nom, identifiant secret d'appareil. Le serveur répond `ok` ou un motif de refus, puis ferme la connexion en cas de refus.

**Deux RPC seulement** (dans `Net`) :

| RPC | Sens | Contenu |
|---|---|---|
| `_c2s(cmd, payload)` | joueur → serveur | Une **demande**. Le serveur la valide ; il ne fait jamais confiance au client. |
| `_s2c(evt, payload)` | serveur → **un** joueur | Un **événement** déjà filtré pour ce joueur. Jamais de diffusion à tous. |

Ce bus de messages permet d'ajouter des fonctions (actions libres, dés, inventaire…) sans toucher au transport : on ajoute une commande dans `Protocol`, son traitement dans `SessionServer.handle_command`, et l'événement correspondant dans `SessionClient.handle_event`.

**Règles côté serveur** (`SessionServer`) :
- un pair non associé à un joueur, ou un joueur non validé, ne peut rien faire ;
- chaque commande porte un `req_id` ; une commande déjà traitée est acquittée sans être réappliquée (renvois après coupure, doubles appuis) ;
- limitation de débit par appareil ;
- textes nettoyés et tronqués ;
- la visibilité est décidée par une seule fonction (`can_see`) avant chaque envoi et pour l'historique envoyé à la (re)connexion.

**Identité et reconnexion** : chaque installation génère un identifiant secret aléatoire (`App.device_token`). Le serveur associe ce jeton à une fiche joueur. Une déconnexion passe la fiche « hors ligne » sans la supprimer ; au retour du même jeton, le joueur retrouve sa fiche (et sa validation). Si une ancienne connexion « fantôme » existe encore, elle est fermée.

**Côté client** (`SessionClient`) : les commandes restent dans une boîte d'envoi jusqu'à l'accusé de réception ; elles sont renvoyées après une reconnexion. L'interface n'affiche un message que lorsque le serveur l'a diffusé (pas d'affichage « optimiste » simulé).

**Détection des coupures** : délai ENet ramené à 4–12 s. Reconnexion automatique toutes les 3 s pendant ~2 min. Une fin de session voulue par le MJ est annoncée aux téléphones (qui ne tentent alors pas de se reconnecter).

## Données (prévu en phase 2)

L'état du serveur est déjà constitué de dictionnaires simples, sérialisables en JSON. La sauvegarde de campagne (phase 2) écrira un fichier JSON par campagne dans `user://campaigns/<id>/`, via écriture dans un fichier temporaire puis renommage (procédure déjà utilisée pour les réglages locaux), avec conservation de la sauvegarde précédente.

## Interface

- Thème construit en code (`Style`) : anthracite, or discret, violet désaturé, blanc cassé ; titres en Cinzel, texte en Alegreya Sans.
- PC : tableau de bord en trois colonnes (connexion & joueurs / messages / réseau & journal).
- Android : portrait, ~400 unités de large quelle que soit la résolution (mise à l'échelle selon la densité de l'écran), barre de navigation basse, boutons ≥ 48 unités, espace réservé au clavier virtuel.
- Les textes des joueurs sont affichés dans des `Label` (aucun balisage interprété).
