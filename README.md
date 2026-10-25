# LEGENDERS RPG

RPG narratif fantastique multijoueur **en réseau local**, pour des soirées entre amis.

- Le **maître du jeu (MJ)** héberge la partie sur un **PC Windows**.
- Les **joueurs** rejoignent depuis leur **téléphone Android** (APK).
- Aucun compte, aucun cloud, aucune connexion Internet pendant la partie : tout passe par le Wi-Fi local.

Moteur : **Godot 4.4** (GDScript), rendu *Compatibility* (OpenGL) pour fonctionner sur la majorité des téléphones.

## État actuel : phase 1 — prototype réseau

| Fonction | État |
|---|---|
| Écran d'accueil : Héberger / Rejoindre | ✅ |
| Serveur ENet sur le PC, port configurable | ✅ |
| Affichage IP locale, port, code de partie, joueurs connectés, ping | ✅ |
| Connexion manuelle IP + port + code depuis Android | ✅ |
| Découverte automatique des parties sur le Wi-Fi (bonus, facultative) | ✅ |
| Authentification (code, version), anti-force brute, validation par le MJ | ✅ |
| Messages publics et privés MJ ⇄ joueurs, filtrés par le serveur | ✅ |
| Reconnexion automatique, personnage conservé, renvoi sans doublon | ✅ |
| Fin de session propre (les téléphones sont prévenus) | ✅ |
| Test automatisé multi-processus (34 vérifications) | ✅ |
| **Test sur un vrai PC Windows + vrais téléphones Android** | ⏳ à faire par vous — voir [docs/TEST_PHASE1.md](docs/TEST_PHASE1.md) |

Les phases suivantes (personnages, actions libres, dés, outils du MJ, combats…) sont décrites dans [docs/ROADMAP.md](docs/ROADMAP.md). Conformément au cahier des charges, **la phase 2 ne démarre qu'après validation du réseau sur de vrais appareils**.

## Démarrage rapide (développement)

1. Installer [Godot 4.4.x](https://godotengine.org/download/) (version standard, pas .NET).
2. Ouvrir `project.godot` dans Godot, puis **F5**.
3. Pour simuler un MJ et des joueurs sur un seul PC, lancer plusieurs instances :
   ```bash
   godot --path . -- --profile=mj
   godot --path . -- --profile=joueur1 --force-mobile   # interface téléphone
   godot --path . -- --profile=joueur2 --force-mobile
   ```
   Les joueurs se connectent à `127.0.0.1`, port `7777`, avec le code affiché par le MJ.

## Documentation

- [docs/COMPILATION.md](docs/COMPILATION.md) — exporter le `.exe` Windows et l'`.apk` Android, installer l'APK.
- [docs/RESEAU.md](docs/RESEAU.md) — pare-feu Windows, permissions Android, Wi-Fi / partage de connexion, dépannage.
- [docs/TEST_PHASE1.md](docs/TEST_PHASE1.md) — protocole de test sur appareils réels.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — organisation du code et du protocole réseau.
- [docs/ROADMAP.md](docs/ROADMAP.md) — phases de développement et ce qui reste à faire.

## Tests automatisés

```bash
GODOT=/chemin/vers/godot tests/run_net_test.sh
```

Lance un serveur et plusieurs clients dans des processus Godot séparés qui communiquent réellement en UDP : authentification, mauvais code, refus par le MJ, confidentialité des messages privés, coupure brutale, reconnexion, file d'envoi, anti-doublons, fin de session.

## Licences

Polices : Cinzel et Alegreya Sans, sous licence SIL Open Font License (voir `assets/fonts/`).
