$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'engine.ps1')
function Assert($condition,$message){if(-not $condition){throw "ECHEC : $message"}}
$a=Invoke-Api '/api/create' @{name='Said'} @{};$b=Invoke-Api '/api/join' @{name='Ami';code=$a.code} @{}
$s=Get-Room $a.code;$p=Get-Player $s $a.token;$q=Get-Player $s $b.token
Assert ($s.tiles.Count -eq 40) 'plateau 40 cases'
Assert (@($s.tiles | Where-Object {$_.kind -eq 'property'}).Count -eq 22) '22 villes'
Assert ($s.tiles[13].name -eq 'Fès' -and $s.tiles[37].name -eq 'Casablanca') 'villes marocaines'
$public=Invoke-Api '/api/state' @{} @{code=$a.code;token=$a.token}
Assert (-not $public.players[0].ContainsKey('token')) 'jetons privés'
Invoke-GameAction $s $p @{type='start'};$s.phase='playing' # Gameplay fixture; opening covered in test-opening.ps1
$denied=$false;try{Invoke-GameAction $s $q @{type='roll'}}catch{$denied=$true};Assert $denied 'tour adverse refusé'
$s.rolled=$true;$p.pos=1;Invoke-GameAction $s $p @{type='buy'}
Assert ($p.money -eq 1440 -and $s.tiles[1].owner -eq $p.id) 'achat'
$s.tiles[3].owner=$p.id;Assert ((Get-Rent $s $s.tiles[1]) -eq 4) 'groupe complet'
Invoke-GameAction $s $p @{type='build';index=1};Assert ((Get-Rent $s $s.tiles[1]) -eq 10) 'maison et loyer'
$denied=$false;try{Invoke-GameAction $s $p @{type='build';index=1}}catch{$denied=$true};Assert $denied 'construction équilibrée'
Invoke-GameAction $s $p @{type='sellhouse';index=1};Invoke-GameAction $s $p @{type='mortgage';index=1};Assert ($s.tiles[1].owner -eq $p.id -and $s.tiles[1].mortgaged) 'hypotheque'
$s.dice=@(2,3);Invoke-GameAction $s $p @{type='end'};Assert ($s.turn -eq 1 -and -not $s.rolled) 'tour suivant'
Invoke-GameAction $s $q @{type='roll'};Assert ($s.rolled -and $q.pos -ge 0 -and $q.pos -lt 40) 'dés'
Assert (@($s.events | Where-Object {$_.type -eq 'dice'}).Count -eq 1) 'événement de dés'
$move=@($s.events | Where-Object {$_.type -eq 'move'})[0]
Assert ($move.path.Count -eq $s.dice[0]+$s.dice[1]) 'parcours case par case'
$p.pos=38;$before=$p.money;Move-Player $s $p 5;$move=@($s.events | Where-Object {$_.type -eq 'move'})[-1]
Assert (($move.path -join ',') -eq '39,0,1,2,3' -and $p.money -eq $before+200) 'passage départ animé'
$s.tiles[12].owner=$p.id;$s.dice=@(3,4);Assert ((Get-Rent $s $s.tiles[12]) -eq 28) 'une compagnie'
$s.tiles[28].owner=$p.id;Assert ((Get-Rent $s $s.tiles[12]) -eq 70) 'deux compagnies'
$q.money=10;$s.tiles[5].owner=$q.id;Pay $s $q 50 $p
Assert (-not $q.out -and $s.tiles[5].owner -eq $q.id -and $q.money -eq 10 -and $s.debts.Count -eq 1) 'dette sans liquidation'
Invoke-GameAction $s $q @{type='mortgage';index=5};Assert ($q.money -eq 60 -and -not $s.debts.Count) 'paiement apres choix'
Pay $s $q 10000 $p;Invoke-GameAction $s $q @{type='bankrupt'};Assert ($q.out -and $s.phase -eq 'finished' -and $s.players[$s.turn].id -eq $p.id) 'victoire'
$solo=Invoke-Api '/api/create' @{name='Solo';mode='solo'} @{};$s=Get-Room $solo.code;$human=$s.players[0];$bot=$s.players[1]
Assert ($s.phase -eq 'opening' -and $bot.bot) 'solo avec robot et tirage initial';$s.phase='playing'
$s.turn=1;$s.rolled=$true;$s.dice=@(2,3);$bot.pos=1;$s.botPhase='buy';$s.botNext=0;Invoke-BotStep $s
Assert ($s.tiles[1].owner -eq $bot.id -and $s.turn -eq 1 -and $s.botPhase -eq 'build') 'achat robot visible séparément'
$s.tiles[3].owner=$bot.id;$s.botNext=0;Invoke-BotStep $s
Assert ($s.tiles[1].level -eq 1 -and $s.turn -eq 1 -and $s.botPhase -eq 'end') 'construction robot séparée'
$s.botNext=0;Invoke-BotStep $s;Assert ($s.turn -eq 0) 'robot rend la main'
$s.turn=1;$s.rolled=$true;$s.botPhase='end';$s.dice=@(3,3);$s.botNext=0;Invoke-BotStep $s
Assert ($s.turn -eq 1 -and -not $s.rolled) 'double robot'
$s.botNext=0;Invoke-BotStep $s;Assert $s.rolled 'relance robot'
# Cards are covered in test-cards.ps1.
$ids=@($s.events | ForEach-Object {$_.id});Assert (($ids | Select-Object -Unique).Count -eq $ids.Count) 'événements uniques'
$s.phase='finished';$count=$s.events.Count;Invoke-BotStep $s;Assert ($s.events.Count -eq $count) 'robot arrêté en fin de partie'
Write-Output 'OK : 40 cases, 22 villes, achats, loyers, maisons, compagnies, faillite, parcours animés, événements ordonnés, paquets de cartes et étapes du robot.'
