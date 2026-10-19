# Quartiers Maroc — Android avec Flutter

Application Android native Flutter, en français, connectée au serveur Node.js existant. Le solo contre un robot et les parties entre amis nécessitent Internet. Les règles et les salons restent sur le serveur ; aucun moteur n'est dupliqué dans l'APK.

L'interface comprend un plateau tactile avec zoom, des commandes de tour en bas de l'écran, les joueurs, le journal, les cartes, les achats, les constructions, les hypothèques, les dettes et les négociations. Le code de salon se copie pour inviter un ami. La session est conservée sur l'appareil et réutilisée après une interruption. Une commande échouée n'est jamais renvoyée automatiquement : l'application relit l'état du serveur.

## Préparer les outils

- Flutter **3.47.7**, indiqué dans `.flutter-version`, avec son SDK Dart.
- Java **21**.
- Android SDK : plateformes **35 et 36**, Build Tools **36.0.0**, NDK **28.2.13676358**, CMake **3.22.1** et Platform Tools.
- Accepter les licences avec `flutter doctor --android-licenses`, puis contrôler `flutter doctor`.

Depuis la racine du dépôt :

```sh
cd mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

Résultat : `mobile/build/app/outputs/flutter-apk/app-debug.apk`. Cet APK de développement s'installe sur les téléphones Android ARM64, à partir d'Android 7 (API 24). Pour inclure également ARMv7 et x86_64, omettre `--target-platform android-arm64`.

Il s'agit d'une version de test, signée avec une clé de développement. Pour publier sur Google Play, définir un identifiant définitif, un keystore de production et sa configuration de signature, puis produire un AAB. Ne jamais committer la clé ou ses mots de passe. La configuration Flutter générée utilise encore la clé de développement pour la variante release.

## Adresse du serveur

Adresse initiale : `https://monopoly-mauve-tau.vercel.app`. Le bouton ⚙ de l'accueil permet de la changer ; la nouvelle adresse est vérifiée avec `/api/health` avant d'être enregistrée. Pour changer la valeur initiale à la compilation :

```sh
flutter build apk --debug --dart-define=API_URL=https://votre-serveur.onrender.com
```

Une URL HTTPS sans chemin est requise. Un navigateur et l'APK peuvent rejoindre le même salon en utilisant le même serveur. Il n'est pas nécessaire d'intégrer le serveur Node.js dans Android.

**Hébergement :** le serveur conserve les salons dans une `Map` en mémoire. Les fonctions Vercel peuvent redémarrer ou utiliser plusieurs instances : l'API de santé peut fonctionner alors qu'un salon disparaît ou devient introuvable. Utiliser un service Node.js persistant, par exemple le service décrit dans `../render.yaml`, pour des parties fiables. Le redémarrage de ce service efface aussi les parties ; une sauvegarde durable des salons nécessiterait une évolution séparée du serveur. Aucun déploiement n'est effectué par cette migration.

## Développer avec un serveur local

Dans un premier terminal, à la racine du dépôt :

```sh
npm ci
npm start
```

Dans un second terminal :

```sh
cd mobile
flutter run --dart-define=API_URL=http://10.0.2.2:8787
```

`10.0.2.2` désigne le PC hôte depuis l'émulateur Android. Les adresses HTTP locales ne sont permises qu'en debug, pour `10.0.2.2`, `127.0.0.1` et `localhost`. Pour un téléphone physique, utiliser un serveur HTTPS accessible depuis le téléphone. Une URL localhost sur le téléphone désigne le téléphone lui-même.

## Vérifications

```sh
flutter analyze
flutter test
# Le serveur local doit être démarré. Ce test crée des salons de test.
flutter test test/server_integration_test.dart --dart-define=SMOKE_SERVER=http://127.0.0.1:8787
```

La suite vérifie les URL, les erreurs API, les sessions, l'absence de commandes renvoyées après une erreur, la sérialisation des requêtes, les cartes et l'affichage en portrait/paysage. Le test d'intégration est ignoré sans `SMOKE_SERVER` pour éviter de contacter un serveur de production par défaut.

Le workflow GitHub **APK Android**, dans `../.github/workflows/android.yml`, permet aussi de lancer l'analyse, les tests et une compilation debug depuis l'onglet Actions. Il fournit l'APK comme artefact. L'ajout du fichier de workflow ne lance ni publication ni déploiement.

## Environnement cloud préparé

```sh
source /workspace/toolchains/flutter-env.sh
cd /workspace/Monopoly-APK/mobile
```

Ce fichier initialise les chemins des outils et caches conservés dans `/workspace/toolchains`. Réutiliser le checkout existant : chaque tâche cloud est déjà isolée, sans besoin de worktree supplémentaire.

Les parties sont en mémoire côté serveur. Le retour à l'accueil oublie la session locale mais ne supprime pas le joueur distant ; son absence peut bloquer le tour. La perte de réseau laisse les dernières informations visibles et bloque les commandes jusqu'à la reconnexion. Les sauvegardes Android de l'application sont désactivées pour ne pas sauvegarder les sessions de jeu.
