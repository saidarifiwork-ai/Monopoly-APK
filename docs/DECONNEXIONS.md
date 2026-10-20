# Joueurs absents : web et Android

Le serveur mesure la dernière requête authentifiée de chaque joueur. Après 30
secondes sans requête, les autres voient « Déconnecté » et le délai restant.
Après 60 secondes, le joueur est contrôlé par un robot temporaire. Il conserve
son identité, son argent, ses propriétés, sa prison et ses dettes. Les décisions
prises par le robot font partie de la partie et ne sont pas annulées au retour.
La vérification tourne toutes les secondes côté serveur, indépendamment des
requêtes des joueurs. Le robot progresse tant qu'au moins un humain reste actif.

« Quitter la partie » demande confirmation et passe immédiatement la main au
robot. Le bouton « Reprendre ma partie » conserve la session sur cet appareil.
Toute nouvelle requête authentifiée de ce joueur lui rend le contrôle. Le code
du salon et le prénom seuls ne permettent pas de récupérer une place : il faut
la session d'origine, dans le même navigateur/profil ou la même installation APK.
Sur le web, elle est sauvegardée localement ; effacer les données du navigateur
ou utiliser la navigation privée peut la perdre. Sur Android, changer de serveur
ou réinstaller après désinstallation peut aussi perdre la session.

Les robots ajoutés dès le départ restent des robots. Un joueur déjà en faillite
ne récupère pas ses biens au retour. Une partie terminée ne redémarre pas.
Dans le salon, le robot garde la place ; l'hôte absent doit revenir pour démarrer.
Les anciennes sessions sans mesure de présence reçoivent une minute de grâce.

Les parties ne sont pas garanties après un redéploiement Render : le stockage
`/tmp` reste temporaire. Le forfait gratuit peut également mettre le serveur en
veille ; le suivi reprend à son réveil. Les clients web et APK doivent partager
le même serveur pour voir ces états.

## Pause volontaire : Mode auto

Pendant le tirage de l’ordre ou la partie, chaque joueur voit « 🤖 Mode auto »
près de son propre nom. Le robot prend immédiatement le relais quand la case
est cochée. Elle reste cochée après une actualisation ou une reconnexion :
il faut la décocher pour reprendre la place. Les actions manuelles sont bloquées
pendant ce mode, mais sa désactivation reste autorisée. Le serveur ne permet pas
de contrôler un autre joueur avec cette commande. Les robots peuvent continuer
à jouer si tous les humains ont volontairement choisi le mode auto.

« Quitter la partie » revient au mécanisme de déconnexion : au retour, la session
authentifiée reprend automatiquement la place, sans imposer de décocher le mode
auto.
