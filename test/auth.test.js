const {test}=require('node:test');
const assert=require('node:assert/strict');
const express=require('express'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {createAuth}=require('../auth');
const CLIENT='test-client.apps.googleusercontent.com';
async function harness(t,{configured=true,claims={},now=Date.now}={}) {
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'quartiers-auth-'));
 let current={sub:'google-said',name:'Said Google',picture:'https://lh3.googleusercontent.com/a',aud:CLIENT,
  iss:'https://accounts.google.com',exp:Math.floor(Date.now()/1000)+3600,...claims};
 let server,base,activeClient=configured?CLIENT:'';
 async function boot(){
  const app=express();app.use(express.json());
  createAuth({clientId:activeClient,accountsFile:path.join(dir,'accounts.json'),now,verifyIdToken:async credential=>{
   if(credential==='forged')throw Error('Invalid signature');return {getPayload:()=>current};
  }}).install(app);
  app.post('/api/create',(req,res)=>res.json({account:req.account}));
  server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
  base='http://127.0.0.1:'+server.address().port;
 }
 await boot();
 t.after(()=>{server.closeAllConnections();server.close();fs.rmSync(dir,{recursive:true,force:true});});
 async function restart(clientId){if(clientId)activeClient=clientId;server.closeAllConnections();await new Promise(r=>server.close(r));await boot();}
 async function request(route,data,headers={}){
  const r=await fetch(base+route,{method:data?'POST':'GET',headers:{...(data?{'Content-Type':'application/json'}:{}),...headers},body:data?JSON.stringify(data):undefined});
  return {status:r.status,body:await r.json(),cookie:r.headers.get('set-cookie')};
 }
 async function login(platform='android'){
  const config=await request('/api/auth/config');current={...current,nonce:config.body.nonce};
  return request('/api/auth/google',{credential:'valid',nonce:config.body.nonce,platform});
 }
 return {request,login,restart,setClaims:value=>current={...current,...value},dir,get base(){return base;}};
}

test('authentication fails closed before Google is configured and anonymous API access is refused',async t=>{
 const h=await harness(t,{configured:false});
 assert.equal((await h.request('/api/auth/config')).body.configured,false);
 assert.equal((await h.request('/api/create',{})).status,503);
 const ready=await harness(t);
 for(const [route,data] of [['/api/create',{}],['/api/join',{}],['/api/state',null],['/api/action',{}]]) assert.equal((await ready.request(route,data)).status,401);
});
test('verified name/photo create the same account, a private web cookie and a revocable native bearer',async t=>{
 const h=await harness(t),first=await h.login();assert.equal(first.status,200);assert.equal(first.body.account.name,'Said Google');
 assert.equal(first.body.account.picture,'https://lh3.googleusercontent.com/a');assert(first.cookie.includes('HttpOnly'));assert(first.cookie.includes('SameSite=Lax'));
 const headers={Authorization:'Bearer '+first.body.token};
 assert.equal((await h.request('/api/create',{},headers)).body.account.id,first.body.account.id);
 const web=await h.login('web');assert.equal(web.body.account.id,first.body.account.id);assert(!web.body.token);
 assert.equal((await h.request('/api/auth/me',null,{Cookie:web.cookie.split(';')[0]})).status,200);
 await h.request('/api/auth/logout',{},headers);assert.equal((await h.request('/api/create',{},headers)).status,401);
});
test('forged credentials, wrong audience, expiry, issuer and web nonce are rejected',async t=>{
 for(const claims of [{aud:'other-client'}, {iss:'https://attacker.example'}, {exp:0}, {sub:''}]){
  const h=await harness(t,{claims});assert.equal((await h.login()).status,401);
 }
 const h=await harness(t),config=(await h.request('/api/auth/config')).body;
 assert.equal((await h.request('/api/auth/google',{credential:'forged',nonce:config.nonce,platform:'android'})).status,401);
 const second=(await h.request('/api/auth/config')).body;
 assert.equal((await h.request('/api/auth/google',{credential:'valid',nonce:second.nonce,platform:'web'})).status,401);
 assert.equal((await h.request('/api/auth/google',{credential:'valid',nonce:second.nonce,platform:'android'})).status,401,'a challenge cannot be replayed');
});
test('profile URLs cannot inject arbitrary remote content and cross-origin login is blocked',async t=>{
 const h=await harness(t,{claims:{picture:'https://attacker.example/avatar'}});
 assert.equal((await h.login()).body.account.picture,'');
 const config=(await h.request('/api/auth/config')).body;
 assert.equal((await h.request('/api/auth/google',{credential:'valid',nonce:config.nonce,platform:'android'},{Origin:'https://attacker.example'})).status,403);
});


test('web cookies and native bearers survive a server restart; only hashes are persisted',async t=>{
 const h=await harness(t),native=await h.login(),web=await h.login('web');
 const saved=fs.readFileSync(path.join(h.dir,'accounts.json.sessions'),'utf8');
 assert(!saved.includes(native.body.token));assert(saved.includes(native.body.account.id));
 assert(web.cookie.includes('Max-Age=7776000'));assert(web.cookie.includes('Expires='));
 const headers={Authorization:'Bearer '+native.body.token},cookies={Cookie:web.cookie.split(';')[0]};
 await h.restart();
 assert.equal((await h.request('/api/auth/me',null,headers)).body.account.id,native.body.account.id);
 assert.equal((await h.request('/api/auth/me',null,cookies)).body.account.id,web.body.account.id);
 await h.request('/api/auth/logout',{},headers);await h.restart();
 assert.equal((await h.request('/api/auth/me',null,headers)).status,401,'logout persists across restarts');
 assert.equal((await h.request('/api/auth/me',null,cookies)).status,200,'another device stays signed in');
});

test('inactive sessions expire after ninety days and are not revived by restarting',async t=>{
 let clock=Date.now();const h=await harness(t,{now:()=>clock}),login=await h.login();
 clock+=91*24*60*60*1000;await h.restart();
 assert.equal((await h.request('/api/auth/me',null,{Authorization:'Bearer '+login.body.token})).status,401);
});


test('a saved session is bound to the Google client that originally verified it',async t=>{
 const h=await harness(t),login=await h.login();
 await h.restart('other-client.apps.googleusercontent.com');
 assert.equal((await h.request('/api/auth/me',null,{Authorization:'Bearer '+login.body.token})).status,401);
});

const DAY = 24*60*60*1000;
test('daily activity renews the same web cookie and native session without Google, including after restart', async t => {
 let clock=Date.now();const start=clock,h=await harness(t,{now:()=>clock});
 const native=await h.login(),web=await h.login('web');
 const headers={Authorization:'Bearer '+native.body.token},cookies={Cookie:web.cookie.split(';')[0]};
 for(const day of [1,25,50,75,100,125]) {
  clock=start+day*DAY;
  await h.restart();
  const a=await h.request('/api/auth/me',null,headers),b=await h.request('/api/auth/me',null,cookies);
  assert.equal(a.status,200);assert.equal(b.status,200);
  assert(b.cookie.includes(web.cookie.split(';')[0]));assert(b.cookie.includes('Max-Age=7776000'));
  assert.equal(b.body.account.id,native.body.account.id);
 }
 const saved=JSON.parse(fs.readFileSync(path.join(h.dir,'accounts.json.sessions'),'utf8'));
 assert(saved.sessions.every(([,s])=>s.expires===clock+90*DAY&&s.absoluteExpires===start+365*DAY));
 assert(!JSON.stringify(saved).includes(native.body.token));
 assert.equal((await h.request('/api/auth/me',null,cookies)).cookie,null,'renew at most daily');
 await h.request('/api/auth/logout',{},headers);await h.restart();
 assert.equal((await h.request('/api/auth/me',null,headers)).status,401);
 assert.equal((await h.request('/api/auth/me',null,cookies)).status,200);
});
test('renewable sessions retain an absolute one-year limit', async t => {
 let clock=Date.now();const start=clock,h=await harness(t,{now:()=>clock}),login=await h.login('web');
 const cookies={Cookie:login.cookie.split(';')[0]};
 for(let day=30;day<=360;day+=30) {
  clock=start+day*DAY;
  const response=await h.request('/api/auth/me',null,cookies);assert.equal(response.status,200);
  const expires=/Expires=([^;]+)/.exec(response.cookie)[1];
  assert(Date.parse(expires)<=start+365*DAY);
 }
 clock=start+365*DAY;await h.restart();
 assert.equal((await h.request('/api/auth/me',null,cookies)).status,401);
});
test('legacy thirty-day sessions are upgraded without replacing credentials or reviving expired sessions', async t => {
 let clock=Date.now();const h=await harness(t,{now:()=>clock}),login=await h.login();
 const file=path.join(h.dir,'accounts.json.sessions'),saved=JSON.parse(fs.readFileSync(file,'utf8'));
 for(const [,s] of saved.sessions) {s.expires=clock+30*DAY;delete s.createdAt;delete s.renewedAt;delete s.absoluteExpires;}
 fs.writeFileSync(file,JSON.stringify(saved));clock+=25*DAY;await h.restart();
 const headers={Authorization:'Bearer '+login.body.token};
 assert.equal((await h.request('/api/auth/me',null,headers)).status,200);
 clock+=31*DAY;await h.restart();
 assert.equal((await h.request('/api/auth/me',null,headers)).status,200);
 clock+=91*DAY;await h.restart();
 assert.equal((await h.request('/api/auth/me',null,headers)).status,401);
});

test('concurrent activity coalesces renewal and a failed renewal preserves the committed session', async t => {
 let clock=Date.now(),writes=0,fail=false;
 const saved={accounts:{},sessions:{version:1,sessions:[]}};
 const store={auth:saved,save:async (_,value)=>{writes++;if(fail)throw Error('offline');Object.assign(saved,JSON.parse(JSON.stringify(value)));}};
 const app=express();app.use(express.json());
 createAuth({clientId:CLIENT,persistence:store,now:()=>clock,verifyIdToken:async()=>({getPayload:()=>({sub:'said',name:'Said',aud:CLIENT,iss:'https://accounts.google.com',exp:clock/1000+3600})})}).install(app);
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
 t.after(()=>{server.closeAllConnections();server.close();});
 const base='http://127.0.0.1:'+server.address().port;
 const config=await(await fetch(base+'/api/auth/config')).json();
 const login=await(await fetch(base+'/api/auth/google',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({credential:'verified',nonce:config.nonce,platform:'android'})})).json();
 const headers={Authorization:'Bearer '+login.token},before=saved.sessions.sessions[0][1].expires;
 clock+=2*DAY;fail=true;
 const unavailable=await fetch(base+'/api/auth/me',{headers});
 assert.equal(unavailable.status,503);assert.equal(unavailable.headers.get('set-cookie'),null);
 assert.equal(saved.sessions.sessions[0][1].expires,before);
 fail=false;writes=0;
 const results=await Promise.all(Array.from({length:8},()=>fetch(base+'/api/auth/me',{headers})));
 assert(results.every(r=>r.status===200));assert.equal(writes,1);
 assert.equal(saved.sessions.sessions[0][1].expires,clock+90*DAY);
});
