// Decisions use public state only: never inspect decks or change dice/money.
const LEVELS = [
 {id:'beginner',name:'Débutant',reserve:50,buyChance:.5,bid:.45,builds:0,skill:0},
 {id:'easy',name:'Facile',reserve:100,buyChance:.8,bid:.65,builds:1,skill:1},
 {id:'normal',name:'Normal',reserve:150,buyChance:1,bid:.9,builds:1,skill:2},
 {id:'hard',name:'Difficile',reserve:180,buyChance:1,bid:1.1,builds:2,skill:3},
 {id:'expert',name:'Expert',reserve:220,buyChance:1,bid:1.25,builds:3,skill:4},
 {id:'ultimate',name:'Ultime',reserve:250,buyChance:1,bid:1.4,builds:5,skill:5}
];
function protectsHumanAssets(p) {return !!(p && (p.temporaryBot || p.autoPlay));}
function normalize(id='normal') {if (!LEVELS.some(l=>l.id===id)) throw Error('Niveau de robot invalide.');return id;}
function profile(p) {return LEVELS.find(l=>l.id===p.botLevel)||LEVELS[2];}
function group(s,t) {return t.kind==='property'?s.tiles.filter(x=>x.kind==='property'&&x.group===t.group):[];}
function rent(s,t) {
 if(!t.owner||t.mortgaged)return 0;
 if(t.kind==='station')return 25*2**(s.tiles.filter(x=>x.kind==='station'&&x.owner===t.owner).length-1);
 if(t.kind==='utility')return s.tiles.filter(x=>x.kind==='utility'&&x.owner===t.owner).length===2?70:28;
 const g=group(s,t);return t.level>0?(t.rents?.[t.level]||t.rent):(t.rent||0)*(g.length&&g.every(x=>x.owner===t.owner)?2:1);
}
// Approximate two future turns from public positions and fair two-dice odds.
// Unknown Chance/Chest cards are deliberately not inspected.
function landingWeights(s,p,turns=2) {
 let positions=new Map([[p.jail?10:(p.pos||0),1]]);const weights=new Array(s.tiles.length).fill(0);
 for(let turn=0;turn<turns;turn++){
  const next=new Map();
  for(const [pos,prob] of positions)for(let n=2;n<=12;n++){
   let at=(pos+n)%s.tiles.length;const chance=prob*(6-Math.abs(7-n))/36;
   if(at===30&&s.tiles.length===40)at=10;
   next.set(at,(next.get(at)||0)+chance);weights[at]+=chance*(turn===0?1:.5);
  }
  positions=next;
 }
 return weights;
}
function expectedIncome(s,p,t,turns=2) {
 const i=s.tiles.indexOf(t);let weight=.08;
 for(const opponent of s.players.filter(o=>o.id!==p.id&&!o.out))weight+=landingWeights(s,opponent,turns)[i]||0;
 return weight;
}
function reserve(s,p) {
 const cfg=profile(p);if(cfg.skill<4)return cfg.reserve;
 const weights=landingWeights(s,p,cfg.skill===5?2:1);let risk=0,large=0,income=0;
 for(let i=0;i<s.tiles.length;i++){
  const t=s.tiles[i];
  if(t.owner&&t.owner!==p.id){const cost=rent(s,t);risk+=cost*weights[i];if(weights[i]>.08)large=Math.max(large,cost);}
  else if(t.owner===p.id)income+=rent(s,t)*expectedIncome(s,p,t,1);
  if(t.kind==='tax')risk+=(t.taxAmount||0)*weights[i];
 }
 const open=s.tiles.filter(t=>t.price>0&&!t.owner).length;
 const base=cfg.reserve*(open>=12?.55:.85);
 return Math.ceil(Math.max(70,base+risk*(cfg.skill===5?2:1.6)+large*.12-Math.min(base*.25,income*.2)));
}
function value(s,p,t,selling=false) {
 const cfg=profile(p);let worth=t.price||0;
 if(cfg.skill<3)return Math.ceil(worth*(selling?1.4:cfg.bid));
 const g=group(s,t), owned=g.filter(x=>x.owner===p.id).length;
 if(g.length){
  const completes=owned+(t.owner===p.id?0:1)===g.length;
  worth*=completes?2.1:owned?1.5:1.05;
  if(selling&&owned===g.length)worth*=1.45;
  if(cfg.skill>=4&&!selling){
   const opponents=s.players.filter(x=>x.id!==p.id&&!x.out);
   if(opponents.some(o=>g.filter(x=>x.owner===o.id).length===g.length-1))worth*=1.3;
  }
  worth+=(t.level||0)*(t.build||0);
 }else if(t.kind==='station')worth*=1.15+.25*s.tiles.filter(x=>x.kind==='station'&&x.owner===p.id&&x!==t).length;
 else if(t.kind==='utility')worth*=s.tiles.some(x=>x!==t&&x.kind==='utility'&&x.owner===p.id)?1.3:.8;
 return Math.ceil(worth);
}
function completesGroup(s,p,t) {
 const g=group(s,t);return g.length>0&&t.owner!==p.id&&g.every(x=>x===t||x.owner===p.id);
}
function investmentReserve(s,p,t) {
 const required=reserve(s,p);
 // Spending on the last missing city can be worth a smaller idle-cash buffer.
 return profile(p).skill>=4&&completesGroup(s,p,t)?Math.ceil(Math.max(60,profile(p).reserve*.3)+Math.max(0,required-profile(p).reserve*.85)):required;
}
function jailDecision(s,p) {
 const card=(p.jailCards||[]).length>0;
 if(!p.jail)return 'roll';
 if(profile(p).skill<4)return card?'usejail':'roll';
 const fee=card?0:50;
 if(p.money<fee)return card?'usejail':'roll';
 if((p.jailTurns||0)>=2)return card?'usejail':'roll';
 let danger=0, opportunity=0, completion=0, reachable=0;
 for(let n=2;n<=12;n++) {
  const t=s.tiles[((p.pos||10)+n)%s.tiles.length];
  const probability=(6-Math.abs(7-n))/36;
  if(t.owner&&t.owner!==p.id)danger+=rent(s,t)*probability;
  if(t.price>0&&!t.owner&&p.money-fee-t.price>=investmentReserve(s,p,t)) {
   reachable++;
   opportunity+=Math.max(t.price*.15,value(s,p,t)-t.price)*probability;
   if(completesGroup(s,p,t))completion+=value(s,p,t)*probability;
  }
 }
 const open=s.tiles.filter(t=>t.price>0&&!t.owner).length;
 const canInvest=p.money-fee>=profile(p).reserve;
 const completionWorthwhile=completion>0&&danger<Math.max(100,completion*2);
 const expanding=open>=5&&reachable>0&&canInvest&&danger<Math.max(40,opportunity*2);
 const profitable=opportunity>fee+danger;
 return completionWorthwhile||expanding||profitable?(card?'usejail':'payjail'):'roll';
}
function bidLimit(s,p,t) {return Math.max(0,Math.min(Math.floor(p.money-investmentReserve(s,p,t)),value(s,p,t)));}
function shouldBuy(s,p,t,rng=Math.random) {
 return p.money-t.price>=investmentReserve(s,p,t)&&(profile(p).skill<3||value(s,p,t)>=t.price)&&rng()<profile(p).buyChance;
}
function buildIndex(s,p) {
 if(!profile(p).builds)return -1;
 const candidates=s.tiles.map((t,i)=>({t,i})).filter(({t})=>t.kind==='property'&&t.owner===p.id&&t.level<5&&p.money-t.build>=Math.max(reserve(s,p),profile(p).skill<3?300:0)&&group(s,t).every(x=>x.owner===p.id&&!x.mortgaged&&x.level>=t.level));
 function score(t){
  if(profile(p).skill>=4)return constructionScore(s,p,t);
  const delta=(t.rents?.[t.level+1]||0)-(t.rents?.[t.level]||t.rent||0);
  return delta/Math.max(1,t.build);
 }
 if(profile(p).skill>=3)candidates.sort((a,b)=>score(b.t)-score(a.t));
 return candidates[0]?.i??-1;
}
function unmortgageIndex(s,p) {
 if(profile(p).skill<3)return -1;
 const choices=s.tiles.map((t,i)=>({t,i})).filter(({t})=>t.owner===p.id&&t.mortgaged&&p.money-redemptionCost(t)>=reserve(s,p));
 choices.sort((a,b)=>profile(p).skill>=4?redemptionScore(s,p,b.t)-redemptionScore(s,p,a.t):value(s,p,b.t)/b.t.price-value(s,p,a.t)/a.t.price);
 return choices[0]?.i??-1;
}
function redemptionCost(t){const half=Math.floor(t.price/2);return half+Math.ceil(half/10);}
function constructionScore(s,p,t) {
 const before=rent(s,t), after=t.rents?.[t.level+1]||before;
 return (after-before)*expectedIncome(s,p,t,profile(p).skill===5?2:1)/Math.max(1,t.build);
}
function redemptionScore(s,p,t) {
 const active={...t,mortgaged:false};
 return rent(s,active)*expectedIncome(s,p,t,profile(p).skill===5?2:1)/Math.max(1,redemptionCost(t));
}
function investmentAction(s,p,allowBuild=true) {
 const build=allowBuild?buildIndex(s,p):-1, restore=unmortgageIndex(s,p);
 if(build>=0&&(restore<0||constructionScore(s,p,s.tiles[build])>=redemptionScore(s,p,s.tiles[restore])))return {type:'build',index:build};
 return restore>=0?{type:'unmortgage',index:restore}:null;
}
function portfolioScore(s,p) {
 let score=0;const seen=new Set();
 for(const t of s.tiles.filter(t=>t.owner===p.id)){
  score+=t.price*(t.mortgaged?.45:1)+(t.level||0)*(t.build||0)*.75;
  if(t.kind==='property'&&!seen.has(t.group)){
   seen.add(t.group);const g=group(s,t),owned=g.filter(x=>x.owner===p.id).length,total=g.reduce((n,x)=>n+x.price,0);
   score+=total*(owned===g.length?1.3:owned===g.length-1?.25:.1);
  }
 }
 return score;
}
function tradeValues(s,p,o) {
 const after={...s,tiles:s.tiles.map(t=>({...t}))};after.tiles[o.index].owner=o.buyer;
 for(const i of o.offered||[])after.tiles[i].owner=o.seller;
 const ownDelta=portfolioScore(after,p)-portfolioScore(s,p);
 const rival=s.players.find(x=>x.id===(p.id===o.buyer?o.seller:o.buyer));
 const rivalDelta=rival?portfolioScore(after,rival)-portfolioScore(s,rival):0;
 // Do not cheaply give a rival a stronger monopoly, even if the rival is a bot.
 const danger=Math.max(0,rivalDelta-Math.max(0,ownDelta))*.2;
 return {fair:Math.ceil(p.id===o.seller?Math.max(0,-ownDelta+danger):Math.max(0,ownDelta-danger)),after};
}
function offerPlan(s,p,now=Date.now()) {
 if(protectsHumanAssets(p)||profile(p).skill<4||s.offer||s.auction||s.debts?.length||p.money<100||now-(p.lastBotOfferAt??-Infinity)<120000)return null;
 let best=null;
 for(let i=0;i<s.tiles.length;i++){
  const t=s.tiles[i],seller=s.players.find(x=>x.id===t.owner);
  if(!seller||seller.out||protectsHumanAssets(seller)||seller.id===p.id||t.mortgaged||!completesGroup(s,p,t)||group(s,t).some(x=>x.level>0))continue;
  const spares=s.tiles.map((x,j)=>({x,j})).filter(({x})=>x.owner===p.id&&!x.mortgaged&&x.price>0&&x.group!==t.group&&(!group(s,x).length||group(s,x).some(y=>y.owner!==p.id))&&group(s,x).every(y=>!y.level)).sort((a,b)=>value(s,seller,b.x)-value(s,seller,a.x)).slice(0,2);
  for(const offered of [[],...spares.map(x=>[x.j])]){
   const proposed={index:i,buyer:p.id,seller:seller.id,offered};const estimate=tradeValues(s,p,proposed);
   const budget=Math.max(0,p.money-investmentReserve(s,p,t));
   const amount=Math.floor(Math.min(budget,estimate.fair*.8,Math.max(t.price*1.25,t.price-offered.reduce((n,j)=>n+s.tiles[j].price,0))));
   if(amount<1||estimate.fair<=amount||!tradeModel(s,p,proposed).evaluate(amount).acceptable)continue;
   const score=estimate.fair-amount;
   if(!best||score>best.score)best={type:'offer',index:i,amount,offered,score};
  }
 }
 if(!best)return null;const {score,...action}=best;return action;
}
function debtAction(s,p) {
 const sale=s.tiles.map((t,i)=>({t,i})).filter(({t})=>t.owner===p.id&&t.level>0&&group(s,t).every(x=>x.level<=t.level));
 const mortgages=s.tiles.map((t,i)=>({t,i})).filter(({t})=>t.owner===p.id&&!t.mortgaged&&t.price>0&&group(s,t).every(x=>!x.level));
 if(profile(p).skill>=3){
  // Preserve income and complete groups when possible; mortgage idle assets first.
  mortgages.sort((a,b)=>value(s,p,a.t,true)/a.t.price-value(s,p,b.t,true)/b.t.price);
  sale.sort((a,b)=>((a.t.rents?.[a.t.level]||0)-(a.t.rents?.[a.t.level-1]||0))/a.t.build-((b.t.rents?.[b.t.level]||0)-(b.t.rents?.[b.t.level-1]||0))/b.t.build);
 }
 if(profile(p).skill>=4){
  const debt=s.debts?.find(d=>d.player===p.id);const need=Math.max(1,(debt?.amount||0)-p.money);
  const choices=[...mortgages.map(({t,i})=>({type:'mortgage',index:i,gain:Math.floor(t.price/2),loss:rent(s,t)*expectedIncome(s,p,t)+value(s,p,t,true)*.08})),...sale.map(({t,i})=>({type:'sellhouse',index:i,gain:Math.floor(t.build/2),loss:Math.max(0,rent(s,t)-rent(s,{...t,level:t.level-1}))*expectedIncome(s,p,t)}))];
  choices.sort((a,b)=>a.loss/Math.max(1,Math.min(need,a.gain))-b.loss/Math.max(1,Math.min(need,b.gain)));
  if(choices.length)return {type:choices[0].type,index:choices[0].index};
 }
 const first=profile(p).skill>=3?(mortgages[0]&&{type:'mortgage',index:mortgages[0].i}):(sale[0]&&{type:'sellhouse',index:sale[0].i});
 return first||(sale[0]?{type:'sellhouse',index:sale[0].i}:mortgages[0]?{type:'mortgage',index:mortgages[0].i}:{type:'bankrupt'});
}
// A public-state projection of balanced building, including the cost of lifting
// mortgages on a complete group. Curves are built once per ownership scenario;
// checking many cash prices does not repeatedly simulate the same houses.
function developmentCurve(s,p) {
 const tiles=s.tiles.map(t=>({...t})), projected={...s,tiles};
 const weights=new Array(tiles.length).fill(.1);
 for(const other of s.players.filter(x=>x.id!==p.id&&!x.out)){
  const landings=landingWeights(s,other,3);
  landings.forEach((v,i)=>weights[i]+=v);
 }
 const complete=tiles.filter(t=>t.kind==='property'&&t.owner===p.id&&group(projected,t).every(x=>x.owner===p.id));
 // Existing rent and monopoly ownership are valued by portfolioScore already.
 // Measure additional income from buildings/redemption without counting it twice.
 let cost=0,strength=0;
 const curve=[{cost,strength}];
 for(const t of complete.filter(t=>t.mortgaged)){
  cost+=redemptionCost(t);t.mortgaged=false;
  strength+=rent(projected,t)*weights[tiles.indexOf(t)];curve.push({cost,strength});
 }
 for(let n=0;n<110;n++){
  let best=null,score=-Infinity;
  for(const t of complete){
   if(t.level>=5||group(projected,t).some(x=>x.mortgaged||x.level<t.level))continue;
   const gain=((t.rents?.[t.level+1]||rent(projected,t))-rent(projected,t))*weights[tiles.indexOf(t)];
   const efficiency=gain/Math.max(1,t.build);
   if(efficiency>score){score=efficiency;best={t,gain};}
  }
  if(!best)break;
  best.t.level++;cost+=best.t.build;strength+=best.gain;curve.push({cost,strength});
 }
 return curve;
}
function collateral(s,p) {
 // Idle, legally mortgageable assets can finance an opponent's new houses.
 return s.tiles.filter(t=>t.owner===p.id&&!t.mortgaged&&t.price>0&&
  (!group(s,t).length||group(s,t).some(x=>x.owner!==p.id))&&group(s,t).every(x=>!x.level))
  .reduce((n,t)=>n+Math.floor(t.price/2),0);
}
function projectedStrength(curve,budget) {
 let strength=curve[0].strength;
 for(const point of curve){if(point.cost>budget)break;strength=point.strength;}
 return strength;
}
function tradeModel(s,p,o) {
 const selling=p.id===o.seller,rival=s.players.find(x=>x.id===(selling?o.buyer:o.seller));
 const {fair,after}=tradeValues(s,p,o),cfg=profile(p);
 const ownBefore=developmentCurve(s,p),ownAfter=developmentCurve(after,p);
 const rivalBefore=developmentCurve(s,rival),rivalAfter=developmentCurve(after,rival);
 const ownReserve=reserve(after,p),rivalReserve=reserve(after,rival);
 const ownBase=projectedStrength(ownBefore,Math.max(0,p.money-reserve(s,p)));
 const rivalBase=projectedStrength(rivalBefore,Math.max(0,rival.money+collateral(s,rival)-reserve(s,rival)));
 const financing=collateral(after,rival);
 const newGroups=after.tiles.filter(t=>t.kind==='property'&&t.owner===rival.id&&
  group(after,t).every(x=>x.owner===rival.id)&&!group(s,s.tiles[after.tiles.indexOf(t)]).every(x=>x.owner===rival.id));
 const unique=[...new Set(newGroups.map(t=>t.group))].map(g=>newGroups.filter(t=>t.group===g));
 const firstRound=unique.reduce((n,g)=>n+g.reduce((sum,t)=>sum+t.build,0),0);
 const unlocking=newGroups.filter(t=>t.mortgaged).reduce((n,t)=>n+redemptionCost(t),0);
 const ownDelta=portfolioScore(after,p)-portfolioScore(s,p);
 const rivalDelta=portfolioScore(after,rival)-portfolioScore(s,rival);
 function evaluate(amount){
  const ownCash=p.money+(selling?amount:-amount),rivalCash=rival.money+(selling?-amount:amount);
  const ownGain=projectedStrength(ownAfter,Math.max(0,ownCash-ownReserve))-ownBase;
  const rivalGain=projectedStrength(rivalAfter,Math.max(0,rivalCash+financing-rivalReserve))-rivalBase;
  // When a rival receives a new monopoly, keep enough leverage to prevent a
  // cheap sale financing an immediate building spree. A genuinely comparable
  // improvement to our own income can justify a reciprocal monopoly exchange.
  const reciprocal=Math.max(0,ownGain)/Math.max(1,rivalGain)*(cfg.skill===5?.9:1.1);
  const safeFunds=firstRound*(cfg.skill===5?.5:1)+unlocking;
  const dangerous=unique.length>0&&
   (rivalCash+financing)*Math.max(0,1-reciprocal)>safeFunds;
  const affordable=ownCash>=0&&rivalCash>=0&&(selling||ownCash>=ownReserve);
  const utility=(selling?amount:-amount)+ownDelta-Math.max(0,rivalDelta)*.25+
   4*(ownGain-Math.max(0,rivalGain)*(cfg.skill===5?1.4:1));
  return {acceptable:affordable&&!dangerous&&utility>=0&&(selling?amount>=fair:amount<=fair),utility};
 }
 return {fair,evaluate};
}
function negotiatedCounter(s,p,o) {
 const selling=p.id===o.seller,buyer=s.players.find(x=>x.id===o.buyer);
 const original=[...(o.offered||[])],sets=[original];
 if(selling){
  const candidates=s.tiles.map((t,i)=>({t,i})).filter(({t})=>t.owner===buyer.id&&t.price>0&&!t.mortgaged&&group(s,t).every(x=>!x.level))
   .sort((a,b)=>value(s,p,b.t)-value(s,p,a.t)).slice(0,8);
  for(const {i} of candidates){sets.push([i]);if(original.length<2)sets.push([...new Set([...original,i])]);}
 }else{
  sets.push([]);for(const i of original)sets.push([i]);
 }
 const seen=new Set();let best=null;
 for(const offered of sets){
  const key=[...offered].sort((a,b)=>a-b).join(',');if(seen.has(key))continue;seen.add(key);
  const proposal={...o,offered},model=tradeModel(s,p,proposal);
  const low=selling?Math.max(1,model.fair):1,high=Math.floor(selling?buyer.money:Math.min(buyer.money,model.fair));
  if(high<low)continue;
  // Seek an affordable acceptable quote; bounded sampling also handles jumps
  // at balanced-house thresholds rather than assuming a smooth valuation.
  const prices=new Set([low,high,Math.min(high,Math.max(low,o.amount))]);
  for(let n=1;n<24;n++)prices.add(Math.round(low+(high-low)*n/24));
  const ordered=[...prices].sort((a,b)=>selling?a-b:b-a);let amount=null,previous=selling?low:high;
  for(const price of ordered){
   if(model.evaluate(price).acceptable){
    let bad=previous,good=price;
    while(Math.abs(good-bad)>1){const mid=Math.floor((good+bad)/2);if(model.evaluate(mid).acceptable)good=mid;else bad=mid;}
    amount=good;break;
   }
   previous=price;
  }
  if(amount===null)continue;
  // An opening mixed counter keeps a cash component instead of silently
  // asking only one dirham plus an expensive property. Still re-evaluate it.
  if(selling&&offered.some(i=>!original.includes(i))){
   const quote=Math.min(high,Math.max(amount,Math.ceil(s.tiles[o.index].price*1.5/50)*50));
   if(model.evaluate(quote).acceptable)amount=quote;
  }
  const assessment=model.evaluate(amount);
  if(!best||assessment.utility>best.utility)best={type:'counteroffer',amount,offered,utility:assessment.utility};
 }
 if(!best)return {type:'rejectoffer'};
 const {utility,...decision}=best;return decision;
}
function tradeDecision(s,p,o) {
 if(protectsHumanAssets(p))return {type:'rejectoffer'};
 if(profile(p).skill>=4){
  if(tradeModel(s,p,o).evaluate(o.amount).acceptable)return {type:'acceptoffer'};
  // A token bid on a protected complete group need not start a negotiation.
  if(p.id===o.seller&&o.amount<tradeValues(s,p,o).fair*.5&&!(o.offered||[]).length&&group(s,s.tiles[o.index]).every(x=>x.owner===p.id))return {type:'rejectoffer'};
  return negotiatedCounter(s,p,o);
 }
 const t=s.tiles[o.index];const extras=(o.offered||[]).map(i=>s.tiles[i]);
 const selling=p.id===o.seller;
 const incoming= selling?extras.reduce((sum,x)=>sum+value(s,p,x),0):value(s,p,t);
 const outgoing= selling?value(s,p,t,true):extras.reduce((sum,x)=>sum+value(s,p,x,true),0);
 const fair=selling?Math.max(0,outgoing-incoming):Math.max(0,incoming-outgoing);
 const affordable=selling||p.money-o.amount>=reserve(s,p);
 if(affordable&&(selling?o.amount>=fair:o.amount<=fair))return {type:'acceptoffer'};
 if(selling&&o.amount+incoming<outgoing*.5)return {type:'rejectoffer'};
 const amount=selling?fair:Math.min(fair,Math.max(0,p.money-reserve(s,p)));
 return amount>0?{type:'counteroffer',amount:Math.floor(amount)}:{type:'rejectoffer'};
}
module.exports={protectsHumanAssets,LEVELS,normalize,profile,reserve,value,bidLimit,shouldBuy,buildIndex,unmortgageIndex,debtAction,tradeDecision,jailDecision,investmentReserve,landingWeights,investmentAction,offerPlan,tradeValues};
