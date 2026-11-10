const {test}=require('node:test');const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const ai=require('../bot-ai');
function engine(rng){const sandbox={Math:Object.assign(Object.create(Math),{random:rng||Math.random}),__dirname:path.resolve(__dirname,'..'),require(name){if(name==='express'){const express=require('express');return Object.assign(()=>{const app=express();app.listen=()=>{};return app},express)}if(name==='fs')return {existsSync:()=>false,writeFileSync:()=>{}};return require(name.startsWith('.')?path.resolve(__dirname,'..',name):name)},process:{env:{}},console,setInterval:()=>({unref(){}})};vm.createContext(sandbox);vm.runInContext(fs.readFileSync(path.join(__dirname,'../server.js'),'utf8')+'\nglobalThis.e={newTiles,newPlayer,invokeGameAction,invokeBotStep};',sandbox);return sandbox.e;}
function fixture(level='ultimate'){const e=engine();const p=e.newPlayer('Robot'),other=e.newPlayer('Ami');p.id='a';other.id='b';p.botLevel=level;const s={phase:'playing',turn:0,rolled:true,players:[p,other],tiles:e.newTiles(),debts:[],offer:null,log:[],events:[],eventSeq:0,dice:[3,4],host:p.id,botPhase:'buy'};return {e,p,other,s};}
test('six valid levels; unknown levels rejected and old robots default to Normal',()=>{assert.equal(ai.LEVELS.length,6);for(const {id} of ai.LEVELS)assert.equal(ai.normalize(id),id);for(const id of [null,0,'Ultimate','bad',{}])assert.throws(()=>ai.normalize(id));assert.equal(ai.profile({}).id,'normal');});
test('beginner can miss an affordable purchase; higher levels purchase deliberately',()=>{const {p,s}=fixture('beginner');assert.equal(ai.shouldBuy(s,p,s.tiles[1],()=>.9),false);p.botLevel='ultimate';assert.equal(ai.shouldBuy(s,p,s.tiles[1],()=>.9),true);});
test('advanced robots value group completion and blocking opponents',()=>{const {p,other,s}=fixture();const base=ai.value(s,p,s.tiles[1]);s.tiles[3].owner=p.id;assert(ai.value(s,p,s.tiles[1])>base);s.tiles[3].owner=other.id;assert(ai.value(s,p,s.tiles[1])>base);});
test('Ultimate reserves extra cash for likely opposing rents and bids within its budget',()=>{const {p,other,s}=fixture();p.pos=0;p.money=500;const safe=ai.reserve(s,p);s.tiles[6].owner=other.id;s.tiles[6].level=4;assert(ai.reserve(s,p)>safe);for(const {id} of ai.LEVELS){p.botLevel=id;const limit=ai.bidLimit(s,p,s.tiles[1]);assert(limit>=0&&limit<=p.money);} });
test('building respects ownership, mortgages, balance and funds; beginners do not build',()=>{const {p,s}=fixture();for(const i of [1,3])s.tiles[i].owner=p.id;assert([1,3].includes(ai.buildIndex(s,p)));s.tiles[1].level=1;assert.equal(ai.buildIndex(s,p),3);s.tiles[1].mortgaged=true;assert.equal(ai.buildIndex(s,p),-1);s.tiles[1].mortgaged=false;p.money=0;assert.equal(ai.buildIndex(s,p),-1);p.money=1500;p.botLevel='beginner';assert.equal(ai.buildIndex(s,p),-1);});
test('debt strategy avoids illegal mortgages of groups with houses and preserves income',()=>{const {p,s}=fixture();s.tiles[1].owner=p.id;s.tiles[3].owner=p.id;s.tiles[1].level=1;assert.deepEqual(ai.debtAction(s,p),{type:'sellhouse',index:1});s.tiles[5].owner=p.id;s.tiles[1].level=3;s.tiles[3].level=3;s.players[1].pos=35;s.debts=[{player:p.id,amount:p.money+100}];assert.deepEqual(ai.debtAction(s,p),{type:'mortgage',index:5});});
test('trade decisions distinguish buying from selling and refuse unaffordable deals',()=>{const {p,other,s}=fixture();s.tiles[1].owner=other.id;p.money=1;assert.equal(ai.tradeDecision(s,p,{index:1,buyer:p.id,seller:other.id,amount:60,offered:[]}).type,'rejectoffer');s.tiles[1].owner=p.id;s.tiles[3].owner=p.id;assert.equal(ai.tradeDecision(s,p,{index:1,buyer:other.id,seller:p.id,amount:10,offered:[]}).type,'rejectoffer');});
test('host assigns each robot separately, rejects bad levels, and replay preserves levels',()=>{const {e,p,s}=fixture();s.phase='lobby';e.invokeGameAction(s,p,{type:'addbot',botLevel:'ultimate'});e.invokeGameAction(s,p,{type:'addbot',botLevel:'beginner'});assert.equal(s.players[2].botLevel,'ultimate');assert.equal(s.players[3].botLevel,'beginner');assert.throws(()=>e.invokeGameAction(s,p,{type:'addbot',botLevel:'cheat'}));s.phase='finished';e.invokeGameAction(s,p,{type:'rematch'});assert.equal(s.players[2].botLevel,'ultimate');assert.equal(s.players[3].botLevel,'beginner');});
test('every bot level performs real legal server actions without extra money or dice privileges',()=>{for(const {id} of ai.LEVELS){const {e,p,s}=fixture(id);p.bot=true;p.pos=1;const before=p.money;e.invokeBotStep(s);if(s.tiles[1].owner===p.id)assert.equal(p.money,before-60);for(let n=0;n<8&&s.turn===0;n++){s.botNext=0;e.invokeBotStep(s);}assert(s.players.every(x=>x.money>=0));assert(s.turn!==0||s.auction);}});

test('advanced bots restore mortgaged assets only when cash reserves allow it',()=>{const {p,s}=fixture();s.tiles[1].owner=p.id;s.tiles[1].mortgaged=true;assert.equal(ai.unmortgageIndex(s,p),1);p.money=10;assert.equal(ai.unmortgageIndex(s,p),-1);p.money=1500;p.botLevel='beginner';assert.equal(ai.unmortgageIndex(s,p),-1);});

test('Expert and Ultimate pay to leave jail when El Jadida completes Safi/Essaouira',()=>{
 for(const level of ['expert','ultimate']){const {p,s}=fixture(level);p.pos=10;p.jail=true;p.money=1000;s.tiles[18].owner=p.id;s.tiles[19].owner=p.id;
 assert.equal(ai.jailDecision(s,p),'payjail');p.jailCards=[{deck:'chest',card:{}}];assert.equal(ai.jailDecision(s,p),'usejail');}
});
test('advanced prison strategy keeps cash when poor or when the next area is dangerous',()=>{
 const {p,s,other}=fixture();p.pos=10;p.jail=true;p.money=20;assert.equal(ai.jailDecision(s,p),'roll');
 p.money=1500;for(let i=12;i<=22;i++){s.tiles[i].owner=other.id;s.tiles[i].mortgaged=false;s.tiles[i].kind='property';s.tiles[i].level=5;s.tiles[i].rents=[10,20,100,400,800,2000];}
 assert.equal(ai.jailDecision(s,p),'roll');p.jailCards=[{deck:'chest',card:{}}];assert.equal(ai.jailDecision(s,p),'roll');
});
test('group completion permits a flexible reserve, without buying beyond the cash available',()=>{
 const {p,s}=fixture('expert');p.money=300;s.tiles[18].owner=p.id;s.tiles[19].owner=p.id;assert(ai.shouldBuy(s,p,s.tiles[16],()=>0));p.money=179;assert(!ai.shouldBuy(s,p,s.tiles[16],()=>0));
});
test('the bot uses the real payjail action and pays exactly 50 before moving',()=>{
 const e=engine(()=>0),p=e.newPlayer('Robot'),other=e.newPlayer('Ami');p.id='a';other.id='b';p.bot=true;p.botLevel='ultimate';p.pos=10;p.jail=true;p.money=1000;
 const s={phase:'playing',turn:0,rolled:false,players:[p,other],tiles:e.newTiles(),debts:[],offer:null,log:[],events:[],eventSeq:0,dice:[3,4],host:p.id,botNext:0};s.tiles[18].owner=p.id;s.tiles[19].owner=p.id;e.invokeBotStep(s);assert(!p.jail);assert.equal(p.money,950);assert.equal(p.pos,12);assert.deepEqual(Array.from(s.dice),[1,1]);
});
test('two Ultimate opponents compete with each other and never pool their cash',()=>{
 const auction=require('../auction');const s={phase:'playing',turn:0,rolled:true,offer:null,debts:[],players:[{id:'human',pos:0,money:0},{id:'one',pos:0,money:1000,bot:true,botLevel:'ultimate'},{id:'two',pos:0,money:1000,bot:true,botLevel:'ultimate'}],tiles:[{name:'Test',price:200,kind:'property',group:0,owner:''}]};
 auction.start(s,s.players[0],0);const bidding=new Set();for(let n=1;s.auction&&n<300;n++){const who=s.auction.respondent,before=s.auction.amount;auction.tick(s,n*500);if(!s.auction||s.auction.amount>before)bidding.add(who);}
 assert(!s.auction);assert(bidding.has('one')&&bidding.has('two'));const winner=s.players.find(p=>p.id===s.tiles[0].owner);assert(winner&&winner.money<1000);const loser=s.players.find(p=>p.bot&&p!==winner);assert.equal(loser.money,1000);
 const {p,s:room,other}=fixture();room.tiles[3].owner=other.id;const againstHuman=ai.value(room,p,room.tiles[1]);other.bot=true;other.botLevel='ultimate';assert.equal(ai.value(room,p,room.tiles[1]),againstHuman);
});

test('reserve adapts between an open board, dangerous rents and own income',()=>{
 const {p,s,other}=fixture();const open=ai.reserve(s,p);
 for(const t of s.tiles)if(t.price>0)t.owner=other.id;
 const closed=ai.reserve(s,p);assert(closed>open);
 s.tiles[6].level=4;assert(ai.reserve(s,p)>closed);
 for(const t of s.tiles)if(t.price>0)t.owner=p.id;
 assert(ai.reserve(s,p)<closed);
});
test('advanced investment compares building income with redeeming an idle property',()=>{
 const {p,s}=fixture();s.tiles[1].owner=p.id;s.tiles[3].owner=p.id;
 s.tiles[1].level=2;s.tiles[3].level=2;s.tiles[5].owner=p.id;s.tiles[5].mortgaged=true;
 const decision=ai.investmentAction(s,p);assert.equal(decision.type,'build');assert([1,3].includes(decision.index));
 p.money=0;assert.equal(ai.investmentAction(s,p),null);
});
test('robots can seek the missing city with a legal affordable offer and a cooldown',()=>{
 const {p,s,other}=fixture();p.money=1000;s.tiles[18].owner=p.id;s.tiles[19].owner=p.id;s.tiles[16].owner=other.id;
 const before=JSON.stringify(s);const offer=ai.offerPlan(s,p,1000000);assert(offer);assert.equal(offer.index,16);assert(offer.amount>0&&offer.amount<p.money);assert.equal(JSON.stringify(s),before);
 for(const i of offer.offered)assert.equal(s.tiles[i].owner,p.id);
 p.lastBotOfferAt=1000000;assert.equal(ai.offerPlan(s,p,1001000),null);
});
test('trade analysis considers the whole exchange and is equally cautious with a bot opponent',()=>{
 const {p,s,other}=fixture();s.tiles[1].owner=other.id;s.tiles[3].owner=p.id;s.tiles[6].owner=p.id;s.tiles[8].owner=p.id;s.tiles[9].owner=p.id;
 const cheap={index:1,buyer:p.id,seller:other.id,amount:1,offered:[]};assert.equal(ai.tradeDecision(s,p,cheap).type,'acceptoffer');
 const costly={...cheap,amount:2000};assert.notEqual(ai.tradeDecision(s,p,costly).type,'acceptoffer');
 const exchange={...cheap,offered:[6]};const human=ai.tradeDecision(s,p,exchange);other.bot=true;assert.deepEqual(ai.tradeDecision(s,p,exchange),human);
 assert(ai.tradeValues(s,p,exchange).fair<ai.tradeValues(s,p,cheap).fair);
});
test('bot-initiated offers expire and bot counteroffers cannot loop forever',()=>{
 const {e,p,s,other}=fixture();p.bot=true;other.bot=true;other.botLevel='ultimate';
 s.tiles[1].owner=other.id;s.offer={index:1,buyer:p.id,seller:other.id,respondent:other.id,amount:50,offered:[],botInitiated:true,botDeadline:Date.now()-1};e.invokeBotStep(s);assert.equal(s.offer,null);
 s.offer={index:1,buyer:p.id,seller:other.id,respondent:other.id,amount:140,offered:[],botCounterRounds:2};
 // A complete group is protected, so an insufficient nontrivial offer would be countered.
 s.tiles[3].owner=other.id;s.offer.amount=300;e.invokeBotStep(s);assert.equal(s.offer,null);
});
test('the real bot turn can initiate a negotiation for its missing group member',()=>{
 const {e,p,s,other}=fixture();p.bot=true;p.money=1000;p.pos=20;s.botPhase='build';s.botNext=0;
 s.tiles[18].owner=p.id;s.tiles[19].owner=p.id;s.tiles[16].owner=other.id;
 e.invokeBotStep(s);assert(s.offer);assert.equal(s.offer.buyer,p.id);assert.equal(s.offer.seller,other.id);assert.equal(s.offer.index,16);assert(s.offer.botDeadline>Date.now());assert.equal(s.tiles[16].owner,other.id);
});
test('seeded multi-bot games keep decisions legal through auctions, debt, trade and construction',()=>{
 for(const seed of [7123,9187]){
  let random=seed;const e=engine(()=>{random=(Math.imul(random,1664525)+1013904223)>>>0;return random/4294967296});
  const players=[e.newPlayer('Expert'),e.newPlayer('Ultime'),e.newPlayer('Normal')];players.forEach((p,i)=>{p.id='p'+i;p.botLevel=['expert','ultimate','normal'][i]});
  const s={phase:'lobby',host:players[0].id,players,tiles:e.newTiles(),log:[],events:[],eventSeq:0,debts:[],offer:null,turn:0};
  e.invokeGameAction(s,players[0],{type:'start'});players.forEach(p=>p.bot=true);
  for(let step=0;step<800&&s.phase!=='finished';step++){
   s.botNext=0;if(s.auction)s.auction.deadline=Date.now()+1000;
   e.invokeBotStep(s);
   for(const t of s.tiles){assert(t.level>=0&&t.level<=5);assert(!t.owner||players.some(p=>p.id===t.owner));}
   for(const p of players)assert(p.money>=0&&Number.isFinite(p.money));
  }
  assert(s.eventSeq>50,'the simulation must progress beyond the opening rolls');
  assert(s.tiles.filter(t=>t.owner).length>=3,'bots must make real acquisitions');
 }
});

test('a trade between other players does not skip the current bot purchase decision',()=>{
 const {e,p,other,s}=fixture();p.bot=true;s.botPhase='buy';const buyer=e.newPlayer('Acheteur');buyer.id='c';s.players.push(buyer);s.tiles[1].owner=other.id;
 e.invokeGameAction(s,buyer,{type:'offer',index:1,amount:100});e.invokeGameAction(s,other,{type:'acceptoffer'});
 assert.equal(s.botPhase,'buy');assert.equal(s.tiles[1].owner,buyer.id);
});

test('human auto and disconnected replacements always reject even a generous offer',()=>{
 for(const flags of [{autoPlay:true,temporaryBot:true},{temporaryBot:true}]){
  const {e,p,other,s}=fixture();p.bot=true;Object.assign(p,flags);s.tiles[1].owner=p.id;
  assert.deepEqual(ai.tradeDecision(s,p,{index:1,seller:p.id,buyer:other.id,amount:100000,offered:[]}),{type:'rejectoffer'});
  const before=[p.money,other.money];e.invokeGameAction(s,other,{type:'offer',index:1,amount:1000});
  assert.equal(s.offer,null);assert.equal(s.tiles[1].owner,p.id);assert.deepEqual([p.money,other.money],before);
  assert.equal(s.events.at(-1).type,'offer-rejected');
 }
});
test('pending sales and purchases are refused when either participant goes auto, including an incoming counteroffer',()=>{
 for(const absentRole of ['buyer','seller'])for(const action of ['acceptoffer','counteroffer']){
  const {e,p,other,s}=fixture();s.tiles[1].owner=other.id;
  e.invokeGameAction(s,p,{type:'offer',index:1,amount:100});
  const absent=absentRole==='buyer'?p:other;absent.bot=true;absent.temporaryBot=true;
  const cash=[p.money,other.money];e.invokeGameAction(s,other,{type:action,amount:150});
  assert.equal(s.offer,null);assert.equal(s.tiles[1].owner,other.id);assert.deepEqual([p.money,other.money],cash);
 }
});
test('the background bot refuses a pending negotiation even when the absent player is waiting for the other response',()=>{
 const {e,p,other,s}=fixture();s.tiles[1].owner=other.id;e.invokeGameAction(s,p,{type:'offer',index:1,amount:100});
 p.bot=true;p.temporaryBot=true;e.invokeBotStep(s);assert.equal(s.offer,null);assert.equal(s.tiles[1].owner,other.id);
});
test('replacements neither initiate offers nor receive targeted offers from permanent advanced bots',()=>{
 const {p,other,s}=fixture();s.tiles[18].owner=p.id;s.tiles[19].owner=p.id;s.tiles[16].owner=other.id;
 assert(ai.offerPlan(s,p));p.temporaryBot=true;assert.equal(ai.offerPlan(s,p),null);
 delete p.temporaryBot;other.temporaryBot=true;assert.equal(ai.offerPlan(s,p),null);
});
test('normal trade is available after a human takes back control, while permanent bots retain their strategy',()=>{
 const presence=require('../presence');const {e,p,other,s}=fixture();s.tiles[1].owner=other.id;
 p.bot=true;p.temporaryBot=true;presence.touch(s,p,1000);assert(!p.bot);
 e.invokeGameAction(s,p,{type:'offer',index:1,amount:100});e.invokeGameAction(s,other,{type:'acceptoffer'});assert.equal(s.tiles[1].owner,p.id);
 other.bot=true;other.botLevel='ultimate';s.tiles[3].owner=other.id;
 p.money=10000; // This is a genuine, affordable generous bid.
 assert.equal(ai.tradeDecision(s,other,{index:3,seller:other.id,buyer:p.id,amount:10000,offered:[]}).type,'acceptoffer');
});

test('Expert and Ultimate do not sell Safi for 500 when it funds an opposing monopoly',()=>{
 for(const level of ['expert','ultimate']){
  const {p,other,s}=fixture(level);p.bot=true;s.tiles[18].owner=p.id;
  for(const i of [16,19])s.tiles[i].owner=other.id;
  other.money=1500;
  const offer={index:18,seller:p.id,buyer:other.id,amount:500,offered:[]};
  const before=JSON.stringify(s),decision=ai.tradeDecision(s,p,offer);
  assert.equal(decision.type,'counteroffer');assert(decision.amount>=1200);
  assert(decision.amount<=other.money);assert.deepEqual(decision.offered,[]);
  assert.equal(JSON.stringify(s),before,'planning cannot move money, land or houses');
  assert.equal(ai.tradeDecision(s,p,{...offer,...decision}).type,'acceptoffer');
 }
});

test('the price depends on development funds, not just face value or taking all cash',()=>{
 const {p,other,s}=fixture();s.tiles[18].owner=p.id;for(const i of [16,19])s.tiles[i].owner=other.id;
 const offer={index:18,seller:p.id,buyer:other.id,amount:500,offered:[]};
 other.money=500;assert.equal(ai.tradeDecision(s,p,offer).type,'acceptoffer');
 other.money=1500;assert.notEqual(ai.tradeDecision(s,p,offer).type,'acceptoffer');
 // An isolated unremarkable city is still tradable at a reasonable price.
 s.tiles[1].owner=p.id;assert.equal(ai.tradeDecision(s,p,{...offer,index:1,amount:150}).type,'acceptoffer');
});

test('Ultimate can request Victoria plus cash and the existing trade API executes exactly those terms',()=>{
 const {e,p,other,s}=fixture();p.bot=true;p.name='Ultime';other.name='Said';
 s.tiles[18].owner=p.id;s.tiles[37].owner=p.id;
 for(const i of [16,19,39])s.tiles[i].owner=other.id;
 const cash=p.money+other.money;
 e.invokeGameAction(s,other,{type:'offer',index:18,amount:350});e.invokeBotStep(s);
 assert(s.offer);assert.equal(s.offer.respondent,other.id);
 assert(s.offer.offered.includes(39),'request Victoria to complete Casablanca/Victoria');
 assert(s.offer.amount>=300&&s.offer.amount<1000,'a reciprocal monopoly can justify less cash');
 assert(s.log.at(-1).includes('Victoria'));assert(s.log.at(-1).includes('Safi'));
 const price=s.offer.amount,beforeBuyer=other.money,beforeSeller=p.money;
 assert.equal(s.tiles[39].owner,other.id,'counteroffers require consent');
 e.invokeGameAction(s,other,{type:'acceptoffer'});
 assert.equal(s.tiles[18].owner,other.id);assert.equal(s.tiles[39].owner,p.id);
 assert.equal(other.money,beforeBuyer-price);assert.equal(p.money,beforeSeller+price);
 assert.equal(p.money+other.money,cash);assert.equal(s.offer,null);
});

test('strategic mixed counters never demand mortgaged land or a group with buildings',()=>{
 for(const blocked of ['mortgage','building']){
  const {p,other,s}=fixture();s.tiles[18].owner=p.id;s.tiles[37].owner=p.id;
  for(const i of [16,19,39])s.tiles[i].owner=other.id;
  if(blocked==='mortgage')s.tiles[39].mortgaged=true;else s.tiles[39].level=1;
  const decision=ai.tradeDecision(s,p,{index:18,seller:p.id,buyer:other.id,amount:350,offered:[]});
  assert(!decision.offered?.includes(39));
 }
});

test('idle mortgage collateral cannot hide the funds for a dangerous new monopoly',()=>{
 const {p,other,s}=fixture();s.tiles[18].owner=p.id;
 for(const i of [16,19,5,15,25,35,12,28])s.tiles[i].owner=other.id;
 // Almost all cash is offered, but idle stations and utilities could fund houses.
 other.money=1500;
 assert.notEqual(ai.tradeDecision(s,p,{index:18,seller:p.id,buyer:other.id,amount:1350,offered:[]}).type,'acceptoffer');
});

test('opponents are evaluated equally, quotes stay affordable and repeated low bids do not cause capitulation',()=>{
 const {e,p,other,s}=fixture();p.bot=true;s.tiles[18].owner=p.id;for(const i of [16,19])s.tiles[i].owner=other.id;
 const offer={index:18,seller:p.id,buyer:other.id,respondent:p.id,amount:500,offered:[]};
 const human=ai.tradeDecision(s,p,offer);other.bot=true;other.botLevel='ultimate';
 assert.deepEqual(ai.tradeDecision(s,p,offer),human);other.bot=false;
 s.offer={...offer,botCounterRounds:2};e.invokeBotStep(s);
 assert.equal(s.offer,null);assert.equal(s.tiles[18].owner,p.id);assert.equal(other.money,1500);
 other.money=10;
 const small=ai.tradeDecision(s,p,offer);assert(small.type==='rejectoffer'||small.amount<=10);
});


test('a buying robot removes a concession that would fund a stronger opposing monopoly',()=>{
 const {p,other,s}=fixture();s.tiles[18].owner=other.id;s.tiles[37].owner=other.id;
 for(const i of [16,19,39])s.tiles[i].owner=p.id;
 const offer={index:18,buyer:p.id,seller:other.id,amount:500,offered:[39]};
 const decision=ai.tradeDecision(s,p,offer);
 assert.equal(decision.type,'counteroffer');assert(!decision.offered.includes(39));
 assert(decision.amount>0&&decision.amount<=p.money);
 assert.equal(ai.tradeDecision(s,p,{...offer,...decision}).type,'acceptoffer');
});


test('payment must not cheaply finance a rival building spree on an existing monopoly',()=>{
 const {p,other,s}=fixture();p.pos=10;s.tiles[1].owner=other.id;other.money=210;
 for(const i of [16,18,19]){s.tiles[i].owner=other.id;s.tiles[i].level=2;}
 // Even a small purchase can fund the jump from two to three houses.
 const decision=ai.tradeDecision(s,p,{index:1,buyer:p.id,seller:other.id,amount:50,offered:[]});
 assert.notEqual(decision.type,'acceptoffer');
});
