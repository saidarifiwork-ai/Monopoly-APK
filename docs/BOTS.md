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

Les niveaux avancés évaluent les offres reçues du point de vue de l’acheteur
ou du vendeur, et cherchent à préserver les sources de revenu lorsqu’ils
règlent une dette. Ils ne consultent pas les cartes à venir et ne changent
ni les probabilités des dés, ni les règles d’argent. Ultime reste battable :
ce moteur repose sur des heuristiques de stratégie, pas sur une garantie de victoire.

Le paramètre optionnel `botLevel` est accepté par `/api/create` et l’action
`addbot`. La valeur par défaut est `normal` ; les valeurs inconnues sont
refusées. Le niveau est enregistré sur chaque robot et conservé lors d’un
rejeu. Le bot temporaire d’un humain utilise Normal s’il n’a pas de niveau.

Sur le web et Android : choix avant le solo, puis choix individuel du niveau
du prochain robot dans le salon. Les changements du moteur nécessitent le
déploiement du serveur ; l’accueil Android nécessite l’APK v1.0.12 ou ultérieur.

Validation : `node --test test/*.test.js`, `flutter analyze`, puis
`flutter test --dart-define=SMOKE_SERVER=http://127.0.0.1:8787` depuis `mobile/`.
