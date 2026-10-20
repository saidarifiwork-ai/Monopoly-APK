# Enchères synchronisées

Le joueur arrivé sur un terrain, une gare ou une compagnie libre peut acheter
au prix normal ou choisir « Mettre aux enchères ». Terminer le tour sans acheter
lance aussi les enchères. Si le joueur ne dispose pas du prix normal à son arrivée,
elles commencent automatiquement. Une dette doit être réglée avant d'enchérir.

Tous les joueurs encore en partie peuvent participer, y compris celui arrivé sur
le bien. Chacun répond à son tour : offre en DH entiers supérieure à la meilleure
(dès 1 DH), ou passage définitif pour cette enchère. Une réponse doit parvenir au
serveur dans les 15 secondes ; sinon le joueur passe. Le meneur attend les autres,
et reprend la parole si quelqu'un le dépasse. Le plus offrant paie uniquement son
offre à la banque ; les autres ne paient rien. Si aucune offre n'est faite, le bien
reste libre. L'achat au prix normal ne peut pas être rouvert pour la même arrivée.
Le joueur dont c'était le tour peut ensuite terminer son tour ou rejouer son double.

Le serveur contrôle le tour de parole, le budget et le délai ; aucune autre action
financière, construction ou déplacement n'est autorisé pendant l'enchère. Les
robots répondent automatiquement, avec un plafond de 90 % du prix affiché, limité
à leur trésorerie. Les mêmes données et commandes sont utilisées sur le site et
l'APK. La saisie du prix est conservée pendant les actualisations du plateau.

Le lien « Télécharger l’APK Android » du site pointe vers le fichier public GitHub
sans numéro de version, actualisé à chaque livraison signée. Le nouvel APK doit
être installé par-dessus l'ancien pour recevoir l'interface des enchères.
