$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'engine.ps1')
function Assert($ok,$why){if(-not $ok){throw $why}}
function Setup {
 $script:rooms=@{};$a=Invoke-Api '/api/create' @{name='Test';mode='solo'} @{};$script:s=Get-Room $a.code;$s.phase='playing';$script:p=$s.players[0];$script:q=$s.players[1];$p.money=10000;$q.money=10000;$s.decks=New-CardDecks
}
function Put-First($deck,$effect,$value=$null){$c=@($s.decks[$deck] | Where-Object {$_.effect -eq $effect -and ($null -eq $value -or $_.value -eq $value)})[0];$s.decks[$deck]=@($c)+@($s.decks[$deck] | Where-Object {$_ -ne $c})}
Setup
Assert ((@($s.tiles | Where-Object {$_.kind -eq 'property'} | ForEach-Object {$_.price}) -join ',') -eq '60,60,100,100,120,140,140,160,180,180,200,220,220,240,260,260,280,300,300,320,350,400') 'Prices'
foreach($deck in @('chance','chest')){
 Assert ($s.decks[$deck].Count -eq 16) 'Deck count'
 $titles=@($s.decks[$deck] | ForEach-Object {$_.title})
 foreach($title in $titles){$p.pos=7;Draw-Card $s $p $deck;Assert (@($s.events | Where-Object {$_.type -eq 'card'})[-1].title -eq $title) 'Deck order changed'}
 Assert ($s.decks[$deck].Count -eq 15) 'Retained card must leave deck'
}
Setup;$p.pos=36;Put-First 'chance' 'back';Put-First 'chest' 'cash' 200;Draw-Card $s $p 'chance'
Assert ($p.pos -eq 33 -and $p.money -eq 10200) 'Back three must trigger chest'
Setup;$p.pos=36;$s.tiles[5].owner=$q.id;Put-First 'chance' 'station';Draw-Card $s $p 'chance'
Assert ($p.pos -eq 5 -and $p.money -eq 10150 -and $q.money -eq 10050) 'Station crossing GO and double rent'
Setup;$p.pos=7;$s.tiles[12].owner=$q.id;Put-First 'chance' 'utility';$turnDice=$s.dice -join ',';Draw-Card $s $p 'chance';$roll=@($s.events | Where-Object {$_.type -eq 'dice'})[-1].dice
Assert ($p.money -eq 10000-10*($roll[0]+$roll[1]) -and ($s.dice -join ',') -eq $turnDice) 'Utility special dice must preserve turn dice'
Setup;$s.tiles[1].owner=$p.id;$s.tiles[1].level=3;Put-First 'chest' 'repairs';Draw-Card $s $p 'chest';Assert ($p.money -eq 9880) 'Repairs'
Setup;Put-First 'chance' 'free';Draw-Card $s $p 'chance';Assert ($p.jailCards.Count -eq 1) 'Retained card';$p.jail=$true;Invoke-GameAction $s $p @{type='usejail'};Assert ($p.jailCards.Count -eq 0 -and $s.decks.chance.Count -eq 16 -and $s.log -match 'utilise sa carte') 'Card return on use'
Setup;Put-First 'chance' 'payall';Draw-Card $s $p 'chance';Assert ($p.money -eq 9950 -and $q.money -eq 10050) 'Pay opponents'
Put-First 'chest' 'collectall';Draw-Card $s $p 'chest';Assert ($p.money -eq 9960 -and $q.money -eq 10040) 'Collect from opponents'
$public=Invoke-Api '/api/state' @{} @{code=$s.code;token=$p.token};Assert (-not $public.ContainsKey('decks')) 'Deck order must stay private'
Write-Output 'OK: all 22 prices, 32 cards, deck order, retained cards, movement chains, special rents, repairs, player payments and private deck state.'
