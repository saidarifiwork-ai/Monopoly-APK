# Classic rents, indexed by board position: bare land, 1-4 houses, hotel.
function Set-ClassicRents($tiles){
 $r=@{
  1=@(2,10,30,90,160,250);3=@(4,20,60,180,320,450)
  6=@(6,30,90,270,400,550);8=@(6,30,90,270,400,550);9=@(8,40,100,300,450,600)
  11=@(10,50,150,450,625,750);13=@(10,50,150,450,625,750);14=@(12,60,180,500,700,900)
  16=@(14,70,200,550,750,950);18=@(14,70,200,550,750,950);19=@(16,80,220,600,800,1000)
  21=@(18,90,250,700,875,1050);23=@(18,90,250,700,875,1050);24=@(20,100,300,750,925,1100)
  26=@(22,110,330,800,975,1150);27=@(22,110,330,800,975,1150);29=@(24,120,360,850,1025,1200)
  31=@(26,130,390,900,1100,1275);32=@(26,130,390,900,1100,1275);34=@(28,150,450,1000,1200,1400)
  37=@(35,175,500,1100,1300,1500);39=@(50,200,600,1400,1700,2000)
 }
 foreach($i in $r.Keys){$tiles[$i].rents=$r[$i];$tiles[$i].rent=$r[$i][0]}
 foreach($t in $tiles){$t.mortgaged=$false}
}
# No automatic liquidation: outstanding payments pause play until settled.
function Pay($s,$p,$amount,$receiver){
 if($amount -le 0){return}
 if(-not $s.ContainsKey('debts')){$s.debts=@()}
 $receiverId='';if($receiver){$receiverId=$receiver.id}
 $s.debts+=,@{player=$p.id;receiver=$receiverId;amount=[int]$amount}
 Settle-Debts $s
}
function Settle-Debts($s){
 while($s.debts.Count){
  $d=$s.debts[0];$payer=@($s.players | Where-Object {$_.id -eq $d.player})[0]
  if($payer.money -lt $d.amount){return}
  $payer.money-=$d.amount
  if($d.receiver){$creditor=@($s.players | Where-Object {$_.id -eq $d.receiver})[0];$creditor.money+=$d.amount}
  $s.debts=@($s.debts | Select-Object -Skip 1)
 }
}
function Invoke-FinanceAction($s,$p,$data){
 if($s.phase -ne 'playing' -or $p.out -or $s.offer){throw 'Gestion indisponible.'}
 if($data.type -eq 'bankrupt'){
  $d=@($s.debts | Where-Object {$_.player -eq $p.id})[0];if(-not $d){throw 'Aucune dette.'}
  $creditor=$null;if($d.receiver){$creditor=@($s.players | Where-Object {$_.id -eq $d.receiver})[0]}
  foreach($t in $s.tiles){if($t.owner -eq $p.id){$p.money+=[int]($t.level*$t.build/2);$t.level=0;if($creditor){$t.owner=$creditor.id}else{$t.owner='';$t.mortgaged=$false}}}
  if($creditor){$creditor.money+=$p.money};$p.money=0;$p.out=$true
  foreach($held in $p.jailCards){$s.decks[$held.deck]+=,$held.card};$p.jailCards=@()
  $s.debts=@($s.debts | Where-Object {$_.player -ne $p.id})
  foreach($claim in $s.debts){if($claim.receiver -eq $p.id){$claim.receiver=if($creditor){$creditor.id}else{''}}}
  Announce $s $p ($p.name+' declare faillite.')
  $alive=@($s.players | Where-Object {-not $_.out});if($alive.Count -eq 1){$s.phase='finished';$s.turn=[array]::IndexOf($s.players,$alive[0]);$s.debts=@();Announce $s $alive[0] ($alive[0].name+' gagne !') 'win'}elseif($s.players[$s.turn].out){Next-Turn $s}
  Settle-Debts $s;return
 }
 if($null -eq $data.index -or $data.index -notmatch '^\d+$' -or [int]$data.index -ge $s.tiles.Count){throw 'Case invalide.'}
 $t=$s.tiles[[int]$data.index];if($t.owner -ne $p.id -or $t.price -le 0){throw 'Ce bien ne vous appartient pas.'}
 $value=[int]($t.price/2)
 if($data.type -eq 'mortgage'){
  if($t.mortgaged){throw 'Bien deja hypotheque.'};Assert-Tradable $s $t
  $t.mortgaged=$true;$p.money+=$value;Announce $s $p ($p.name+' hypotheque '+$t.name+' : +'+$value+' DH.')
 }else{
  if($s.debts.Count){throw 'Reglez les dettes avant de lever une hypotheque.'}
  $cost=($value+[int][math]::Ceiling($value/10));if(-not $t.mortgaged -or $p.money -lt $cost){throw 'Remboursement impossible.'}
  $p.money-=$cost;$t.mortgaged=$false;Announce $s $p ($p.name+' leve l''hypotheque de '+$t.name+' : '+$cost+' DH.')
 }
 Settle-Debts $s
}
function Validate-OfferedTiles($s,$buyer,$indices){
 $seen=@{}
 foreach($i in @($indices)){
  if($null -eq $i -or $i -notmatch '^\d+$' -or [int]$i -ge $s.tiles.Count -or $seen.ContainsKey([int]$i)){throw 'Liste de proprietes invalide.'}
  $seen[[int]$i]=$true;$t=$s.tiles[[int]$i]
  if($t.owner -ne $buyer -or $t.mortgaged){throw 'Offrez uniquement vos biens non hypotheques.'};Assert-Tradable $s $t
 }
}
function Invoke-DebtBot($s){
 if(-not $s.debts.Count){return};$d=$s.debts[0];$p=@($s.players | Where-Object {$_.id -eq $d.player})[0];if(-not $p.bot){return}
 for($i=0;$i -lt $s.tiles.Count;$i++){$t=$s.tiles[$i];if($t.owner -eq $p.id -and $t.level -gt 0){$higher=@($s.tiles | Where-Object {$_.group -eq $t.group -and $_.level -gt $t.level});if(-not $higher.Count){Invoke-TradeAction $s $p @{type='sellhouse';index=$i};return}}}
 for($i=0;$i -lt $s.tiles.Count;$i++){$t=$s.tiles[$i];if($t.owner -eq $p.id -and -not $t.mortgaged){Invoke-FinanceAction $s $p @{type='mortgage';index=$i};return}}
 Invoke-FinanceAction $s $p @{type='bankrupt'}
}
