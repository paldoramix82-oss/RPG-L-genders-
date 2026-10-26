# Architecture

## Vue d'ensemble

Un seul projet Godot pour le PC et Android ; le rôle (hôte-MJ / joueur) est choisi à l'écran d'accueil. Tout appareil peut héberger.

```
project.godot
assets/fonts/            Polices (OFL)
scenes/                  Une scène par écran (racine Control + script)
scripts/
  autoload/
    app.gd               App   : réglages locaux, profil, identifiant d'appareil, navigation
    style.gd             Style : thème visuel commun, mise à l'échelle sur téléphone
    net.gd               Net   : transport ENet, authentification, reconnexion, 2 RPC
    music.gd             Music : lecture avec fondu enchaîné, volume local
  game/
    character_data.gd    Fiche de personnage : valeurs par défaut, validation, vue publique
    map_data.gd          Cartes en cases : terrains, pions, étiquettes, modèles, vue joueur filtrée
    dice.gd              Lancers de dés (formules), toujours exécutés par l'hôte
    universe.gd          Univers (codex, suggestions) ; filtrage des entrées « MJ »
    campaign_store.gd    Sauvegarde JSON atomique avec copie de secours
    music_library.gd     Liste des morceaux (data/music.json)
    npc_library.gd       Packs de PNJ (data/npcs/*.json)
  net/
    protocol.gd          Constantes, noms des commandes/événements, nettoyage des entrées
    session_server.gd    État officiel de la session (PC du MJ) + règles de visibilité
    session_client.gd    Vue locale d'un joueur + file d'envoi avec accusés de réception
    lan_discovery.gd     Annonce / écoute des parties sur le Wi-Fi (facultatif)
    net_utils.gd         Adresses IP locales
  ui/                    Écrans + composants : MapView (carte et pions), FeedView (fil),
                         Composer (message/action/dés), CharacterEditor/CharacterSheet,
                         CodexView, TabbedPages, UIKit, Palette
data/
  universes/*.json       Univers (lore, codex, suggestions de création)
  maps/*.json            Cartes prêtes à l'emploi (générées par tools/generate_maps.py)
tests/                   Test réseau multi-processus (3 scénarios), captures d'écran
docs/
```

## Réseau

**Transport** : `ENetMultiplayerPeer` (UDP, canaux fiables), via le `SceneMultiplayer` de Godot. Le PC du MJ est le serveur (identifiant de pair 1).

**Authentification** : on utilise la phase d'authentification native de `SceneMultiplayer` (`auth_callback`). Tant qu'elle n'est pas terminée, le pair ne peut ni envoyer ni recevoir de RPC. Le téléphone envoie (en JSON) : version du protocole, nom, identifiant secret d'appareil (pas de code de partie : l'adresse IP suffit). Le serveur répond `ok` ou un motif de refus, puis ferme la connexion en cas de refus.

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

## Commandes et événements

| Commande (joueur → hôte) | Validation par l'hôte |
|---|---|
| `chat_send` | destinataire « groupe » ou « MJ », texte nettoyé |
| `action_declare` | enregistrée « en attente » ; seul le MJ la résout |
| `dice_roll` | formule analysée, dés tirés par l'hôte |
| `char_save` | uniquement sa propre fiche, champs validés, refusé si le MJ a verrouillé les fiches |
| `pawn_move` | uniquement son propre pion, sur la carte affichée, case franchissable, autorisé par le MJ, selon la phase : à son tour et dans la limite de sa vitesse |
| `char_save` (assistant) | répartition limitée à 12 points (−4 à +6), PV / énergie / défense recalculés par l'hôte (`Rules.refresh`) |
| `turn` | seulement à son tour, pour son pion : `end`, `attack` (portée de l'arme, jet d20 + mod. contre la défense, critique), `ability` (coût en énergie), `item` |
| `roll_answer` | uniquement un jet que le MJ a demandé à ce joueur, une seule fois ; le dé est tiré par l'hôte |

| Événement (hôte → joueur) | Filtrage |
|---|---|
| `welcome` | historique visible, univers sans entrées MJ, fiches (la sienne complète, les autres en vue publique), carte filtrée |
| `chat`, `msg_update` | seulement si le message est public, adressé au joueur ou écrit par lui |
| `characters` | idem `welcome` |
| `map` | sans pions, étiquettes ni notes cachés (envoyée quand le terrain ou les étiquettes changent) |
| `tokens` | seulement les pions visibles (envoi léger à chaque déplacement) |
| `music` | morceau, lecture, heure de départ (si le MJ diffuse la musique) |
| `phase` | type de phase, tour, ordre limité aux pions visibles, déplacements restants, action utilisée |

Les changements de carte, de fiches et de phase sont regroupés et envoyés au plus une fois par image (`SessionServer.flush()`).

## Données et sauvegarde

L'état de l'hôte est fait de dictionnaires simples, sérialisés en JSON dans `user://profiles/<profil>/campaigns/<id>.json` : écriture dans un fichier temporaire, relecture de contrôle, l'ancienne version devient `.bak`, puis remplacement. Sauvegarde automatique toutes les 60 s (si quelque chose a changé) et à la fin de la session. Les jetons des appareils sont sauvegardés : après reprise, chaque joueur retrouve sa place.

## Interface

- Thème construit en code (`Style`) : anthracite, or discret, violet désaturé, blanc cassé ; titres en Cinzel, texte en Alegreya Sans.
- PC : tableau de bord en trois colonnes (connexion & joueurs / messages / réseau & journal).
- Android : portrait, ~400 unités de large quelle que soit la résolution (mise à l'échelle selon la densité de l'écran), barre de navigation basse, boutons ≥ 48 unités, espace réservé au clavier virtuel.
- Les textes des joueurs sont affichés dans des `Label` (aucun balisage interprété).
- Carte : le terrain est dessiné une seule fois dans une texture (`TerrainPainter` dans un `SubViewport`, 2048 px maximum pour rester compatible avec tous les téléphones) ; seuls les pions, étiquettes et sélections sont redessinés.
- Dés : `DiceTray` anime le lancer pendant que l'hôte tire le résultat, puis affiche les vraies valeurs.
