$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'engine.ps1')
function Assert($ok,$text){if(-not $ok){throw $text}}
$tiles=New-Tiles
foreach($g in 0..7){
 $cost=@(50,50,100,100,150,150,200,200)[$g]
 foreach($t in @($tiles | Where-Object {$_.group -eq $g})){Assert ($t.build -eq $cost) 'Classic house price'}
 $deal=Invoke-Api '/api/create' @{name='Seller';mode='solo'} @{};$room=Get-Room $deal.code;$room.phase='playing';$seller=$room.players[0]
 $index=0;while($room.tiles[$index].group -ne $g){$index++}
 $room.tiles[$index].owner=$seller.id;$room.tiles[$index].level=1;$cash=$seller.money
 Invoke-GameAction $room $seller @{type='sellhouse';index=$index}
 Assert ($seller.money -eq $cash+$cost/2 -and $room.tiles[$index].level -eq 0) 'Exact half-price house refund'
}
$a=Invoke-Api '/api/create' @{name='Builder';mode='solo'} @{};$s=Get-Room $a.code;$s.phase='playing';$p=$s.players[0];$p.money=10000;$s.turn=1
foreach($i in @(21,23,24)){$s.tiles[$i].owner=$p.id}
$before=$p.money;$failed=$false;try{Invoke-GameAction $s $p @{type='build';index=21}}catch{$failed=$true};Assert ($failed -and $p.money -eq $before -and $s.tiles[21].level -eq 0) 'Construction must be rejected outside own turn'
$s.turn=0
for($level=1;$level -le 5;$level++){
 foreach($i in @(21,23,24)){Invoke-GameAction $s $p @{type='build';index=$i};Assert ($s.tiles[$i].level -eq $level) 'Building failed during own turn'}
}
Assert ((Get-Rent $s $s.tiles[21]) -eq 1050) 'Hotel rent'
$failed=$false;try{Invoke-GameAction $s $p @{type='build';index=21}}catch{$failed=$true};Assert $failed 'Cannot build beyond hotel'
Invoke-GameAction $s $p @{type='sellhouse';index=21};Assert ($s.tiles[21].level -eq 4) 'Hotel returns four houses'
$failed=$false;try{Invoke-GameAction $s $p @{type='sellhouse';index=21}}catch{$failed=$true};Assert $failed 'Balanced demolition'
$s.decks=New-CardDecks;$card=@($s.decks.chance | Where-Object {$_.effect -eq 'repairs'})[0];$s.decks.chance=@($card);$before=$p.money;Draw-Card $s $p 'chance'
Assert ($p.money -eq $before-300) 'Four houses and two hotels repairs'
Write-Output 'OK: construction restricted to own turn, four houses then hotel, hotel rent, maximum level, balanced demolition, hotel repairs.'
