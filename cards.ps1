# Texts adapted for Quartiers Maroc; two independent shuffled queues.
function New-Card($title,$text,$effect,$value=0){return @{title=$title;text=$text;effect=$effect;value=$value}}
function New-CardDecks {
 $chance=@(
  (New-Card 'Cap sur le depart' 'Retournez au depart et recevez 200 DH.' 'go'),
  (New-Card 'Voyage sur la cote' 'Avancez a Victoria. Recevez 200 DH si vous passez le depart.' 'move' 39),
  (New-Card 'Rendez-vous au sud' 'Avancez a Ouarzazate. Recevez 200 DH si vous passez le depart.' 'move' 24),
  (New-Card 'Visite imperiale' 'Avancez a Meknes. Recevez 200 DH si vous passez le depart.' 'move' 11),
  (New-Card 'Train express' 'Rejoignez la prochaine gare. Si elle appartient a un adversaire, payez le double du loyer.' 'station'),
  (New-Card 'Correspondance ferroviaire' 'Rejoignez la prochaine gare. Si elle appartient a un adversaire, payez le double du loyer.' 'station'),
  (New-Card 'Visite technique' 'Rejoignez la prochaine compagnie. Si elle est adverse, relancez les des et payez 10 fois leur total.' 'utility'),
  (New-Card 'Benefice bancaire' 'Votre placement vous rapporte 50 DH.' 'cash' 50),
  (New-Card 'Bon de liberation' 'Gardez cette carte. Vous choisissez quand utiliser cette carte.' 'free'),
  (New-Card 'Demi-tour' 'Reculez de trois cases et appliquez la case arrivee.' 'back'),
  (New-Card 'Convocation' 'Allez en prison sans prime de depart.' 'jail'),
  (New-Card 'Entretien des logements' 'Payez 25 DH par maison et 100 DH par hotel.' 'repairs' 25),
  (New-Card 'Exces de vitesse' 'Payez une amende de 15 DH.' 'cash' -15),
  (New-Card 'Billet pour Fes' 'Rejoignez la gare de Fes. Recevez 200 DH si vous passez le depart.' 'move' 5),
  (New-Card 'Participation collective' 'Versez 50 DH a chaque autre joueur encore en partie.' 'payall' 50),
  (New-Card 'Placement arrive a terme' 'Recevez 150 DH de la banque.' 'cash' 150)
 )
 $chest=@(
  (New-Card 'Nouveau depart' 'Rejoignez le depart et recevez 200 DH.' 'go'),
  (New-Card 'Regularisation bancaire' 'La banque vous rembourse 200 DH.' 'cash' 200),
  (New-Card 'Consultation medicale' 'Payez 50 DH de frais de consultation.' 'cash' -50),
  (New-Card 'Petite vente' 'Une vente vous rapporte 50 DH.' 'cash' 50),
  (New-Card 'Autorisation de sortie' 'Gardez cette carte pour sortir gratuitement de prison. Choisissez cette carte ou tentez un double.' 'free'),
  (New-Card 'Passage au commissariat' 'Allez en prison sans recevoir la prime de depart.' 'jail'),
  (New-Card 'Epargne debloquee' 'Recevez 100 DH de votre epargne.' 'cash' 100),
  (New-Card 'Trop-percu rembourse' 'Recuperez 20 DH.' 'cash' 20),
  (New-Card 'Votre anniversaire' 'Chaque autre joueur encore en partie vous verse 10 DH.' 'collectall' 10),
  (New-Card 'Assurance versee' 'Recevez 100 DH de votre assurance.' 'cash' 100),
  (New-Card 'Soins hospitaliers' 'Payez 100 DH de frais de soins.' 'cash' -100),
  (New-Card 'Frais de scolarite' 'Payez 50 DH pour les frais scolaires.' 'cash' -50),
  (New-Card 'Mission accomplie' 'Un service rendu vous rapporte 25 DH.' 'cash' 25),
  (New-Card 'Travaux dans le quartier' 'Payez 40 DH par maison et 115 DH par hotel.' 'repairs' 40),
  (New-Card 'Prix du quartier' 'Recevez un prix de 10 DH.' 'cash' 10),
  (New-Card 'Heritage familial' 'Recevez un heritage de 100 DH.' 'cash' 100)
 )
 return @{chance=@($chance | Sort-Object {Get-Random});chest=@($chest | Sort-Object {Get-Random})}
}
function Resolve-Landing($s,$p,$multiplier=1,$utilityRoll=$false){
 $t=$s.tiles[$p.pos]
 if($t.price -gt 0 -and $t.owner -and $t.owner -ne $p.id -and -not $t.mortgaged){
  $owner=@($s.players | Where-Object {$_.id -eq $t.owner})[0];$rent=(Get-Rent $s $t)*$multiplier
  if($utilityRoll){$roll=@((Get-Random -Minimum 1 -Maximum 7),(Get-Random -Minimum 1 -Maximum 7));$rent=10*($roll[0]+$roll[1]);Add-Event $s 'dice' @{playerId=$p.id;dice=$roll;text='Des de la compagnie (sans deplacement)'}}
  Pay $s $p $rent $owner;Announce $s $p ($p.name+' verse '+$rent+' DH a '+$owner.name+'.')
 }elseif($t.kind -eq 'tax'){Pay $s $p $t.taxAmount $null;Announce $s $p ($p.name+' paie '+$t.taxAmount+' DH de taxes.')}
 elseif($p.pos -eq 30){Send-ToJail $s $p}
 elseif($t.kind -in @('chance','chest')){Draw-Card $s $p $t.kind}
}
function Draw-Card($s,$p,$deck){
 if(-not $s.decks){$s.decks=New-CardDecks}
 $card=$s.decks[$deck][0];$s.decks[$deck]=@($s.decks[$deck] | Select-Object -Skip 1)
 if($card.effect -ne 'free'){$s.decks[$deck]+=,$card}
 Add-Event $s 'card' @{playerId=$p.id;deck=$deck;title=$card.title;text=$card.text};Add-Log $s ($p.name+' : '+$card.title+' — '+$card.text)
 switch($card.effect){
  'cash' {if($card.value -ge 0){$p.money+=$card.value}else{Pay $s $p (-$card.value) $null}}
  'go' {Jump-Player $s $p 0;$p.money+=200}
  'jail' {Send-ToJail $s $p}
  'free' {$p.jailCards=@($p.jailCards)+@(@{deck=$deck;card=$card})}
  'repairs' {$houses=0;$hotels=0;foreach($t in $s.tiles){if($t.owner -eq $p.id){if($t.level -eq 5){$hotels++}else{$houses+=$t.level}}};$hotelRate=100;if($deck -eq 'chest'){$hotelRate=115};$bill=$houses*$card.value+$hotels*$hotelRate;Pay $s $p $bill $null;Announce $s $p ([string]$houses+' maisons et '+$hotels+' hotels : '+$bill+' DH de travaux.')}
  'payall' {foreach($other in @($s.players | Where-Object {-not $_.out -and $_.id -ne $p.id})){if($p.out -or $s.phase -ne 'playing'){break};Pay $s $p $card.value $other}}
  'collectall' {foreach($other in @($s.players | Where-Object {-not $_.out -and $_.id -ne $p.id})){if($s.phase -ne 'playing'){break};Pay $s $other $card.value $p}}
  'back' {$from=$p.pos;$path=@(1..3 | ForEach-Object {($from-$_+40)%40});$p.pos=$path[-1];Add-Event $s 'move' @{playerId=$p.id;from=$from;to=$p.pos;path=$path;jump=$false};Resolve-Landing $s $p}
  {$_ -in 'move','station','utility'} {
   $destination=$card.value
   if($card.effect -ne 'move'){$targets=if($card.effect -eq 'station'){@(5,15,25,35)}else{@(12,28)};$destination=@($targets | Where-Object {$_ -gt $p.pos} | Select-Object -First 1);if(-not $destination.Count){$destination=$targets[0]}else{$destination=$destination[0]}}
   $steps=($destination-$p.pos+40)%40;Move-Player $s $p $steps
   $multiplier=1;if($card.effect -eq 'station'){$multiplier=2};Resolve-Landing $s $p $multiplier ($card.effect -eq 'utility')
  }
 }
 $s.botNext=[DateTime]::UtcNow.AddSeconds(15).Ticks
}
