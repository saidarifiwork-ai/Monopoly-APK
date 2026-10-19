$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'engine.ps1')
function Assert($ok,$why){if(-not $ok){throw $why}}
$a=Invoke-Api '/api/create' @{name='Test';mode='solo'} @{};$s=Get-Room $a.code;$s.phase='playing';$p=$s.players[0]
Assert ($s.tiles[5].name -eq 'Gare de Fès' -and $s.tiles[15].name -eq 'Gare de Marrakech' -and $s.tiles[35].name -eq 'Gare de Bouskoura' -and $s.tiles[39].name -eq 'Victoria') 'Names'
function Get-Random {param($Minimum,$Maximum);$v=$script:rolls[0];$script:rolls=@($script:rolls | Select-Object -Skip 1);return $v}
try{
 Send-ToJail $s $p
 for($turn=1;$turn -le 2;$turn++){$s.turn=0;$s.rolled=$false;$script:rolls=@(1,2);Invoke-GameAction $s $p @{type='roll'};Assert ($p.jail -and $p.pos -eq 10 -and $p.money -eq 1500 -and $p.jailTurns -eq $turn) 'Failed attempt';Invoke-GameAction $s $p @{type='end'}}
 $s.turn=0;$s.rolled=$false;$script:rolls=@(1,2);Invoke-GameAction $s $p @{type='roll'};Assert (-not $p.jail -and $p.pos -eq 13 -and $p.money -eq 1450) 'Mandatory third turn payment'
 Send-ToJail $s $p;$s.rolled=$false;$script:rolls=@(3,3);$before=$s.eventSeq;Invoke-GameAction $s $p @{type='roll'};Assert (-not $p.jail -and $p.pos -eq 10 -and $p.money -eq 1450 -and -not $s.rolled) 'Double releases without moving'
 Assert (@($s.events | Where-Object {$_.id -gt $before -and $_.type -eq 'move'}).Count -eq 0) 'No movement on release'
 $script:rolls=@(1,2);Invoke-GameAction $s $p @{type='roll'};Assert ($p.pos -eq 13 -and $p.money -eq 1450 -and $s.rolled) 'Separate movement roll without payment'
 Invoke-GameAction $s $p @{type='end'};Assert ($s.turn -eq 1) 'End after movement'
 $s.turn=0;Send-ToJail $s $p;$s.rolled=$false;$script:rolls=@(1,2);Invoke-GameAction $s $p @{type='payjail'};Assert (-not $p.jail -and $p.money -eq 1400 -and $p.pos -eq 13) 'Voluntary payment'
}finally{Remove-Item Function:\Get-Random}
Write-Output 'OK: renamed squares, two free attempts, forced T3 payment, double release then separate movement roll, voluntary payment.'
