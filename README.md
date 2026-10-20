# Quartiers — jeu immobilier entre amis

Le site et l’APK partagent désormais ce dépôt. Voir le [guide du dépôt commun et du raccordement Render](docs/DEPOT-COMMUN.md). Les demandes de changement concernent les deux versions par défaut ; les consignes sont dans `AGENTS.md`.

## Application Android Flutter

L'application mobile se trouve dans [`mobile/`](mobile/README.md). Elle propose une interface tactile avec plateau zoomable et commandes en bas de l'écran. Le solo avec robot et les salons entre amis utilisent le serveur Node.js et nécessitent Internet. Consultez le guide mobile pour compiler et installer un APK de test, configurer le serveur et exécuter les tests.

Les instructions Windows ci-dessous concernent la version web PowerShell d'origine.

Jeu original en français, inspiré du principe de Monopoly. Plateau vert à **40 cases et 22 villes marocaines** : Fès, Casablanca, Rabat, Marrakech, Tanger… Mode solo contre un robot ou 2 à 6 joueurs (humains et robots). Aucune installation de dépendances, aucun compte, aucune clé payante. Windows PowerShell 5.1 suffit.

## Un plateau animé

- Pions illustrés : voiture, chapeau, bateau, bottine, bague et vélo. Le premier joueur a la voiture et le premier robot le chapeau bleu.
- Lancer de dés visible, puis déplacement case par case, avec la case traversée mise en évidence.
- Le bandeau indique qui joue et ce qui se passe. Le robot lance, avance, achète, construit puis termine son tour en plusieurs étapes visibles.
- Une carte Chance ou Caisse commune sort de sa pile et se retourne pour afficher son effet. « Continuer » ferme la carte ; elle se ferme aussi automatiquement après quelques secondes.
- Les événements sont ordonnés par le serveur et les commandes sont bloquées pendant leur animation dans le navigateur.
- Illustrations SVG, polices système et styles locaux : le jeu reste gratuit et utilisable sans Internet.

## Démarrer

Dans l'Explorateur Windows, double-cliquez sur **Lancer.cmd** : le serveur démarre en arrière-plan et le navigateur s'ouvre quand il est prêt. Ouvrir le fichier dans un onglet de VS Code ne l'exécute pas. Vous pouvez aussi taper `.\monopolie\Lancer.cmd` dans le terminal depuis le dossier `testff`.

Saisissez votre prénom, puis cliquez sur **Jouer contre le robot**. Les joueurs lancent les dés pour déterminer leur ordre de passage. Lancez les dés, achetez si vous le souhaitez, puis terminez votre tour : le robot lance ses dés, achète et construit automatiquement. Ses décisions apparaissent dans le journal. Aucun deuxième appareil nécessaire.

Pour jouer entre amis, choisissez **Créer un salon entre amis**. L'hôte peut aussi ajouter des robots avant de commencer.

Adresse directe : **http://127.0.0.1:8787**. Pour arrêter le serveur, double-cliquez sur **Arreter.cmd** (les parties sont effacées). Relancez avec Lancer.cmd après une mise à jour. Si la page affiche `ERR_CONNECTION_REFUSED`, exécutez Lancer.cmd et consultez `server-error.log` si le lancement échoue.

## Amis sur le même Wi-Fi

Dans PowerShell, tapez `ipconfig` pour trouver l'adresse IPv4 du PC, par exemple `192.168.1.25`. Tous les joueurs, y compris l'hôte, ouvrent alors **http://192.168.1.25:8787**. Le bouton « Copier le lien » contient ainsi la bonne adresse. Un lien avec `localhost` fonctionne uniquement sur votre propre PC.

Si Windows demande l'autorisation réseau, autorisez PowerShell sur votre **réseau privé**. Si la connexion reste bloquée, vérifiez le pare-feu et l'isolation Wi-Fi des invités. N'ouvrez pas de port sur votre routeur.

## Amis à distance

Solution conseillée : un réseau privé Tailscale. Installez Tailscale sur le PC hôte et les appareils des amis, partagez l'accès à la machine hôte via les fonctions de partage Tailscale. Les amis ouvrent **http://ADRESSE-TAILSCALE-DU-PC:8787** et rejoignent avec le code. L'hôte doit également utiliser cette adresse avant de copier le lien d'invitation. Vérifiez les limites et conditions actuelles du forfait personnel sur https://tailscale.com/pricing et le partage sur https://tailscale.com/kb/1084/sharing. L'installation et la configuration Tailscale ne sont pas effectuées par ce projet.

Cette version est prévue pour des amis de confiance sur un réseau privé. Ne publiez pas le serveur directement sur Internet. Le PC hôte doit rester allumé et le serveur ouvert.

## Règles de cette édition

- 40 cases, 1 500 DH au départ, +200 DH en passant le départ.
- Prix, loyers par terrain et constructions du plateau classique, avec noms marocains et monnaie en DH. Chefchaouen : 2 DH sans maison, 4 avec la couleur complète, puis 10 / 30 / 90 / 160 / 250 DH pour 1 à 4 maisons et un hôtel.
- Quatre maisons puis un hôtel, construction équilibrée et uniquement pendant son tour. Stock de bâtiments illimité.
- Gares : 25 / 50 / 100 / 200 DH selon le nombre possédé. Compagnies : 4 ou 10 fois les dés. Aucun loyer sur un bien hypothéqué.
- Hypothèque : la banque prête la moitié du prix, le joueur conserve la propriété. Lever l’hypothèque coûte ce montant plus 10 % (arrondi au DH supérieur). Aucun bâtiment dans le groupe avant hypothèque ; toutes les hypothèques du groupe doivent être levées avant de construire.
- Une dette bloque les lancers et fins de tour. Le joueur choisit les maisons à vendre et les propriétés à hypothéquer. Dès que les liquidités suffisent, la dette est réglée. Aucune vente automatique des terrains. Le robot gère uniquement ses propres biens.
- Offres : argent + plusieurs terrains, gares ou compagnies contre une propriété. Acceptation, refus et contre-offre. Il faut lever les hypothèques et vendre les bâtiments du groupe avant un échange. Les transferts sont vérifiés et appliqués ensemble.
- Carte de prison : choix explicite entre l’utiliser, tenter un double ou payer. La règle personnalisée T3 reste le paiement obligatoire avant le lancer, sauf utilisation d’une carte.
- 16 cartes Chance et 16 Caisse commune, paquets séparés. Impôts simplifiés à 100 DH, parc gratuit sans cagnotte. Pas d’enchères.
- Faillite volontaire pendant une dette : actifs remis au créancier, ou rendus disponibles si la dette est envers la banque. La remise en vente sans enchères reste une simplification.
- Espace lance les dés avant le déplacement, puis termine le tour (ou prépare la relance d’un double). Le raccourci reste inactif pendant une saisie, une fenêtre, une animation, une négociation, une dette ou le tour adverse. En prison, choisissez un bouton.
- Dés et pions agrandis de 5 %, déplacement interpolé case par case avec repérage de la case traversée.

Sources : [loyers classiques](https://www.monopolyland.com/monopoly-rent-rules/), [règles Hasbro : hypothèques et ventes de bâtiments](https://www.hasbro.com/common/instruct/00009.pdf). Tests supplémentaires : `test-economy.ps1`.

## Reconnexion et limites

Une actualisation dans le même onglet conserve votre place et affiche la position actuelle sans rejouer les anciennes animations. L'état et les codes restent en mémoire du serveur : l'arrêt du serveur efface les parties. Un joueur absent bloque son tour jusqu'à son retour ; aucune exclusion automatique. Les salons sont limités à 50 par lancement. Après la mise à jour vers le plateau à 40 cases, relancez le serveur et créez une nouvelle partie.

## Vérifier le moteur

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-engine.ps1`

Vérification de l'interface avec Brave installé : `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check-browser.ps1`. Utilise un profil de test séparé, lance une vraie partie solo et vérifie les mouvements, le robot, le retournement d'une carte et le format mobile. Les images `preview-*.png` montrent les résultats.
# Offres entre joueurs et affichage large

## Prison et noms du plateau

La gare de Bouskoura remplace la gare de Casa, Victoria remplace Mohammédia et les gares de Fès et Marrakech échangent leurs positions. Les cartes de déplacement suivent ces noms.

Règle personnalisée de prison : aux tours 1 et 2, payer 50 DH avant de lancer ou tenter gratuitement un double. Un double libère gratuitement sans déplacement. Le joueur reste en simple visite et doit relancer les dés pour avancer ; ce nouveau lancer suit les règles normales. Un échec laisse le pion en prison ; terminez le tour. Au tour 3, paiement obligatoire de 50 DH avant le lancer. Une carte conservée peut être utilisée gratuitement au choix du joueur. Le robot tente les doubles puis paie au troisième tour. Tests : `test-jail.ps1`.

## Construire des maisons et hôtels

Tarifs classiques par maison : marron et bleu clair 50 DH (revente 25), rose et orange 100 DH (revente 50), rouge et jaune 150 DH (revente 75), vert et bleu foncé 200 DH (revente 100). Le passage de quatre maisons à un hôtel coûte une construction supplémentaire au même tarif. Les fiches utilisent directement ces montants. Les loyers suivent les titres classiques.

Cliquez une ville ou utilisez **Mes biens / Gérer**. Avec toute la couleur et assez d'argent, construisez de façon équilibrée, uniquement pendant votre tour, après les animations. Après quatre maisons sur chaque ville, ajoutez un hôtel au prix d'une construction. Il remplace les quatre maisons. Revendre un hôtel remet quatre maisons et rembourse la moitié du prix de construction. Le robot peut aussi construire des hôtels. Le stock de bâtiments reste illimité ; les loyers suivent les titres classiques.

Test : `powershell -NoProfile -ExecutionPolicy Bypass -File .\test-buildings.ps1`.

## Prix des villes et cartes

Prix d'achat par groupe (DH) : 60/60 ; 100/100/120 ; 140/140/160 ; 180/180/200 ; 220/220/240 ; 260/260/280 ; 300/300/320 ; 350/400. Les gares restent à 200 DH et les compagnies à 150 DH. Les loyers et constructions suivent les tarifs classiques.

Deux paquets séparés de 16 cartes sont mélangés à leur première utilisation dans chaque salon. Une carte revient sous son paquet après le tirage ; la carte de sortie de prison reste chez le joueur jusqu'à son utilisation choisie (ou sa faillite). Les deux cartes Chance « prochaine gare » ont volontairement le même effet. Les déplacements déclenchent les loyers et les éventuelles autres cartes de la case d'arrivée. Les cartes de compagnie utilisent un lancer séparé, sans changer les doubles du tour.

Textes et destinations adaptés au Maroc, effets inspirés du jeu classique historique ; ce ne sont pas les textes de la nouvelle Caisse commune de 2021. Les réparations concernent les maisons et hôtels. L'échange des cartes de sortie de prison n'est pas pris en charge.

Sources : [prix du plateau classique](https://en.wikipedia.org/wiki/List_of_London_Monopoly_locations), [contenu officiel Hasbro : 16 cartes de chaque type](https://consumercare.hasbro.com/en-us/product/monopoly-game/7EABAF97-5056-9047-F577-8F4663C79E75), [référence des cartes et variantes historiques](https://www.monopolyland.com/list-monopoly-chance-community-chest-cards/), [règles Hasbro](https://www.hasbro.com/common/instruct/00009.pdf).

Tests : `powershell -NoProfile -ExecutionPolicy Bypass -File .\test-cards.ps1`.

Cliquez sur un bien appartenant à un autre joueur, puis **Faire une offre**. Indiquez un montant en DH et cochez les propriétés à ajouter. Le vendeur peut accepter, refuser ou proposer un autre prix. Le robot répond gratuitement, sans API, selon la valeur du bien et son groupe. Une négociation à la fois ; le tour est suspendu jusqu'à son acceptation, refus ou annulation. L'argent et la propriété sont transférés ensemble après vérification.

Les terrains, gares et compagnies sont négociables. Pour un terrain, tout le groupe de couleur doit être sans bâtiments. Le bouton **Vendre une maison** rembourse la moitié du coût ; les maisons doivent être retirées de façon équilibrée. Les terrains sont hypothéqués et restent à leur propriétaire ; seuls les bâtiments sont revendus à la banque.

Sur ordinateur, le plateau s'étend sur la largeur disponible et devient rectangulaire pour conserver tous les côtés à l'écran. **Plein écran** permet de gagner encore de la place. Après une mise à jour du moteur, utilisez `Arreter.cmd`, puis `Lancer.cmd`, et actualisez avec Ctrl+F5. Attention : arrêter le serveur efface les parties en mémoire.

Tests des négociations : `powershell -NoProfile -ExecutionPolicy Bypass -File .\test-trades.ps1`.


Effets sonores : dés, déplacements, cartes, achats, constructions, prison et changement de tour. Ils sont synthétisés localement dans le navigateur, sans API ni téléchargement. Le premier clic active le son. Le bouton Son et le curseur Volume sont dans la barre latérale ; les préférences sont conservées sur ce navigateur. Le son est coupé quand l'onglet est masqué.

Avant chaque nouvelle partie, chaque joueur (robots compris) lance deux dés pour déterminer sa place. Le total le plus élevé commence, puis les autres jouent par total décroissant. Les égalités sont départagées par un nouveau lancer entre les joueurs concernés, sans modifier les autres places. Ce tirage ne déplace pas les pions. Le bouton rouge ou Espace permet de lancer ; l'ordre obtenu est affiché dans la liste des joueurs et reste valable pendant la partie. Tests : test-opening.ps1.

## Copier le projet sur un autre PC ou GitHub

1. Décompressez entièrement le ZIP (clic droit, **Extraire tout**). Ne lancez pas le jeu directement à l’intérieur du ZIP.
2. Sur un PC Windows 10 ou 11, ouvrez le dossier `monopolie`, puis double-cliquez sur **Lancer.cmd**.
3. Le jeu s’ouvre sur http://127.0.0.1:8787. Aucun compte, API, Node.js ou Python n’est nécessaire. Brave n’est pas obligatoire : utilisez votre navigateur habituel.
4. Pour arrêter le jeu, utilisez **Arreter.cmd**. Les salons et parties sont en mémoire : ils ne sont pas transférés avec le ZIP et disparaissent à l’arrêt du serveur.

Pour GitHub, ajoutez les **fichiers décompressés**, y compris `.gitignore`, dans votre dépôt. Conservez les fichiers du projet ensemble ; ils peuvent être à la racine du dépôt ou dans le dossier `monopolie`. Le ZIP peut également servir de sauvegarde. GitHub héberge le code ; le serveur PowerShell doit être lancé sur un PC Windows pour jouer. GitHub Pages seul ne lance pas ce serveur.

L’image d’accueil est intégrée dans `index.html` ; les images sources sont incluses pour les modifications futures. Le dossier de navigateur de test, les journaux, les captures de contrôle et le fichier `server.pid` sont exclus du ZIP. `check-browser.ps1` est un outil de développement qui utilise Brave ; il n’est pas nécessaire pour jouer.

Impôts près de Tétouan : **200 DH**. Taxe de luxe : **100 DH**.
