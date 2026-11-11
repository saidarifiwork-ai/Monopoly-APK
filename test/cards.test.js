const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const {shuffle} = require('../cards');

function engine(savedRooms, realRandom = false) {
    let shuffles = 0;
    const sandbox = {
        __dirname: path.resolve(__dirname, '..'),
        require(name) {
            if (name === 'express') {
                const express = require('express');
                return Object.assign(() => {const app = express(); app.listen = () => {}; return app;}, express);
            }
            if (name === 'fs') return {existsSync: () => !!savedRooms, readFileSync: () => JSON.stringify(savedRooms), writeFileSync: () => {}};
            if (name === './cards') return {shuffle(cards) {shuffles++; return realRandom ? shuffle(cards) : shuffle(cards, n => (shuffles - 1) % n);}};
            return require(name.startsWith('.') ? path.resolve(__dirname, '..', name) : name);
        },
        process: {env: {}}, console, setInterval: () => ({unref() {}}),
        Math: Object.assign(Object.create(Math), {random: () => 0}),
    };
    vm.createContext(sandbox);
    vm.runInContext(fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8') + '\nglobalThis.e={newPlayer,newTiles,newCardDecks,resolveLanding,drawCard,invokeGameAction,prepareCardDecks,getRoom,invokeFinanceAction};', sandbox);
    return {...sandbox.e, shuffleCount: () => shuffles};
}
function room(e) {
    const a=e.newPlayer('Saïd'), b=e.newPlayer('Ami'); a.id='a'; b.id='b';
    return {phase:'lobby',host:a.id,turn:0,players:[a,b],tiles:e.newTiles(),rolled:false,debts:[],offer:null,log:[],events:[],eventSeq:0};
}

test('Fisher–Yates produces every four-card permutation exactly once for uniform choices', () => {
    const originals=['a','b','c','d'], outcomes=new Set();
    for (let a=0;a<4;a++) for (let b=0;b<3;b++) for (let c=0;c<2;c++) {
        const choices=[a,b,c]; outcomes.add(shuffle(originals, () => choices.shift()).join(''));
    }
    assert.equal(outcomes.size,24);
    assert.deepEqual(originals,['a','b','c','d']);
    assert.deepEqual(shuffle([]),[]); assert.deepEqual(shuffle(['a']),['a']);
});

test('both complete decks are shuffled before the opening dice, and freshly on replay', () => {
    const e=engine(), s=room(e); assert.equal(e.shuffleCount(),0);
    e.invokeGameAction(s,s.players[0],{type:'start'});
    assert.equal(s.phase,'opening'); assert.equal(e.shuffleCount(),2);
    for (const deck of ['chance','chest']) {
        assert.equal(s.decks[deck].length,16);
        assert.equal(new Set(s.decks[deck].map(c=>c.title)).size,16);
    }
    const first=s.decks;
    s.phase='finished'; e.invokeGameAction(s,s.players[0],{type:'rematch'});
    assert.equal(e.shuffleCount(),2);
    e.invokeGameAction(s,s.players[0],{type:'start'});
    assert.equal(e.shuffleCount(),4); assert.notEqual(s.decks,first);
    assert.notDeepEqual(Array.from(s.decks.chance,c=>c.title),Array.from(first.chance,c=>c.title));
});

// Reorder genuine, complete decks to exercise each square without fake cards
// that the production integrity check must reject.
function cashFirst(s, kind) {
    s.decks[kind].sort((a,b) => Number(b.effect === 'cash') - Number(a.effect === 'cash'));
}

test('all Chance squares and all players share one queue; Chest has its own queue', () => {
    const e=engine(), s=room(e);e.invokeGameAction(s,s.players[0],{type:'start'});s.phase='playing';
    for(const kind of ['chance','chest']) cashFirst(s,kind);
    const chanceOrder=s.decks.chance.slice(),chestOrder=s.decks.chest.slice(), count=e.shuffleCount();
    for (const [turn,index] of [7,22,36].entries()) {const p=s.players[turn%2];p.pos=index;e.resolveLanding(s,p);}
    assert.deepEqual(Array.from(s.events.filter(x=>x.type==='card'),x=>x.title),Array.from(chanceOrder.slice(0,3),c=>c.title));
    assert.deepEqual(s.decks.chest,chestOrder);
    assert.deepEqual(Array.from(s.decks.chance,c=>c.id),Array.from([...chanceOrder.slice(3),...chanceOrder.slice(0,3)],c=>c.id));
    for (const [turn,index] of [2,17,33].entries()) {const p=s.players[turn%2];p.pos=index;e.resolveLanding(s,p);}
    assert.deepEqual(Array.from(s.events.filter(x=>x.type==='card').slice(3),x=>x.title),Array.from(chestOrder.slice(0,3),c=>c.title));
    assert.equal(e.shuffleCount(),count); // Normal draws never reshuffle the queues.
});

test('rooms have independent decks and restored games keep their existing order', () => {
    const e=engine(), a=room(e), b=room(e);
    e.invokeGameAction(a,a.players[0],{type:'start'});
    e.invokeGameAction(b,b.players[0],{type:'start'});
    assert.notEqual(a.decks.chance,b.decks.chance);
    const previous=b.decks.chance.slice();a.phase='playing';cashFirst(a,'chance');
    const [first,next]=a.decks.chance;
    e.drawCard(a,a.players[0],'chance');assert.equal(a.events.at(-1).title,first.title);
    assert.equal(a.decks.chance[0].id,next.id);assert.deepEqual(b.decks.chance,previous);assert.equal(e.shuffleCount(),4);
    const saved=JSON.parse(JSON.stringify(a)),loaded=engine({RESTORED:saved}),restored=loaded.getRoom('RESTORED');
    assert.equal(JSON.stringify(restored.decks),JSON.stringify(a.decks));
    assert.equal(loaded.shuffleCount(),0);
});

test('a prison-release card stays out of the deck until used, then returns to the bottom', () => {
    const e=engine(), s=room(e), p=s.players[0];e.invokeGameAction(s,p,{type:'start'});s.phase='playing';
    s.decks.chest.sort((a,b)=>Number(b.effect==='free')-Number(a.effect==='free'));
    const free=s.decks.chest[0],next=s.decks.chest[1];e.drawCard(s,p,'chest');
    assert.equal(p.jailCards.length,1); assert.equal(s.decks.chest.length,15);
    e.prepareCardDecks(s);assert.equal(s.decks.chest.length,15);assert.equal(e.shuffleCount(),2);
    p.jail=true;p.pos=10;e.invokeGameAction(s,p,{type:'usejail'});
    assert.equal(p.jailCards.length,0);assert.equal(s.decks.chest[0].id,next.id);assert.equal(s.decks.chest.at(-1).id,free.id);
    e.prepareCardDecks(s);assert.equal(e.shuffleCount(),2);
});

test('legacy saved queues are reshuffled once, preserving held cards, balances and positions', () => {
    const e=engine(),s=room(e),p=s.players[0];s.phase='playing';
    const original=e.newCardDecks();
    p.pos=22;p.money=777;p.jailCards=[{deck:'chance',card:original.chance.find(c=>c.effect==='free')}];
    s.decks={chance:original.chance.filter(c=>c.effect!=='free'),chest:original.chest};
    const prior=Array.from(s.decks.chance,c=>c.title),count=e.shuffleCount();
    e.prepareCardDecks(s);
    assert.equal(s.cardShuffleVersion,4);assert.equal(e.shuffleCount(),count+2);
    assert.equal(s.decks.chance.length,15);assert.equal(s.decks.chest.length,16);
    assert.deepEqual([...Array.from(s.decks.chance,c=>c.title)].sort(),[...prior].sort());
    assert.equal(s.decks.chance.some(c=>c.effect==='free'),false);
    assert.equal(p.jailCards.length,1);assert.equal(p.money,777);assert.equal(p.pos,22);
    const order=JSON.stringify(s.decks);e.prepareCardDecks(s);assert.equal(JSON.stringify(s.decks),order);assert.equal(e.shuffleCount(),count+2);
});

test('an absent saved deck is repaired without duplicating a held prison-release card', () => {
    const e=engine(),s=room(e);s.phase='playing';
    s.players[0].jailCards=[{deck:'chance',card:{effect:'free'}}];
    s.decks={chest:[{title:'Remaining chest card',effect:'cash',value:1}]};
    e.prepareCardDecks(s);
    assert.equal(s.decks.chance.length,15);assert(s.decks.chance.every(c=>c.effect!=='free'));
    assert.equal(s.decks.chest.length,16);
    assert.equal(new Set(s.decks.chest.map(c=>c.id)).size,16);
    assert.equal(s.players[0].jailCards[0].card.effect,'free');
});

test('real cryptographic shuffle drives the first card on every Chance and Chest square', () => {
    const e=engine(undefined,true),firstCards={chance:new Set(),chest:new Set()};
    for(let match=0;match<48;match++)for(const [kind,positions] of Object.entries({chance:[7,22,36],chest:[2,17,33]})) {
        const s=room(e);e.invokeGameAction(s,s.players[0],{type:'start'});
        const top=s.decks[kind][0].title;firstCards[kind].add(top);
        // Independent restored copies: each square must draw the same prepared
        // top card. A square itself must never select a fixed destination.
        for(const position of positions) {
            const copy=JSON.parse(JSON.stringify(s)),p=copy.players[0];copy.phase='playing';p.pos=position;
            e.resolveLanding(copy,p);
            assert.equal(copy.events.find(event=>event.type==='card').title,top);
            assert.equal(copy.cardShuffleVersion,4);
        }
    }
    for(const kind of ['chance','chest']) assert(firstCards[kind].size>3,`${kind}: matches must not have a fixed first card`);
});

test('loading an active legacy save migrates both queues before the first client request', () => {
    const first=engine(),s=room(first);s.phase='playing';s.decks=first.newCardDecks();
    const balance=s.players[0].money,position=s.players[0].pos;
    const loaded=engine({SAVED1:s}),restored=loaded.getRoom('SAVED1');
    assert.equal(restored.cardShuffleVersion,4);assert.equal(loaded.shuffleCount(),2);
    assert.equal(restored.players[0].money,balance);assert.equal(restored.players[0].pos,position);
    loaded.prepareCardDecks(restored);assert.equal(loaded.shuffleCount(),2);
});

test('a shortened saved deck marked current is rebuilt instead of repeating its few cards forever', () => {
    const e=engine(),s=room(e);e.invokeGameAction(s,s.players[0],{type:'start'});
    const version=s.cardShuffleVersion;
    s.decks.chance=s.decks.chance.filter(c=>[39,24].includes(c.value));
    s.decks.chest=s.decks.chest.slice(0,2);
    e.prepareCardDecks(s);
    assert.equal(s.cardShuffleVersion,version);
    assert.equal(s.decks.chance.length,16);
    assert.equal(s.decks.chest.length,16);
});


test('duplicate or modified cards are repaired without reordering the other valid deck', () => {
    for(const damage of ['duplicate','effect','empty','null']) {
        const e=engine(),s=room(e);e.invokeGameAction(s,s.players[0],{type:'start'});
        const chest=JSON.stringify(s.decks.chest),count=e.shuffleCount();
        if(damage==='duplicate') s.decks.chance[1]={...s.decks.chance[0]};
        if(damage==='effect') s.decks.chance[0].value=999;
        if(damage==='empty') s.decks.chance=[];
        if(damage==='null') s.decks.chance[0]=null;
        e.prepareCardDecks(s);
        assert.equal(s.decks.chance.length,16);assert.equal(new Set(s.decks.chance.map(c=>c.id)).size,16);
        assert.equal(JSON.stringify(s.decks.chest),chest);assert.equal(e.shuffleCount(),count+1);
        assert(!s.decks.chance.some(c=>c.value===999));
    }
});

test('old version-3 short queues rebuild from all cards while preserving both held release cards', () => {
    const e=engine(),s=room(e);s.phase='playing';
    s.decks={chance:[{effect:'move',value:39},{effect:'move',value:24}],chest:[{effect:'cash',value:100}]};
    s.cardShuffleVersion=3;
    s.players[0].money=777;s.players[0].pos=19;s.tiles[19].owner=s.players[0].id;
    s.players[0].jailCards=[{deck:'chance',card:{effect:'free'}}];
    s.players[1].jailCards=[{deck:'chest',card:{effect:'free'}}];
    e.prepareCardDecks(s);
    for(const kind of ['chance','chest']) {
        assert.equal(s.decks[kind].length,15);assert(!s.decks[kind].some(c=>c.effect==='free'));
        assert.equal(new Set(s.decks[kind].map(c=>c.id)).size,15);
    }
    assert.equal(s.players[0].money,777);assert.equal(s.players[0].pos,19);assert.equal(s.tiles[19].owner,s.players[0].id);
    assert.equal(s.players[0].jailCards[0].card.id,'chance-9');
    assert.equal(s.players[1].jailCards[0].card.id,'chest-5');
    const loaded=engine({HELD:s}),restored=loaded.getRoom('HELD');
    assert.equal(loaded.shuffleCount(),0);assert.equal(JSON.stringify(restored.decks),JSON.stringify(s.decks));
});

test('bankruptcy returns a held release card exactly once without triggering another shuffle', () => {
    const e=engine(),s=room(e),p=s.players[0];e.invokeGameAction(s,p,{type:'start'});s.phase='playing';
    s.decks.chance.sort((a,b)=>Number(b.effect==='free')-Number(a.effect==='free'));
    e.drawCard(s,p,'chance');assert.equal(s.decks.chance.length,15);
    s.debts=[{player:p.id,amount:2000}];
    e.invokeFinanceAction(s,p,{type:'bankrupt'});e.prepareCardDecks(s);
    assert.equal(p.jailCards.length,0);assert.equal(s.decks.chance.length,16);
    assert.equal(s.decks.chance.filter(c=>c.effect==='free').length,1);assert.equal(e.shuffleCount(),2);
});
