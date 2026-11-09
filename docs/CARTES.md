# Mélange et pioche des cartes

Le serveur prépare deux paquets indépendants de 16 cartes : Chance et Caisse
commune. Ils sont mélangés avant le tirage de l’ordre des joueurs, à chaque
lancement de partie, y compris après « Rejouer ».

Le mélange Fisher–Yates utilise les entiers aléatoires uniformes de Node.js
(`crypto.randomInt`), au lieu du tri biaisé `sort(() => Math.random() - 0.5)`.
Il ne modifie pas les dés ni les décisions des robots.

Toutes les cases Chance et tous les joueurs partagent une même file de cartes
Chance dans un salon. Les cases Caisse commune partagent leur propre file.
La carte du dessus est appliquée puis placée sous le paquet. Une carte de
sortie de prison est conservée par le joueur et revient sous son paquet
lorsqu’elle est utilisée ou rendue à la banque.

Chaque salon possède ses propres paquets. Les tours et les tirages ne relancent
pas le mélange. Lorsqu’une partie enregistrée contient déjà ses paquets, leur
ordre est conservé. Le correctif prend donc effet au lancement d’une nouvelle
partie ; il ne change pas les cartes encore en attente d’une partie en cours.

Une même carte peut naturellement apparaître en premier dans deux nouvelles
parties : le hasard ne garantit pas une première carte différente à chaque fois.
Aucune case n’impose Victoria, Ouarzazate ou une autre destination.

Le serveur ne transmet pas les paquets cachés dans `/api/state`. Le moteur des
robots ne les consulte pas. Le même tirage s’applique au web, à l’APK et au PC
quand ces clients sont présents dans une partie commune.

Tests : `node --test test/cards.test.js` puis `node --test test/*.test.js`.
Les tests couvrent les permutations, les démarrages et rejeux, la pioche commune,
l’indépendance des salons, la restauration des parties et les cartes conservées.
