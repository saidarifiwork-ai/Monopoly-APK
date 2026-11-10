# Activer la connexion Google obligatoire

Le code web et Android est prêt sur la branche `google-required-login`.
**La production reste sur sa version actuelle tant que les identifiants Google
ne sont pas configurés.** Ne déployer cette branche sur Render qu'après les
étapes ci-dessous : son serveur refuse le jeu anonyme, y compris sans configuration.

## 1. Créer le projet Google

Ouvrir https://console.cloud.google.com/projectcreate avec le compte Google
qui administrera le jeu. Créer un projet nommé « Quartiers Maroc » et le sélectionner.
Ouvrir **Google Auth Platform** (ou « APIs et services → Écran de consentement OAuth »).

- **Branding / Présentation** : nom « Quartiers Maroc », adresse d'assistance et
  adresse de contact du propriétaire du projet.
- **Audience** : choisir « Externe ». Pendant le mode test, ajouter les adresses
  Google des personnes qui testeront la connexion. Publier l'application lorsque
  la console le permet pour ouvrir la connexion aux autres joueurs.
- Seuls l'identifiant Google, le nom et la photo servent au jeu. Aucun accès
  Instagram, contacts, Drive ou Gmail n'est demandé. Aucun mot de passe n'est
  transmis au jeu. Le jeton Google peut contenir une adresse e-mail, mais le
  serveur ne l'enregistre pas et ne la distribue pas aux autres joueurs.

## 2. Créer l'identifiant Web

Dans **Clients → Créer un client**, choisir **Application Web**.
Nom : « Quartiers Web ».

Ajouter cette **origine JavaScript autorisée**, sans chemin :

```text
https://monopoly-bw6e.onrender.com
```

Le bouton utilise une fenêtre Google, sans redirection OAuth gérée par le jeu.
Il n'est pas nécessaire d'ajouter une URI de redirection pour ce parcours.
Copier l'**identifiant client**, qui finit par `.apps.googleusercontent.com`.
**C'est une valeur publique que tu peux me transmettre. Aucun secret client
n'est nécessaire ; ne partage pas le secret proposé par la console.**

## 3. Enregistrer l'application Android

Dans le **même projet Google**, créer un second client de type **Android** :

| Champ | Valeur |
| --- | --- |
| Nom | Quartiers Android |
| Nom de package | `com.quartiersmaroc.quartiers_mobile` |
| Empreinte SHA-1 | `52:51:8A:4F:69:FB:AD:65:C5:5F:E0:2F:1D:A3:6C:28:57:21:EA:B0` |

L'empreinte est celle de la clé conservée pour les APK déjà distribués. Le nouvel
APK doit être signé avec cette même clé. Un APK compilé par la CI avec une autre
clé debug ne pourra pas utiliser cette inscription Android ni mettre à jour les
APK publiés ici. En cas de nouvelle signature officielle, inscrire aussi sa SHA-1.

L'APK utilise l'identifiant **Web** de l'étape 2 comme `serverClientId`, récupéré
depuis le serveur. Il n'a besoin ni d'un secret client ni de `google-services.json`.

## 4. Raccorder l'identifiant et activer le code

Transmets-moi **l'identifiant client Web public** après avoir enregistré les deux
clients Google. Je pourrai renseigner `webClientId` dans `google-client.json`,
puis publier la mise à jour commune. Le serveur et l'APK lisent cette même valeur ;
aucun nouvel APK n'est nécessaire pour ajouter cet identifiant public.

Pour une configuration manuelle, la variable Render `GOOGLE_CLIENT_ID` prend le
pas sur ce fichier. `PUBLIC_ORIGIN` peut préciser l'origine du site si nécessaire ;
sur Render elle est normalement déduite de `RENDER_EXTERNAL_URL`. Conserver
`NODE_ENV=production`. Ne jamais ajouter de secret Google à `google-client.json`.

Ensuite intégrer la branche `google-required-login` à `flutter-android-download`
et déployer cette dernière sur Render. Cette intégration n'a pas été effectuée
avant la création de ton projet Google pour conserver un site jouable.
L'URL `/api/auth/config` doit alors indiquer `configured: true`.
Faire cette bascule après la fin des parties en cours : les anciennes places,
créées sans compte Google, ne sont pas attribuées à un compte sur la seule base
d'un prénom ou d'un ancien jeton. Elles nécessiteront une nouvelle partie.

Installer l'APK **1.0.15** préparé sur cette branche, puis essayer une vraie
connexion Google sur le site et sur Android. Les anciens APK n'ont pas le bouton
Google : ils doivent être mis à jour lorsque l'obligation est activée.
Le prototype PC 3D existant doit lui aussi adopter une session Google avant
de pouvoir utiliser ces API ; cette livraison prépare le web et Android.

## Comptes, données et reprise

Le compte de jeu est créé automatiquement après vérification du jeton Google
(signature, destinataire, émetteur et expiration). Son identifiant stable dérive
de l'identifiant Google, et non du nom ou de l'adresse e-mail. Le prénom du jeu
est prérempli mais reste modifiable. La photo vient exclusivement du profil Google.

Le cookie web est `HttpOnly`, `SameSite=Lax` et `Secure` en production. Android
stocke son jeton de session dans le stockage sécurisé du téléphone et l'envoie
uniquement dans les requêtes natives ; il n'est pas exposé au JavaScript du jeu.
Une session dure au maximum sept jours ; un redémarrage du serveur impose de se
reconnecter. La déconnexion invalide immédiatement la session utilisée.

La même identité Google peut reprendre sa place avec le code du salon, sur un
autre appareil, même après le début de la partie. Elle ne crée pas un second
joueur dans ce salon. Un autre compte ne peut pas reprendre sa place avec son
seul jeton de partie. Les comptes et e-mails ne sont pas exposés dans l'état public.

Le nom, la photo et la date de création du compte sont enregistrés dans
`ACCOUNTS_FILE` (par défaut `/tmp/quartiers-accounts.json`, hors du répertoire servi
au public). Sur Render gratuit, ce fichier et les parties peuvent être perdus lors
d'un redéploiement. L'identifiant du compte sera identique à la connexion suivante,
mais cela ne constitue pas une sauvegarde durable des parties. Pour conserver ces
données entre déploiements, utiliser un disque persistant et adapter `ACCOUNTS_FILE`
et `ROOMS_FILE`, ou une base de données.

## Vérifications réalisées et limites

Les tests locaux utilisent un vérificateur Google **fictif** explicitement chargé
par le lanceur de tests. Le démarrage normal `npm start` ne charge pas ce lanceur
et n'accepte aucun faux jeton ni visiteur anonyme. Les tests couvrent les refus,
les mauvais destinataires/émetteurs, l'expiration, le nonce web, les sessions, la
protection des places, les photos et la déconnexion. Le navigateur vérifie le
parcours complet avec le fournisseur fictif ; Flutter vérifie l'accueil et l'API.
Une vraie connexion Google et un essai sur téléphone restent nécessaires après
la configuration du projet Google.

Pour les tests locaux :

```sh
npm ci
node --test test/*.test.js
NODE_ENV=test GOOGLE_CLIENT_ID=test-client.apps.googleusercontent.com \
  ACCOUNTS_FILE=/tmp/quartiers-test-accounts.json \
  ROOMS_FILE=/tmp/quartiers-test-rooms.json PORT=8787 \
  node --require ./test/fixtures/google-auth-server.cjs server.js
# Dans un autre terminal, depuis mobile/ :
flutter analyze
flutter test --dart-define=SMOKE_SERVER=http://127.0.0.1:8787
```
