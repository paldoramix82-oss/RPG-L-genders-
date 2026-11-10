# Compilation et export

Version de Godot : **4.4.x** standard (pas la version .NET). Le projet utilise le rendu *Compatibility* (OpenGL ES 3 / OpenGL 3.3).

Les préréglages d'export sont déjà dans `export_presets.cfg` :
- **Windows (MJ)** → `build/windows/LegendersRPG.exe` (un seul fichier, `.pck` intégré).
- **Android (joueurs)** → `build/android/LegendersRPG.apk` (arm64-v8a + armeabi-v7a).

Le dossier `build/` est ignoré par git.

## 1. Modèles d'export

Dans Godot : **Éditeur → Gérer les modèles d'export… → Télécharger et installer** (même version que l'éditeur). Une seule fois par version de Godot.

## 2. Windows (PC du MJ)

1. **Projet → Exporter… → Windows (MJ) → Exporter le projet**, décocher « Exporter avec débogage » pour la version finale.
2. Copier `LegendersRPG.exe` où vous voulez sur le PC. Aucune installation requise.
3. Au premier lancement en tant qu'hôte, autoriser l'accès sur les **réseaux privés** (voir [RESEAU.md](RESEAU.md)).

En ligne de commande :
```bash
godot --headless --path . --export-release "Windows (MJ)" build/windows/LegendersRPG.exe
```

> Depuis Linux/macOS, l'export Windows fonctionne aussi ; seule la modification de l'icône de l'exécutable nécessite `rcedit` (facultatif, réglage `application/modify_resources`).

## 3. Android (téléphones des joueurs)

### Prérequis (une seule fois)

1. Installer **OpenJDK 17** (ex. [Adoptium Temurin 17](https://adoptium.net/)).
2. Installer le **SDK Android** : le plus simple est [Android Studio](https://developer.android.com/studio) → *SDK Manager* → installer *Android SDK Platform-Tools*, *Build-Tools 34* (ou plus récent) et *Android SDK Platform 34*.
3. Dans Godot : **Éditeur → Paramètres de l'éditeur → Export → Android** :
   - *Java SDK Path* : dossier du JDK 17 ;
   - *Android SDK Path* : dossier du SDK (ex. `C:\Users\<vous>\AppData\Local\Android\Sdk`).
4. Clé de débogage : Godot en génère une automatiquement (`debug.keystore`) lors du premier export de débogage. Pour une version « release » il faut une clé à vous :
   ```bash
   keytool -genkeypair -v -keystore legenders-release.keystore -alias legenders -keyalg RSA -keysize 2048 -validity 10000
   ```
   puis renseigner *Keystore → Release*, l'alias et le mot de passe dans le préréglage Android (ces informations sont stockées dans `.godot/export_credentials.cfg`, jamais dans git). **Ne perdez pas cette clé** : sans elle, les mises à jour de l'APK devront être désinstallées/réinstallées.

### Export

**Projet → Exporter… → Android (joueurs) → Exporter le projet** → `LegendersRPG.apk`.

Pour une soirée entre amis, l'export **avec débogage** (signé avec la clé de débogage) suffit parfaitement.

En ligne de commande :
```bash
godot --headless --path . --export-debug "Android (joueurs)" build/android/LegendersRPG.apk
```

### Permissions

Le préréglage active `INTERNET` (indispensable, même en local), `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE` et `CHANGE_WIFI_MULTICAST_STATE`. Voir [RESEAU.md](RESEAU.md#permissions-android). Ne pas décocher `INTERNET` : sans elle, l'application ne peut joindre aucun appareil.

### Installer l'APK sur les téléphones

- **Par câble USB** (téléphone en mode développeur + débogage USB) :
  ```bash
  adb install -r build/android/LegendersRPG.apk
  ```
  Ou directement depuis Godot : bouton **Déploiement à distance** (icône Android en haut à droite) quand le téléphone est branché.
- **Sans câble** : envoyer le fichier `.apk` au joueur (clé USB, partage de fichiers local…), l'ouvrir sur le téléphone, et autoriser « Installer des applications inconnues » pour l'application utilisée (Fichiers, navigateur…).
- Android peut afficher un avertissement Play Protect (application non publiée) : choisir « Installer quand même ».

**Tous les appareils doivent avoir la même version** (le numéro de protocole est vérifié à la connexion, et affiché en bas de l'écran d'accueil).

## 4. Vérifications automatiques

```bash
# Importer le projet (première fois, ou après ajout de ressources)
godot --headless --path . --import
# Test réseau multi-processus
GODOT=godot tests/run_net_test.sh
```

## 5. Captures d'écran (développement)

```bash
godot --path . res://tests/screenshot.tscn -- --shot=host --profile=a --out=/tmp/mj.png &
godot --path . --resolution 412x900 res://tests/screenshot.tscn -- --shot=player --force-mobile --profile=b --out=/tmp/joueur.png
```
