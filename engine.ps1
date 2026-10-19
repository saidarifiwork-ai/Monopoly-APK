$script:rooms = @{}
function New-Tiles {
    $names=@('Départ','Chefchaouen','Caisse commune','Tétouan','Impôts','Gare de Fès','Oujda','Chance','Nador','Al Hoceïma','Prison','Meknès','Électricité','Fès','Ifrane','Gare de Marrakech','El Jadida','Caisse commune','Safi','Essaouira','Parc gratuit','Agadir','Chance','Marrakech','Ouarzazate','Gare de Tanger','Tanger','Kénitra','Compagnie des eaux','Larache','Allez en prison','Rabat','Salé','Caisse commune','Témara','Gare de Bouskoura','Chance','Casablanca','Taxe de luxe','Victoria')
    $groups=@(@(1,3),@(6,8,9),@(11,13,14),@(16,18,19),@(21,23,24),@(26,27,29),@(31,32,34),@(37,39))
    $prices=@(@(60,60),@(100,100,120),@(140,140,160),@(180,180,200),@(220,220,240),@(260,260,280),@(300,300,320),@(350,400))
    $palette=@('#905b42','#91cbdc','#d54b94','#ed9136','#d94343','#efd352','#29905b','#3164ab');$tiles=@()
    for($i=0;$i -lt 40;$i++){
        $t=@{name=$names[$i];kind='special';price=0;rent=0;build=0;level=0;owner='';group=-1;color='';symbol=''}
        for($g=0;$g -lt 8;$g++){if($groups[$g] -contains $i){$t.kind='property';$t.price=$prices[$g][[array]::IndexOf($groups[$g],$i)];$t.rent=8+5*$g;$t.build=50+50*[math]::Floor($g/2);$t.group=$g;$t.color=$palette[$g]}}
        if(@(5,15,25,35) -contains $i){$t.kind='station';$t.price=200;$t.rent=25}
        if(@(12,28) -contains $i){$t.kind='utility';$t.price=150;$t.rent=4}
        if(@(7,22,36) -contains $i){$t.kind='chance'};if(@(2,17,33) -contains $i){$t.kind='chest'}
        if(@(4,38) -contains $i){$t.kind='tax';$t.taxAmount=if($i -eq 4){200}else{100};$t.symbol='−'+$t.taxAmount};$tiles+=,$t
    };Set-ClassicRents $tiles;return ,$tiles
}
function Add-Event($s,$type,$details){
    if(-not $s.ContainsKey('eventSeq')){$s.eventSeq=0;$s.events=@()};$s.eventSeq++;$e=@{id=$s.eventSeq;type=$type}
    foreach($key in $details.Keys){$e[$key]=$details[$key]};$s.events=@($s.events)+@($e)
    if($s.events.Count -gt 160){$s.events=@($s.events | Select-Object -Last 160)}
}
function Add-Log($s,$message){$s.log=@($s.log)+@($message);if($s.log.Count -gt 60){$s.log=@($s.log | Select-Object -Last 60)}}
function Announce($s,$p,$message,$kind='notice'){Add-Log $s $message;Add-Event $s $kind @{playerId=$p.id;text=$message}}
function New-Player($name){
    if(-not $name -or -not $name.Trim() -or $name.Trim().Length -gt 20){throw 'Prénom requis (20 caractères maximum).'}
    return @{id=[guid]::NewGuid().ToString('N');token=[guid]::NewGuid().ToString('N');name=$name.Trim();money=1500;pos=0;jail=$false;jailTurns=0;jailDouble=$false;out=$false;doubles=0;bot=$false;jailCards=@()}
}
function Get-Room($code){if(-not $code -or -not $script:rooms.ContainsKey($code)){throw 'Salon introuvable'};return $script:rooms[$code]}
function Get-Player($s,$token){$p=@($s.players | Where-Object {$_.token -ceq $token});if($p.Count -ne 1){throw 'Session invalide.'};return $p[0]}
function Get-Rent($s,$t){
    if($t.mortgaged){return 0}
    if($t.kind -eq 'station'){$n=@($s.tiles | Where-Object {$_.kind -eq 'station' -and $_.owner -eq $t.owner}).Count;return [int](25*[math]::Pow(2,$n-1))}
    if($t.kind -eq 'utility'){$n=@($s.tiles | Where-Object {$_.kind -eq 'utility' -and $_.owner -eq $t.owner}).Count;$m=4;if($n -eq 2){$m=10};return ($s.dice[0]+$s.dice[1])*$m}
    if($t.level -gt 0){return $t.rents[$t.level]}
    if($t.owner -and @($s.tiles | Where-Object {$_.group -eq $t.group -and $_.owner -ne $t.owner}).Count -eq 0){return 2*$t.rent};return $t.rent
}
. (Join-Path $PSScriptRoot 'economy.ps1')
function Move-Player($s,$p,$steps){
    $from=$p.pos;$path=@();for($i=1;$i -le $steps;$i++){$path+=($from+$i)%$s.tiles.Count};$p.pos=($from+$steps)%$s.tiles.Count
    Add-Event $s 'move' @{playerId=$p.id;from=$from;to=$p.pos;path=$path;jump=$false}
    if($from+$steps -ge $s.tiles.Count){$p.money+=200;Announce $s $p ($p.name+' passe le départ : +200 DH.')}
}
function Jump-Player($s,$p,$destination){$from=$p.pos;$p.pos=$destination;Add-Event $s 'move' @{playerId=$p.id;from=$from;to=$destination;path=@($destination);jump=$true}}
function Send-ToJail($s,$p){Jump-Player $s $p 10;$p.jail=$true;$p.jailTurns=0;$p.jailDouble=$false;$p.doubles=0;Announce $s $p ($p.name+' va en prison.')}
. (Join-Path $PSScriptRoot 'cards.ps1')
function Next-Turn($s){
    if($s.phase -ne 'playing'){return}
    $order=if($s.turnOrder){@($s.turnOrder)}else{@(0..($s.players.Count-1))}
    $slot=[array]::IndexOf($order,$s.turn)
    do{$slot=($slot+1)%$order.Count;$s.turn=$order[$slot]}while($s.players[$s.turn].out)
    $s.rolled=$false;$s.botPhase='buy';$s.botNext=[DateTime]::UtcNow.AddMilliseconds(1800).Ticks
}
function Start-Opening($s){
    $s.phase='opening';$s.turn=0;$s.rolled=$false
    $s.openingGroups=@(@{ids=@($s.players.id)})
    $s.openingPending=@($s.players.id);$s.openingScores=@{};$s.openingHistory=@{};$s.openingRound=1
    $s.botNext=[DateTime]::UtcNow.AddSeconds(2).Ticks
    Add-Log $s 'Tirage de l''ordre : chacun lance deux dés. Le plus grand total commence.'
}
function Invoke-OpeningRoll($s,$p){
    if($s.phase -ne 'opening' -or $s.players[$s.turn].id -ne $p.id){throw 'Attendez votre tour pour le tirage.'}
    $a=Get-Random -Minimum 1 -Maximum 7;$b=Get-Random -Minimum 1 -Maximum 7;$total=$a+$b
    $s.dice=@($a,$b);$s.openingScores[$p.id]=$total
    $s.openingHistory[$p.id]=@(@($s.openingHistory[$p.id])+@($total) | Where-Object {$null -ne $_})
    Add-Event $s 'dice' @{playerId=$p.id;dice=@($a,$b);text=($p.name+' : tirage de l''ordre')}
    Add-Log $s ($p.name+' obtient '+$a+' + '+$b+' = '+$total+' pour l''ordre de jeu.')
    $s.openingPending=@($s.openingPending | Select-Object -Skip 1)
    if(-not $s.openingPending.Count){
        $groups=@()
        foreach($group in $s.openingGroups){
            if($group.ids.Count -eq 1){$groups+=,$group;continue}
            foreach($score in @($group.ids | ForEach-Object {$s.openingScores[$_]} | Sort-Object -Descending -Unique)){
                $groups+=,@{ids=@($group.ids | Where-Object {$s.openingScores[$_] -eq $score})}
            }
        }
        $s.openingGroups=$groups
        $s.openingPending=@($groups | Where-Object {$_.ids.Count -gt 1} | ForEach-Object {$_.ids})
        if(-not $s.openingPending.Count){
            $ids=@($groups | ForEach-Object {$_.ids})
            $s.turnOrder=@($ids | ForEach-Object {[array]::IndexOf(@($s.players.id),$_)})
            $s.turn=$s.turnOrder[0];$s.phase='playing';$s.rolled=$false;$s.botPhase='buy'
            $s.botNext=[DateTime]::UtcNow.AddSeconds(5).Ticks
            $names=@($ids | ForEach-Object {$id=$_;($s.players | Where-Object {$_.id -eq $id}).name})
            Announce $s $s.players[$s.turn] ('Ordre de jeu : '+($names -join ' > ')+'. La partie commence !')
            return
        }
        $s.openingRound++
        Announce $s $p 'Égalité : seuls les joueurs à départager relancent. Les autres places sont conservées.'
    }
    $s.turn=[array]::IndexOf(@($s.players.id),$s.openingPending[0])
    $s.botNext=[DateTime]::UtcNow.AddSeconds(3).Ticks
}
function Invoke-GameAction($s,$p,$data){
    if($data.type -in @('mortgage','unmortgage','bankrupt')){Invoke-FinanceAction $s $p $data;return}
    if($s.debts.Count -and $data.type -notin @('sellhouse','offer','acceptoffer','rejectoffer','counteroffer','canceloffer')){throw 'Reglez les dettes avant de continuer.'}
    if($data.type -in @('offer','acceptoffer','rejectoffer','counteroffer','canceloffer','sellhouse')){Invoke-TradeAction $s $p $data;return}
    if($data.type -eq 'addbot'){if($s.phase -ne 'lobby' -or $p.id -ne $s.host -or $s.players.Count -ge 6){throw 'Ajout du robot impossible.'};$bot=New-Player ('Robot '+(@($s.players | Where-Object {$_.bot}).Count+1));$bot.bot=$true;$s.players+=,$bot;Add-Log $s ($bot.name+' rejoint la table.');return}
    if($data.type -eq 'start'){if($p.id -ne $s.host -or $s.phase -ne 'lobby' -or $s.players.Count -lt 2){throw 'Il faut être l''hôte et avoir au moins 2 joueurs.'};Start-Opening $s;return}
    if($data.type -eq 'orderroll'){Invoke-OpeningRoll $s $p;return}
    if($s.phase -ne 'playing' -or $s.players[$s.turn].id -ne $p.id -or $p.out){throw 'Ce n''est pas votre tour.'}
    if($s.offer){throw 'Terminez ou annulez la negociation avant de continuer le tour.'}
    switch($data.type){
        {$_ -in 'roll','payjail','usejail'} {
            if($s.rolled){throw 'Vous avez déjà lancé les dés.'}
            if($data.type -eq 'usejail' -and -not $p.jailCards.Count){throw 'Aucune carte de sortie de prison.'}
            if($data.type -in @('payjail','usejail') -and -not $p.jail){throw 'Vous n''etes pas en prison.'}
            $s.rolled=$true;$s.botPhase='buy';$p.jailDouble=$false;$tryDouble=$false
            if($p.jail){
                if($data.type -eq 'usejail'){$held=$p.jailCards[0];$p.jailCards=@($p.jailCards | Select-Object -Skip 1);$s.decks[$held.deck]+=,$held.card;$p.jail=$false;Announce $s $p ($p.name+' utilise sa carte de sortie de prison.')}
                elseif($data.type -eq 'payjail' -or $p.jailTurns -ge 2){Pay $s $p 50 $null;$p.jail=$false;Announce $s $p ($p.name+' doit 50 DH pour sortir de prison.');if($s.debts.Count){$s.rolled=$false;$p.jailTurns=0;return}}
                else{$tryDouble=$true;$p.jailTurns++}
                if(-not $p.jail){$p.jailTurns=0}
            }
            $a=Get-Random -Minimum 1 -Maximum 7;$b=Get-Random -Minimum 1 -Maximum 7;$s.dice=@($a,$b)
            Add-Event $s 'dice' @{playerId=$p.id;dice=@($a,$b);text=($p.name+' lance les dés : '+$a+' + '+$b)};$s.botNext=[DateTime]::UtcNow.AddSeconds(6).Ticks
            if($tryDouble){
                if($a -ne $b){$p.doubles=0;Announce $s $p ($p.name+' reste en prison (tentative '+$p.jailTurns+'/2).');return}
                $p.jail=$false;$p.jailTurns=0;$p.jailDouble=$true;$p.doubles=0;$s.rolled=$false
                Announce $s $p ($p.name+' sort gratuitement avec un double. Relancez les des pour avancer.')
                return
            }
            if($a -eq $b -and -not $p.jailDouble){$p.doubles++}else{$p.doubles=0}
            if($p.doubles -ge 3){Announce $s $p 'Trois doubles de suite !';Send-ToJail $s $p;return}
            Move-Player $s $p ($a+$b);$t=$s.tiles[$p.pos];Add-Log $s ($p.name+' lance '+$a+' + '+$b+' et arrive à '+$t.name+'.')
            if($t.price -gt 0 -and $t.owner -and $t.owner -ne $p.id){$owner=@($s.players | Where-Object {$_.id -eq $t.owner})[0];$rent=Get-Rent $s $t;Pay $s $p $rent $owner;Announce $s $p ($p.name+' verse '+$rent+' DH de loyer à '+$owner.name+'.')}
            elseif($t.kind -eq 'tax'){Pay $s $p $t.taxAmount $null;Announce $s $p ($p.name+' paie '+$t.taxAmount+' DH de taxes.')}
            elseif($p.pos -eq 30){Send-ToJail $s $p}
            elseif($t.kind -in @('chance','chest')){Draw-Card $s $p $t.kind}
            if($p.out){Next-Turn $s}
        }
        'buy' {if(-not $s.rolled){throw 'Lancez les dés avant d''acheter.'};$t=$s.tiles[$p.pos];if($t.price -le 0 -or $t.owner -or $p.money -lt $t.price){throw 'Achat impossible.'};$p.money-=$t.price;$t.owner=$p.id;Announce $s $p ($p.name+' achète '+$t.name+' pour '+$t.price+' DH.') 'purchase'}
        'end' {if(-not $s.rolled){throw 'Lancez les dés avant de terminer.'};if($s.dice[0] -eq $s.dice[1] -and -not $p.jail -and -not $p.jailDouble){$s.rolled=$false;$s.botNext=[DateTime]::UtcNow.AddSeconds(2).Ticks;Announce $s $p ($p.name+' a fait un double et rejoue.')}else{$p.doubles=0;Next-Turn $s}}
        'build' {
            if($null -eq $data.index -or $data.index -notmatch '^\d+$' -or [int]$data.index -ge $s.tiles.Count){throw 'Case invalide.'};$t=$s.tiles[[int]$data.index];if($t.owner -ne $p.id){throw 'Cette propriété ne vous appartient pas.'}
            
            if($t.kind -ne 'property' -or $t.level -ge 5 -or $p.money -lt $t.build){throw 'Construction impossible.'};$group=@($s.tiles | Where-Object {$_.group -eq $t.group});if(@($group | Where-Object {$_.owner -ne $p.id -or $_.mortgaged -or $_.level -lt $t.level}).Count){throw 'Possédez tout le groupe et construisez de façon équilibrée.'};$p.money-=$t.build;$t.level++;Announce $s $p ($p.name+' construit à '+$t.name+' (niveau '+$t.level+').') 'build'
        }
        default {throw 'Action inconnue.'}
    }
}
function Invoke-BotStep($s){
    if($s.phase -eq 'opening'){
        $p=$s.players[$s.turn]
        if($p.bot -and [DateTime]::UtcNow.Ticks -ge $s.botNext){Invoke-OpeningRoll $s $p}
        return
    }
    if($s.debts.Count -and -not $s.offer){Invoke-DebtBot $s;return}
    if($s.phase -eq 'playing' -and $s.offer){
        $o=$s.offer;$bot=@($s.players | Where-Object {$_.id -eq $o.respondent -and $_.bot})
        if($bot.Count){
            $t=$s.tiles[$o.index];$group=@($s.tiles | Where-Object {$_.group -eq $t.group -and $_.owner -eq $bot[0].id});$factor=1.4
            if($t.kind -eq 'property' -and $group.Count -gt 1){$factor=2.5}
            $target=[int][math]::Ceiling($t.price*$factor)
            $extras=0;foreach($i in $o.offered){$extras+=$s.tiles[$i].price}
            if($o.amount+$extras -ge $target){Invoke-TradeAction $s $bot[0] @{type='acceptoffer'}}
            elseif($o.amount+$extras -lt $t.price*.5){Invoke-TradeAction $s $bot[0] @{type='rejectoffer'}}
            else{Invoke-TradeAction $s $bot[0] @{type='counteroffer';amount=([math]::Max(0,$target-$extras))}}
        }
        return
    }
    if($s.phase -ne 'playing'){return};$p=$s.players[$s.turn];if(-not $p.bot){return}
    if($s.botNext -and [DateTime]::UtcNow.Ticks -lt $s.botNext){return};$s.botNext=[DateTime]::UtcNow.AddMilliseconds(1800).Ticks
    if(-not $s.rolled){$type='roll';if($p.jail -and $p.jailCards.Count){$type='usejail'};Invoke-GameAction $s $p @{type=$type};return}
    if($s.botPhase -eq 'buy'){$s.botPhase='build';$t=$s.tiles[$p.pos];if($t.price -gt 0 -and -not $t.owner -and $p.money -ge $t.price+150){Invoke-GameAction $s $p @{type='buy'};return}}
    if($s.botPhase -eq 'build'){
        $s.botPhase='end'
        for($i=0;$i -lt $s.tiles.Count;$i++){
            $t=$s.tiles[$i];if($t.kind -ne 'property' -or $t.owner -ne $p.id -or $t.level -ge 5 -or $p.money -lt $t.build+300){continue}
            $group=@($s.tiles | Where-Object {$_.group -eq $t.group})
            if(@($group | Where-Object {$_.owner -ne $p.id -or $_.mortgaged -or $_.level -lt $t.level}).Count -eq 0){Invoke-GameAction $s $p @{type='build';index=$i};return}
        }
    };Invoke-GameAction $s $p @{type='end'}
}
function Assert-Tradable($s,$t){
    if($t.price -le 0 -or -not $t.owner){throw 'Propriete indisponible.'}
    if($t.kind -eq 'property' -and @($s.tiles | Where-Object {$_.group -eq $t.group -and $_.level -gt 0}).Count){throw 'Revendez toutes les maisons du groupe de couleur avant la vente.'}
}
function Invoke-TradeAction($s,$p,$data){
    if($s.phase -ne 'playing' -or $p.out){throw 'Negociation impossible.'}
    if($data.type -eq 'sellhouse'){
        if($null -eq $data.index -or $data.index -notmatch '^\d+$' -or [int]$data.index -ge $s.tiles.Count){throw 'Case invalide.'}
        $t=$s.tiles[[int]$data.index]
        if($t.owner -ne $p.id -or $t.level -lt 1){throw 'Aucune maison a vendre.'}
        if(@($s.tiles | Where-Object {$_.group -eq $t.group -and $_.level -gt $t.level}).Count){throw 'Revendez les maisons de facon equilibree : commencez par les terrains les plus construits.'}
        $t.level--;$p.money+=[int][math]::Floor($t.build/2);Announce $s $p ($p.name+' revend une maison de '+$t.name+'.');Settle-Debts $s;return
    }
    if($data.type -eq 'offer'){
        if($s.offer){throw 'Terminez la negociation en cours.'}
        if($null -eq $data.index -or $data.index -notmatch '^\d+$' -or [int]$data.index -ge $s.tiles.Count){throw 'Case invalide.'}
        $t=$s.tiles[[int]$data.index];Assert-Tradable $s $t
        if($t.owner -eq $p.id){throw 'Cette propriete vous appartient deja.'}
        if($t.mortgaged){throw 'Levez l''hypotheque avant cet echange.'}
        if($data.amount -notmatch '^\d{1,7}$' -or [int]$data.amount -gt $p.money){throw 'Montant invalide ou argent insuffisant.'}
        $offered=@();if($null -ne $data.offered){$offered=@($data.offered)};Validate-OfferedTiles $s $p.id $offered
        $s.offer=@{index=[int]$data.index;buyer=$p.id;seller=$t.owner;respondent=$t.owner;amount=[int]$data.amount;offered=$offered}
        Add-Log $s ($p.name+' propose '+$data.amount+' DH pour '+$t.name+'.');return
    }
    $o=$s.offer;if(-not $o){throw 'Cette offre est terminee.'}
    if($p.id -notin @($o.buyer,$o.seller)){throw 'Cette offre ne vous concerne pas.'}
    if($data.type -eq 'canceloffer'){$s.offer=$null;Add-Log $s ($p.name+' annule la negociation.');return}
    if($p.id -ne $o.respondent){throw 'Attendez la reponse de votre partenaire.'}
    if($data.type -eq 'rejectoffer'){$s.offer=$null;Add-Log $s ($p.name+' refuse l''offre.');return}
    $buyer=@($s.players | Where-Object {$_.id -eq $o.buyer})[0];$seller=@($s.players | Where-Object {$_.id -eq $o.seller})[0];$t=$s.tiles[$o.index]
    if($buyer.out -or $seller.out -or $t.owner -ne $seller.id -or $t.mortgaged){$s.offer=$null;throw 'La propriete a change de proprietaire.'};Assert-Tradable $s $t
    Validate-OfferedTiles $s $buyer.id $o.offered
    if($data.type -eq 'counteroffer'){
        if($data.amount -notmatch '^\d{1,7}$'){throw 'Montant invalide.'}
        if($null -ne $data.offered){Validate-OfferedTiles $s $buyer.id $data.offered;$o.offered=@($data.offered)}
        $o.amount=[int]$data.amount;$o.respondent=if($p.id -eq $o.buyer){$o.seller}else{$o.buyer};Add-Log $s ($p.name+' propose maintenant '+$o.amount+' DH.');return
    }
    if($buyer.money -lt $o.amount){throw 'L''acheteur n''a plus assez d''argent. Refusez ou negociez un autre montant.'}
    $buyer.money-=$o.amount;$seller.money+=$o.amount;$t.owner=$buyer.id;foreach($i in $o.offered){$s.tiles[[int]$i].owner=$seller.id};$s.offer=$null;Settle-Debts $s
    Announce $s $buyer ($buyer.name+' achete '+$t.name+' a '+$seller.name+' pour '+$o.amount+' DH.') 'purchase'
}
function Invoke-Api($path,$data,$query){
    switch($path){
        '/api/health' {return @{app='quartiers';version=10}}
        '/api/create' {
            if($script:rooms.Count -ge 50){throw 'Limite de salons atteinte : redémarrez le serveur.'};$p=New-Player $data.name
            do{$code=-join (1..6 | ForEach-Object {'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[(Get-Random -Maximum 31)]})}while($script:rooms.ContainsKey($code))
            $s=@{code=$code;host=$p.id;players=@($p);tiles=New-Tiles;turn=0;phase='lobby';rolled=$false;dice=@(5,3);log=@($p.name+' ouvre la table.');events=@();eventSeq=0;botPhase='buy';botNext=0};$script:rooms[$code]=$s
            if($data.mode -eq 'solo'){Invoke-GameAction $s $p @{type='addbot'};Invoke-GameAction $s $p @{type='start'}};return @{code=$code;token=$p.token}
        }
        '/api/join' {$s=Get-Room $data.code;if($s.phase -ne 'lobby' -or $s.players.Count -ge 6){throw 'Partie commencée ou salon complet.'};$p=New-Player $data.name;$s.players+=,$p;Add-Log $s ($p.name+' rejoint la table.');return @{code=$s.code;token=$p.token}}
        '/api/state' {$s=Get-Room $query.code;$p=Get-Player $s $query.token;Invoke-BotStep $s;$public=@{};foreach($k in $s.Keys){if($k -notin @('botNext','botPhase','decks')){$public[$k]=$s[$k]}};$public.players=@($s.players | ForEach-Object {$copy=@{};foreach($k in $_.Keys){if($k -ne 'token'){$copy[$k]=$_[$k]}};$copy});$public.me=$p.id;return $public}
        '/api/action' {$s=Get-Room $data.code;$p=Get-Player $s $data.token;Invoke-GameAction $s $p $data;return @{ok=$true}}
        default {throw 'Route inconnue.'}
    }
}
