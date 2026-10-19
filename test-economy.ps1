$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'engine.ps1')
function Assert($ok,$why){if(-not $ok){throw $why}}
function Reject($block){$no=$false;try{& $block}catch{$no=$true};Assert $no 'Expected denial'}
function Setup {
 $script:rooms=@{};$a=Invoke-Api '/api/create' @{name='A'} @{};$b=Invoke-Api '/api/join' @{name='B';code=$a.code} @{}
 $script:s=Get-Room $a.code;$script:p=$s.players[0];$script:q=$s.players[1];Invoke-GameAction $s $p @{type='start'};$s.phase='playing' # Gameplay fixture; opening covered in test-opening.ps1
}
Setup
Assert (($s.tiles[1].rents -join ',') -eq '2,10,30,90,160,250') 'Chefchaouen classic table'
Assert (($s.tiles[39].rents -join ',') -eq '50,200,600,1400,1700,2000') 'Victoria classic table'
foreach($t in $s.tiles){if($t.kind -eq 'property'){Assert ($t.rents.Count -eq 6) 'Six rent tiers';$t.owner=$p.id;foreach($level in 1..5){$t.level=$level;Assert ((Get-Rent $s $t) -eq $t.rents[$level]) 'Rent tier'};$t.level=0}}
Setup;$s.tiles[18].owner=$p.id;$cash=$p.money
Invoke-GameAction $s $p @{type='mortgage';index=18};Assert ($p.money -eq $cash+90 -and $s.tiles[18].owner -eq $p.id -and (Get-Rent $s $s.tiles[18]) -eq 0) 'Mortgage retains deed/no rent'
Reject {Invoke-GameAction $s $p @{type='mortgage';index=18}}
Invoke-GameAction $s $p @{type='unmortgage';index=18};Assert ($p.money -eq $cash-9 -and -not $s.tiles[18].mortgaged) 'Principal plus 10 percent'
Reject {Invoke-GameAction $s $p @{type='sell';index=18}}
Setup;$p.money=10;$s.tiles[18].owner=$p.id;$s.tiles[5].owner=$p.id;Pay $s $p 80 $q
Assert ($s.debts.Count -eq 1 -and $p.money -eq 10 -and $q.money -eq 1500 -and -not $s.tiles[5].mortgaged) 'No auto sale or premature transfer'
Reject {Invoke-GameAction $s $p @{type='roll'}}
Invoke-GameAction $s $p @{type='mortgage';index=18};Assert ($p.money -eq 20 -and $q.money -eq 1580 -and -not $s.debts.Count -and -not $s.tiles[5].mortgaged) 'Chosen deed only'
Setup;$s.tiles[37].owner=$q.id;foreach($i in @(18,5,12)){$s.tiles[$i].owner=$p.id}
Invoke-GameAction $s $p @{type='offer';index=37;amount=200;offered=@(18,5,12)}
Invoke-GameAction $s $q @{type='acceptoffer'}
Assert ($s.tiles[37].owner -eq $p.id -and $s.tiles[18].owner -eq $q.id -and $s.tiles[5].owner -eq $q.id -and $s.tiles[12].owner -eq $q.id -and $p.money -eq 1300 -and $q.money -eq 1700) 'Cash plus three deeds'
Reject {Invoke-GameAction $s $p @{type='offer';index=18;amount=0;offered=@(37,37)}}
Reject {Invoke-GameAction $s $p @{type='offer';index=18;amount=0;offered=@(5)}}
Setup;$s.tiles[37].owner=$q.id;$s.tiles[18].owner=$p.id;Invoke-GameAction $s $p @{type='offer';index=37;amount=0;offered=@(18)}
$s.tiles[18].owner=$q.id;Reject {Invoke-GameAction $s $q @{type='acceptoffer'}};Assert ($s.tiles[37].owner -eq $q.id -and $p.money -eq 1500) 'Stale proposal atomic rejection'
Setup;$q.bot=$true;$q.money=0;$s.tiles[5].owner=$q.id;Pay $s $q 50 $p;Invoke-BotStep $s;Assert ($s.tiles[5].mortgaged -and -not $s.debts.Count) 'Robot handles own debt'
Setup;$p.money=0;$s.tiles[1].owner=$p.id;Send-ToJail $s $p
Invoke-GameAction $s $p @{type='payjail'};Assert ($s.debts.Count -eq 1 -and -not $s.rolled -and $p.pos -eq 10) 'Jail payment waits before rolling'
$s.tiles[5].owner=$p.id;Invoke-GameAction $s $p @{type='mortgage';index=5};Assert ($p.money -eq 50 -and -not $s.debts.Count -and -not $p.jail) 'Jail payment paid once after finance'
Setup;$p.money=0;$s.tiles[5].owner=$p.id;Pay $s $p 500 $q;Invoke-GameAction $s $p @{type='bankrupt'};Assert ($p.out -and $s.tiles[5].owner -eq $q.id -and $s.phase -eq 'finished') 'Explicit bankruptcy transfers estate'
Setup;$s.decks=New-CardDecks;$card=@($s.decks.chance | Where-Object {$_.effect -eq 'free'})[0];$p.jailCards=@(@{deck='chance';card=$card});Send-ToJail $s $p
function Get-Random {param($Minimum,$Maximum);return 2}
try{Invoke-GameAction $s $p @{type='roll'};Assert ($p.jailCards.Count -eq 1 -and -not $p.jail) 'Attempt double preserves held card'}finally{Remove-Item Function:\Get-Random}
Write-Output 'OK: classic rents, mortgages, redemption, manual debt selection, no land sale, package trades, stale/invalid offers, debt robot, optional jail card.'
