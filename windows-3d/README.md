# Quartiers Maroc — préparation Windows 3D

Cette version est un **prototype de développement**, pas encore le jeu 3D final.
Une scène Godot présente une table, une pièce inspirée du Maroc et les 40 cases.
Les formes placées sur les villes sont des silhouettes provisoires : elles ne
représentent pas encore les monuments recherchés. Les dés sont représentés en 3D, les pions suivent les déplacements reçus du serveur et les paiements s’affichent sur les cases. Le son fourni pour un refus d’offre est repris ; les cartes, les autres sons et animations restent à adapter. Le prototype n'a pas été testé sur
un PC Windows physique et les performances graphiques restent à vérifier.

L'accueil permet de créer ou rejoindre un salon, ou de lancer une partie contre
un robot. Une session est conservée localement pour reprendre une partie. Les
commandes prévues incluent le tirage, les dés, l'achat, les enchères, la prison,
les hypothèques, les constructions, les échanges, les dettes, le mode auto et
« Rejouer ». Les contrôles sont rudimentaires et nécessitent davantage d'essais.
Les décisions sont validées par le serveur commun, qui reste l'unique source des
règles et de l'état. Les pions 3D suivent les chemins reçus du serveur ; la parité complète avec les interfaces web et Android reste à faire.

## Essais locaux

```sh
PORT=8799 ROOMS_FILE=/tmp/quartiers-godot-test-rooms.json node server.js
# Dans un autre terminal, depuis la racine :
godot --headless --editor --path windows-3d --quit
godot --headless --path windows-3d --script res://tests/api_smoke.gd
godot --headless --path windows-3d --script res://tests/scene_smoke.gd
godot --headless --path windows-3d --script res://tests/session_ui_smoke.gd
godot --headless --path windows-3d --script res://tests/session_ui_smoke.gd
```

Le test API vérifie la création, l'accès au même salon, les droits de l'hôte et
la confidentialité des jetons. Le test de scène vérifie les 40 cases, le trajet des pions, les dés, les paiements, le son de refus, les enchères, les échanges et la reprise de session. Un essai local
supplémentaire a lancé simultanément un navigateur utilisant le code du site, le
client Flutter utilisé par l'APK et la scène Godot : les trois ont rejoint le même
salon et reçu un déplacement. Cela ne remplace pas un essai en partie complète sur
un vrai téléphone Android et un vrai PC Windows.

Le choix artistique demandé est une pièce inspirée du Maroc et un symbole 3D par
ville sur le plateau existant. Les références des monuments doivent être vérifiées
sur le web avant la modélisation ; les sources web de référence ne sont pas
accessibles depuis l'environnement actuel. `VILLES.md` liste les cases extraites
du serveur, sans inventer de correspondance ville-monument.

Victoria est le quartier personnel du propriétaire du jeu : une maquette originale de quartier inspirée de l’univers Monopoly est souhaitée.

## Prototype Windows

[ Télécharger le prototype Windows 64 bits ](https://github.com/saidarifiwork-ai/Monopoly-APK/raw/refs/heads/windows-3d-preparation/windows-3d/downloads/Quartiers-Maroc-3D-prototype-Windows.zip)

L’archive téléchargeable contient un exécutable Godot Windows 64 bits et la licence de Godot. Décompresser tous les fichiers puis ouvrir `Quartiers-Maroc-3D-prototype.exe`. Un accès Internet est nécessaire. C’est une version de travail, distincte du site et de l’APK, avec des symboles de villes provisoires ; elle n’a pas encore été validée sur un PC Windows réel ni lors d’une partie complète.

Le symbole de Victoria est représenté par un petit quartier imaginaire. Les autres silhouettes ne sont pas encore des monuments vérifiés.
