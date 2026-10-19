const $=s=>document.querySelector(s),colors=['#d9483b','#4383bc','#bd8b32','#986ab6','#408558','#bc617b'];
let session=null;try{session=JSON.parse(sessionStorage.getItem('quartiers')||'null')}catch{sessionStorage.removeItem('quartiers')}
let state=null,selected=-1,busy=false,animating=false,pollPromise=null,lastEvent=0,generation=0,cardResolve=null;
const positions=new Map(),sleep=ms=>new Promise(r=>setTimeout(r,ms)),reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=n=>Number(n).toLocaleString('fr-FR');
const API_BASE = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1' ? '' : (window.API_URL || '');
function toast(text){$('#toast').textContent=text;$('#toast').style.display='block';clearTimeout(window.toastTimer);window.toastTimer=setTimeout(()=>$('#toast').style.display='none',4500)}
async function api(path,data){const response=await fetch(API_BASE+path,{method:data?'POST':'GET',headers:data?{'Content-Type':'application/json'}:{},body:data?JSON.stringify(data):undefined,signal:AbortSignal.timeout(10000)});const result=await response.json();if(!response.ok)throw Error(result.error||'Erreur serveur');return result}
function resetView(){generation++;state=null;selected=-1;lastEvent=0;positions.clear();$('#board').querySelectorAll('.tile').forEach(n=>n.remove());$('#token-layer').replaceChildren();closeCard();animating=false;document.body.classList.remove('animating')}
async function enter(create,mode){
 if(busy)return;if(!$('#name').value.trim()){toast('Saisissez votre prénom pour jouer.');$('#name').focus();return}
 busy=true;$('#entry').querySelectorAll('button').forEach(b=>b.disabled=true);
 try{if(pollPromise)await pollPromise;const result=await api('/api/'+(create?'create':'join'),{name:$('#name').value.trim(),code:$('#code').value.toUpperCase().trim(),mode});resetView();session={code:result.code,token:result.token};sessionStorage.setItem('quartiers',JSON.stringify(session));await poll(true)}catch(e){toast(e.message)}finally{busy=false;$('#entry').querySelectorAll('button').forEach(b=>b.disabled=false);if(state)render()}
}
async function action(type,index,extra={}){
 if(busy||animating)return;busy=true;render();
 try{if(pollPromise)await pollPromise;await api('/api/action',{...session,type,index,...extra});await poll(true)}catch(e){toast(e.message)}finally{busy=false;if(state)render()}
}
function poll(force=false){
 if(pollPromise)return pollPromise;if(!session||busy&&!force)return Promise.resolve();const ticket=generation,activeSession=session;
 pollPromise=(async()=>{try{
  const next=await api('/api/state?code='+activeSession.code+'&token='+activeSession.token);if(ticket!==generation)return;
  $('#connection').textContent='● Connecté · salon privé';
  if(!state){state=next;lastEvent=next.eventSeq||0;next.players.forEach(p=>positions.set(p.id,p.pos));render();return}
  const events=(next.events||[]).filter(e=>e.id>lastEvent);
  if(events.length){animating=true;document.body.classList.add('animating');$('#activity').classList.add('busy');renderActions();
   for(const event of events){if(ticket!==generation)return;await playEvent(event,next,ticket);lastEvent=event.id}
  }
  if(ticket!==generation)return;if(next.phase==='playing'&&next.players[next.turn].id===next.me&&(state.players[state.turn].id!==next.me||!state.rolled&&state.phase==='lobby'))gameSound.play('turn');state=next;state.players.forEach(p=>positions.set(p.id,p.pos));animating=false;document.body.classList.remove('animating');$('#activity').classList.remove('busy');render();
 }catch(e){if(ticket!==generation)return;$('#connection').textContent='● Connexion interrompue';animating=false;document.body.classList.remove('animating');if(e.message==='Salon introuvable'||e.message==='Session invalide.'){session=null;sessionStorage.removeItem('quartiers');resetView();$('#game').hidden=true;$('#welcome').hidden=false;toast('Le plateau a été mis à jour. Créez une nouvelle partie.')}else{toast('Connexion au serveur interrompue. Vérifiez Lancer.cmd.')}}})().finally(()=>{pollPromise=null});return pollPromise;
}
function announce(text,playerId){$('#activity-text').textContent=text;if(playerId){document.querySelectorAll('.player').forEach(el=>el.classList.toggle('active',el.dataset.player===playerId));document.querySelectorAll('.pawn').forEach(el=>el.classList.toggle('active',el.dataset.player===playerId))}}
async function playEvent(e,next,ticket){
 const p=next.players.find(p=>p.id===e.playerId),name=p?.name||'';
 if(e.type==='dice'){gameSound.play('dice');
  announce((p?.bot?'🤖 ':'')+name+' lance les dés…',e.playerId);$('#turn').textContent=name+' lance les dés';$('#dice').classList.add('rolling');
  for(let i=0;i<(reduced?1:9);i++){showDice([1+Math.floor(Math.random()*6),1+Math.floor(Math.random()*6)]);await sleep(reduced?30:90)}
  showDice(e.dice);$('#dice').classList.remove('rolling');announce(name+' obtient '+e.dice[0]+' + '+e.dice[1]+' = '+(e.dice[0]+e.dice[1])+'.',e.playerId);await sleep(reduced?60:450);
 }else if(e.type==='move'){
  const token=$('#pawn-'+e.playerId);if(!token)return;positions.set(e.playerId,e.from);placePawn(p,next);token.classList.add(e.jump?'jump':'moving');
  for(const square of e.path){if(ticket!==generation)break;positions.set(e.playerId,square);placePawn(p,next);gameSound.play(e.jump?'jump':'step');document.querySelectorAll('.tile.landing').forEach(n=>n.classList.remove('landing'));$('#tile-'+square)?.classList.add('landing');announce(name+(e.jump?' se rend à ':' avance vers ')+next.tiles[square].name+'.',e.playerId);await sleep(reduced?35:e.jump?850:320)}
  token.classList.remove('jump','moving');await sleep(reduced?40:350);document.querySelectorAll('.tile.landing').forEach(n=>n.classList.remove('landing'));
 }else if(e.type==='card'){gameSound.play('card');
  announce(name+' tire une carte '+(e.deck==='chest'?'Caisse commune':'Chance')+'.',e.playerId);await showCard(e,name,p?.bot);
 }else{
  gameSound.play(e.type==='win'?'win':e.type==='build'?'build':e.type==='purchase'?'money':/va en prison/.test(e.text||'')?'jail':/DH/.test(e.text||'')?'money':'');announce(e.text||'',e.playerId);if(e.type==='purchase'||e.type==='build')updateTiles(next);await sleep(reduced?100:1200);
 }
}
function showDice(values){const faces={1:[4],2:[0,8],3:[0,4,8],4:[0,2,6,8],5:[0,2,4,6,8],6:[0,2,3,5,6,8]};$('#dice').innerHTML=values.map(n=>`<div class="die" aria-label="${n}">${Array.from({length:9},(_,i)=>`<span class="pip ${faces[n].includes(i)?'on':''}"></span>`).join('')}</div>`).join('');$('#dice').setAttribute('aria-label','Dés : '+values.join(' et '))}
function closeCard(){if(cardResolve){cardResolve();cardResolve=null}$('#card-overlay').hidden=true;document.querySelectorAll('.deck').forEach(n=>n.classList.remove('drawing'))}
async function showCard(e,name,isBot){
 const deck=e.deck==='chest'?'Caisse commune':'Chance';$('#card-deck').textContent=deck;$('#card-title').textContent=e.title;$('#card-text').textContent=e.text;$('#card-player').textContent='Carte tirée par '+name+(isBot?' · robot':'');$('#card-art').innerHTML=e.deck==='chest'?art('chest'):art('car');$('.card-back strong').textContent=deck.toUpperCase();$('.card-back>span').textContent=e.deck==='chest'?'✦':'?';$('#drawn-card').classList.remove('flipped');$('#card-overlay').hidden=false;$('#deck-'+(e.deck==='chest'?'chest':'chance')).classList.add('drawing');
 await sleep(reduced?30:350);$('#drawn-card').classList.add('flipped');$('#close-card').focus();
 await new Promise(resolve=>{let timer;cardResolve=()=>{clearTimeout(timer);resolve()};timer=setTimeout(()=>closeCard(),isBot?3600:5500)});closeCard();
}
function coords(i){if(i<=10)return {row:11,col:11-i,edge:'bottom'};if(i<=20)return {row:21-i,col:1,edge:'left'};if(i<=30)return {row:1,col:i-19,edge:'top'};return {row:i-29,col:11,edge:'right'}}
function tileArt(t,i){if(i===0)return '<span class="go">GO</span><span class="arrow">←</span>';if(i===10)return art('jail');if(i===20)return art('car');if(i===30)return art('police');if(t.kind==='station')return art('train');if(t.kind==='chest')return art('chest');if(t.kind==='chance')return '<span class="question">?</span>';if(t.kind==='tax')return art('tax');if(t.kind==='utility')return art(i===12?'bulb':'water');return ''}
function makeBoard(s){
 if($('#board').querySelectorAll('.tile').length===s.tiles.length)return;
 $('#board').querySelectorAll('.tile').forEach(n=>n.remove());
 s.tiles.forEach((t,i)=>{const c=coords(i),corner=i%10===0,el=document.createElement('button');el.id='tile-'+i;el.className=`tile ${t.kind} edge-${c.edge}${corner?' corner':''}${i===10?' jail':''}${i===20?' parking':''}`;el.style.gridRow=c.row;el.style.gridColumn=c.col;el.style.setProperty('--group',t.color||'transparent');el.setAttribute('aria-label',t.name+(t.price?', '+t.price+' dirhams':''));el.innerHTML=`${t.kind==='property'?'<span class="strip"></span>':''}<span class="tile-inner">${i!==0?'<strong>'+esc(t.name)+'</strong>':''}${t.kind!=='property'?'<span class="tile-art">'+tileArt(t,i)+'</span>':''}<span class="price">${t.price?t.price+' DH':i===0?'+200 DH':t.symbol||''}</span></span><span class="houses"></span><span class="owner" hidden></span>`;el.onclick=()=>{selected=i;renderSelection();document.querySelectorAll('.tile').forEach(n=>n.classList.toggle('chosen',n.id==='tile-'+i))};if(i===10){el.setAttribute('aria-label','Prison / Simple visite');el.insertAdjacentHTML('beforeend','<span class="jail-floor" aria-hidden="true"><span class="jail-word">PRISON</span><svg class="prison-picture" viewBox="0 0 80 80"><path d="M1 1h78v78H1z" fill="#fff7dd" stroke="#26382b" stroke-width="2"/><path d="M22 71q1-23 18-23t18 23" fill="#26382b"/><ellipse cx="40" cy="32" rx="14" ry="18" fill="#fff7dd" stroke="#26382b" stroke-width="2"/><path d="M25 24q2-18 15-15t16 15l-8-4-8 3-7-3zM29 29h8m7 0h7m-15 11q5 4 10 0" fill="none" stroke="#26382b" stroke-width="3"/><path d="M15 2v76M32 2v76M49 2v76M66 2v76" stroke="#26382b" stroke-width="4"/><path d="M8 49l9-5 6 4-1 9-9 1zM57 49l9-5 6 4-1 9-9 1z" fill="#fff7dd" stroke="#26382b" stroke-width="2"/></svg></span><span class="visiting-label">VISITE</span><span class="visiting-side">SIMPLE</span>')}$('#board').append(el)});
}
function updateTiles(s){s.tiles.forEach((t,i)=>{const el=$('#tile-'+i);if(!el)return;el.classList.toggle('chosen',selected===i);el.classList.toggle('mortgaged',!!t.mortgaged);const owner=s.players.findIndex(p=>p.id===t.owner);el.querySelector('.owner').hidden=owner<0;el.querySelector('.owner').style.background=colors[owner]||'transparent';el.querySelector('.houses').textContent=t.level===5?'🏨':'🏠'.repeat(t.level)})}
function placePawn(p,s=state){const el=$('#pawn-'+p.id),tile=$('#tile-'+(positions.get(p.id)??p.pos));if(!el||!tile)return;const index=s.players.findIndex(x=>x.id===p.id),offsets=[[-12,-6],[12,6],[0,-13],[-14,11],[14,-11],[0,15]],off=offsets[index];el.style.left=(tile.offsetLeft+tile.offsetWidth*.5+off[0]*$('#board').offsetWidth/850)+'px';el.style.top=(tile.offsetTop+tile.offsetHeight*.66+off[1]*$('#board').offsetWidth/850)+'px';if((positions.get(p.id)??p.pos)===10){const peers=s.players.filter(x=>!x.out&&(positions.get(x.id)??x.pos)===10&&Boolean(x.jail)===Boolean(p.jail)),slot=peers.findIndex(x=>x.id===p.id);el.style.left=(tile.offsetLeft+tile.offsetWidth*(p.jail ? .36+.55*(slot+1)/(peers.length+1) : .13))+'px';el.style.top=(tile.offsetTop+tile.offsetHeight*(p.jail ? .4 : .25+.45*(slot+1)/(peers.length+1)))+'px'}el.classList.toggle('behind-bars',(positions.get(p.id)??p.pos)===10&&p.jail);el.hidden=p.out}
function updatePawns(s){s.players.forEach((p,i)=>{let el=$('#pawn-'+p.id);if(!el){el=document.createElement('div');el.id='pawn-'+p.id;el.className='pawn';el.dataset.player=p.id;el.style.color=colors[i];el.innerHTML=art(pawnArts[i])+`<span class="pawn-label">${p.bot?'ROBOT':esc(p.name.slice(0,8))}</span>`;$('#token-layer').append(el)}el.classList.toggle('active',s.players[s.turn].id===p.id);placePawn(p,s)})}
function addButton(container,label,type,index,secondary=false){const b=document.createElement('button');b.textContent=label;b.dataset.action=type;b.className=secondary?'secondary':'';b.disabled=busy||animating;b.onclick=()=>action(type,index);$(container).append(b)}
function renderActions(){
 if(!state)return;const s=state,me=s.players.find(p=>p.id===s.me),current=s.players[s.turn];$('#actions').replaceChildren();
 $('#action-title').textContent=s.phase==='lobby'?'Rassemblez vos amis.':s.phase==='finished'?'La victoire est à vous ?':current.bot?'Le robot joue.':current.id===s.me?'C’est votre tour !':current.name+' joue.';
 $('#status').textContent=s.phase==='lobby'?'Ajoutez un robot ou partagez le salon. Lancez quand tout le monde est prêt.':s.phase==='finished'?current.name+' remporte la partie. Revenez à l’accueil pour rejouer.':animating?'Suivez le lancer et le déplacement sur le plateau…':current.id===s.me?(s.rolled?'Achetez la ville si elle est libre, puis terminez votre tour.':'Lancez les dés : votre pion avancera case par case.'):current.bot?'Regardez ses dés, son pion et ses décisions. Il joue automatiquement.':'Vous pouvez examiner les villes pendant son tour.';
 if(s.phase==='lobby'&&me.id===s.host){if(s.players.length<6)addButton('#actions','Ajouter un robot 🤖','addbot',null,true);if(s.players.length>=2)addButton('#actions','Commencer la partie →','start')}
 if(s.phase==='opening'){
  $('#action-title').textContent='Qui commence ?';
  $('#status').textContent=(s.openingRound>1?'Égalité : les joueurs concernés relancent. ':'Chaque joueur lance deux dés. Le plus grand total commence. ')+(current.id===me.id?'À vous de lancer !':current.name+' doit lancer'+(current.bot?' automatiquement.':'.'));
  if(current.id===me.id)addButton('#actions',s.openingRound>1?'Relancer pour départager 🎲':'Lancer pour ma place 🎲','orderroll');
  else if(current.bot)$('#actions').insertAdjacentHTML('beforeend','<div class="thinking"><span></span><span></span><span></span> Le robot prépare son lancer</div>');
  $('#actions').insertAdjacentHTML('beforeend','<ol class="opening-results">'+s.openingGroups.flatMap(g=>g.ids).map(id=>{const p=s.players.find(x=>x.id===id),scores=[s.openingHistory[id]??[]].flat();return '<li><strong>'+esc(p.name)+'</strong><span>'+ (scores.length?scores.join(' → '):'À lancer')+(s.openingRound>1&&s.openingPending.includes(id)?' · relance attendue':'')+'</span></li>'}).join('')+'</ol><small>Ce lancer détermine les places : les pions restent au départ.</small>');
  if(current.id===me.id)$('#actions').insertAdjacentHTML('beforeend','<small class="keyboard-hint"><kbd>Espace</kbd> : lancer pour ma place</small>');
 }
 if(s.phase==='playing'&&current.id===me.id&&!me.out){if(!s.rolled){
 if(me.jail){
  $('#status').textContent='Prison · Tour '+((me.jailTurns||0)+1)+' / 3';
  if(me.jailCards?.length)addButton('#actions','Utiliser ma carte prison + dés','usejail');
  if((me.jailTurns||0)>=2)addButton('#actions','T3 : payer 50 DH et lancer les dés','payjail');
  else{addButton('#actions','Tenter un double · gratuit','roll');addButton('#actions','Payer 50 DH et lancer les dés','payjail',null,true)}
 }else addButton('#actions',me.jailDouble?'Sortie de prison : lancer pour avancer 🎲':'Lancer les dés 🎲','roll');
}else{const t=s.tiles[me.pos];if(t.price&&!t.owner&&me.money>=t.price)addButton('#actions','Acheter '+t.name+' · '+t.price+' DH','buy');addButton('#actions',s.dice[0]===s.dice[1]&&!me.jail&&!me.jailDouble?'Rejouer mon double →':'Terminer mon tour →','end',null,true)}}
 if(s.phase==='playing'&&(current.bot||animating)){$('#actions').insertAdjacentHTML('beforeend','<div class="thinking"><span></span><span></span><span></span> '+(animating?'Action en cours':'Le robot réfléchit')+'</div>')}
 if(s.phase==='playing'&&current.id===me.id&&!me.jail&&!s.debts?.length)$('#actions').insertAdjacentHTML('beforeend','<small class="keyboard-hint"><kbd>Espace</kbd> : '+(s.rolled?'terminer le tour':'lancer les dés')+'</small>');
 renderSelection();
}
function rent(t,s){if(t.mortgaged)return 0;if(t.kind==='station')return t.owner?25*2**(s.tiles.filter(x=>x.kind==='station'&&x.owner===t.owner).length-1):25;if(t.kind==='utility')return (t.owner&&s.tiles.filter(x=>x.kind==='utility'&&x.owner===t.owner).length===2?'10':'4')+' × dés';const full=t.owner&&s.tiles.filter(x=>x.group===t.group).every(x=>x.owner===t.owner);return t.level?t.rents[t.level]:t.rent*(full?2:1)}
function propertySchedule(t,s){
 if(t.kind!=='property')return '';
 const full=t.owner&&s.tiles.filter(x=>x.group===t.group).every(x=>x.owner===t.owner);
 const rows=[{label:'Terrain seul',cost:0,rent:t.rent,active:!!t.owner&&!t.mortgaged&&!full&&!t.level},{label:'Couleur complète',cost:0,rent:t.rent*2,active:!!full&&!t.mortgaged&&!t.level},...Array.from({length:5},(_,i)=>({label:i===4?'Hôtel':(i+1)+' maison'+(i?'s':''),cost:(i+1)*t.build,rent:rent({...t,mortgaged:false,level:i+1},s),active:!!t.owner&&!t.mortgaged&&t.level===i+1}))];
 return `<div class="deed-details"><table class="deed-table"><caption>Constructions et loyers · DH</caption><thead><tr><th scope="col">État</th><th scope="col">Coût total*</th><th scope="col">Loyer</th></tr></thead><tbody>${rows.map(r=>`<tr class="${r.active?'current-rent':''}" ${r.active?'aria-current="true"':''}><th scope="row">${r.label}${r.active?' ●':''}</th><td>${money(r.cost)}</td><td>${money(r.rent)}</td></tr>`).join('')}</tbody></table><p>*Coût cumulé des constructions sur cette ville, hors achat du terrain. Chaque maison : <strong>${money(t.build)} DH</strong>. Revente à la banque : <strong>${money(t.build/2)} DH par maison</strong> (moitié prix). Après 4 maisons, l’hôtel coûte <strong>${money(t.build)} DH de plus</strong> et remplace les maisons.</p><p>Possédez toute la couleur et construisez de façon équilibrée. Les dépenses sur les autres villes du groupe ne sont pas incluses.</p><p class="rent-example">Avec <strong>3 maisons sur cette case</strong>, un adversaire paie <strong>${money(rent({...t,mortgaged:false,level:3},s))} DH</strong> au propriétaire.</p><p>● Niveau actuel · Tarifs classiques.</p></div>`;
}
function renderSelection(){
 $('#property-actions').replaceChildren();if(!state||selected<0){$('#selected').textContent='Cliquez une ville pour voir son prix, son propriétaire et son loyer.';return}
 const s=state,t=s.tiles[selected],owner=s.players.find(p=>p.id===t.owner),me=s.players.find(p=>p.id===s.me);$('#selected').innerHTML=`<div class="property-title"><span class="swatch" style="--group:${t.color||'#b5c4aa'}"></span>${esc(t.name)}</div>${t.price?`<div class="property-stats"><span>PRIX<strong>${t.price} DH</strong></span><span>LOYER<strong>${rent(t,s)}${t.kind==='utility'?'':' DH'}</strong></span></div><span>${owner?'Propriétaire : '+esc(owner.name):'Disponible à l’achat après y être arrivé.'}</span>`:`<p>${t.kind==='chance'||t.kind==='chest'?'Une carte est tirée quand un joueur arrive ici.':selected===0?'Recevez 200 DH en passant le départ.':selected===30?'Direction la prison, sans prime de départ.':selected===10?'Arrivée normale : simple visite, sans frais ni blocage. Seuls les joueurs envoyés en prison doivent suivre les règles de sortie.':t.kind==='tax'?'Payez '+(t.taxAmount??100)+' DH à la banque.':'Une pause gratuite.'}</p>`}`;
 $('#selected').insertAdjacentHTML('beforeend',propertySchedule(t,s));
 if(t.price)$('#selected').insertAdjacentHTML('beforeend',`<p class="mortgage-info">${t.mortgaged?'🔒 Hypothéqué : aucun loyer.':'Hypothèque possible : '+money(t.price/2)+' DH.'} Remboursement : ${money((t.price/2+Math.ceil(t.price/20)))} DH (intérêts inclus).</p>`);
 if(s.phase==='playing'&&!me.out&&!s.offer&&owner&&owner.id!==me.id){const b=document.createElement('button');b.textContent='Faire une offre';b.disabled=busy||animating;b.onclick=()=>openOffer(selected);$('#property-actions').append(b)}
 if(s.phase==='playing'&&!s.offer&&!me.out&&t.owner===me.id&&s.players[s.turn].id!==me.id){const note=document.createElement('p');note.textContent='Vous pourrez construire pendant votre tour.';$('#property-actions').append(note)}
 if(s.phase==='playing'&&!s.offer&&!me.out&&t.owner===me.id&&(s.players[s.turn].id===me.id||s.debts?.some(d=>d.player===me.id))){
  if(t.kind==='property'){
   const group=s.tiles.filter(x=>x.group===t.group),complete=group.every(x=>x.owner===me.id),balanced=group.every(x=>x.level>=t.level);
   const note=document.createElement('p');note.textContent=(t.level===5?'Un hôtel':t.level+' maison(s)')+' · '+(!complete?'Possédez toutes les villes de cette couleur.':t.level===5?'Construction terminée.':!balanced?'Construisez d’abord sur les villes les moins équipées.':me.money<t.build?'Argent insuffisant : '+t.build+' DH nécessaires.':'Groupe complet : construction disponible.');$('#property-actions').append(note);
   if(t.level<5&&!s.debts?.length){addButton('#property-actions',(t.level===4?'Construire un hôtel':'Ajouter une maison')+' · '+t.build+' DH','build',selected);$('#property-actions button').disabled=busy||animating||!complete||!balanced||group.some(x=>x.mortgaged)||me.money<t.build}
   if(t.level)addButton('#property-actions',(t.level===5?'Revendre l’hôtel → 4 maisons':'Vendre une maison')+' · '+Math.floor(t.build/2)+' DH','sellhouse',selected,true);
  }
  addButton('#property-actions',t.mortgaged?'Lever l’hypothèque · '+(t.price/2+Math.ceil(t.price/20))+' DH':'Hypothéquer · recevoir '+t.price/2+' DH',t.mortgaged?'unmortgage':'mortgage',selected,true)
 }
}
function render(){
 if(!state)return;const s=state,current=s.players[s.turn];$('#welcome').hidden=true;$('#game').hidden=false;$('#room-code').textContent=session.code;$('#player-count').textContent=s.players.length+' / 6';
 $('#players').innerHTML=s.players.map((p,i)=>`<div class="player ${i===s.turn?'active':''} ${p.out?'out':''}" data-player="${p.id}"><div class="player-pawn" style="color:${colors[i]}">${art(pawnArts[i])}</div><div><span class="player-name">${esc(p.name)}${p.id===s.me?' · vous':''}</span><small>${p.out?'Faillite':p.jail?'En prison':p.pos===10?'Simple visite':pawnNames[i]+(p.bot?' · robot':'')} · ${s.tiles.filter(t=>t.owner===p.id).length} biens</small></div><span class="money">${money(p.money)}<small>DIRHAMS</small></span></div>`).join('');
 makeBoard(s);updateTiles(s);updatePawns(s);if(!animating)showDice(s.dice);$('#turn').textContent=s.phase==='lobby'?'En attente des joueurs':s.phase==='finished'?'🏆 '+current.name:current.name+(current.id===s.me?' · à vous de jouer':current.bot?' · robot':' · à son tour');
 $('#log').innerHTML=s.log.slice().reverse().map(l=>'<p>'+esc(l)+'</p>').join('');renderActions();renderOffers();renderDebt();
 if(s.turnOrder)document.querySelectorAll('#players .player').forEach((el,i)=>{const rank=document.createElement('small');rank.className='turn-rank';rank.textContent='Ordre : '+(s.turnOrder.indexOf(i)+1)+(s.turnOrder.indexOf(i)===0?'er':'e');el.querySelector('.player-name').after(rank)});
 if(s.phase==='opening'){$('#turn').textContent=current.name+' · tirage de l’ordre';if(!animating)announce('Tirage de l’ordre · '+(current.id===s.me?'à vous de lancer les dés !':current.name+' va lancer les dés.'),current.id);return}
 if(!animating)announce(s.phase==='lobby'?'Le salon est prêt. Invitez vos amis ou ajoutez un robot.':s.phase==='finished'?'🏆 '+current.name+' remporte la partie !':current.id===s.me?(s.rolled?'À vous : achetez, construisez ou terminez votre tour.':'À vous de lancer les dés !'):current.bot?'🤖 '+current.name+' prépare son prochain coup…':current.name+' joue.',current.id);
}
$('#solo').onclick=()=>enter(true,'solo');$('#create').onclick=()=>enter(true);$('#entry').onsubmit=e=>{e.preventDefault();enter(false)};$('#code').value=new URLSearchParams(location.search).get('room')||'';
$('#home').onclick=()=>{if(busy||animating){toast('Attendez la fin de cette action.');return}if(state?.phase==='playing'&&!confirm('Revenir à l’accueil ? Vous quitterez cette partie.'))return;session=null;sessionStorage.removeItem('quartiers');resetView();$('#game').hidden=true;$('#welcome').hidden=false};
$('#invite').onclick=async()=>{const url=location.origin+'/?room='+session.code;try{await navigator.clipboard.writeText(url);toast('Lien copié : '+url)}catch{toast(url)}};
$('#close-card').onclick=closeCard;document.addEventListener('keydown',e=>{if(!$('#card-overlay').hidden){if(e.key==='Escape')closeCard();if(e.key==='Tab'){e.preventDefault();$('#close-card').focus()}}});
$('#welcome-car').innerHTML=art('car');$('#chest-art').innerHTML=art('chest');$('#skyline').innerHTML=skylineArt;new ResizeObserver(()=>{if(state)state.players.forEach(p=>placePawn(p))}).observe($('#board'));
const offerPanel=document.createElement('section');offerPanel.className='panel trade-panel';offerPanel.id='offers';offerPanel.hidden=true;document.querySelector('aside').prepend(offerPanel);
const offerDialog=document.createElement('dialog');offerDialog.id='offer-dialog';offerDialog.innerHTML='<form method="dialog"><h2 id="offer-heading">Faire une offre</h2><p id="offer-description"></p><label>Montant en DH<input id="offer-amount" type="number" min="1" max="9999999" step="1" required></label><div class="offer-buttons"><button value="cancel" type="button" id="offer-close" class="secondary">Annuler</button><button type="submit">Envoyer</button></div></form>';document.body.append(offerDialog);
let offerIndex=-1,offerMode='offer';
$('#offer-amount').min='0';$('#offer-amount').closest('label').insertAdjacentHTML('afterend','<fieldset id="offer-properties"><legend>Propriétés ajoutées à l’offre</legend><div></div></fieldset>');
function openOffer(index,mode='offer'){offerIndex=index;offerMode=mode;$('#offer-heading').textContent=mode==='offer'?'Faire une offre':'Modifier la proposition';$('#offer-description').textContent='En échange de '+state.tiles[index].name+' : argent + propriétés sélectionnées.';$('#offer-amount').value=mode==='offer'?state.tiles[index].price:state.offer.amount;
 const buyer=mode==='offer'?state.me:state.offer.buyer,chosen=mode==='offer'?[]:state.offer.offered||[];
 $('#offer-properties div').innerHTML=state.tiles.map((t,i)=>({t,i})).filter(({t})=>t.owner===buyer&&!t.mortgaged&&t.price>0&&(t.kind!=='property'||!state.tiles.some(x=>x.group===t.group&&x.level>0))).map(({t,i})=>`<label><input type="checkbox" value="${i}" ${chosen.includes(i)?'checked':''}>${esc(t.name)} · ${t.price} DH</label>`).join('')||'<p>Aucune propriété échangeable.</p>';
 offerDialog.showModal();$('#offer-amount').focus()}
$('#offer-close').onclick=()=>offerDialog.close();offerDialog.querySelector('form').onsubmit=e=>{e.preventDefault();const amount=Number($('#offer-amount').value);if(!Number.isInteger(amount)||amount<0)return;const offered=[...document.querySelectorAll('#offer-properties input:checked')].map(x=>Number(x.value));offerDialog.close();action(offerMode,offerIndex,{amount,offered})};
function renderOffers(){const o=state.offer;offerPanel.hidden=!o;if(!o)return;const involved=[o.buyer,o.seller].includes(state.me),respond=o.respondent===state.me;offerPanel.innerHTML='<span class="eyebrow">NÉGOCIATION EN COURS</span><h3>'+esc(state.tiles[o.index].name)+'</h3><p>'+esc(state.players.find(p=>p.id===o.buyer).name)+' achète à '+esc(state.players.find(p=>p.id===o.seller).name)+' pour <strong>'+money(o.amount)+' DH</strong>.</p><p>'+(respond?'À vous de répondre.':'En attente de la réponse de '+esc(state.players.find(p=>p.id===o.respondent).name)+'.')+'</p><div id="offer-actions"></div>';
 if(respond){addButton('#offer-actions','Accepter','acceptoffer');addButton('#offer-actions','Refuser','rejectoffer',null,true);const b=document.createElement('button');b.textContent='Faire une contre-offre';b.className='secondary';b.disabled=busy||animating;b.onclick=()=>openOffer(o.index,'counteroffer');$('#offer-actions').append(b)}
 if(involved)addButton('#offer-actions','Annuler la négociation','canceloffer',null,true);
 if(o.offered?.length)$('#offer-actions').insertAdjacentHTML('beforebegin','<p><strong>Propriétés remises au vendeur :</strong> '+o.offered.map(i=>esc(state.tiles[i].name)).join(', ')+'</p>');
 $('#actions').querySelectorAll('button').forEach(b=>b.disabled=true);$('#status').textContent='Le tour reprendra après la négociation.';
}
const fullscreen=document.createElement('button');fullscreen.className='secondary';fullscreen.textContent='Plein écran';fullscreen.onclick=async()=>{try{if(document.fullscreenElement)await document.exitFullscreen();else await document.documentElement.requestFullscreen()}catch{toast('Utilisez F11 pour le plein écran.')}};$('.table-tools').prepend(fullscreen);
poll();setInterval(()=>poll(),800);

// Keep table controls beside the board, freeing the entire title row.
const tableTools=document.querySelector('.table-tools');document.querySelector('aside').prepend(tableTools);document.querySelector('.game-top').remove();
const manage=document.createElement('button');manage.className='secondary';manage.textContent='Mes biens / Gérer';manage.onclick=()=>{const owned=state?.tiles.map((t,i)=>({t,i})).filter(x=>x.t.owner===state.me&&x.t.price>0)||[];if(!owned.length){toast('Achetez des villes pour construire.');return}const next=owned.find(x=>x.i>selected)||owned[0];selected=next.i;renderSelection();document.querySelector('#property-panel').scrollIntoView({block:'nearest',behavior:'smooth'})};tableTools.append(manage);
function renderDebt(){
 const d=state.debts?.[0];if(!d)return;
 $('#actions').replaceChildren();$('#action-title').textContent='Dette à régler';const p=state.players.find(x=>x.id===d.player),creditor=state.players.find(x=>x.id===d.receiver);
 $('#status').textContent=p.name+' doit '+money(d.amount)+' DH à '+(creditor?.name||'la banque')+'. Disponible : '+money(p.money)+' DH. Le jeu est en pause.';
 if(d.player===state.me){
  const help=document.createElement('p');help.textContent='Choisissez les biens à hypothéquer ou les maisons à revendre. Le paiement se fera dès que la somme sera réunie.';$('#actions').append(help);
  state.tiles.forEach((t,i)=>{if(t.owner!==state.me)return;const b=document.createElement('button');b.className='secondary';b.textContent=t.name+(t.level?' · vendre des bâtiments':t.mortgaged?' · déjà hypothéqué':' · hypothèque '+t.price/2+' DH');b.onclick=()=>{selected=i;renderSelection();$('#property-panel').scrollIntoView({block:'nearest'})};$('#actions').append(b)});
  const b=document.createElement('button');b.className='secondary';b.textContent='Déclarer faillite';b.disabled=busy||animating;b.onclick=()=>{if(confirm('Abandonner vos biens au créancier et quitter la partie ?'))action('bankrupt')};$('#actions').append(b);
 }
}
// All effects are synthesized locally. One context and master volume per tab.
const gameSound={
 ctx:null,master:null,muted:false,volume:.35,lastStep:0,
 async unlock(){
  try{
   if(!this.ctx){const Audio=window.AudioContext||window.webkitAudioContext;if(!Audio)return;this.ctx=new Audio();this.master=this.ctx.createGain();this.master.connect(this.ctx.destination);this.sync()}
   if(this.ctx.state==='suspended')await this.ctx.resume();
  }catch{/* Audio must never interrupt gameplay. */}
 },
 sync(){if(this.master)this.master.gain.setValueAtTime(this.muted||document.hidden?0:this.volume,this.ctx.currentTime)},
 tone(freq,delay,duration,type='sine',level=.16,end=freq){
  const c=this.ctx,o=c.createOscillator(),g=c.createGain(),at=c.currentTime+delay;
  o.type=type;o.frequency.setValueAtTime(freq,at);o.frequency.exponentialRampToValueAtTime(Math.max(20,end),at+duration);
  g.gain.setValueAtTime(0,at);g.gain.linearRampToValueAtTime(level,at+.006);g.gain.exponentialRampToValueAtTime(.0001,at+duration);
  o.connect(g);g.connect(this.master);o.start(at);o.stop(at+duration+.02);o.onended=()=>{o.disconnect();g.disconnect()};
 },
 play(kind){
  if(!kind||this.muted||!this.volume||document.hidden||this.ctx?.state!=='running')return;
  try{
   const t=(...args)=>this.tone(...args);
   switch(kind){
    case 'dice':for(let i=0;i<8;i++)t(450+Math.random()*800,i*.085,.05,'triangle',.12,130);break;
    case 'step':if(performance.now()-this.lastStep<100)return;this.lastStep=performance.now();t(290,0,.055,'sine',.075,170);break;
    case 'jump':t(240,0,.3,'sine',.12,640);break;
    case 'card':t(950,0,.13,'triangle',.07,350);t(600,.14,.12,'sine',.08,1000);break;
    case 'money':t(1047,0,.17,'sine',.13);t(1568,.1,.23,'sine',.1);break;
    case 'build':t(180,0,.09,'triangle',.16,65);t(240,.18,.1,'triangle',.12,80);break;
    case 'jail':t(110,0,.28,'triangle',.15,45);t(650,.03,.12,'sine',.07,280);break;
    case 'turn':t(523,0,.18);t(784,.2,.25);break;
    case 'win':[523,659,784,1047].forEach((f,i)=>t(f,i*.17,.35,'sine',.14));break;
   }
  }catch{/* An unavailable audio device does not stop an animation. */}
 }
};
try{const saved=JSON.parse(localStorage.getItem('quartiers-audio')||'null');if(saved){gameSound.muted=!!saved.muted;if(Number.isFinite(saved.volume))gameSound.volume=Math.max(0,Math.min(1,saved.volume))}}catch{}
const audioControls=document.createElement('div');audioControls.className='audio-controls';audioControls.innerHTML='<button type="button" class="secondary" id="sound-toggle"></button><label for="sound-volume">Volume</label><input id="sound-volume" type="range" min="0" max="100" step="5" aria-label="Volume des effets sonores">';tableTools.append(audioControls);
function updateAudioControls(){const b=$('#sound-toggle');b.textContent=gameSound.muted?'🔇 Son coupé':'🔊 Son actif';b.setAttribute('aria-pressed',String(!gameSound.muted));b.setAttribute('aria-label',gameSound.muted?'Activer les effets sonores':'Couper les effets sonores');$('#sound-volume').value=String(Math.round(gameSound.volume*100));gameSound.sync();try{localStorage.setItem('quartiers-audio',JSON.stringify({muted:gameSound.muted,volume:gameSound.volume}))}catch{}}
$('#sound-toggle').onclick=async()=>{await gameSound.unlock();gameSound.muted=!gameSound.muted;updateAudioControls();if(!gameSound.muted)gameSound.play('turn')};
$('#sound-volume').oninput=e=>{gameSound.volume=Number(e.target.value)/100;updateAudioControls()};
$('#sound-volume').onchange=async()=>{await gameSound.unlock();gameSound.play('step')};
document.addEventListener('pointerdown',()=>gameSound.unlock(),{passive:true});document.addEventListener('keydown',()=>gameSound.unlock());document.addEventListener('visibilitychange',()=>gameSound.sync());updateAudioControls();
document.addEventListener('keydown',e=>{
 if(e.code!=='Space'||e.repeat||e.altKey||e.ctrlKey||e.metaKey||e.target.closest('input,textarea,select,a,[contenteditable="true"]')||document.querySelector('dialog[open]')||!$('#card-overlay').hidden)return;
 if(!state||!['playing','opening'].includes(state.phase)||state.players[state.turn].id!==state.me||busy||animating||state.offer||state.debts?.length)return;
 if(state.phase==='opening'){e.preventDefault();action('orderroll');return}
 e.preventDefault();const me=state.players.find(p=>p.id===state.me);if(!state.rolled&&me.jail){toast('Choisissez : carte, tentative de double ou paiement.');return}action(state.rolled?'end':'roll');
});
