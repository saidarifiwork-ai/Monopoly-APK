// Decisions use public state only: never inspect decks or change dice/money.
const LEVELS = [
 {id:'beginner',name:'Débutant',reserve:50,buyChance:.5,bid:.45,builds:0,skill:0},
 {id:'easy',name:'Facile',reserve:100,buyChance:.8,bid:.65,builds:1,skill:1},
 {id:'normal',name:'Normal',reserve:150,buyChance:1,bid:.9,builds:1,skill:2},
 {id:'hard',name:'Difficile',reserve:180,buyChance:1,bid:1.1,builds:2,skill:3},
 {id:'expert',name:'Expert',reserve:220,buyChance:1,bid:1.25,builds:3,skill:4},
 {id:'ultimate',name:'Ultime',reserve:250,buyChance:1,bid:1.4,builds:5,skill:5}
];
function normalize(id='normal') {if (!LEVELS.some(l=>l.id===id)) throw Error('Niveau de robot invalide.');return id;}
function profile(p) {return LEVELS.find(l=>l.id===p.botLevel)||LEVELS[2];}
function group(s,t) {return t.kind==='property'?s.tiles.filter(x=>x.kind==='property'&&x.group===t.group):[];}
function rent(s,t) {
 if(!t.owner||t.mortgaged)return 0;
 if(t.kind==='station')return 25*2**(s.tiles.filter(x=>x.kind==='station'&&x.owner===t.owner).length-1);
 if(t.kind==='utility')return s.tiles.filter(x=>x.kind==='utility'&&x.owner===t.owner).length===2?70:28;
 const g=group(s,t);return t.level>0?(t.rents?.[t.level]||t.rent):(t.rent||0)*(g.length&&g.every(x=>x.owner===t.owner)?2:1);
}
function reserve(s,p) {
 const cfg=profile(p);if(cfg.skill<4)return cfg.reserve;
 let risk=0;for(let n=2;n<=12;n++){
  const t=s.tiles[((p.pos||0)+n)%s.tiles.length];
  if(t?.owner&&t.owner!==p.id)risk+=rent(s,t)*(6-Math.abs(7-n))/36;
 }
 return Math.ceil(cfg.reserve+risk*(cfg.skill===5?2.5:1.5));
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
function bidLimit(s,p,t) {return Math.max(0,Math.min(Math.floor(p.money-reserve(s,p)),value(s,p,t)));}
function shouldBuy(s,p,t,rng=Math.random) {
 return p.money-t.price>=reserve(s,p)&&(profile(p).skill<3||value(s,p,t)>=t.price)&&rng()<profile(p).buyChance;
}
function buildIndex(s,p) {
 if(!profile(p).builds)return -1;
 const candidates=s.tiles.map((t,i)=>({t,i})).filter(({t})=>t.kind==='property'&&t.owner===p.id&&t.level<5&&p.money-t.build>=Math.max(reserve(s,p),profile(p).skill<3?300:0)&&group(s,t).every(x=>x.owner===p.id&&!x.mortgaged&&x.level>=t.level));
 function score(t){
  const delta=(t.rents?.[t.level+1]||0)-(t.rents?.[t.level]||t.rent||0);
  let exposure=1;
  if(profile(p).skill===5){exposure=0;for(const o of s.players.filter(o=>o.id!==p.id&&!o.out))for(let n=2;n<=12;n++)if(((o.pos||0)+n)%s.tiles.length===s.tiles.indexOf(t))exposure+=(6-Math.abs(7-n))/36;exposure+=.12;}
  return delta/Math.max(1,t.build)*exposure;
 }
 if(profile(p).skill>=3)candidates.sort((a,b)=>score(b.t)-score(a.t));
 return candidates[0]?.i??-1;
}
function unmortgageIndex(s,p) {
 if(profile(p).skill<3)return -1;
 const choices=s.tiles.map((t,i)=>({t,i})).filter(({t})=>t.owner===p.id&&t.mortgaged&&p.money-Math.ceil(t.price*.55)>=reserve(s,p));
 choices.sort((a,b)=>value(s,p,b.t)/b.t.price-value(s,p,a.t)/a.t.price);
 return choices[0]?.i??-1;
}
function debtAction(s,p) {
 const sale=s.tiles.map((t,i)=>({t,i})).filter(({t})=>t.owner===p.id&&t.level>0&&group(s,t).every(x=>x.level<=t.level));
 const mortgages=s.tiles.map((t,i)=>({t,i})).filter(({t})=>t.owner===p.id&&!t.mortgaged&&t.price>0&&group(s,t).every(x=>!x.level));
 if(profile(p).skill>=3){
  // Preserve income and complete groups when possible; mortgage idle assets first.
  mortgages.sort((a,b)=>value(s,p,a.t,true)/a.t.price-value(s,p,b.t,true)/b.t.price);
  sale.sort((a,b)=>((a.t.rents?.[a.t.level]||0)-(a.t.rents?.[a.t.level-1]||0))/a.t.build-((b.t.rents?.[b.t.level]||0)-(b.t.rents?.[b.t.level-1]||0))/b.t.build);
 }
 const first=profile(p).skill>=3?(mortgages[0]&&{type:'mortgage',index:mortgages[0].i}):(sale[0]&&{type:'sellhouse',index:sale[0].i});
 return first||(sale[0]?{type:'sellhouse',index:sale[0].i}:mortgages[0]?{type:'mortgage',index:mortgages[0].i}:{type:'bankrupt'});
}
function tradeDecision(s,p,o) {
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
module.exports={LEVELS,normalize,profile,reserve,value,bidLimit,shouldBuy,buildIndex,unmortgageIndex,debtAction,tradeDecision};
