# Conserver les comptes Google, les connexions et les parties

Le serveur utilise PostgreSQL dès que `DATABASE_URL` est renseignée. Le web et
l’APK 1.0.18 utilisent déjà les mêmes API : cette modification serveur ne nécessite
pas une nouvelle installation Android. La base hébergée doit être créée dans le
compte du propriétaire ; ce dépôt ne provisionne aucun abonnement ni ressource
chez un fournisseur.

## Activation sur le service Render existant

1. Créer un projet PostgreSQL chez un hébergeur de stockage persistant, par exemple
   [Neon](https://console.neon.tech). Utiliser un projet dédié **Quartiers Maroc**,
   dans une région proche du service Render. Choisir une offre dont la durée de
   conservation convient ; vérifier les conditions du fournisseur. Une base
   d’essai qui expire ne résout pas durablement la conservation des données.
2. Dans le projet, ouvrir **Connect**, choisir la connexion PostgreSQL et copier
   l’adresse de connexion complète. Elle commence par `postgresql://` et contient
   un nom d’utilisateur, un mot de passe, l’hôte et le nom de la base. Conserver
   `sslmode=require` si le fournisseur l’ajoute.
3. Dans [Render](https://dashboard.render.com), ouvrir le service web **monopoly**
   déjà utilisé par les joueurs, puis **Environment**. Ajouter :

   | Clé | Valeur |
   | --- | --- |
   | `DATABASE_URL` | L’adresse privée copiée depuis l’hébergeur PostgreSQL |
   | `REQUIRE_DATABASE` | `true` |

   Saisir cette adresse directement dans Render ; ne pas la mettre dans GitHub,
   dans une capture d’écran ou dans une conversation. Ne pas changer le client
   Google ni l’URL publique du jeu. Ne pas créer un second service de jeu.
4. Enregistrer puis redéployer la branche `flutter-android-download` contenant
   cette modification. `npm install` installe le pilote `pg`. Le serveur crée
   ses tables et recharge ses données **avant d’accepter des requêtes**.
5. Attendre **Live**. Les journaux doivent annoncer
   `Stockage durable PostgreSQL actif.` À l’adresse publique
   `https://monopoly-bw6e.onrender.com/api/health`, vérifier :

   ```json
   {"storage":"postgresql","authPersistence":"postgresql","storageReady":true}
   ```

   Si la réponse contient `"storage":"file"`, la base n’est pas encore branchée.
   Si la base n’est pas joignable ou manque de droits, le démarrage est refusé ;
   `DATABASE_URL` configurée n’entraîne jamais un retour silencieux aux fichiers
   temporaires. `REQUIRE_DATABASE=true` empêche aussi de démarrer si l’adresse
   vient à manquer.
6. Se connecter une fois avec Google, créer une partie, puis redémarrer le service.
   Vérifier que le même navigateur et l’APK retrouvent le compte et proposent
   **Reprendre ma partie**. Faire l’essai dans les deux sens avec le même compte.

Le Blueprint `render.yaml` contient ces deux variables et une instance de serveur.
Pour un service existant configuré manuellement, ajouter les variables dans son
onglet Environment ; modifier le fichier YAML dans GitHub ne les renseigne pas
à sa place. Les valeurs du Blueprint sont saisies lors de son installation : renseigner
`DATABASE_URL` avec l’adresse privée et `REQUIRE_DATABASE` avec `true`. Elles ne
sont pas imposées automatiquement à un service existant avant le raccordement
de sa base. Le dépôt ne contient aucune adresse privée.

## Données conservées et migration

La migration `migrations/001-durable-storage.sql` crée deux tables dans la base
PostgreSQL sélectionnée :

- `quartiers_documents` : un document `auth` contient les comptes et les empreintes
  des sessions Google du jeu ; un document `rooms` contient les salons, les places,
  l’argent, les terrains, les dés et les paquets de cartes.
- `quartiers_writer` : identifie le processus serveur autorisé à sauvegarder.
  Au démarrage d’un nouveau serveur, l’ancienne instance perd le droit d’écrire,
  pour éviter qu’un déploiement Render écrase une sauvegarde plus récente.

Les jetons Google reçus ne sont pas sauvegardés. Les sessions d’authentification
sont enregistrées par leur empreinte, avec leur compte, leur expiration et leur
client Google. Les jetons privés des places font partie de la sauvegarde des
parties et ne sont jamais exposés dans les listes ou états publics. L’APK et le
navigateur ne reçoivent pas l’adresse PostgreSQL et ne s’y connectent jamais.

Si les entrées PostgreSQL n’existent pas encore, les fichiers désignés par
`ACCOUNTS_FILE`, `SESSIONS_FILE` et `ROOMS_FILE` sont importés lorsqu’ils sont
encore présents. L’import est effectué une seule fois par document, dans la
transaction de démarrage. Les documents PostgreSQL existants restent prioritaires
sur les anciens fichiers, même si ces fichiers sont périmés ou endommagés.
Des fichiers déjà effacés par Render ne peuvent pas être reconstitués. Une première
reconnexion Google peut donc être nécessaire au passage à PostgreSQL.

Les connexions expirent toujours après trente jours. La déconnexion volontaire
reste effective après un redémarrage. La sauvegarde durable ne garantit pas une
connexion sans interaction à vie : Google et les réglages du navigateur peuvent
aussi imposer une nouvelle authentification.

## Sauvegardes, erreurs et limites

Le serveur attend l’enregistrement des connexions, déconnexions, créations de
salon, transferts de place et actions des joueurs avant d’envoyer une réussite.
Les tours des robots et les enchères sont sauvegardés par la boucle de jeu ;
une sauvegarde périodique complète aussi la présence. Une panne brutale peut
perdre un changement de robot intervenu entre deux sauvegardes (environ une
seconde), sans effacer les comptes ou la dernière action confirmée.

Une interruption PostgreSQL renvoie `503 STORAGE_UNAVAILABLE` ; elle n’est pas
présentée comme un compte Google invalide et ne supprime pas les identifiants
mémorisés sur les appareils. Le serveur suspend les tours pendant l’erreur et
réessaie sa sauvegarde. Il reprend lorsque la base est disponible. Les erreurs
et la page de santé ne révèlent pas l’adresse ou le mot de passe.

Le serveur conserve la limite existante de cinquante salons. Un redémarrage ne
supprime plus ces salons ; reprendre une partie existante reste possible.

Une seule instance active du moteur de partie est prise en charge. Ne pas activer
l’autoscaling. Le mécanisme de succession protège les remplacements de processus ;
il ne répartit pas le jeu entre plusieurs serveurs. Les sauvegardes sont des
documents JSONB adaptés à cette instance ; les comptes et salons ne sont plus
liés au disque local de Render. Pour une forte montée en charge, il faudra faire
évoluer le moteur et le modèle de stockage. Activer les sauvegardes/restaurations
proposées par l’hébergeur PostgreSQL selon l’offre choisie.

PostgreSQL hébergé utilise TLS avec vérification du certificat. Une autorité
privée peut être renseignée via `DATABASE_SSL_CA` ; la vérification n’est pas
désactivée. Seules les connexions de test sur l’interface locale utilisent du
PostgreSQL sans TLS.

## Vérifications locales

```sh
npm ci
node --test test/*.test.js
# Base PostgreSQL locale dédiée aux tests, dont le rôle peut créer des schémas :
POSTGRES_TEST_URL=postgresql://USER@127.0.0.1:5432/DATABASE \
  node --test test/database.test.js
```

Les tests PostgreSQL créent et suppriment leurs propres schémas. Ne pas les lancer
sur la base des joueurs. Ils vérifient un import depuis des fichiers réels, la
suppression des fichiers temporaires, un arrêt brutal du serveur, la conservation
des cookies web et des sessions Android, les terrains et positions, la révocation
après redémarrage, l’erreur temporaire et sa récupération, l’ordre des sauvegardes
et le refus des écritures de l’ancienne instance. Ces tests ne prouvent pas que
la base du compte Render a été créée ou branchée : contrôler la page de santé
de production après sa configuration.
