$pidPath=Join-Path $PSScriptRoot 'server.pid'
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $pidPath){
    $serverPid=[int](Get-Content -LiteralPath $pidPath)
    $process=Get-CimInstance Win32_Process -Filter "ProcessId = $serverPid"
    $expected=Join-Path $PSScriptRoot 'serve.ps1'
    if($process){if($process.Name -ne 'powershell.exe' -or -not $process.CommandLine.Contains($expected)){throw 'Le PID ne correspond pas au serveur de ce jeu.'};$result=Invoke-CimMethod -InputObject $process -MethodName Terminate;if($result.ReturnValue -ne 0){throw 'Windows refuse l''arrêt du serveur.'}}
    Remove-Item -LiteralPath $pidPath
}
Write-Output 'Serveur arrete. Les parties en memoire sont effacees.'
