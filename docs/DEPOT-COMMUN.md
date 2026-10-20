# Un seul dépôt pour le web et l'APK

Dépôt commun : https://github.com/saidarifiwork-ai/Monopoly-APK

Branche contenant actuellement les deux versions : `flutter-android-download`.
La branche `main` ne contient pas encore cette livraison Android. Les changements
du dépôt web `Demnatikhalid/monopoly` au commit
`aa97d1fb23d516acdf67c8bb3d44c36162e952c4` sont intégrés sans retirer l'application
mobile. Le fichier `/tmp/monopoly-rooms.json` utilisé par ce serveur reste un
stockage temporaire : il ne garantit pas la conservation des parties lors d'un
redéploiement Render.

## Réglage Render à effectuer une fois

Dans le service existant `monopoly-bw6e`, ouvrir **Settings** et modifier le dépôt
lié pour sélectionner `saidarifiwork-ai/Monopoly-APK`. Si nécessaire, autoriser ce
dépôt dans l'intégration GitHub de Render. Choisir la branche
`flutter-android-download`, laisser Root Directory vide, Build Command
`npm install`, Start Command `node server.js`, et `NODE_ENV=production`.

Activer Auto-Deploy sur les commits de cette branche, puis déployer le dernier
commit. Garder le service existant permet de conserver son adresse publique.
Si le champ Repository n'est pas modifiable, consulter les options de connexion
GitHub de Render avant de créer un autre service : un nouveau service aura une
autre adresse et exigera un nouveau réglage des clients.

Cette modification dans Render n'a pas été effectuée depuis Codex. Elle reste
nécessaire pour que les prochains commits de ce dépôt mettent le site à jour.

## Prochaines modifications

Demander : « Modifie le jeu sur le web et l'APK ». Les instructions `AGENTS.md`
prévoient déjà les deux plateformes par défaut. Ouvrir les prochaines tâches Codex
sur ce dépôt et cette branche, afin de travailler sur le même code.

Les fichiers du jeu à la racine sont la source du rendu commun. Le script
`python3 mobile/tool/sync_game_assets.py` les copie dans l'application, en gardant
les commandes tactiles propres au mobile. Le workflow GitHub **APK Android**
vérifie la synchronisation, teste l'API commune et compile sur les changements du
web ou du mobile. Les fichiers compilés sont disponibles dans les artifacts du
workflow si GitHub Actions est activé. Leur téléchargement nécessite généralement
une connexion GitHub. Ces artifacts de test utilisent une clé debug de CI ; les
APK publics installables en mise à jour sont publiés séparément dans `downloads/`
avec la signature existante.

Le web reçoit ses mises à jour par Render. Les joueurs Android doivent télécharger
et installer le nouvel APK pour recevoir les fichiers embarqués modifiés. Les
deux clients utilisent le même serveur Render et le même code de salon pour jouer
ensemble. Les salons de deux serveurs différents ne sont pas fusionnés.
