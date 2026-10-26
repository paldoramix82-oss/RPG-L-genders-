# LEGENDERS RPG

RPG narratif fantastique multijoueur **en réseau local**, pour des soirées entre amis.

- **N'importe qui peut héberger** : PC Windows ou téléphone Android. Les autres rejoignent depuis leur téléphone (ou un PC).
- Aucun compte, aucun cloud, aucune connexion Internet pendant la partie : tout passe par le Wi-Fi local.

Moteur : **Godot 4.4** (GDScript), rendu *Compatibility* (OpenGL) pour fonctionner sur la majorité des téléphones.

## Ce qu'on peut faire

- **Univers au choix** : *Légenders* (codex complet tiré des documents de l'univers : Légenders, AEC, 10 catégories de magie, Gardiens, rangs, Kurtzuma, nations, créatures), *Fantasy classique* (Les Cendres de Valombre) ou *Univers libre*.
- **Personnages entièrement libres** : identité, pion (couleur, initiales), magie et pouvoirs, capacités, caractéristiques et compétences à volonté, PV / énergie / niveau / rang, inventaire, histoire, secret réservé au MJ.
- **Cartes interactives façon plateau** : 13 cartes prêtes dont **4 grandes cartes pour les longues campagnes** (Kurtzuma — carte du monde 120×80, Région de Valombre, Shima la capitale, Forêt-Monde), rendu illustré (transitions entre terrains, rivages, arbres, montagnes, toits, murs, cristaux, lave…), éditeur pour le MJ (29 terrains au pinceau, pions, étiquettes visibles ou secrètes, cartes jusqu'à 128×128), **pions 3D façon jeu de plateau** qui se déplacent en direct sur tous les écrans.
- **Packs de PNJ** : 47 fiches prêtes (mages de Shima d'après les documents de l'univers, gens et créatures de Kurtzuma, habitants de Valombre, bestiaire générique) à importer d'un clic.
- **Les joueurs lancent eux-mêmes leurs dés** : plateau de dés animé, dés rapides sous la carte, et le MJ peut demander un jet (avec difficulté → réussite / échec).
- **Bande originale** : 14 morceaux composés pour le jeu (rock de combat, épique, taverne, exploration, mystère, ville, repos…), choisis par le MJ, synchronisés sur les téléphones, musique de combat automatique.
- **Combat au tour par tour** sur la carte : initiative automatique, ordre des tours, PV sur les pions, tour en surbrillance.
- **Actions libres** déclarées par les joueurs et résolues par le MJ, **dés** (d4 à d100, formules libres, jets publics ou secrets, calculés par l'hôte), messages publics et privés.
- **Secrets protégés** : pions cachés, étiquettes secrètes, codex MJ, jets secrets, secrets des fiches ne sont jamais envoyés aux joueurs non autorisés.
- **Sauvegarde automatique** et reprise de campagne ; reconnexion automatique des joueurs.
- Interface soignée et adaptée : colonnes sur PC, onglets sur téléphone.

Mode d'emploi : [docs/GUIDE_DE_JEU.md](docs/GUIDE_DE_JEU.md).

## État

| Élément | État |
|---|---|
| Réseau local (hôte autoritaire, code, validation, reconnexion, confidentialité) | ✅ testé automatiquement |
| Fiches, cartes et pions, combat, dés, actions, codex, sauvegarde | ✅ testé automatiquement |
| Test automatisé multi-processus | ✅ 72 vérifications |
| **Essai sur vrais appareils (Windows + Android)** | ⏳ à faire : [docs/TEST_PHASE1.md](docs/TEST_PHASE1.md) |

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

Contenu généré par des scripts (les fichiers produits sont versionnés, les scripts ne servent qu'à les recréer) :
- cartes : `tools/generate_maps.py` → `data/maps/*.json` (numpy + scipy) ;
- PNJ : `tools/make_npc_packs.py` → `data/npcs/*.json` ;
- musique : `tools/compose_music.py` → `assets/music/*.ogg` + `data/music.json` (numpy + scipy + ffmpeg ; tout est synthétisé, aucun échantillon externe).

Les univers sont dans `data/universes/*.json`.

## Documentation

- [docs/GUIDE_DE_JEU.md](docs/GUIDE_DE_JEU.md) — comment jouer (joueurs et MJ).
- [docs/COMPILATION.md](docs/COMPILATION.md) — exporter le `.exe` Windows et l'`.apk` Android, installer l'APK.
- [docs/RESEAU.md](docs/RESEAU.md) — pare-feu Windows, permissions Android, Wi-Fi / partage de connexion, dépannage.
- [docs/TEST_PHASE1.md](docs/TEST_PHASE1.md) — protocole de test sur appareils réels.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — organisation du code et du protocole réseau.
- [docs/ROADMAP.md](docs/ROADMAP.md) — phases de développement et ce qui reste à faire.

## Tests automatisés

```bash
GODOT=/chemin/vers/godot tests/run_net_test.sh
```

Lance des hôtes et des joueurs dans des processus Godot séparés qui communiquent réellement en UDP : authentification, mauvais code, refus par le MJ, confidentialité (messages privés, pions et étiquettes cachés, codex MJ, jets secrets, secrets des fiches), coupure brutale, reconnexion, file d'envoi, anti-doublons, fin de session, fiches, déplacement des pions, dés, actions, sauvegarde et reprise.

## Licences

Polices : Cinzel et Alegreya Sans, sous licence SIL Open Font License (voir `assets/fonts/`).
Musiques : composées et synthétisées pour ce projet par `tools/compose_music.py`.
