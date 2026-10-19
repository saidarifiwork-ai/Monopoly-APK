param([string]$Url='http://127.0.0.1:8787',[switch]$KeepBrowser)
$ErrorActionPreference='Stop'
$browserPath='C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe'
$profile=Join-Path $PSScriptRoot '.browser-check'
$browser=Start-Process -FilePath $browserPath -ArgumentList @('--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-background-networking','--remote-debugging-port=9237',('--user-data-dir="'+$profile+'"'),'about:blank') -WindowStyle Hidden -PassThru
$socket=[Net.WebSockets.ClientWebSocket]::new();$script:messageId=0;$script:browserErrors=@()
function CDP($method,$parameters=@{}) {
    $script:messageId++;$id=$script:messageId
    $json=@{id=$id;method=$method;params=$parameters}|ConvertTo-Json -Depth 40 -Compress
    $bytes=[Text.Encoding]::UTF8.GetBytes($json)
    $socket.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    while($true){
        $buffer=[byte[]]::new(65536);$memory=[IO.MemoryStream]::new();$cancel=[Threading.CancellationTokenSource]::new(60000)
        do{$result=$socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),$cancel.Token).GetAwaiter().GetResult();$memory.Write($buffer,0,$result.Count)}while(-not $result.EndOfMessage)
        $response=[Text.Encoding]::UTF8.GetString($memory.ToArray())|ConvertFrom-Json;$memory.Dispose();$cancel.Dispose()
        if($response.method -eq 'Runtime.exceptionThrown'){$script:browserErrors+=,$response.params.exceptionDetails}
        if($response.id -eq $id){if($response.error){throw ($response.error|ConvertTo-Json -Compress)};return $response.result}
    }
}
function JS($expression){$r=CDP 'Runtime.evaluate' @{expression=$expression;awaitPromise=$true;returnByValue=$true};if($r.exceptionDetails){throw ($r.exceptionDetails|ConvertTo-Json -Depth 10 -Compress)};return $r.result.value}
function Screenshot($name){$r=CDP 'Page.captureScreenshot' @{format='png';captureBeyondViewport=$false};[IO.File]::WriteAllBytes((Join-Path $PSScriptRoot $name),[Convert]::FromBase64String($r.data))}
try {
    $tabs=$null;for($i=0;$i -lt 40;$i++){try{$tabs=Invoke-RestMethod 'http://127.0.0.1:9237/json/list' -TimeoutSec 1}catch{};if($tabs){break};Start-Sleep -Milliseconds 250}
    if(-not $tabs){throw 'Navigateur de test indisponible.'}
    $socket.ConnectAsync([Uri]$tabs[0].webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    $null=CDP 'Runtime.enable';$null=CDP 'Page.enable'
    $null=CDP 'Emulation.setDeviceMetricsOverride' @{width=1440;height=1120;deviceScaleFactor=1;mobile=$false}
    $null=CDP 'Page.navigate' @{url=$Url};Start-Sleep -Seconds 2
    $health=Invoke-RestMethod "$Url/api/health";if($health.version -ne 10){throw 'Le serveur doit etre en version 10.'}
    $welcome=JS '({image:document.querySelector(".welcome-backdrop").complete&&document.querySelector(".welcome-backdrop").naturalWidth>0,left:document.querySelector("#entry").getBoundingClientRect().left,right:document.querySelector("#entry").getBoundingClientRect().right,width:innerWidth})'
    if(-not $welcome.image -or $welcome.right -gt $welcome.width/2){throw 'Welcome image or left form failed'}
    Screenshot 'preview-welcome.png'
    $multiOpening=JS '(async()=>{const created=await api("/api/create",{name:"Host test"});for(const name of ["Ami A","Ami B","Ami C"])await api("/api/join",{name,code:created.code});await api("/api/action",{...created,type:"start"});resetView();session=created;await poll(true);const button=document.querySelector("#actions [data-action=orderroll]");if(!button||button.disabled||state.players.length!==4)throw Error("Four-player opening button missing");await action("orderroll");const result={players:state.players.length,button:true,next:state.turn,stationary:state.players.every(p=>p.pos===0)};session=null;resetView();return result})()'
    if($multiOpening.next -ne 1 -or -not $multiOpening.stationary){throw 'Four-player opening failed'}
    Write-Output ('MULTIPLAYER OPENING: '+($multiOpening|ConvertTo-Json -Compress))
    $null=JS "document.querySelector('#name').value='Said'; document.querySelector('#solo').click();"
    $ready=JS "new Promise((resolve,reject)=>{let tries=0;const t=setInterval(()=>{if(document.querySelectorAll('.tile').length===40){clearInterval(t);resolve(true)}else if(++tries>50){clearInterval(t);reject(Error('Solo failed'))}},100)})"
    $null=CDP 'Page.bringToFront'
    $audioUnlock=CDP 'Runtime.evaluate' @{expression='gameSound.unlock()';awaitPromise=$true;userGesture=$true;returnByValue=$true}
    $audio=JS '(async()=>{const a=gameSound.ctx.createAnalyser();gameSound.master.disconnect();gameSound.master.connect(a);a.connect(gameSound.ctx.destination);gameSound.muted=false;gameSound.volume=.35;updateAudioControls();gameSound.play("money");await new Promise(r=>setTimeout(r,150));const samples=new Float32Array(a.fftSize);a.getFloatTimeDomainData(samples);const liveContext=gameSound.ctx,liveMaster=gameSound.master;const offline=new OfflineAudioContext(1,22050,44100);gameSound.ctx=offline;gameSound.master=offline.createGain();gameSound.master.connect(offline.destination);gameSound.tone(523,0,.2);const rendered=await offline.startRendering();let peak=0;for(const sample of rendered.getChannelData(0))peak=Math.max(peak,Math.abs(sample));gameSound.ctx=liveContext;gameSound.master=liveMaster;await document.querySelector("#sound-toggle").onclick();await new Promise(r=>setTimeout(r,60));const silent=gameSound.master.gain.value===0;const v=document.querySelector("#sound-volume");v.value="50";v.dispatchEvent(new Event("input"));const saved=JSON.parse(localStorage.getItem("quartiers-audio"));gameSound.muted=false;gameSound.volume=.35;updateAudioControls();gameSound.master.disconnect(a);a.disconnect();gameSound.master.connect(gameSound.ctx.destination);return {hidden:document.hidden,running:gameSound.ctx.state,peak,silent,saved:saved.muted&&saved.volume===.5}})()'
    if($audio.running -ne 'running' -or $audio.peak -le 0 -or -not $audio.silent -or -not $audio.saved){throw ('Audio verification failed: '+($audio|ConvertTo-Json -Compress))}
    Write-Output ('AUDIO: '+($audio|ConvertTo-Json -Compress))
    Screenshot 'preview-opening.png'
    $opening=JS '(async()=>{const pause=ms=>new Promise(r=>setTimeout(r,ms));let rolls=0;for(let i=0;i<400;i++){if(!busy&&!animating){if(state.phase==="playing")return {order:state.turnOrder,rank:document.querySelector(".turn-rank")?.textContent,rolls,positions:state.players.map(p=>p.pos)};if(state.phase==="opening"&&state.players[state.turn].id===state.me){document.body.dispatchEvent(new KeyboardEvent("keydown",{code:"Space",bubbles:true,cancelable:true}));rolls++}}await pause(100)}throw Error("Opening did not finish")})()'
    if($opening.order.Count -ne 2 -or -not $opening.rank -or $opening.rolls -lt 1 -or @($opening.positions | Where-Object {$_ -ne 0}).Count){throw 'Opening or stationary pawns failed'}
    Write-Output ('OPENING: '+($opening|ConvertTo-Json -Compress))
    Screenshot 'preview-board.png'
    $bounds=JS '({bottom:document.querySelector("#board").getBoundingClientRect().bottom,height:innerHeight})'
    if($bounds.bottom -gt $bounds.height){throw 'Le bas du plateau sort de la fenetre.'}
    if($env:QUARTIERS_LAYOUT_ONLY -eq '1'){
        $layout=JS '({board:Math.round(document.querySelector("#board").getBoundingClientRect().width),sidebar:Math.round(document.querySelector("aside").getBoundingClientRect().width),bottom:Math.round(document.querySelector("#board").getBoundingClientRect().bottom),viewport:innerHeight})'
        Write-Output ('LAYOUT: '+($layout|ConvertTo-Json -Compress))
        $null=CDP 'Emulation.setDeviceMetricsOverride' @{width=1280;height=800;deviceScaleFactor=1;mobile=$false}
        Start-Sleep -Milliseconds 400;Screenshot 'preview-laptop.png'
        $laptop=JS '({board:Math.round(document.querySelector("#board").getBoundingClientRect().width),sidebar:Math.round(document.querySelector("aside").getBoundingClientRect().width),bottom:Math.round(document.querySelector("#board").getBoundingClientRect().bottom),viewport:innerHeight,overflow:document.documentElement.scrollWidth>innerWidth})'
        if($laptop.bottom -gt $laptop.viewport -or $laptop.overflow){throw 'Plateau hors fenetre sur ordinateur portable.'}
        Write-Output ('LAPTOP: '+($laptop|ConvertTo-Json -Compress))
        $tradeUI=JS @'
        (()=>{
          state.turn=state.players.findIndex(p=>p.id===state.me);renderActions();const seller=state.players[1];state.tiles[5].owner=seller.id;selected=5;renderSelection();
          if(!document.querySelector('#property-actions').textContent.includes('Faire une offre'))throw Error('Offer button missing');
          document.querySelector('#property-actions button').click();
          if(!document.querySelector('#offer-dialog').open)throw Error('Offer dialog missing');
          document.querySelector('#offer-close').click();
          state.offer={index:5,buyer:state.me,seller:seller.id,respondent:state.me,amount:280};renderOffers();
          if(document.querySelector('#offers').hidden||!document.querySelector('#offers').textContent.includes('Accepter'))throw Error('Counteroffer UI missing');
          return {dialog:true,counteroffer:true,turnPaused:document.querySelector('#actions button').disabled};
        })()
'@
        Write-Output ('TRADE UI: '+($tradeUI|ConvertTo-Json -Compress))
        $economyUI=JS @'
        (()=>{
          const me=state.players.find(p=>p.id===state.me),other=state.players.find(p=>p.id!==state.me);
          state.offer=null;state.turn=state.players.indexOf(me);state.rolled=false;state.debts=[];
          state.tiles[37].owner=other.id;state.tiles[18].owner=me.id;state.tiles[5].owner=me.id;
          openOffer(37);
          if(document.querySelectorAll('#offer-properties input').length<2)throw Error('Missing package deed choices');
          document.querySelectorAll('#offer-properties input').forEach(x=>x.checked=true);
          if(!document.querySelector('#offer-dialog').open)throw Error('Offer dialog');offerDialog.close();
          selected=1;state.tiles[1].owner=me.id;state.tiles[1].level=5;renderSelection();
          if(!document.querySelector('#selected').textContent.includes('250'))throw Error('Classic hotel rent missing');
          state.debts=[{player:me.id,receiver:other.id,amount:2000}];renderDebt();selected=18;renderSelection();
          if(!document.querySelector('#actions').textContent.includes('Safi')||!document.querySelector('#property-actions').textContent.includes('Hypothéquer'))throw Error('Debt choice missing');
          state.debts=[];me.jail=true;me.jailTurns=0;me.jailCards=[{deck:'chance'}];renderActions();
          if(!document.querySelector('#actions').textContent.includes('Utiliser ma carte')||!document.querySelector('#actions').textContent.includes('Tenter un double'))throw Error('Jail choice missing');
          me.jail=false;const savedAction=action,calls=[];action=(type)=>calls.push(type);
          const space=()=>document.body.dispatchEvent(new KeyboardEvent('keydown',{code:'Space',bubbles:true,cancelable:true}));
          try{space();state.rolled=true;space();busy=true;space();busy=false;document.querySelector('#name').dispatchEvent(new KeyboardEvent('keydown',{code:'Space',bubbles:true,cancelable:true}));if(calls.join(',')!=='roll,end')throw Error('Space guard: '+calls.join(','))}finally{action=savedAction;busy=false}
          selected=1;renderSelection();return {packageChoices:true,classicHotel:250,debtChoice:true,jailChoice:true,space:calls};
        })()
'@
        Write-Output ('ECONOMY UI: '+($economyUI|ConvertTo-Json -Compress))
        Screenshot 'preview-trade.png'
        $null=CDP 'Emulation.setDeviceMetricsOverride' @{width=390;height=844;deviceScaleFactor=1;mobile=$true}
        Start-Sleep -Milliseconds 300
        $overflow=JS 'document.documentElement.scrollWidth>innerWidth'
        if($overflow){throw 'Mobile overflow'}
        if($script:browserErrors.Count){throw 'JavaScript error'}
        return
    }
    $null=JS '(async()=>{for(let i=0;i<600;i++){if(!busy&&!animating&&state.players[state.turn].id===state.me)return true;await new Promise(r=>setTimeout(r,100))}throw Error("Human turn timeout")})()'
    # Exercise the real UI and observe token positions while the real server rolls.
    $move=JS @'
    (async()=>{
      const records=[];const pawn=document.querySelector('.pawn');
      const recorder=setInterval(()=>records.push(pawn.style.left+','+pawn.style.top),60);
      document.querySelector('#actions button').click();
      await new Promise(r=>setTimeout(r,500));
      for(let i=0;i<500&&(busy||animating);i++)await new Promise(r=>setTimeout(r,80));
      clearInterval(recorder);
      return {positions:new Set(records).size,tiles:document.querySelectorAll('.tile').length,pawns:document.querySelectorAll('.pawn').length,action:document.querySelector('#actions').textContent,animating};
    })()
'@
    if($move.positions -lt 3){throw 'Le pion ne passe pas par plusieurs positions.'}
    Write-Output ('REAL MOVE: '+($move|ConvertTo-Json -Compress))
    Screenshot 'preview-after-roll.png'
    # End the human turn, including doubles, then observe the real robot.
    $robot=JS @'
    (async()=>{
      const pause=ms=>new Promise(r=>setTimeout(r,ms));
      for(let k=0;k<8&&state.players[state.turn].id===state.me;k++){
        await action(state.rolled?'end':'roll');await pause(100);
      }
      const records=[],initial=state.eventSeq;
      const timer=setInterval(()=>{const p=document.querySelectorAll('.pawn')[1];records.push(p.style.left+','+p.style.top)},70);
      for(let k=0;k<400;k++){
        await pause(100);
        if(state.players[state.turn].id===state.me&&!animating&&!busy&&state.eventSeq>initial)break;
      }
      clearInterval(timer);
      return {positions:new Set(records).size,robotRolled:state.log.some(l=>l.includes('Robot 1 lance')),humanTurn:state.players[state.turn].id===state.me,log:state.log.slice(-6)};
    })()
'@
    if(-not $robot.robotRolled -or $robot.positions -lt 3){throw 'Le robot ne se déplace pas visiblement.'}
    Write-Output ('REAL ROBOT: '+($robot|ConvertTo-Json -Compress))
    # Test card presentation independently of random landing; no server state is changed.
    $null=JS "showCard({deck:'chance',title:'Bonne nouvelle !',text:'Votre investissement porte ses fruits. Recevez 150 DH.'},'Robot 1',true); 'started'"
    Start-Sleep -Seconds 1;Screenshot 'preview-chance.png'
    $card=JS "({visible:!document.querySelector('#card-overlay').hidden,flipped:document.querySelector('#drawn-card').classList.contains('flipped')})"
    if(-not $card.visible -or -not $card.flipped){throw 'Carte non visible.'};$null=JS 'closeCard()'
    $null=CDP 'Emulation.setDeviceMetricsOverride' @{width=390;height=844;deviceScaleFactor=1;mobile=$true}
    Start-Sleep -Milliseconds 500;Screenshot 'preview-mobile.png'
    $mobile=JS '({width:innerWidth,contentWidth:document.documentElement.scrollWidth,tiles:document.querySelectorAll(".tile").length})'
    if($mobile.contentWidth -gt $mobile.width){throw 'Débordement horizontal sur mobile.'}
    Write-Output ('MOBILE: '+($mobile|ConvertTo-Json -Compress))
    if($script:browserErrors.Count){throw ($script:browserErrors|ConvertTo-Json -Depth 10 -Compress)}
    Write-Output 'OK : interface solo, déplacement réel, robot réel, carte animée, mobile et aucune erreur JavaScript.'
} finally {
    if(-not $KeepBrowser){try{$null=CDP 'Browser.close'}catch{}}
    $socket.Dispose()
}
