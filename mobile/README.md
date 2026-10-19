# Quartiers Maroc — Android

L’accueil et l’entrée en partie sont natifs en Flutter. Le jeu utilise **le rendu original du site** : même plateau, pions SVG, dés, cartes, sons et animations. Les fichiers du jeu sont embarqués dans l’APK. Seules les données des parties sont récupérées sur le serveur ; la page du site distant n’est pas affichée.

Les commandes autour du plateau sont adaptées au tactile : actions en bas de l’écran et onglets Plateau / Biens / Joueurs / Journal / Son. Le plateau n’est pas redessiné en Flutter.

## Compilation

Outils : Flutter **3.47.7**, JDK **21**, Android SDK plateformes **35/36**, Build Tools **36.0.0**, NDK **28.2.13676358**, CMake **3.22.1**, Platform Tools et licences acceptées.

```sh
cd mobile
python3 tool/sync_game_assets.py
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

Résultat : `mobile/build/app/outputs/flutter-apk/app-release.apk`, pour Android ARM64 et Android 7 / API 24 minimum. La variante release est optimisée pour réduire sa taille mais reste **signée avec la clé de développement** : version d’essai, pas une publication Google Play. Pour une distribution durable, définir une clé de signature de production stable. Ne jamais committer un keystore ni ses mots de passe.

`tool/sync_game_assets.py` copie `../app.js`, `../art.js` et `../style.css` à l’identique, avec leurs empreintes SHA-256. Il adapte le chargement du HTML et omet la photographie d’accueil PC inutilisée. Le complément `mobile.css` organise les commandes ; `mobile-bootstrap.js` relie le rendu à l’application. Relancer le script après une évolution du rendu web. Les fichiers web de la racine ne sont pas modifiés pour Android.

## Serveur

Le solo avec robot et les salons entre amis nécessitent Internet. Adresse initiale : `https://monopoly-mauve-tau.vercel.app`. Le bouton ⚙ de l’accueil permet de la changer après vérification avec `/api/health`. La valeur initiale peut aussi être définie avec `--dart-define=API_URL=https://votre-serveur.onrender.com`.

Le réseau passe par Dart, sans autoriser d’accès universel aux fichiers locaux dans Android WebView. Seules les routes santé, état et action du serveur configuré sont permises. Le vrai jeton de session est ajouté côté natif et n’est pas transmis au rendu du jeu.

Le serveur garde les salons en mémoire. Les fonctions Vercel peuvent redémarrer ou utiliser des instances distinctes : un service Node.js persistant, par exemple celui de `../render.yaml`, convient mieux aux parties entre amis. Même sur ce service, un redémarrage efface les parties. Aucun déploiement du serveur n’est effectué ici.

## Développement et vérification

À la racine, démarrer `npm ci` puis `npm start`. Dans un autre terminal :

```sh
cd mobile
flutter run --dart-define=API_URL=http://10.0.2.2:8787
flutter analyze
flutter test
# Crée des salons sur le serveur local, qui doit être démarré.
flutter test --dart-define=SMOKE_SERVER=http://127.0.0.1:8787
```

`10.0.2.2` désigne le PC hôte depuis l’émulateur Android. HTTP local n’est accepté qu’en debug pour `10.0.2.2`, `127.0.0.1` et `localhost`. Sur téléphone physique, utiliser HTTPS.

Les tests couvrent le transport natif et ses restrictions, les sessions, les erreurs réseau, l’accueil et le passage vers le rendu original. L’intégration réelle est ignorée sans `SMOKE_SERVER`. Un contrôle Chromium des fichiers embarqués vérifie également le plateau, le déplacement animé et les commandes. Cela ne remplace pas un essai sur un téléphone Android.

Le workflow GitHub **APK Android** analyse, teste et compile un APK d’essai. Les clés de développement de machines différentes peuvent différer : les mises à jour distribuées doivent conserver la même clé.

## Environnement cloud

```sh
source /workspace/toolchains/flutter-env.sh
cd /workspace/Monopoly-APK/mobile
```

Réutiliser le checkout existant : chaque tâche cloud est déjà isolée, sans worktree supplémentaire. Les outils et caches sont conservés dans `/workspace/toolchains`. Relancer les processus nécessaires après restauration. Le retour à l’accueil oublie la session locale mais ne supprime pas le joueur distant ; son absence peut bloquer son tour.
