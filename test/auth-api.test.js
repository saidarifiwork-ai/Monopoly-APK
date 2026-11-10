const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),os=require('node:os');
const {createAuth}=require('../auth');

test('the real game API binds seats to Google accounts, resumes across devices and hides account IDs',async t=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'quartiers-api-auth-'));
 let server;
 const sandbox={__dirname:path.resolve(__dirname,'..'),require(name){
  if(name==='express'){
   const express=require('express');return Object.assign(()=>{const app=express(),listen=app.listen.bind(app);app.listen=(_,cb)=>{server=listen(0,'127.0.0.1',cb);return server;};return app;},express);
  }
  if(name==='fs')return {existsSync:()=>false,writeFileSync:()=>{}};
  if(name==='./auth')return {createAuth:()=>createAuth({clientId:'test.apps.googleusercontent.com',accountsFile:path.join(dir,'accounts.json'),verifyIdToken:async credential=>{
   if(!['said','abdo'].includes(credential))throw Error('Invalid Google token');
   return {getPayload:()=>({sub:credential,name:credential.toUpperCase(),aud:'test.apps.googleusercontent.com',iss:'https://accounts.google.com',exp:Date.now()/1000+3600,picture:'https://lh3.googleusercontent.com/photo'})};
  }})};
  return require(name.startsWith('.')?path.resolve(__dirname,'..',name):name);
 },process:{env:{}},console:{log(){},error:console.error},setInterval:()=>({unref(){}})};
 vm.createContext(sandbox);vm.runInContext(fs.readFileSync(path.join(__dirname,'../server.js'),'utf8'),sandbox);
 await new Promise(r=>server.once('listening',r));
 t.after(()=>{server.closeAllConnections();server.close();fs.rmSync(dir,{recursive:true,force:true});});
 const base='http://127.0.0.1:'+server.address().port;
 async function call(route,data,token){const response=await fetch(base+route,{method:data?'POST':'GET',headers:{...(data?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{})},body:data?JSON.stringify(data):undefined});return {status:response.status,body:await response.json()};}
 async function login(credential){const config=(await call('/api/auth/config')).body;return (await call('/api/auth/google',{credential,nonce:config.nonce,platform:'android'})).body;}
 const said=await login('said'),abdo=await login('abdo');
 assert.equal((await call('/api/create',{name:'Imposteur'})).status,401);
 const host=(await call('/api/create',{name:'Said',accountId:abdo.account.id,picture:'https://attacker.example/photo'},said.token)).body;
 const state=(await call('/api/state?code='+host.code+'&token='+host.token,null,said.token)).body;
 assert.equal(state.players[0].picture,said.account.picture);assert(!('accountId' in state.players[0]));assert(!('token' in state.players[0]));
 assert.equal((await call('/api/state?code='+host.code+'&token='+host.token,null,abdo.token)).status,403);
 assert.equal((await call('/api/action',{...host,type:'start'},abdo.token)).status,403);
 const guest=(await call('/api/join',{code:host.code,name:'Abdo'},abdo.token)).body;
 const secondDevice=await login('said');
 const resumed=(await call('/api/join',{code:host.code,name:'Autre nom'},secondDevice.token)).body;
 assert.equal(resumed.token,host.token,'same Google identity resumes the existing seat');
 const two=(await call('/api/state?code='+host.code+'&token='+host.token,null,said.token)).body;
 assert.equal(two.players.length,2);assert.equal(two.players[1].name,'Abdo');
 await call('/api/action',{...host,type:'start'},said.token);
 assert.equal((await call('/api/join',{code:host.code},secondDevice.token)).body.token,host.token,'a started game remains resumable');
 await call('/api/auth/logout',{},said.token);
 assert.equal((await call('/api/action',{...host,type:'roll'},said.token)).status,401);
 assert.equal((await call('/api/state?code='+guest.code+'&token='+guest.token,null,abdo.token)).status,200);
});
