# Quartiers Maroc pour Android — version 1.0.1

[**Télécharger l’APK mis à jour**](https://github.com/saidarifiwork-ai/Monopoly-APK/raw/refs/heads/flutter-android-download/downloads/quartiers-maroc-android-arm64-v1.0.1.apk)

Environ 19 Mo. Android 7 minimum, téléphone ARM64, connexion Internet obligatoire. La signature est identique à la version 1.0.0 publiée ici : installer la mise à jour par-dessus l’application précédente.

Cette version reprend **le vrai plateau du site**, ses pions SVG, les dés, les cartes, les sons et les animations. L’accueil est en Flutter ; les fichiers originaux du jeu sont embarqués dans l’APK. Les commandes sont adaptées au tactile, avec des onglets Biens / Joueurs / Journal / Son et les actions en bas de l’écran.

![Aperçu du plateau original et des commandes mobiles](preview-mobile-original.png)

L’aperçu du rendu embarqué est contrôlé dans Chromium à une taille de téléphone ; il ne constitue pas un essai sur téléphone physique. Les tests de l’application et de l’API, les vérifications du rendu original et la signature de l’APK ont été contrôlés. La somme SHA-256 est fournie dans le fichier voisin.

Version d’essai signée avec une clé de développement, pas une publication Google Play. Le serveur configuré est `https://monopoly-mauve-tau.vercel.app`, modifiable dans les réglages de l’accueil. Vercel peut perdre les salons stockés en mémoire ; un serveur Node.js persistant est recommandé pour les parties entre amis.

Le code se trouve dans `../mobile/`. Le fichier sans numéro de version est aussi actualisé pour les anciens liens.
