param([switch]$NoBrowser)
$ErrorActionPreference='Stop'
$url='http://127.0.0.1:8787'
try {
    $health=$null
    try {$health=Invoke-RestMethod "$url/api/health" -TimeoutSec 2} catch {}
    if($health.app -eq 'quartiers' -and $health.version -ne 10){throw 'Une ancienne version tourne encore. Executez Arreter.cmd puis Lancer.cmd.'}
    if($health.app -ne 'quartiers') {
        $serverPath=Join-Path $PSScriptRoot 'serve.ps1'
        $process=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$serverPath+'"')) -WindowStyle Hidden -WorkingDirectory $PSScriptRoot -RedirectStandardOutput (Join-Path $PSScriptRoot 'server.log') -RedirectStandardError (Join-Path $PSScriptRoot 'server-error.log') -PassThru
        Set-Content -LiteralPath (Join-Path $PSScriptRoot 'server.pid') -Value $process.Id
        for($i=0;$i -lt 30;$i++) {
            Start-Sleep -Milliseconds 300
            try {$health=Invoke-RestMethod "$url/api/health" -TimeoutSec 1} catch {}
            if($health.app -eq 'quartiers'){break}
            if($process.HasExited){throw 'Le serveur ne demarre pas. Consultez server-error.log dans ce dossier.'}
        }
        if($health.app -ne 'quartiers'){throw 'Le serveur ne repond pas. Consultez server-error.log.'}
    }
    Write-Output "Jeu pret : $url — le serveur reste actif en arriere-plan."
    if(-not $NoBrowser){Start-Process $url}
} catch {Write-Host $_.Exception.Message -ForegroundColor Red;exit 1}
