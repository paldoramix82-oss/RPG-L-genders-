# Réseau local : configuration et dépannage

## Principe

- L'appareil qui héberge (PC Windows **ou téléphone Android**) est le **serveur autoritaire** : il détient l'état officiel de la partie.
- Transport : **ENet sur UDP**, port **7777** par défaut (modifiable à l'écran « Héberger »).
- Découverte automatique facultative : annonces UDP *broadcast* sur le port **7778**.
- Aucune donnée ne passe par Internet. Les données mobiles des téléphones ne sont pas utilisées.

```
  Téléphone joueur ──┐
  Téléphone joueur ──┼── Wi-Fi commun (box, routeur, ou partage de connexion d'un joueur) ── PC du MJ (serveur, UDP 7777)
  Téléphone joueur ──┘
```

## Réseaux possibles

| Situation | Fonctionne ? | Remarques |
|---|---|---|
| Box Internet / routeur Wi-Fi de la maison | ✅ | Cas idéal. Internet n'est pas nécessaire, le Wi-Fi suffit. |
| Partage de connexion du téléphone d'un joueur | ✅ en général | Le PC et les autres téléphones se connectent au point d'accès de ce joueur. Ce joueur peut lui-même jouer sur son téléphone. Certains constructeurs isolent les clients : voir dépannage. |
| Point d'accès créé par le PC (« Point d'accès mobile » Windows) | ✅ en général | Les téléphones se connectent au PC ; utiliser l'adresse affichée pour ce réseau (souvent `192.168.137.1`). |
| Wi-Fi public / hôtel / entreprise | ❌ souvent | « Isolation des clients » activée : les appareils ne peuvent pas se voir. |
| Téléphone en 4G/5G uniquement | ❌ | Le téléphone doit être sur le même Wi-Fi que le PC. |

## Héberger depuis un téléphone Android

C'est possible : dans l'application, *Héberger une partie*. Points d'attention :
- l'application doit rester **au premier plan, écran allumé** (l'écran ne se met pas en veille tant que l'application est ouverte) ; si on change d'application, Android peut suspendre le serveur et les joueurs passent en « Reconnexion… » jusqu'au retour ;
- si ce téléphone partage sa connexion (point d'accès), son adresse est souvent `192.168.43.1` ou `192.168.x.1` ; elle s'affiche dans « Pour rejoindre » ;
- les sauvegardes restent sur ce téléphone.

## Pare-feu Windows (PC hôte)

Au **premier lancement** de `LegendersRPG.exe` comme serveur, Windows affiche « Le Pare-feu Windows a bloqué certaines fonctionnalités » :

1. Cocher **Réseaux privés**.
2. Cliquer **Autoriser l'accès**.

Le réseau Wi-Fi du PC doit être de type **Privé** :
*Paramètres → Réseau et Internet → Wi-Fi → (votre réseau) → Type de profil réseau → Privé.*
Sur un réseau « Public », Windows bloque les connexions entrantes même si l'application est autorisée.

Si la fenêtre n'est pas apparue ou si l'accès a été refusé, ouvrir **PowerShell en administrateur** :

```powershell
# Autoriser le port de jeu (UDP 7777) et la découverte (UDP 7778) sur les réseaux privés
New-NetFirewallRule -DisplayName "Legenders RPG (jeu)" -Direction Inbound -Protocol UDP -LocalPort 7777 -Action Allow -Profile Private
New-NetFirewallRule -DisplayName "Legenders RPG (découverte)" -Direction Inbound -Protocol UDP -LocalPort 7778 -Action Allow -Profile Private
```

Pour supprimer ces règles : `Remove-NetFirewallRule -DisplayName "Legenders RPG*"`.

Un antivirus tiers (Norton, Avast, Kaspersky…) peut avoir son propre pare-feu : y autoriser également l'application.

## Permissions Android

Déclarées dans `export_presets.cfg` (préréglage « Android (joueurs) ») :

| Permission | Pourquoi |
|---|---|
| `INTERNET` | **Obligatoire** : sans elle, Android interdit toute communication réseau, y compris locale. |
| `ACCESS_NETWORK_STATE` | Connaître l'état du réseau. |
| `ACCESS_WIFI_STATE` | Lire l'état du Wi-Fi. |
| `CHANGE_WIFI_MULTICAST_STATE` | Permettre la réception des annonces de découverte (broadcast). |

Aucune de ces permissions n'est « dangereuse » : Android ne demande rien au joueur à l'installation.

**Limite connue** : sur beaucoup de téléphones Android, la réception des paquets *broadcast* est filtrée par le système. La liste « Parties détectées sur ce Wi-Fi » peut donc rester vide : **c'est normal**, la saisie manuelle de l'adresse IP fonctionne toujours.

## Ce que le joueur saisit

L'écran du MJ affiche :
- **Adresse IP de ce PC** (ex. `192.168.1.20`). Si plusieurs adresses apparaissent (Ethernet + Wi-Fi, VPN, machine virtuelle), utiliser celle du réseau partagé avec les téléphones — en général celle qui commence comme l'adresse du téléphone (*Paramètres → Wi-Fi → réseau → Adresse IP* sur Android).
- **Port** (`7777` par défaut, caché côté joueur dans *Options avancées*).

Il n'y a **pas de code de partie** : l'adresse IP suffit. Le champ IP est prérempli avec le début de l'adresse du téléphone (ex. `192.168.1.`) et se saisit avec un pavé numérique intégré.

## Sécurité et confidentialité

- Un appareil doit présenter la **même version** du protocole, sinon il est refusé *avant* de recevoir la moindre donnée.
- Par défaut, les joueurs entrent directement. Pour filtrer, le MJ coche « Valider moi-même chaque nouveau joueur » : chaque demande attend alors son accord.
- Les clients ne peuvent pas se parler directement (`server_relay = false`) : tout passe par le serveur.
- Les messages privés ne sont **envoyés qu'aux destinataires autorisés** : un téléphone ne reçoit jamais une information qu'il n'a pas le droit de voir (le filtrage est fait sur le PC, pas par l'interface).
- Chaque téléphone possède un identifiant secret (généré à la première ouverture) qui lui permet de retrouver son personnage après une coupure. Il n'est jamais transmis aux autres joueurs.
- La communication n'est pas chiffrée : c'est acceptable sur un Wi-Fi privé entre amis, à ne pas utiliser sur un réseau public.

## Coupures et reconnexion

- Une coupure est détectée en 4 à 12 secondes.
- Le téléphone tente de se reconnecter automatiquement toutes les 3 secondes, pendant environ 2 minutes.
- Le personnage n'est jamais supprimé par une déconnexion ; le MJ le voit « Hors ligne ».
- Les messages écrits pendant la coupure sont envoyés au retour, une seule fois.
- Si le MJ termine la session, les téléphones sont prévenus et ne tentent pas de se reconnecter.

## Dépannage

| Symptôme | Causes probables |
|---|---|
| « Le PC du MJ ne répond pas » | Mauvaise IP ; téléphone en 4G ; PC et téléphone sur deux réseaux différents (ex. Wi-Fi 2,4 GHz *invité*) ; pare-feu Windows ; réseau « Public » sous Windows. |
| Fonctionne sur la box, pas sur le partage de connexion | Isolation des clients du point d'accès. Essayer le partage d'un autre téléphone, ou le point d'accès mobile de Windows. |
| « Version du jeu différente » | Le PC et le téléphone n'ont pas la même version : réinstaller l'APK correspondant. |
| « Le nom est déjà utilisé » | Un autre appareil a pris ce nom. Si c'est le même joueur avec un nouveau téléphone, le MJ peut « Retirer » l'ancienne fiche. |
| Impossible d'ouvrir le port | Une autre instance du jeu tourne déjà, ou le port est utilisé : en choisir un autre (ex. `7780`). |

Pour isoler un problème de pare-feu : désactiver **temporairement** le pare-feu Windows pour les réseaux privés et réessayer depuis le téléphone. Si cela fonctionne, réactiver le pare-feu et ajouter les règles ci-dessus. (Une connexion depuis le PC lui-même vers son adresse IP ne prouve rien : Windows ne filtre pas ce trafic local.)
