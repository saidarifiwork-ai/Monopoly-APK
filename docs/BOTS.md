# Niveaux des robots

Le même moteur `bot-ai.js` est exécuté sur le serveur pour le web, Android et
les joueurs PC présents dans le salon. Le client choisit le niveau, mais ne
décide jamais des dés, du solde ni des actions autorisées.

| Niveau | Identifiant API | Robots en solo | Stratégie |
| --- | --- | --- | --- |
| Débutant | `beginner` | 1 | Achats parfois manqués, enchères prudentes, une construction simple par tour. |
| Facile | `easy` | 1 | Achats plus fréquents, réserve simple, une construction par tour. |
| Normal | `normal` | 1 | Valorisation des groupes et choix des constructions selon leur rendement. |
| Difficile | `hard` | 2 | Réserve adaptée au prochain déplacement, protection des groupes et sortie de prison pour compléter un groupe. |
| Expert | `expert` | 3 | Risques sur deux déplacements, comparaison des investissements et négociations stratégiques. |
| Ultime | `ultimate` | 4 | Risques et revenus sur quatre déplacements pondérés, développement adverse et jusqu’à cinq constructions légales par tour. |

Expert et Ultime évaluent aussi la sortie de prison : ils privilégient une
carte ou un paiement de 50 DH quand des achats utiles les attendent, en
particulier la dernière ville d’un groupe. Ils peuvent attendre un double
si les prochains loyers sont trop dangereux ou si leur budget est insuffisant.
Leur réserve de trésorerie est plus souple pour compléter un groupe.

Les niveaux avancés évaluent les offres reçues du point de vue de l’acheteur
ou du vendeur, et cherchent à préserver les sources de revenu lorsqu’ils
règlent une dette. Ils ne consultent pas les cartes à venir et ne changent
ni les probabilités des dés, ni les règles d’argent. Ultime reste battable :
ce moteur repose sur des heuristiques de stratégie, pas sur une garantie de victoire.

Le paramètre optionnel `botLevel` est accepté par `/api/create` et l’action
`addbot`. La valeur par défaut est `normal` ; les valeurs inconnues sont
refusées. Le niveau est enregistré sur chaque robot et conservé lors d’un
rejeu. Le bot temporaire d’un humain utilise Normal s’il n’a pas de niveau.

Le solo crée automatiquement un humain et le nombre de robots indiqué ci-dessus,
au niveau sélectionné. Chaque robot défend ses propres intérêts : pas d’équipe,
pas de partage de biens ou d’argent, et chaque autre robot est un adversaire comme
les humains. Les salons privés gardent l’ajout manuel des robots (six joueurs
au maximum). Les parties déjà commencées et les rejeux conservent leur effectif ;
créer un nouveau solo applique la nouvelle répartition.

Sur le web et Android : choix avant le solo, puis choix individuel du niveau
du prochain robot dans le salon. Les changements du moteur nécessitent le
déploiement du serveur ; les nouveaux nombres et descriptions de l’accueil Android nécessitent l’APK v1.0.20. Les anciens APK utilisent aussi la nouvelle répartition serveur pour les nouveaux solos.

Validation : `node --test test/*.test.js`, `flutter analyze`, puis
`flutter test --dart-define=SMOKE_SERVER=http://127.0.0.1:8866` depuis `mobile/`.

## Stratégie contextuelle d’Expert et d’Ultime

Le moteur compare les décisions à partir de la situation courante :

- Trésorerie : état du marché, loyers adverses atteignables, impôts connus et
  revenus probables des biens déjà possédés. Expert estime deux déplacements et Ultime quatre déplacements
  futurs, avec un poids décroissant avec les probabilités normales des dés, sans consulter les cartes cachées.
- Investissements : comparaison du gain de loyer d’une construction avec celui
  d’une levée d’hypothèque. Une construction n’est plus retardée systématiquement
  par la levée d’hypothèque d’un bien peu rentable.
- Échanges : évaluation du portefeuille avant et après l’échange complet,
  y compris les groupes que l’adversaire reçoit. Un robot peut proposer l’achat
  ou l’échange de la dernière ville d’un groupe.
- Dettes : comparaison des revenus et des options stratégiques perdus en vendant
  des bâtiments ou en hypothéquant des propriétés légales.
- Enchères : possibilité d’ouvrir directement une enchère lorsqu’un achat direct
  ne convient pas, plutôt que d’investir ailleurs avant de tenter d’enchérir.

Une proposition initiée par un robot expire après 45 secondes sans réponse,
avec une annonce dans le journal. Le délai repart après une contre-offre.
Les propositions sont espacées d’au moins deux minutes par robot, et chaque
robot ne fait au maximum que deux contre-offres dans une même négociation.
Les robots restent des concurrents indépendants et utilisent les mêmes actions
validées par le serveur que les humains.

Ces changements sont exécutés sur le serveur : l’APK v1.0.13 reste compatible,
sans réinstallation pour cette évolution de la stratégie.

## Protection des joueurs humains en mode auto

Quand un robot remplace un humain (`autoPlay` ou `temporaryBot`), il refuse
systématiquement les offres et ne propose pas de négociations à sa place.
Cette protection s’applique aussi après une déconnexion ou un départ volontaire.

Le serveur refuse immédiatement une nouvelle offre impliquant ce joueur. Une
négociation déjà en attente est également refusée si l’un des participants passe
en auto, même si l’autre participant tente ensuite d’accepter ou de contre-proposer.
Aucun argent ni bien n’est transféré dans ce cas. Les achats à la banque,
constructions et décisions courantes du mode auto ne sont pas modifiés.

Dès que l’humain reprend le contrôle, il peut à nouveau négocier lui-même.
Les robots adversaires permanents continuent d’utiliser leurs stratégies d’échange.
Cette règle côté serveur est commune au web, à l’APK et au PC, sans nouvelle APK.


## Négociations et construction après l’échange

Expert et Ultime évaluent les groupes et la trésorerie des **deux** participants
après le paiement et le transfert des terrains. Une projection de constructions
équilibrées estime les loyers accessibles, le coût des levées d’hypothèque et les
positions publiques des adversaires. Les biens adverses inutilisés qui peuvent
être hypothéqués sont également pris en compte : dépenser son argent disponible
ne signifie pas toujours perdre sa capacité de construire.

Quand la vente offre le dernier terrain d’un groupe adverse, Ultime exige un
prix qui limite le financement d’une construction immédiate, sauf si l’échange
améliore suffisamment son propre potentiel de revenu. Expert applique cette
protection avec davantage de souplesse. Le prix varie avec la situation ; il ne
consiste pas à réclamer systématiquement tout l’argent du joueur.

Le robot peut proposer un ou deux terrains échangeables en complément de
l’argent, par exemple Victoria contre Safi s’il possède déjà Casablanca. Il peut
aussi retirer un terrain d’une offre qu’il reçoit en tant qu’acheteur. Il compare
les propositions, vérifie les fonds disponibles et refuse si aucune solution
acceptable n’existe. Les contre-offres ne transfèrent rien sans acceptation ; les
terrains hypothéqués ou les groupes portant des bâtiments restent protégés par
les règles d’échange. Les biens demandés figurent dans le panneau de négociation
et dans le journal. Répéter une offre basse ne fait pas céder le robot.

Cette stratégie est la même face à un humain ou à un autre robot. Elle utilise
les informations publiques et des heuristiques de projection ; elle ne garantit
aucun taux de victoire et n’intervient pas sur les dés ou les cartes.

La modification s’exécute sur le serveur commun : elle est compatible avec
l’APK 1.0.14 actuel, sans nouveau téléchargement. L’API `/api/health` indique
`botStrategy: 5` après le déploiement.


## Progression et coût de calcul

Les niveaux représentent des stratégies programmées, pas un QI humain mesuré.
Tous essaient d’acquérir des propriétés et peuvent construire avec un groupe
complet ; les niveaux faibles prennent des décisions plus simples. À partir de
Difficile, le budget tient compte des loyers probables. Expert et Ultime comparent
les occasions d’investissement, les hypothèques et le développement de chacun.
Les probabilités de déplacement sont mises en cache à partir de la position
publique et de l’horizon seulement, dans un cache borné. Un déplacement modifie
la clé ; aucun paquet de cartes n’entre dans ce cache. Cette économie de calcul
permet d’augmenter l’effectif sans recalculer les mêmes probabilités pour chaque
prix envisagé dans une négociation.

Les tests couvrent les six effectifs via la vraie API, la conservation au rejeu,
les enchères entre quatre robots indépendants, les différences de décision selon
le niveau et une simulation légale à cinq joueurs. Le web et le choix des niveaux
sur téléphone sont vérifiés dans Chromium et les tests Flutter.

## Déblocage progressif des solos

Un compte Google commence avec Débutant. Une victoire valide débloque exactement
le niveau suivant : Débutant → Facile → Normal → Difficile → Expert → Ultime.
Les niveaux déjà débloqués restent jouables. Après une victoire en Ultime, tous
les niveaux sont marqués validés. Le nombre de robots reste celui du tableau.

Le serveur contrôle `botLevel` lors de la création d’un solo, même si le client
modifie le menu ou envoie directement une requête. Un niveau verrouillé renvoie
`403 LEVEL_LOCKED`. Une victoire doit être constatée par le moteur, avec un seul
survivant propriétaire du compte et tous les adversaires initiaux éliminés, au
bon niveau et au bon effectif. Une simple déclaration de victoire du client ne
vaut pas validation. Une défaite ne débloque rien.

Les défis sont identifiés à leur création par des métadonnées serveur privées.
Leur effectif ne peut pas être modifié au rejeu. Les salons entre amis restent
des parties libres : gagner un salon personnalisé n’attribue pas de palier solo.
Les anciennes parties restent reprenables, avec leurs joueurs ; leurs résultats
sans ces métadonnées de défi ne sont pas ajoutés rétroactivement à la progression.

Les premières victoires sont enregistrées par compte dans le document `auth`
PostgreSQL, avec le niveau, la date et l’identifiant du tour de jeu. La sauvegarde
de la partie terminée précède l’attribution, et les attributions sont idempotentes.
Après une interruption entre ces deux sauvegardes, le serveur reprend la
validation du résultat conservé. Une reconnexion Google préserve les paliers.
Les requêtes répétées et les rejeux d’un ancien niveau ne débloquent pas le
palier d’après. Une sauvegarde refusée ne donne pas accès à un niveau supérieur.

`GET /api/progression` exige la connexion Google et renvoie les niveaux validés
et débloqués du compte. Ce résumé apparaît aussi dans le profil authentifié,
`/api/my-games` et l’état privé du joueur. La progression d’un autre compte et
les métadonnées privées du défi ne sont pas exposées. Le web et l’APK 1.0.21
présentent les cadenas, le palier à gagner et le niveau disponible après victoire.
Un changement de compte réinitialise immédiatement l’affichage des accès.

Aucune nouvelle configuration de base n’est nécessaire si PostgreSQL est déjà
actif. Sans PostgreSQL, la progression suit les limites des fichiers temporaires
[documentées ici](BASE-DE-DONNEES.md). Les anciens APK restent soumis au contrôle
serveur ; installer 1.0.21 pour afficher correctement les cadenas.

Les tests vérifient les six paliers via l’API, les victoires et défaites réelles
du moteur, les demandes falsifiées, les rejeux, le changement d’appareil et de
compte, la conservation dans PostgreSQL après perte des fichiers, les erreurs de
sauvegarde, ainsi que les menus et le message de victoire dans Chromium et Flutter.
