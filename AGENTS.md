# Web et Android : un seul projet

Ce dépôt est la source commune du site Node.js et de l'APK Flutter. Par défaut,
une demande de modification du jeu concerne les deux plateformes, sauf indication
explicite de l'utilisateur.

- Modifier les règles/API dans `server.js` et le rendu commun dans `app.js`,
  `art.js`, `style.css`, `index.html` à la racine. Conserver le plateau et les
  illustrations d'origine, sauf demande explicite de les changer.
- Exécuter `python3 mobile/tool/sync_game_assets.py` après chaque changement du
  rendu web et inclure les fichiers générés dans le même commit. Ne pas modifier
  directement les copies générées dans `mobile/assets/game/`.
- Les adaptations tactiles spécifiques restent dans `mobile/assets/game/mobile.css`
  et `mobile-bootstrap.js`. L'accueil et le transport natifs sont dans `mobile/lib/`.
  Vérifier leur compatibilité avec tout changement du rendu ou de l'API.
- Tester le serveur partagé et l'APK : `flutter analyze`, puis `flutter test
  --dart-define=SMOKE_SERVER=http://127.0.0.1:8787` depuis `mobile/` avec un serveur
  local actif. Vérifier aussi le rendu navigateur pour les changements visuels.
- Pour livrer une modification embarquée, augmenter la version Android, compiler
  un APK ARM64, conserver la signature des APK publiés, publier le fichier et sa
  somme SHA-256 dans `downloads/`, puis vérifier le téléchargement distant.
  Actualiser aussi la version affichée près du lien APK dans `index.html`.
  Une compilation CI avec une nouvelle clé debug ne constitue pas une mise à jour
  installable par-dessus les APK déjà distribués.
- Le serveur commun de production est `https://monopoly-bw6e.onrender.com`.
  Render doit utiliser ce dépôt et la branche contenant les changements. Ne pas
  annoncer un déploiement Render sans l'avoir vérifié. Les joueurs Android
  doivent installer un nouvel APK pour recevoir les changements embarqués.
- Le dépôt web précédent `Demnatikhalid/monopoly` a été comparé au commit
  `aa97d1fb23d516acdf67c8bb3d44c36162e952c4` ; ses changements de `server.js`,
  `app.js` et `style.css` ont été intégrés. Il ne doit plus servir de seconde
  source après le changement du dépôt dans Render.

La configuration Render et le fonctionnement commun sont décrits dans
`docs/DEPOT-COMMUN.md`.
