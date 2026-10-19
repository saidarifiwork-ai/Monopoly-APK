# Quartiers Maroc pour Android — version 1.0.2

[**Télécharger l’APK mis à jour**](https://github.com/saidarifiwork-ai/Monopoly-APK/raw/refs/heads/flutter-android-download/downloads/quartiers-maroc-android-arm64-v1.0.2.apk)

Environ 18 Mo. Android 7 minimum, téléphone ARM64, connexion Internet obligatoire. La signature est identique à la version 1.0.0 publiée ici : installer la mise à jour par-dessus l’application précédente.

Cette version reprend **le vrai plateau du site**, ses pions SVG, les dés, les cartes, les sons et les animations. L’accueil est en Flutter ; les fichiers originaux du jeu sont embarqués dans l’APK. Les commandes sont adaptées au tactile, avec des onglets Biens / Joueurs / Journal / Son et les actions en bas de l’écran.

![Aperçu du plateau original et des commandes mobiles](preview-mobile-original.png)

L’aperçu du rendu embarqué est contrôlé dans Chromium à une taille de téléphone ; il ne constitue pas un essai sur téléphone physique. Les tests de l’application et de l’API, les vérifications du rendu original et la signature de l’APK ont été contrôlés. La somme SHA-256 est fournie dans le fichier voisin.

Version d’essai signée avec une clé de développement, pas une publication Google Play. Le serveur configuré est `https://monopoly-mauve-tau.vercel.app`, modifiable dans les réglages de l’accueil. Vercel peut perdre les salons stockés en mémoire ; un serveur Node.js persistant est recommandé pour les parties entre amis.

Le code se trouve dans `../mobile/`. Le fichier sans numéro de version est aussi actualisé pour les anciens liens.

## Démarrage — version 1.0.2

L’interface apparaît avant la lecture des réglages ; un délai limite et une reprise sont prévus si cette lecture échoue. Le stockage Android utilise l’implémentation par canaux 2.4.28 et le moteur Flutter utilise Skia pour améliorer la compatibilité d’affichage. Treize tests automatisés réussissent. L’écran blanc signalé sur un Xiaomi 12 Pro Android 15 doit encore être confirmé comme résolu sur cet appareil. Aucun essai Android complet n’est revendiqué : l’émulateur sans accélération matérielle n’a pas terminé son démarrage système.

L’accueil est toujours présenté au lancement, y compris après la restauration d’une session : le bouton « Reprendre ma partie » ouvre ensuite le jeu. Un délai limite protège aussi le chargement du rendu embarqué, avec les boutons de reprise et d’accueil.
