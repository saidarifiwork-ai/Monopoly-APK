# Niveaux des robots

Le même moteur `bot-ai.js` est exécuté sur le serveur pour le web, Android et
les joueurs PC présents dans le salon. Le client choisit le niveau, mais ne
décide jamais des dés, du solde ni des actions autorisées.

| Niveau | Identifiant API | Stratégie |
| --- | --- | --- |
| Débutant | `beginner` | Achats parfois manqués, enchères prudentes, pas de construction. |
| Facile | `easy` | Achats plus fréquents, réserve simple, une construction par tour. |
| Normal | `normal` | Achats et construction avec réserve fixe ; niveau des anciennes parties. |
| Difficile | `hard` | Valorisation des groupes, choix des constructions selon leur rendement. |
| Expert | `expert` | Blocage des groupes adverses et réserve adaptée aux loyers atteignables. |
| Ultime | `ultimate` | Réserve plus protectrice, classement des constructions selon les positions adverses, jusqu’à cinq constructions légales par tour. |

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

En solo Ultime, la partie commence avec un humain et deux robots Ultime.
Chaque robot défend ses propres intérêts : pas d’équipe, pas de partage de
biens ou d’argent, et le second robot est un adversaire comme les humains.
Les autres niveaux de solo conservent un seul robot.

Sur le web et Android : choix avant le solo, puis choix individuel du niveau
du prochain robot dans le salon. Les changements du moteur nécessitent le
déploiement du serveur ; l’accueil Android nécessite l’APK v1.0.13 ou ultérieur.

Validation : `node --test test/*.test.js`, `flutter analyze`, puis
`flutter test --dart-define=SMOKE_SERVER=http://127.0.0.1:8866` depuis `mobile/`.

## Stratégie contextuelle d’Expert et d’Ultime

Le moteur compare les décisions à partir de la situation courante :

- Trésorerie : état du marché, loyers adverses atteignables, impôts connus et
  revenus probables des biens déjà possédés. Ultime estime deux déplacements
  futurs avec les probabilités normales des dés, sans consulter les cartes cachées.
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
`botStrategy: 4` après le déploiement.
