$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'engine.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject($block){$failed=$false;try{& $block}catch{$failed=$true};Assert $failed 'Expected rejection'}
$a=Invoke-Api '/api/create' @{name='Buyer'} @{};$b=Invoke-Api '/api/join' @{name='Seller';code=$a.code} @{}
$s=Get-Room $a.code;$p=Get-Player $s $a.token;$q=Get-Player $s $b.token
Invoke-GameAction $s $p @{type='start'};$s.phase='playing' # Gameplay fixture; opening covered in test-opening.ps1
foreach($i in @(1,5,12)){
 $s.tiles[$i].owner=$q.id;$before=$p.money+$q.money
 Invoke-GameAction $s $p @{type='offer';index=$i;amount=100}
 Reject {Invoke-GameAction $s $p @{type='acceptoffer'}}
 Reject {Invoke-GameAction $s $p @{type='roll'}}
 Invoke-GameAction $s $q @{type='counteroffer';amount=200}
 Invoke-GameAction $s $p @{type='acceptoffer'}
 Assert ($s.tiles[$i].owner -eq $p.id -and $p.money+$q.money -eq $before -and -not $s.offer) 'Atomic trade failed'
 Reject {Invoke-GameAction $s $p @{type='acceptoffer'}}
}
$s.tiles[3].owner=$q.id;$s.tiles[1].owner=$q.id;$s.tiles[1].level=1
Reject {Invoke-GameAction $s $p @{type='offer';index=3;amount=100}}
Invoke-GameAction $s $q @{type='sellhouse';index=1}
Invoke-GameAction $s $p @{type='offer';index=3;amount=100}
Invoke-GameAction $s $q @{type='rejectoffer'}
Assert (-not $s.offer -and $s.tiles[3].owner -eq $q.id) 'Refusal failed'
$q.bot=$true
Invoke-GameAction $s $p @{type='offer';index=3;amount=100}
$cash=$p.money;$p.money=0
Reject {Invoke-GameAction $s $q @{type='acceptoffer'}}
Assert ($s.tiles[3].owner -eq $q.id) 'Unfunded trade changed ownership'
$p.money=$cash;Invoke-GameAction $s $p @{type='canceloffer'}
Invoke-GameAction $s $p @{type='offer';index=3;amount=80};Invoke-BotStep $s
Assert ($s.offer.respondent -eq $p.id -and $s.offer.amount -eq 150) 'Robot counteroffer failed'
Invoke-GameAction $s $p @{type='canceloffer'}
Invoke-GameAction $s $p @{type='offer';index=3;amount=300};Invoke-BotStep $s
Assert ($s.tiles[3].owner -eq $p.id) 'Robot acceptance failed'
Write-Output 'OK: property, station, utility trades; counteroffer; authorization; duplicate acceptance; houses; refusal; robot; conservation of money.'
