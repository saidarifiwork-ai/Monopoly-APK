# Logo commun et mélange des cartes

Le même portrait est utilisé dans l'en-tête du site, le favori du navigateur,
l'accueil Flutter et les icônes Android, y compris les icônes adaptatives.
Le dessin source est dans `design/logo-source.png`. Les différentes tailles
sont exportées sans modifier le dessin par :

```sh
python3 mobile/tool/build_brand_assets.py  # nécessite Pillow
python3 mobile/tool/sync_game_assets.py
```

## Paquets de cartes

Chaque démarrage d'une partie, y compris après « Rejouer », prépare deux paquets
indépendants de 16 cartes avec Fisher–Yates et `crypto.randomInt`, avant le tirage
de l'ordre des joueurs. Une ligne dans le journal confirme leur préparation.
Les trois cases Chance tirent dans **le même paquet** ; les cases Caisse commune
partagent leur propre paquet. Une case ne possède aucune destination prédéfinie.
Une carte comme Victoria ou Ouarzazate peut donc être la première, par hasard,
sur n'importe quelle case Chance. Le hasard peut aussi répéter une carte entre
plusieurs parties ; le moteur ne l'exclut pas artificiellement du premier tirage.

Le mélange existait déjà dans le moteur Node. Cette mise à jour ajoute une
migration explicite des anciennes sauvegardes sans version de mélange : les
cartes restantes de leurs deux paquets sont remélangées une seule fois au chargement,
ou avant leur premier tirage. Les cartes de sortie de prison détenues par les
joueurs restent détenues. Le solde, les positions et les propriétés sont conservés.
Les sauvegardes déjà mises à jour conservent ensuite l'ordre de leurs paquets.

L'API publique `/api/health` indique `cardShuffle: 3` et chaque partie porte
`cardShuffleVersion: 3`. L'ordre des cartes reste privé côté serveur.
Une reconnexion ne recrée pas un paquet à chaque requête. Un rejeu garde aussi
l'identité Google et la photo de chaque joueur, tout en créant de nouveaux paquets
au lancement de la nouvelle partie.

Les tests couvrent les trois cases Chance, la séparation des deux paquets, les
cartes détenues, le rejeu et la migration lors du chargement d'une sauvegarde.
Le navigateur et Flutter sont contrôlés localement. La mise en ligne Render et
l'apparence sur un téléphone physique restent à confirmer après déploiement.
