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
 vm.runInContext(fs.readFileSync(path.join(__dirname,'../server.js'),'utf8')+'\nglobalThis.engine={invokeGameAction,invokeBotStep,newTiles,newPlayer,pay,settleDebts};',sandbox);
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

test('payment animation is emitted only when debt is paid, at its original square',()=>{
 const e=engine(),{p,s}=fixture(e);p.pos=6;p.money=10;
 e.pay(s,p,50,s.players[1]);assert.equal(s.events.length,0);assert.equal(p.money,10);
 p.pos=7;p.money=70;e.settleDebts(s);assert.equal(p.money,20);
 const event=s.events.find(x=>x.type==='payment');assert.equal(event.amount,50);assert.equal(event.tileIndex,6);
});

test('host rematch resets the game but preserves the room, players and sessions',()=>{
 const e=engine(),{p,s}=fixture(e),friend=s.players[1];s.code='ROOM';s.host=p.id;s.phase='finished';s.gameRound=2;s.eventSeq=19;
 p.money=2;p.out=true;p.jail=true;p.pos=18;friend.money=9000;s.tiles[5].level=3;s.debts=[{player:p.id,amount:42}];s.offer={buyer:p.id};s.auction={index:5};s.decks={chance:[]};s.turnOrder=[1,0];
 const tokens=s.players.map(x=>x.token);assert.throws(()=>e.invokeGameAction(s,friend,{type:'rematch'}));
 e.invokeGameAction(s,p,{type:'rematch'});
 assert.equal(s.phase,'lobby');assert.equal(s.code,'ROOM');assert.equal(s.host,'a');assert.equal(s.gameRound,3);assert.equal(s.eventSeq,19);
 assert.equal(s.players.length,2);assert.equal(s.players[0].token,tokens[0]);assert.equal(s.players[1].token,tokens[1]);
 for(const player of s.players){assert.equal(player.money,1500);assert.equal(player.pos,0);assert.equal(player.out,false);assert.equal(player.jail,false)}
 assert.equal(s.tiles[5].owner,'');assert.equal(s.tiles[5].level,0);assert.equal(s.debts.length,0);assert.equal(s.offer,null);assert.equal(s.auction,undefined);assert.equal(s.decks,undefined);assert.equal(s.turnOrder,undefined);
 assert.throws(()=>e.invokeGameAction(s,s.players[0],{type:'rematch'}));
 e.invokeGameAction(s,s.players[0],{type:'start'});assert.equal(s.phase,'opening');
});
