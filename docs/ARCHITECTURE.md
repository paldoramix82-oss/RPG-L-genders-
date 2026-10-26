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
    style.gd             Style : thème visuel commun, mise à l'échelle sur téléphone (portrait
                         et paysage), orientation
    net.gd               Net   : transport ENet, authentification, reconnexion, 2 RPC
    music.gd             Music : lecture avec fondu enchaîné, volume local, thème des menus
  game/
    content.gd           Catalogue de campagne : règles, classes, capacités, statuts, objets,
                         butin, monstres ; validation des créations du MJ ; vue joueur
    rules.gd             Formules : répartition, valeurs dérivées, attaques, paliers d'XP
    combat.gd            Moteur de combat (hôte) : PA, effets composables, statuts, passifs,
                         ultime, victoire et butin, jeu automatique des monstres
    effects.gd           Description en français des effets et capacités
    inventory.gd         Inventaire : instances d'objets, équipement, aperçu, tables de butin
    vision.gd            Brouillard de guerre : rayon de vision, ligne de vue, exploration
    map_gen.gd           Générateur de cartes (forêt, village, donjon, grotte, plaine, île)
    adventures.gd        Aventures prêtes à jouer (data/adventures/*.json)
    migrate.gd           Conversion des anciennes fiches / sauvegardes
    phases.gd            Phases de jeu et leurs règles
    character_data.gd    Fiche de personnage : valeurs par défaut, validation (récit / complète), vue publique
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
  ui/                    Écrans + composants : MapView (carte, pions, brouillard, chiffres
                         flottants), DiceHud (jets de combat), FeedView (récit), Composer, CreationWizard,
                         CharacterSheet, InventoryView, OverlayPanel, ConfirmBox, Notifier,
                         OrnateStyle (habillage), ResourceBar, Portrait, Icons, GameUI,
                         CodexView, TabbedPages, UIKit, Palette, Backdrop
    host/                Outils du MJ : CharacterTools, ContentPanel / ContentEditor /
                         EffectList (créateurs), QuestPanel / QuestEditor
data/
  universes/*.json       Univers (lore, codex, suggestions de création)
  maps/*.json            Cartes prêtes à l'emploi (générées par tools/generate_maps.py)
  content/*.json         Catalogue par défaut de chaque univers (tools/make_content.py)
  adventures/*.json      Aventures prêtes à jouer (tools/make_adventures.py)
tests/                   rules_test (règles et combat), net_test (réseau multi-processus,
                         3 scénarios), check_scripts (compilation), captures d'écran
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
| `char_save` | uniquement la partie « récit » de sa propre fiche (nom, histoire, apparence, portrait, magie) ; jamais les valeurs de jeu ; refusé si le MJ a verrouillé les fiches |
| `pawn_move` | uniquement son propre pion, sur la carte affichée, case franchissable et libre, autorisé par le MJ ; au tour par tour : à son tour, dans la limite de sa vitesse (en combat, 1 PA par déplacement) ; jamais s'il est immobilisé |
| `char_create` | classe connue, répartition valide (règles de la campagne), choix d'équipement ; **la fiche est construite par l'hôte** |
| `turn` | à son tour (ou capacités / objets hors tour par tour) : `end`, `quick`, `power`, `defend`, `ability` (id), `item` (uid) ; coûts en PA et ressource, portée, cible, recharge, ultime vérifiés par `Combat` |
| `item` | ses propres objets : `equip`, `unequip`, `use`, `read` (livre), `drop` (sauf objet de quête), `give` (à un autre joueur) |
| `loot_take` | un objet encore présent dans le coffre commun (premier arrivé) |
| `level` | un point de caractéristique, une capacité apprenable à son niveau, ou l'amélioration d'une capacité connue, seulement s'il reste des choix à faire |
| `ability_equip` | une capacité connue, dans la limite des emplacements ; en combat seulement si les règles l'autorisent |
| `roll_answer` | uniquement un jet que le MJ a demandé à ce joueur, une seule fois ; le dé est tiré par l'hôte |

| Événement (hôte → joueur) | Filtrage |
|---|---|
| `welcome` | historique visible, univers sans entrées MJ, fiches (la sienne complète, les autres en vue publique), carte filtrée |
| `chat`, `msg_update` | seulement si le message est public, adressé au joueur ou écrit par lui |
| `characters` | idem `welcome` |
| `map` | sans pions, étiquettes ni notes cachés (envoyée quand le terrain ou les étiquettes changent) |
| `tokens` | seulement les pions visibles (envoi léger à chaque déplacement) |
| `music` | morceau, lecture, heure de départ (si le MJ diffuse la musique) |
| `phase` | type de phase, tour, ordre et initiative limités aux pions visibles, PA et déplacements restants, résultat (victoire / défaite) |
| `content` | catalogue pour les joueurs : règles, caractéristiques, classes, capacités, statuts, objets des kits (ni monstres, ni butin, ni objets secrets) |
| `quests` | quêtes données (pas les brouillons) au groupe ou à ce joueur |
| `loot` | coffre commun du groupe |
| `fx` | retours visuels d'une action (dégâts, soins, critiques, effets), seulement pour les pions visibles |

Les changements de carte, de fiches, de phase, de catalogue, de quêtes et de coffre sont regroupés et envoyés au plus une fois par image (`SessionServer.flush()`).

## Données et sauvegarde

L'état de l'hôte est fait de dictionnaires simples, sérialisés en JSON dans `user://profiles/<profil>/campaigns/<id>.json` : écriture dans un fichier temporaire, relecture de contrôle, l'ancienne version devient `.bak`, puis remplacement. Sauvegarde automatique toutes les 60 s (si quelque chose a changé) et à la fin de la session. Les jetons des appareils sont sauvegardés : après reprise, chaque joueur retrouve sa place.

## Interface

- Thème construit en code (`Style`) : noir bleuté, or doux, violet désaturé, blanc cassé ; titres en Cinzel, texte en Alegreya Sans. Panneaux et boutons dessinés par `OrnateStyle` (sous-classe de `StyleBox` : coins biseautés, dégradé, liseré, équerres dorées) ; variations `CardPanel`, `InsetPanel`, `HighlightPanel`, `MagicPanel`, `DangerPanel`, `PrimaryButton`, `DangerButton`, `NavButton`.
- Composants partagés : `ResourceBar` (jauges animées), `Portrait`, `Icons`, `GameUI` (cartes de capacité / passif / objet, cases de caractéristique avec base + bonus, rangées d'effets, titres de section), `OverlayPanel`, `ConfirmBox` (confirmation intégrée), `Notifier` (notifications typées, empilées, non bloquantes).
- L'interface n'applique jamais de règle : elle envoie une demande, affiche l'état confirmé par l'hôte, et appelle `Rules` / `Effects` / `Inventory.preview` pour décrire ou comparer. Les notifications du joueur naissent de la différence entre deux états confirmés de sa fiche. `SessionClient.outbox_changed` alimente l'indicateur « Envoi… ».
- PC (MJ) : quatre zones à séparateurs déplaçables (`HSplitContainer` / `VSplitContainer`) — joueurs | carte & récit, avec en bas la saisie et le journal des actions | outils ; raccourcis clavier (`_unhandled_key_input`).
- Android : le petit côté de l'écran fait ~400 unités quelle que soit la résolution ; orientation automatique (`window/handheld/orientation = sensor`, réglable par le joueur). Portrait : barre du bas, actions de tour sous la carte. Paysage : les nœuds sont déplacés (pas reconstruits) vers une colonne de droite, le panneau de tour passe à côté de la carte. Marges des zones système (`get_display_safe_area`), espace réservé au clavier virtuel, boutons ≥ 40–48 unités.
- Les textes des joueurs sont affichés dans des `Label` (aucun balisage interprété).
- Carte : le terrain est dessiné une seule fois dans une texture (`TerrainPainter` dans un `SubViewport`, 2048 px maximum pour rester compatible avec tous les téléphones) ; seuls les pions, étiquettes et sélections sont redessinés. Le brouillard est une image d'un pixel par case, étirée et lissée sur le plateau.

## Peuples, jets visibles, butin, aventures

- **Peuples** : `content.species[id] = {stats, mods, trait, abilities, synergies: {class_id: {mods, abilities}}}`. `Rules.stat_values` ajoute les bonus de caractéristiques du peuple à la valeur de base ; `Rules.mods` ajoute les bonus du peuple et de la synergie peuple + classe ; `Rules.build_sheet` copie les capacités innées (`innate: true`, hors emplacements) et l'équipement de départ (`content.starter_kit`). La fiche garde `species_id`.
- **Jets visibles** : `Combat` publie, en plus des lignes du récit, des retours `roll` (d20, bonus, total, Défense, issue), `dmg_roll` (faces des dés, bonus, ×1,5, résistance, dégâts subis) et `heal_roll`, regroupés par `DiceHud` (bandeau non bloquant au-dessus de la carte).
- **Vaincus et butin** : `Combat._on_defeated` (une fois par adversaire) met l'XP de côté (`phase.xp_pool`), tire la table de butin et appelle `SessionServer.give_drop` (sac du vainqueur ou coffre du groupe) ; `Combat.remove_defeated` retire le pion et l'ordre des tours ; la victoire tient compte des adversaires déjà retirés (`phase.defeated`). Coffres : jetons `object` avec `loot`, ouverts par `CMD_OPEN` depuis une case voisine.
- **Aventures** : `SessionServer.mj_load_adventure` crée la carte, importe les PNJ (`NpcLibrary.find`), place monstres, coffres et étiquettes, enregistre les quêtes en brouillon ; `adventure` (scènes, quêtes, scènes jouées) est sauvegardé avec la campagne ; `mj_play_scene` raconte et exécute l'action de la scène.
- **Cartes** : `MapGen.generate(kind, w, h, seed)` ; `mj_fill`, `mj_paint_rect` (rectangle / pièce), `mj_snapshot` / `mj_undo` (20 étapes par carte, non sauvegardées).

## Combats locaux et quêtes automatiques

- `SessionServer.encounters` : combats locaux de la même forme que `phase` (+ `local`, `players`, `map_id`, `manual`, `timer`). `_with(enc, f)` **prête** le combat comme phase le temps d'un appel : `Combat`, les tours, l'IA, le butin et la victoire sont réutilisés. `phase_view_for_player` envoie à chaque joueur la phase de son combat (champ `encounter`).
- `tick(delta)` (appelé par `Net._process`) : fin des combats terminés, monstres automatiques (`monster_delay`, sauf `manual`), délai de tour (`turn_timeout`), agressivité (`_scan_aggro` toutes les 0,5 s ; `_after_move` après chaque déplacement libre ; `_first_spotted_cell` arrête le mouvement).
- Commandes : `turn_action("engage", cible)` hors combat, `turn_action("flee")` en combat ; `CMD_TALK`, `CMD_QUEST_ACCEPT`. MJ : `mj_encounter_next/auto/manual/end`, `mj_engage_party`.
- Quêtes : objectifs `kind` (`manual`, `kill`, `reach`, `item`, `talk`) avec `target`/`count`/`progress` (et `x`/`y`/`radius`) ; `quest_event` les met à jour (appelé par `Combat._on_defeated`, les déplacements, les objets reçus, `CMD_TALK`) et termine la quête si `auto`. `quests_for` ajoute les quêtes proposées (`status: "offer"`) par leur PNJ.

## Épreuves, bâtiments prêts, quêtes prêtes

- `Checks` (données) : 12 compétences liées aux caractéristiques (mots-clés pour deviner la compétence d'une action, DD par défaut, portée), difficultés, issues (`crit`, `success`, `partial`, `failure`, `fumble`), chance de réussite. `CheckRunner` (hôte) : `run(player, skill, {target, text, to, dc, message_id})` vérifie le tour et les PA, devine la cible, lance d20 + carac., applique les conséquences, publie un message `action` avec `check` et `lines` et un retour `roll` (`vs_label: "DD"`) pour `DiceHud` ; `consequence(message_id, kind)` pour les conséquences du MJ. Commandes : `CMD_CHECK`, `CMD_ACTION` avec `skill` (`auto` = deviné). MJ : `mj_check_action`, `mj_action_consequence`, `mj_request_roll(…, skill)`.
- `Prefabs` : plans de bâtiments (codes de terrain + `+` porte, `@` habitant, `$` coffre, `M` monstre caché). `SessionServer.mj_place_prefab` pose le plan (annulable), le nom, le coffre (parfois `lock`), le monstre et l'habitant (`_add_role_npc`) ; `mj_place_role_npc` pour un habitant seul. `MapGen` renvoie aussi `buildings` (village, ville, lieux des grandes cartes), posés par `mj_generate_map`.
- `QuestLibrary` : métiers (`ROLES` : titre, prénoms, salutations, quêtes possibles), 25 modèles (`TEMPLATES` : objectifs, `spawn`, `pickups`, `give`, `place`, `return`, `deliver`) et objets de quête (`ITEMS`, ajoutés au catalogue si besoin). `npc_offer` : quête ouverte du PNJ, sinon nouvelle quête de son métier (`_role_quest`) ; `_quest_setup` à l'acceptation ; objectif `talk` avec `return: true` = revenir voir le PNJ une fois le reste accompli ; `_consume_quest_items` reprend les objets demandés. Objets à ramasser : jetons `object` avec `pickup: true`.

## Brouillard de guerre

`Vision` calcule, pour chaque pion de joueur, les cases à moins de « vision » cases (`Rules.derived().vision` = base + Dextérité ÷ diviseur + bonus `vision`) dont la ligne de vue (Bresenham) ne traverse pas de terrain opaque. `SessionServer._map_view(player_id)` construit la carte envoyée à **ce** joueur : pions limités aux cases visibles (plus les siens), étiquettes limitées aux cases explorées, et `fog = {explored, visible}` (chaînes de « 0 »/« 1 »). L'exploration est stockée dans `map.explored[player_id]` et donc sauvegardée avec la carte. `EVT_TOKENS` transporte aussi `fog` et `labels` quand le brouillard est actif ; les retours visuels (`EVT_FX`) sont filtrés de la même façon. Désactivable par carte (`map.fog_of_war`), vision partagée par règle (`shared_vision`).
- Dés : `DiceTray` anime le lancer pendant que l'hôte tire le résultat, puis affiche les vraies valeurs.

## Règles et combat

- **Données plutôt que code** : classes, capacités, objets, effets de statut, monstres et tables de butin sont des dictionnaires JSON (catalogue par défaut dans `data/content/`, copie modifiable dans chaque campagne). Les `Resource` Godot ont été écartées : ces données sont modifiées en pleine partie par le MJ, envoyées sur le réseau et sauvegardées avec la campagne.
- **Un seul moteur d'effets** : capacités, ultimes, passifs, objets utilisables, effets à l'impact et statuts partagent la même liste d'effets composables (`damage`, `heal`, `restore`, `status`, `cleanse`, `push`, `pull`, `ap`, `stat`, `drain`, `summon`, `if`, `narrate`), interprétée par `Combat` sur l'hôte et décrite en français par `Effects`.
- **Copies sur les fiches** : une fiche porte des copies des capacités (avec rang et état équipé) et des instances d'objets (identifiant `uid` unique) ; le MJ peut répercuter la modification d'une capacité du catalogue sur tous les personnages.
- **Idempotence** : récompenses de quête et de victoire distribuées une seule fois (état de la quête, `phase.result`) ; objets du coffre identifiés par `uid` (un seul preneur) ; commandes dédoublonnées par `req_id`.

## Sauvegarde

Format 2 (`CampaignStore.FORMAT`) : session, joueurs, fiches, cartes, messages, musique, **catalogue**, **quêtes**, **coffre**, **phase**. Un fichier au format 1 est converti au chargement (`Migrate`), après copie de l'original en `<id>.json.v1`.
