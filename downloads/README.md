# Télécharger Quartiers Maroc pour Android

[**Télécharger l’APK de test**](https://github.com/saidarifiwork-ai/Monopoly-APK/raw/refs/heads/flutter-android-download/downloads/quartiers-maroc-android-arm64.apk)

Android 7 minimum, téléphone ARM64, connexion Internet obligatoire. Ouvrir le fichier APK téléchargé sur le téléphone pour l’installer. Android peut demander d’autoriser l’installation depuis le navigateur utilisé.

Application Flutter : plateau tactile avec zoom, solo contre un robot et salons entre amis. Le serveur configuré est `https://monopoly-mauve-tau.vercel.app` ; il peut être changé dans les paramètres de l’application.

Version de développement signée pour les essais, sans validation sur téléphone physique. Neuf tests automatisés et la vérification de signature ont réussi. La somme SHA-256 figure dans le fichier `.sha256` voisin.

Le code source de cette version se trouve dans `../mobile/`. Cette branche de distribution n’a pas modifié `main`. L’hébergement Vercel du serveur peut perdre les salons, qui sont stockés en mémoire ; un serveur Node.js persistant est recommandé pour les parties entre amis.
