param([int]$Port=8787,[string]$BindAddress='0.0.0.0')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'engine.ps1')
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($BindAddress),$Port)
$listener.Start()
Write-Output "QUARTIERS : http://localhost:$Port — Ctrl+C pour arrêter."
Write-Output 'Amis : utilisez l''adresse IPv4 de ce PC à la place de localhost. Les salons restent en mémoire jusqu''à l''arrêt du serveur.'
try{while($true){
    $client=$listener.AcceptTcpClient()
    try{
        $client.ReceiveTimeout=5000;$client.SendTimeout=5000;$stream=$client.GetStream()
        $head=[Collections.Generic.List[byte]]::new();$tail=''
        while($head.Count -lt 16384){$byte=$stream.ReadByte();if($byte -lt 0){throw 'Connexion interrompue.'};$head.Add([byte]$byte);$tail=($tail+[char]$byte);if($tail.Length -gt 4){$tail=$tail.Substring($tail.Length-4)};if($tail -eq "`r`n`r`n"){break}}
        $lines=[Text.Encoding]::ASCII.GetString($head.ToArray()).Split(@("`r`n"),[StringSplitOptions]::None);$request=$lines[0].Split(' ');$method=$request[0];$uri=[Uri]('http://localhost'+$request[1]);$path=$uri.AbsolutePath;$length=0
        foreach($line in $lines){if($line -match '^Content-Length:\s*(\d+)'){$length=[int]$Matches[1]}}
        if($length -gt 16384){throw 'Requête trop grande.'};$raw=[byte[]]::new($length);$read=0;while($read -lt $length){$n=$stream.Read($raw,$read,$length-$read);if($n -le 0){throw 'Requête incomplète.'};$read+=$n}
        $status='200 OK';$type='application/json; charset=utf-8';$query=@{};foreach($pair in $uri.Query.TrimStart('?').Split('&')){$kv=$pair.Split('=',2);if($kv.Length -eq 2){$query[$kv[0]]=[Uri]::UnescapeDataString($kv[1])}}
        if($path.StartsWith('/api/')){
            try{if(($path -in @('/api/state','/api/health') -and $method -ne 'GET') -or ($path -notin @('/api/state','/api/health') -and $method -ne 'POST')){throw 'Méthode invalide.'}
                # Les navigateurs externes ne peuvent pas envoyer de commandes au serveur local.
                $origin=@($lines | Where-Object {$_ -match '^Origin:'});$hostLine=@($lines | Where-Object {$_ -match '^Host:'})
                if($origin.Count -and $hostLine.Count){$originHost=([Uri]($origin[0].Substring(7).Trim())).Authority;if($originHost -ne $hostLine[0].Substring(5).Trim()){throw 'Origine refusée.'}}
                $data=@{};if($length){$data=[Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json};$result=Invoke-Api $path $data $query;$body=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $result -Depth 20 -Compress))
            }catch{$status='400 Bad Request';$body=[Text.Encoding]::UTF8.GetBytes((@{error=$_.Exception.Message}|ConvertTo-Json -Compress))}
        }else{
            $files=@{'/'='index.html';'/index.html'='index.html';'/app.js'='app.js';'/art.js'='art.js';'/style.css'='style.css'}
            if($method -ne 'GET' -or -not $files.ContainsKey($path)){$status='404 Not Found';$body=[Text.Encoding]::UTF8.GetBytes('Not found')}
            else{$file=$files[$path];$type=@{'.html'='text/html';'.js'='application/javascript';'.css'='text/css'}[[IO.Path]::GetExtension($file)]+'; charset=utf-8';$body=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $file))}
        }
        $header=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $status`r`nContent-Type: $type`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nConnection: close`r`n`r`n");$stream.Write($header,0,$header.Length);$stream.Write($body,0,$body.Length)
    }catch{Write-Warning $_.Exception.Message}finally{$client.Close()}
}}finally{$listener.Stop()}
