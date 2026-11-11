const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),os=require('node:os');
const {createAuth}=require('../auth');
async function gameServer(t){
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'quartiers-api-auth-'));let server;
 const sandbox={__dirname:path.resolve(__dirname,'..'),require(name){
  if(name==='express'){
   const express=require('express');return Object.assign(()=>{const app=express(),listen=app.listen.bind(app);app.listen=(_,cb)=>{server=listen(0,'127.0.0.1',cb);return server;};return app;},express);
  }
  if(name==='fs')return {existsSync:()=>false,writeFileSync:()=>{}};
  if(name==='./auth')return {createAuth:()=>createAuth({clientId:'test.apps.googleusercontent.com',accountsFile:path.join(dir,'accounts.json'),verifyIdToken:async credential=>{
   const [identity,nonce]=credential.split(':');if(!['said','abdo','third'].includes(identity))throw Error('Invalid Google token');
   return {getPayload:()=>({sub:identity,name:identity.toUpperCase(),nonce,aud:'test.apps.googleusercontent.com',iss:'https://accounts.google.com',exp:Date.now()/1000+3600,picture:'https://lh3.googleusercontent.com/photo'})};
  }})};
  return require(name.startsWith('.')?path.resolve(__dirname,'..',name):name);
 },Math:Object.create(Math),process:{env:{}},console:{log(){},error:console.error},setInterval:()=>({unref(){}})};
 vm.createContext(sandbox);vm.runInContext(fs.readFileSync(path.join(__dirname,'../server.js'),'utf8')+'\nglobalThis.testing={getRoom,invokeGameAction};',sandbox);
 await new Promise(r=>server.once('listening',r));
 t.after(()=>{server.closeAllConnections();server.close();fs.rmSync(dir,{recursive:true,force:true});});
 const base='http://127.0.0.1:'+server.address().port;
 async function call(route,data,auth){
  const authorization=typeof auth==='string'?{Authorization:'Bearer '+auth}:auth?.token?{Authorization:'Bearer '+auth.token}:auth?.cookie?{Cookie:auth.cookie}:{};
  const response=await fetch(base+route,{method:data?'POST':'GET',headers:{...(data?{'Content-Type':'application/json'}:{}),...authorization},body:data?JSON.stringify(data):undefined});
  return {status:response.status,body:await response.json(),cookie:response.headers.get('set-cookie')};
 }
 async function login(identity,platform='android'){
  const config=(await call('/api/auth/config')).body;
  const response=await call('/api/auth/google',{credential:identity+':'+config.nonce,nonce:config.nonce,platform});
  return {...response.body,...(response.cookie?{cookie:response.cookie.split(';')[0]}:{})};
 }
 const state=(seat,auth)=>call('/api/state?code='+seat.code+'&token='+seat.token,null,auth);
 return {call,login,state,engine:sandbox.testing,setDice(value){sandbox.Math.random=value===null?Math.random:()=>value;}};
}

test('the real game API binds seats to Google accounts, resumes across devices and hides account IDs',async t=>{
 const {call,login,state}=await gameServer(t),said=await login('said'),abdo=await login('abdo');
 assert.equal((await call('/api/create',{name:'Imposteur'})).status,401);
 let host=(await call('/api/create',{name:'Said',accountId:abdo.account.id,picture:'https://attacker.example/photo'},said)).body;
 const initial=(await state(host,said)).body;
 assert.equal(initial.players[0].picture,said.account.picture);assert(!('accountId' in initial.players[0]));assert(!('token' in initial.players[0]));
 assert.equal((await state(host,abdo)).status,403);
 assert.equal((await call('/api/action',{...host,type:'start'},abdo)).status,403);
 const guest=(await call('/api/join',{code:host.code,name:'Abdo'},abdo)).body;
 const secondDevice=await login('said'),previous=host;
 host=(await call('/api/join',{code:host.code,name:'Autre nom'},secondDevice)).body;
 assert.notEqual(host.token,previous.token,'an explicit rejoin transfers control');
 assert.equal((await state(previous,said)).body.code,'SEAT_MOVED');
 const two=(await state(host,secondDevice)).body;
 assert.equal(two.players.length,2);assert.equal(two.players[1].name,'Abdo');assert(!('previousTokenHashes' in two.players[0]));
 await call('/api/action',{...host,type:'start'},secondDevice);
 const started=(await call('/api/join',{code:host.code},secondDevice)).body;
 assert.equal((await state(started,secondDevice)).status,200,'a started game remains resumable');
 await call('/api/auth/logout',{},said);
 assert.equal((await call('/api/action',{...started,type:'roll'},said)).status,401);
 assert.equal((await state(guest,abdo)).status,200);
});

test('the same Google account discovers and transfers a friends game web → Android → web without a room code',async t=>{
 const {call,login,state,engine}=await gameServer(t),web=await login('said','web'),android=await login('said'),friend=await login('abdo');
 const original=(await call('/api/create',{name:'Said'},web)).body;
 await call('/api/join',{code:original.code,name:'Abdo'},friend);
 const s=engine.getRoom(original.code),p=s.players[0];
 s.phase='playing';s.turn=0;s.rolled=true;p.money=875;p.pos=18;p.jail=true;p.jailTurns=1;
 for(const index of [16,18,19]){s.tiles[index].owner=p.id;s.tiles[index].level=2;}
 const preserved=()=>JSON.stringify({tiles:s.tiles,dice:s.dice,turn:s.turn,rolled:s.rolled,money:p.money,pos:p.pos,jail:p.jail,jailTurns:p.jailTurns,players:s.players.map(x=>({id:x.id,money:x.money,pos:x.pos}))});
 const before=preserved();
 const games=(await call('/api/my-games',null,android)).body.games;
 assert.equal(games.length,1);assert.equal(games[0].code,original.code);assert.equal(games[0].mode,'friends');assert(!('token' in games[0]));
 assert.equal((await state(original,web)).status,200,'discovery alone cannot steal control');
 const phone=(await call('/api/resume',{code:games[0].code},android)).body;
 assert.equal(preserved(),before);assert.notEqual(phone.token,original.token);
 assert.equal((await state(original,web)).body.code,'SEAT_MOVED');
 assert.equal((await call('/api/action',{...original,type:'leave'},web)).status,409,'late leave from the old device cannot give control to a robot');
 assert.equal(p.bot,false);assert.equal((await state(phone,android)).status,200);
 const laptop=(await call('/api/resume',{code:(await call('/api/my-games',null,web)).body.games[0].code},web)).body;
 assert.equal(preserved(),before);assert.equal((await state(phone,android)).status,409);assert.equal((await state(laptop,web)).status,200);
 assert.equal(s.players.length,2);
});

test('solo games, waiting lobbies and temporary robot takeovers can be resumed; other Google accounts cannot claim them',async t=>{
 const {call,login,state,engine}=await gameServer(t),web=await login('said','web'),android=await login('said'),other=await login('abdo');
 const solo=(await call('/api/create',{name:'Said',mode:'solo',botLevel:'beginner'},android)).body;
 const lobby=(await call('/api/create',{name:'Said'},web)).body;
 const games=(await call('/api/my-games',null,web)).body.games;
 assert(games.some(g=>g.code===solo.code&&g.mode==='solo'));assert(games.some(g=>g.code===lobby.code&&g.phase==='lobby'));
 assert.equal((await call('/api/my-games',null,other)).body.games.length,0);
 assert.equal((await call('/api/resume',{code:solo.code},other)).status,403);
 const s=engine.getRoom(solo.code),p=s.players[0];p.bot=true;p.temporaryBot=true;p.autoPlay=true;
 const resumed=(await call('/api/resume',{code:solo.code},web)).body;
 assert.equal(p.bot,false);assert.equal(p.temporaryBot,undefined);assert.equal(p.autoPlay,undefined);
 assert.equal(s.players.filter(x=>x.bot).length,1);assert.equal((await state(resumed,web)).status,200);
 s.phase='finished';assert(!(await call('/api/my-games',null,web)).body.games.some(g=>g.code===solo.code));
 assert.equal((await call('/api/resume',{code:solo.code},android)).status,400);
 for(const route of ['/api/my-games','/api/resume'])assert.equal((await call(route,route.endsWith('resume')?{code:lobby.code}:null)).status,401);
});


test('solo creates the requested independent opponents at every difficulty and replay preserves them',async t=>{
 const {call,login,state,engine}=await gameServer(t),account=await login('said');
 const expected={beginner:1,easy:1,normal:1,hard:2,expert:3,ultimate:4};
 for(const [botLevel,count] of Object.entries(expected)){
  const response=await call('/api/create',{mode:'solo',botLevel,name:'Said'},account);assert.equal(response.status,200);
  const seat=response.body,s=(await state(seat,account)).body;
  assert.equal(s.players.length,count+1);assert.equal(s.players.filter(p=>p.bot).length,count);
  assert(s.players.filter(p=>p.bot).every(p=>p.botLevel===botLevel&&p.money===1500));
  assert.equal(new Set(s.players.map(p=>p.id)).size,count+1);
  assert.equal(s.phase,'opening');
  const room=engine.getRoom(seat.code);room.phase='playing';room.turn=0;
  for(const bot of room.players.filter(p=>p.bot)){room.debts=[{player:bot.id,receiver:room.players[0].id,amount:100000}];engine.invokeGameAction(room,bot,{type:'bankrupt'});}
  assert.equal((await state(seat,account)).body.soloProgress.completedLevels.at(-1),botLevel);
  engine.invokeGameAction(room,room.players[0],{type:'rematch'});
  const replay=(await state(seat,account)).body;
  assert.equal(replay.players.length,count+1);assert(replay.players.filter(p=>p.bot).every(p=>p.botLevel===botLevel));
 }
 const privateRoom=(await call('/api/create',{botLevel:'ultimate'},account)).body;
 assert.equal((await state(privateRoom,account)).body.players.length,1,'private lobbies stay manual');
});


test('only server-verified solo victories unlock the next level across devices and accounts',async t=>{
 const {call,login,state,engine}=await gameServer(t),web=await login('said','web'),phone=await login('said'),other=await login('abdo');
 const progress=async auth=>(await call('/api/progression',null,auth)).body.progression;
 assert.deepEqual((await progress(web)).unlockedLevels,['beginner']);
 for(const level of ['easy','normal','hard','expert','ultimate']){
  const denied=await call('/api/create',{mode:'solo',botLevel:level,soloVictories:{beginner:{wonAt:Date.now(),gameId:'fake'}}},phone);
  assert.equal(denied.status,403);assert.equal(denied.body.code,'LEVEL_LOCKED');
 }
 const seat=(await call('/api/create',{mode:'solo',botLevel:'beginner'},web)).body;
 assert(!('soloChallenge' in (await state(seat,web)).body));
 assert.equal((await call('/api/action',{...seat,type:'win',phase:'finished',winner:web.account.id},web)).status,400);
 assert.deepEqual((await progress(phone)).completedLevels,[]);
 const room=engine.getRoom(seat.code);room.phase='playing';room.turn=0;
 room.debts=[{player:room.players[1].id,receiver:room.players[0].id,amount:100000}];
 engine.invokeGameAction(room,room.players[1],{type:'bankrupt'});
 const won=(await state(seat,web)).body;
 assert.equal(won.phase,'finished');assert.equal(won.soloUnlock.nextLevel,'easy');
 assert.deepEqual((await progress(phone)).unlockedLevels,['beginner','easy']);
 assert.deepEqual((await progress(other)).unlockedLevels,['beginner']);
 for(let i=0;i<4;i++)await state(seat,phone);
 assert.deepEqual((await progress(web)).completedLevels,['beginner'],'polling never awards a second level');
 const loggedAgain=await login('said');assert.deepEqual(loggedAgain.account.soloProgress.completedLevels,['beginner']);
 const easy=(await call('/api/create',{mode:'solo',botLevel:'easy'},phone)).body;assert(easy.token);
 assert.equal((await call('/api/create',{mode:'solo',botLevel:'normal'},phone)).status,403);
 const easyRoom=engine.getRoom(easy.code);easyRoom.phase='playing';easyRoom.turn=0;easyRoom.debts=[{player:easyRoom.players[1].id,receiver:easyRoom.players[0].id,amount:100000}];engine.invokeGameAction(easyRoom,easyRoom.players[1],{type:'bankrupt'});
 assert.equal((await call('/api/action',{...easy,type:'rematch'},phone)).status,200);
 assert.deepEqual((await progress(web)).completedLevels,['beginner','easy'],'replaying immediately must save the victory before resetting the room');
 const loss=(await call('/api/create',{mode:'solo',botLevel:'beginner'},other)).body;
 const losingRoom=engine.getRoom(loss.code);losingRoom.phase='playing';losingRoom.turn=0;losingRoom.debts=[{player:losingRoom.players[0].id,receiver:losingRoom.players[1].id,amount:100000}];
 assert.equal((await call('/api/action',{...loss,type:'bankrupt'},other)).status,200);
 assert.deepEqual((await progress(other)).completedLevels,[]);
 // A custom friends lobby can be used for practice, but cannot award solo levels.
 const custom=(await call('/api/create',{botLevel:'beginner'},other)).body;
 await call('/api/action',{...custom,type:'addbot'},other);
 const practice=engine.getRoom(custom.code);practice.phase='playing';practice.turn=0;practice.debts=[{player:practice.players[1].id,receiver:practice.players[0].id,amount:100000}];engine.invokeGameAction(practice,practice.players[1],{type:'bankrupt'});await state(custom,other);
 assert.deepEqual((await progress(other)).completedLevels,[]);
 assert.equal((await call('/api/progression')).status,401);
});

test('new games deliver the server-shuffled first card through both web cookies and Android bearer sessions',async t=>{
 const {call,login,state,engine,setDice}=await gameServer(t),web=await login('said','web'),phone=await login('said'),friend=await login('abdo');
 const seen={chance:new Set(),chest:new Set()},codes=new Set();
 for(let match=0;match<24;match++) {
  for(const [kind,positions] of Object.entries({chance:[7,22,36],chest:[2,17,33]})) {
   const account=match%2?phone:web;
   const created=await call('/api/create',{},account);assert.equal(created.status,200);const seat=created.body;codes.add(seat.code);
   assert.equal((await call('/api/join',{code:seat.code},friend)).status,200);
   assert.equal((await call('/api/action',{...seat,type:'start'},account)).status,200);
   const room=engine.getRoom(seat.code);
   assert.equal(room.phase,'opening');assert.equal(room.cardShuffleVersion,4);
   assert.equal(room.decks.chance.length,16);assert.equal(room.decks.chest.length,16);
   const top=room.decks[kind][0].title;seen[kind].add(top);
   // Only select the square and turn in the private fixture. The actual roll,
   // draw, effect and event travel through the authenticated production routes.
   room.phase='playing';room.turn=0;room.players[0].pos=positions[match%3]-2;
   setDice(0);
   try {assert.equal((await call('/api/action',{...seat,type:'roll'},account)).status,200);}
   finally {setDice(null);}
   const publicState=(await state(seat,account)).body;
   assert.equal(publicState.events.find(event=>event.type==='card').title,top);
   assert(!('decks' in publicState));
  }
 }
 assert.equal(codes.size,48);
 for(const kind of ['chance','chest'])assert(seen[kind].size>3,`${kind}: fresh API-created games cannot have a fixed first card`);
});
