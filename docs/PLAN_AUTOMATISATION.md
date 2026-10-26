# Jeu plus automatique : combats locaux, monstres agressifs, quêtes qui avancent seules

Demande : « plus automatisé, liberté totale, chacun peut vivre sa propre aventure ;
quand quelqu'un déclare un combat, pas besoin que tout le monde le soit ; les monstres
attaquent quand on entre dans leur périmètre ; un RPG structuré, avec beaucoup de
possibilités mais automatique, pour que ça ne devienne pas le chaos, surtout pour le MJ. »

## Ce qui change

| Avant | Après |
|---|---|
| Une seule phase pour tout le monde : quand le MJ lance « Combat », tous les joueurs y passent. | **Combats locaux** : chaque combat ne concerne que les personnages qui y sont. Les autres continuent d'explorer, de parler, de faire leurs quêtes. Plusieurs combats peuvent avoir lieu en même temps. |
| Le MJ pose les monstres puis lance le combat. | **Agressivité** : un monstre visible attaque tout personnage qui entre dans son **périmètre** (4 cases par défaut, ligne de vue nécessaire). Sa meute le suit. Les joueurs proches rejoignent le combat. |
| Le MJ joue chaque tour de monstre. | **Les monstres jouent seuls**, après une courte pause pour que l'on voie les dés. Le MJ peut reprendre la main sur un combat (mode manuel) à tout moment. |
| Un joueur ne peut pas lancer un combat. | **Engager** : toucher un monstre → *Attaquer* ; le joueur commence. **Fuir** : jet de Dextérité, plus dur s'il y a des ennemis au contact. |
| Les quêtes avancent quand le MJ coche les objectifs. | **Objectifs automatiques** : *vaincre* (ex. 3 loups), *atteindre* un lieu, *obtenir* un objet, *parler* à un PNJ. Quand tout est fait, la quête se termine et les récompenses tombent seules. |
| Le MJ donne les quêtes. | **Les PNJ proposent leurs quêtes** : en touchant un PNJ à côté de soi, on lit sa présentation et on accepte ses quêtes. Une quête secondaire acceptée est **personnelle** (son propre fil) ; une quête principale concerne le groupe. |
| Déplacement libre sans limite. | Déplacement libre limité à 2 × la vitesse par mouvement (réglable), et le mouvement **s'arrête** si l'on est repéré en chemin. |

## Comment c'est fait (sans casser l'existant)

- Un combat local (`encounter`) a exactement la forme de la phase de combat actuelle
  (ordre, tour, PA, initiative, résultat). Pour le jouer, l'hôte **prête** ce combat au
  moteur existant (`Combat`, tours, déplacements) le temps d'une action : tout le code
  de règles, d'IA, de butin, de victoire est réutilisé tel quel.
- La phase envoyée à un joueur dépend de lui : celle de son combat s'il est engagé,
  sinon la phase générale. L'écran du téléphone n'a donc presque pas à changer.
- Une horloge de l'hôte (`tick`) fait jouer les monstres, termine les combats finis,
  vérifie l'agressivité des monstres et, si le MJ l'active, passe le tour d'un joueur absent.
- Les phases générales du MJ (Récit libre, Exploration, Dialogue, Combat, Repos) restent :
  un « Combat » général fonctionne comme avant (et clôt les combats locaux).
- Réglages (Créer › Règles) : agressivité automatique, périmètre, rayon de combat,
  monstres automatiques, délai, limite de déplacement libre, délai de tour des joueurs.

## Tests prévus

Règles (sans réseau) : un joueur repéré déclenche un combat qui ne concerne que lui ; un
autre joueur reste libre ; les monstres jouent seuls ; un joueur proche rejoint ; victoire →
XP pour les participants seulement ; fuite ; objectifs automatiques (vaincre, atteindre,
obtenir, parler) et fin de quête automatique ; quête acceptée auprès d'un PNJ.
Réseau : les scénarios existants doivent continuer de passer.

## Journal

- Serveur : combats locaux, agressivité, monstres automatiques, engager / fuir, objectifs automatiques, quêtes proposées par les PNJ (tests de règles : 148 OK).
- Téléphone : toucher un monstre → *Attaquer* ; toucher un PNJ → *Parler* et quêtes proposées ; *Fuir · 1 PA* ; bandeau « Combat ! » ; Victoire / Défaite seulement pour les participants ; quêtes proposées dans le journal.
- MJ : carte *Combats en cours* (Jouer ce tour, Tour suivant, Je joue les monstres, Terminer) ; cases *Monstres agressifs* et *Monstres automatiques* dans les règles ; type d'objectif dans l'éditeur de quête ; la partie commence en Récit libre quand les monstres sont agressifs.
- Non testé sur de vrais téléphones (captures et tests automatiques seulement).
