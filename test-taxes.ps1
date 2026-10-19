$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'engine.ps1')
$a=Invoke-Api '/api/create' @{name='Tax test';mode='solo'} @{};$s=Get-Room $a.code;$s.phase='playing';$p=$s.players[0]
function Get-Random {param($Minimum,$Maximum);return 2}
try {
Invoke-GameAction $s $p @{type='roll'}
if($p.pos -ne 4 -or $p.money -ne 1300 -or $s.tiles[4].taxAmount -ne 200){throw 'Income tax roll failed'}
$p.pos=4;Resolve-Landing $s $p;if($p.money -ne 1100){throw 'Income tax card landing failed'}
$p.pos=38;Resolve-Landing $s $p;if($p.money -ne 1000 -or $s.tiles[38].taxAmount -ne 100){throw 'Luxury tax changed'}
}finally{Remove-Item Function:\Get-Random}
'OK: Impots 200 via dice and card landing, luxury tax 100.'