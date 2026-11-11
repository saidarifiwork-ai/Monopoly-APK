# Chance et Caisse commune

Le serveur commun prépare deux paquets distincts de 16 cartes avant le tirage
initial de l’ordre des joueurs. Chaque nouvelle partie, y compris après
« Rejouer », reçoit deux nouveaux mélanges Fisher–Yates utilisant les nombres
aléatoires cryptographiques de Node.js. Toutes les cases Chance puisent dans le
même paquet Chance ; toutes les cases Caisse commune dans le même paquet Caisse.
Le web et l’APK affichent le résultat envoyé par ce serveur.

La version de mélange 4 vérifie les identifiants, l’unicité et le contenu des
cartes sauvegardées. L’ancienne vérification acceptait deux simples tableaux,
même réduits à quelques cartes : mélanger ces tableaux ne restaurait pas les
cartes manquantes. Les paquets anciens ou invalides sont désormais reconstruits
à partir du catalogue complet, puis mélangés. L’argent, les terrains, les
positions et les cartes de sortie de prison détenues sont conservés.

Une partie valide conserve l’ordre de ses cartes quand on la reprend, change
d’appareil ou redémarre le serveur. Une carte tirée retourne sous son paquet,
sauf la sortie de prison gardée par le joueur jusqu’à utilisation ou faillite.
Il peut arriver que deux nouvelles parties aient la même première carte : le
mélange ne force pas une carte différente au prix d’un tirage biaisé.

## Vérification de livraison

`/api/health` doit annoncer `"version":25` et `"cardShuffle":4` (ou une version
ultérieure). Un commit GitHub publié ne prouve pas que Render l’a déployé.
La correction concerne le serveur : aucun nouvel APK n’est nécessaire.

## Tests

`node --test test/cards.test.js` vérifie la préparation avant le tirage initial,
les replays, les six cases, l’indépendance des salons, les sauvegardes tronquées
ou dupliquées et le retour des cartes de prison. Il exerce aussi le véritable
mélange cryptographique, indépendamment des tests à hasard contrôlé.

Avec `POSTGRES_TEST_URL` pointant exclusivement vers une base de test séparée,
`node --test test/database.test.js` vérifie la réparation des documents
PostgreSQL et la conservation de leur ordre après redémarrage et changement
d’appareil. Ces tests ne doivent jamais viser la base de production.
