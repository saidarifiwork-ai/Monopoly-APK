const {test}=require('node:test');
const assert=require('node:assert/strict');
const auction=require('../auction');
function room(kind='property') {return {phase:'playing',turn:0,rolled:true,debts:[],players:[{id:'a',money:200,pos:0},{id:'b',money:300,pos:0},{id:'c',money:400,pos:0}],tiles:[{name:'Victoria',kind,price:200,owner:''}]};}
test('1 DH wins when everyone else passes; inclusive of the landing player',()=>{
 const s=room();auction.start(s,s.players[0],0);assert.equal(s.auction.respondent,'a');
 auction.respond(s,s.players[0],'bid',1,1);auction.respond(s,s.players[1],'auctionpass',null,2);
 const message=auction.respond(s,s.players[2],'auctionpass',null,3);
 assert.match(message,/1 DH/);assert.equal(s.tiles[0].owner,'a');assert.equal(s.players[0].money,199);assert.equal(s.auction,null);
});
test('highest offer wins across rounds on land, station and utility',()=>{
 for(const kind of ['property','station','utility']){
  const s=room(kind);auction.start(s,s.players[0],0);
  auction.respond(s,s.players[0],'bid',10,1);auction.respond(s,s.players[1],'bid',20,2);auction.respond(s,s.players[2],'bid',30,3);
  auction.respond(s,s.players[0],'auctionpass',null,4);auction.respond(s,s.players[1],'auctionpass',null,5);
  assert.equal(s.tiles[0].owner,'c');assert.equal(s.players[2].money,370);assert.equal(s.players[0].money,200);
 }
});
test('invalid, unaffordable, fractional, stale and out of turn bids are rejected',()=>{
 const s=room();auction.start(s,s.players[0],0);
 for(const amount of [0,-1,1.5,201,NaN,Infinity,'1'])assert.throws(()=>auction.respond(s,s.players[0],'bid',amount,1));
 assert.throws(()=>auction.respond(s,s.players[1],'bid',1,1));
 assert.throws(()=>auction.respond(s,s.players[0],'bid',1,15000));
 auction.respond(s,s.players[0],'bid',10,1);
 assert.throws(()=>auction.respond(s,s.players[1],'bid',10,2));
});
test('15 second timeouts pass and no offer keeps property at the bank',()=>{
 const s=room();auction.start(s,s.players[0],0);
 auction.tick(s,15000);assert.equal(s.auction.respondent,'b');auction.tick(s,30000);auction.tick(s,45000);
 assert.equal(s.auction,null);assert.equal(s.tiles[0].owner,'');assert.equal(s.auctioned,true);
 assert.throws(()=>auction.start(s,s.players[0],45001));
});
test('robots bid within their budgets; no-money players are skipped',()=>{
 const s=room();s.players[0].money=0;s.players[1].bot=true;s.players[2].money=0;
 auction.start(s,s.players[0],0);assert.equal(s.auction.respondent,'b');auction.tick(s,1000);
 assert.equal(s.tiles[0].owner,'b');assert(s.players[1].money>=0);assert(s.players[1].money<300);
});
test('no auction on owned property, jail, debts or pending trade',()=>{
 for(const mutate of [s=>s.tiles[0].owner='b',s=>s.players[0].jail=true,s=>s.debts=[{}],s=>s.offer={}]){
  const s=room();mutate(s);assert.throws(()=>auction.start(s,s.players[0],0));
 }
});
