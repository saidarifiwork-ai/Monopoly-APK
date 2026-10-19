$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'engine.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject($block){$failed=$false;try{& $block}catch{$failed=$true};Assert $failed 'Expected rejected action'}
$a=Invoke-Api '/api/create' @{name='A'} @{}
foreach($name in @('B','C','D')){$null=Invoke-Api '/api/join' @{name=$name;code=$a.code} @{}}
$s=Get-Room $a.code;$hostPlayer=$s.players[0]
Reject {Invoke-GameAction $s $s.players[1] @{type='start'}}
Invoke-GameAction $s $hostPlayer @{type='start'}
Assert ($s.phase -eq 'opening') 'Opening must precede gameplay'
Reject {Invoke-GameAction $s $hostPlayer @{type='roll'}}
Reject {Invoke-GameAction $s $s.players[1] @{type='orderroll'}}
Reject {Invoke-Api '/api/join' @{name='Late';code=$a.code} @{}}
function Get-Random {param($Minimum,$Maximum);if(-not $script:testRolls.Count){throw 'No test dice'};$value=$script:testRolls[0];$script:testRolls=@($script:testRolls | Select-Object -Skip 1);return $value}
try{
 # A=8, B=11, C=8, D=4. Only A/C reroll; their second score cannot overtake B.
 $script:testRolls=@(4,4,5,6,2,6,1,3)
 foreach($p in $s.players){Invoke-GameAction $s $p @{type='orderroll'}}
 Assert ($s.phase -eq 'opening' -and $s.openingPending.Count -eq 2 -and $s.turn -eq 0) 'Tied players reroll'
 Assert (@($s.events | Where-Object {$_.type -eq 'move'}).Count -eq 0) 'Opening must not move pawns'
 Assert (@($s.players | Where-Object {$_.pos -ne 0 -or $_.money -ne 1500 -or $_.doubles -ne 0}).Count -eq 0) 'Opening must not alter money, position, doubles'
 Reject {Invoke-GameAction $s $s.players[1] @{type='orderroll'}}
 $script:testRolls=@(6,6,6,6)
 Invoke-GameAction $s $s.players[0] @{type='orderroll'};Invoke-GameAction $s $s.players[2] @{type='orderroll'}
 Assert ($s.openingRound -eq 3 -and $s.openingPending.Count -eq 2) 'Repeated ties reroll again'
 $script:testRolls=@(1,1,6,6)
 Invoke-GameAction $s $s.players[0] @{type='orderroll'};Invoke-GameAction $s $s.players[2] @{type='orderroll'}
 Assert ($s.phase -eq 'playing' -and ($s.turnOrder -join ',') -eq '1,2,0,3' -and $s.turn -eq 1 -and -not $s.rolled) 'Stable descending rank after ties'
 Assert ($s.players[0].id -eq $hostPlayer.id) 'Keep pawn identities and player array stable'
 Reject {Invoke-GameAction $s $hostPlayer @{type='orderroll'}}
 foreach($expected in @(2,0,3,1)){Next-Turn $s;Assert ($s.turn -eq $expected) 'Turn follows drawn order and wraps'}
 $s.players[2].out=$true;Next-Turn $s;Assert ($s.turn -eq 0) 'Skip bankrupt player in drawn order'
}finally{Remove-Item Function:\Get-Random}
$solo=Invoke-Api '/api/create' @{name='Solo';mode='solo'} @{};$s=Get-Room $solo.code
function Get-Random {param($Minimum,$Maximum);$value=$script:testRolls[0];$script:testRolls=@($script:testRolls | Select-Object -Skip 1);return $value}
try{
 $script:testRolls=@(1,2,6,5)
 Invoke-GameAction $s $s.players[0] @{type='orderroll'}
 $before=$s.eventSeq;Invoke-BotStep $s;Assert ($s.eventSeq -eq $before) 'Bot waits for visible human dice animation'
 $s.botNext=0;Invoke-BotStep $s
 Assert ($s.phase -eq 'playing' -and $s.turn -eq 1 -and -not $s.rolled) 'Robot rolls and may start first'
 Assert ($s.players[1].pos -eq 0) 'Bot opening roll does not move'
 $public=Invoke-Api '/api/state' @{} @{code=$solo.code;token=$solo.token}
 Assert ($public.turnOrder.Count -eq 2 -and -not $public.players[1].ContainsKey('token')) 'Public order without credentials'
}finally{Remove-Item Function:\Get-Random}
Write-Output 'OK: opening permissions, ties and repeat ties, rankings, no movement or payment, turn rotation, bankruptcy skip, robot opening.'
