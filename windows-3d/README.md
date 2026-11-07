# Quartiers Maroc — préparation Windows 3D

Cette partie est **en cours de développement**. Elle ne contient pas encore de
plateau 3D, de scènes, d'interface de jeu complète ni d'exécutable Windows.
Elle ne modifie ni le site ni l'APK.

`scripts/game_api.gd` est un premier client Godot 4 du serveur commun. Il peut
vérifier le serveur, créer ou rejoindre un salon, lire l'état et envoyer les
commandes avec le code et le jeton de sa propre session. Les règles, enchères,
dettes, robots, événements et animations restent pilotés par le serveur existant.
Le client 3D devra les représenter sans modifier leurs règles et gérer toutes les
commandes et les situations : prison, cartes, doubles, offres, enchères,
hypothèques, faillite, mode auto, reconnexion, victoire et nouvelle partie.

Test local :

```sh
PORT=8799 ROOMS_FILE=/tmp/quartiers-godot-test-rooms.json node server.js
# Dans un autre terminal, depuis la racine :
godot --headless --path windows-3d --script res://tests/api_smoke.gd
```

Le test crée deux sessions Godot qui utilisent le protocole du site et de l'APK ;
il vérifie la création, l'accès au même salon, le démarrage visible par les deux
clients, les droits de l'hôte et l'absence des jetons dans la liste des joueurs.
Un second essai local a vérifié qu’un navigateur utilisant `app.js` crée un salon, qu’un client Godot y entre et qu’il reçoit le démarrage. L’interface PC complète et l’interopérabilité avec un appareil Android physique restent à tester.

Le choix artistique demandé est une pièce inspirée du Maroc et un symbole 3D par
ville sur le plateau existant. Les références des monuments doivent être vérifiées
sur le web avant la modélisation ; les sources web de référence ne sont pas
accessibles depuis l'environnement actuel. `VILLES.md` liste les cases extraites
du serveur, sans inventer de correspondance ville-monument.

Victoria est le quartier personnel du propriétaire du jeu : une maquette originale de quartier inspirée de l’univers Monopoly est souhaitée.
