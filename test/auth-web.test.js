const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
function browser({readyAt=0,online=true}={}) {
 let clock=0,calls=0,id=0,googleCalls=0;
 const timers=new Map(),events=new Map(),nodes=new Map();
 const storage=new Map([['quartiers-google-known','said'],['quartiers','saved-game']]);
 const profile={id:'said',name:'Said',picture:''};
 const document={hidden:false,documentElement:{classList:{contains:()=>false}},
  querySelector(selector){if(!nodes.has(selector))nodes.set(selector,{hidden:false,disabled:false,textContent:'',value:'',src:'',replaceChildren(){}});return nodes.get(selector);},
  addEventListener:(event,fn)=>events.set(event,fn),head:{append(){googleCalls++;throw Error('A valid remembered session must not load Google');}}};
 const window={addEventListener:(event,fn)=>events.set(event,fn),dispatchEvent(){}};
 const navigator={onLine:online};
 const sandbox={window,document,navigator,AbortSignal,CustomEvent:class{constructor(type,init){this.type=type;Object.assign(this,init);}},
  localStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},
  setTimeout:(fn,delay)=>{const key=++id;timers.set(key,{fn,at:clock+delay});return key;},clearTimeout:key=>timers.delete(key),
  fetch:async path=>{calls++;assert.equal(path,'/api/auth/me');const ok=navigator.onLine&&clock>=readyAt;
   return {ok,status:ok?200:503,json:async()=>ok?{account:profile}:{code:'STORAGE_UNAVAILABLE',error:'Waking up'}};}};
 vm.createContext(sandbox);vm.runInContext(fs.readFileSync(require.resolve('../auth-web.js'),'utf8'),sandbox);
 return {window,document,navigator,events,storage,timers,get calls(){return calls;},get googleCalls(){return googleCalls;},get clock(){return clock;},
  async next(){const [key,timer]=[...timers].sort((a,b)=>a[1].at-b[1].at)[0];timers.delete(key);clock=timer.at;timer.fn();await window.QuartiersAuth.ready;}};
}
test('the web waits through a long server wake-up and restores the account without asking Google',async()=>{
 const b=browser({readyAt:120000});await b.window.QuartiersAuth.ready;
 while(b.timers.size&&!b.window.QuartiersAuth.allowed)await b.next();
 assert(b.calls>3);assert(b.clock>=120000);assert.equal(b.googleCalls,0);
 assert.equal(b.window.QuartiersAuth.account.id,'said');assert.equal(b.window.QuartiersAuth.pending,false);
 assert.equal(b.storage.get('quartiers'),'saved-game');assert.equal(b.timers.size,0);
});
test('background and offline pages retain their identity and retry when visible or online again',async()=>{
 const b=browser({readyAt:5000});await b.window.QuartiersAuth.ready;b.document.hidden=true;
 await b.next();assert.equal(b.calls,1);assert.equal(b.timers.size,0);assert.equal(b.window.QuartiersAuth.pending,true);
 b.document.hidden=false;b.events.get('visibilitychange')();await b.window.QuartiersAuth.ready;
 assert.equal(b.window.QuartiersAuth.allowed,true);assert.equal(b.googleCalls,0);
 const offline=browser({online:false});await offline.window.QuartiersAuth.ready;
 assert.equal(offline.timers.size,0);assert.equal(offline.storage.get('quartiers-google-known'),'said');
 offline.navigator.onLine=true;offline.events.get('online')();await offline.window.QuartiersAuth.ready;
 assert.equal(offline.window.QuartiersAuth.allowed,true);assert.equal(offline.googleCalls,0);
});
