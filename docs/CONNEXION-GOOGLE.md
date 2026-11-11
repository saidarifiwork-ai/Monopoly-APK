# Activer la connexion Google obligatoire

La connexion obligatoire est publiée dans le dépôt commun, sur
`flutter-android-download`, avec l’APK 1.0.15. Le client Web est renseigné dans
`google-client.json` et le propriétaire a créé le client Android dans Google Cloud.
La disponibilité du nouveau serveur dépend du déploiement Render ; la vraie
connexion Google et l’inscription Android restent à vérifier sur les appareils.

**Audience Google** : en mode Test, ajouter les comptes autorisés dans
« Audience → Utilisateurs de test ». Pour permettre aux autres joueurs de se
connecter, publier l’application depuis « Audience » lorsque la console le permet.
Le mode de l’audience est géré dans Google Cloud, pas dans le code du jeu.

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

L’identifiant client Web public fourni est renseigné dans `webClientId` de
`google-client.json`. Le serveur et l'APK lisent cette même valeur ;
aucun nouvel APK n'est nécessaire pour ajouter cet identifiant public.

Pour une configuration manuelle, la variable Render `GOOGLE_CLIENT_ID` prend le
pas sur ce fichier. `PUBLIC_ORIGIN` peut préciser l'origine du site si nécessaire ;
sur Render elle est normalement déduite de `RENDER_EXTERNAL_URL`. Conserver
`NODE_ENV=production`. Ne jamais ajouter de secret Google à `google-client.json`.

La branche de connexion Google est intégrée à `flutter-android-download`.
Render doit déployer cette branche ; vérifier le statut « Live » sur la dernière
mise à jour.
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
Une session dure au maximum trente jours. Les empreintes des jetons sont
sauvegardées dans `SESSIONS_FILE` (par défaut `ACCOUNTS_FILE + '.sessions'`),
avec l’expiration, le profil et le client Google d’origine. Le fichier ne contient
pas les jetons utilisables par un navigateur ou un téléphone. Si le fichier est
conservé, un redémarrage recharge les sessions ; une déconnexion les invalide
également dans le fichier. Le cookie web possède une expiration persistante.

La même identité Google retrouve ses parties depuis l’accueil sur un autre
appareil, même après le début de la partie, sans ressaisir le code du salon.
La reprise avec le code reste aussi possible. Elle ne crée pas un second
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


## Conserver la connexion

Fermer le navigateur ou l’APK ne déconnecte pas volontairement le compte.
L’APK conserve son jeton et les métadonnées du compte dans le stockage sécurisé.
Une erreur réseau au démarrage ne les supprime pas. Deux nouvelles tentatives
sont prévues après un court délai ; « Réessayer ma connexion » reste disponible.
Si le serveur refuse un ancien jeton, Android tente une authentification Google
légère, sans ouvrir le sélecteur de comptes. Le compte vérifié doit correspondre
au compte mémorisé ; le renouvellement silencieux n’accepte pas un autre compte.
Google peut toutefois imposer une nouvelle interaction ou une nouvelle autorisation.

Le web commence par vérifier son cookie, sans charger Google lorsque la session
est toujours valide. Une interruption réseau ne supprime pas le code de salon
mémorisé. Si une connexion Google est à nouveau nécessaire, la sélection
automatique est proposée uniquement après une connexion antérieure, selon les
possibilités du navigateur. La déconnexion explicite efface ce choix automatique.

**Limite de Render gratuit :** un fichier local n’est pas une base de données
durable. Si Render remplace l’instance ou efface son disque éphémère, le fichier
de sessions peut disparaître. La reprise Google peut alors être nécessaire.
Pour garantir la conservation après ces événements, un disque persistant ou
un stockage externe est nécessaire ; cette mise à jour n’en provisionne aucun.
Avec un disque persistant, placer `ACCOUNTS_FILE`, `SESSIONS_FILE` et `ROOMS_FILE`
sur le volume conservé. Ne jamais placer ces fichiers dans le répertoire servi
par Express, ni les ajouter au dépôt Git.

Les tests incluent le redémarrage d’un serveur avec son fichier de sessions,
la révocation après redémarrage, l’expiration, la fermeture/réouverture d’un onglet,
la reprise après une erreur réseau et le renouvellement Android simulé. Ces essais
ne garantissent pas que Google autorisera toujours une connexion silencieuse sur
un appareil réel.


## Reprendre sa partie entre le web et Android

Après connexion au même compte Google, l’accueil web et Android affiche les
parties actives de ce compte, même si aucun code de salon n’est enregistré sur
cet appareil. « Reprendre ma partie » transfère le contrôle de la place choisie.
Plusieurs parties sont proposées séparément. Les salons en attente, les parties
solo avec robots et les parties entre amis sont pris en charge ; les parties
terminées et les places éliminées sont exclues.

Le serveur conserve la même place, les terrains, l’argent, la position, les dés
et les adversaires. Si un robot temporaire jouait pour cette place, le joueur
reprend le contrôle. Un simple affichage de l’accueil ne touche pas la présence
et ne reprend pas la place à l’autre appareil.

`GET /api/my-games` exige une session Google vérifiée et renvoie uniquement des
résumés des parties appartenant au compte, sans jeton de jeu. `POST /api/resume`
vérifie la participation du compte puis renouvelle le jeton de cette place.
Les anciennes commandes, y compris un départ envoyé tardivement, sont refusées
avec `409 SEAT_MOVED`. Les clients reviennent à l’accueil sans déconnecter Google.
Rejoindre manuellement le salon avec le même compte effectue aussi ce transfert.

Cette reprise s’appuie sur les parties présentes sur le serveur commun. Elle ne
crée pas une sauvegarde dans Google Drive et ne rend pas durable le disque
éphémère de Render. Si la sauvegarde du salon disparaît, le compte Google ne
suffit pas à recréer la partie. Voir les limites de stockage ci-dessus.

Les tests couvrent le transfert web → Android → web, l’absence de code local,
les parties entre amis et solo Ultime, le retour du robot temporaire, les droits
entre comptes et les commandes de l’ancien appareil. Le navigateur vérifie les
boutons et l’affichage desktop/téléphone avec un fournisseur Google simulé ; les
tests Flutter incluent un serveur Node réel local. Aucun essai sur téléphone
physique n’est revendiqué.
