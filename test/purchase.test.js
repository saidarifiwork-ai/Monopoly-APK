const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
function engine(){
 const sandbox={__dirname:path.resolve(__dirname,'..'),require(name){
  if(name==='express') {const express=require('express');return Object.assign(()=>{const app=express();app.listen=()=>{};return app},express)}
  if(name==='fs')return {existsSync:()=>false,writeFileSync:()=>{}};
  return require(name.startsWith('.')?path.resolve(__dirname,'..',name):name);
 },process:{env:{}},console,setInterval:()=>({unref(){}}),Math:Object.assign(Object.create(Math),{random:()=>0})};
 vm.createContext(sandbox);
 vm.runInContext(fs.readFileSync(path.join(__dirname,'../server.js'),'utf8')+'\nglobalThis.engine={invokeGameAction,invokeBotStep,newTiles,newPlayer};',sandbox);
 return sandbox.engine;
}
function fixture(e){const p=e.newPlayer('Saïd'),friend=e.newPlayer('Ami');p.id='a';friend.id='b';p.money=1;p.pos=4;const s={phase:'playing',turn:0,players:[p,friend],tiles:e.newTiles(),rolled:false,deals:[],debts:[],offer:null,log:[],events:[],eventSeq:0};s.tiles[5].owner=p.id;return {p,s};}
test('cash-poor arrival allows mortgage at half value, then normal purchase',()=>{
 const e=engine(),{p,s}=fixture(e);
 e.invokeGameAction(s,p,{type:'roll'});
 assert.equal(p.pos,6);assert.equal(s.auction,undefined);assert.equal(p.money,1);
 assert.throws(()=>e.invokeGameAction(s,p,{type:'buy'}));
 e.invokeGameAction(s,p,{type:'mortgage',index:5});
 assert.equal(p.money,1+s.tiles[5].price/2);assert.equal(s.tiles[5].mortgaged,true);
 e.invokeGameAction(s,p,{type:'buy'});assert.equal(s.tiles[6].owner,p.id);assert.equal(s.auction,undefined);
});
test('declining explicitly or ending without buying still opens auctions',()=>{
 for(const type of ['auction','end']){const e=engine(),{p,s}=fixture(e);e.invokeGameAction(s,p,{type:'roll'});e.invokeGameAction(s,p,{type});assert.equal(s.auction.index,6);}
});

test('manual auto persists through heartbeats, runs real bot actions, and rejects client bypasses',()=>{
 const e=engine(),{p,s}=fixture(e);
 e.invokeGameAction(s,p,{type:'autoplay',enabled:true});
 assert.equal(p.bot,true);assert.equal(p.autoPlay,true);
 assert.throws(()=>e.invokeGameAction(s,p,{type:'roll',botAction:true}));
 s.botNext=0;e.invokeBotStep(s);assert.equal(p.pos,6);assert.equal(s.rolled,true);
 e.invokeGameAction(s,p,{type:'autoplay',enabled:false});assert.equal(p.bot,false);assert.equal(p.autoPlay,undefined);
 e.invokeGameAction(s,p,{type:'mortgage',index:5});assert.equal(p.money,101);
});

test('refusing an offer broadcasts one sound event; cancel and invalid repeat do not',()=>{
 const e=engine(),{p,s}=fixture(e),other=s.players[1];
 s.offer={buyer:other.id,seller:p.id,respondent:p.id,index:5};
 e.invokeGameAction(s,p,{type:'rejectoffer'});
 assert.equal(s.offer,null);assert.equal(s.events.length,1);
 assert.equal(s.events[0].type,'offer-rejected');assert.equal(s.events[0].playerId,p.id);
 assert.throws(()=>e.invokeGameAction(s,p,{type:'rejectoffer'}));assert.equal(s.events.length,1);
 s.offer={buyer:other.id,seller:p.id,respondent:p.id,index:5};
 e.invokeGameAction(s,other,{type:'canceloffer'});assert.equal(s.events.length,1);
});
