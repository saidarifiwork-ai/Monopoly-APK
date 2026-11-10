const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const {shuffle} = require('../cards');

function engine(savedRooms) {
    let shuffles = 0;
    const sandbox = {
        __dirname: path.resolve(__dirname, '..'),
        require(name) {
            if (name === 'express') {
                const express = require('express');
                return Object.assign(() => {const app = express(); app.listen = () => {}; return app;}, express);
            }
            if (name === 'fs') return {existsSync: () => !!savedRooms, readFileSync: () => JSON.stringify(savedRooms), writeFileSync: () => {}};
            if (name === './cards') return {shuffle(cards) {shuffles++; return shuffle(cards, n => (shuffles - 1) % n);}};
            return require(name.startsWith('.') ? path.resolve(__dirname, '..', name) : name);
        },
        process: {env: {}}, console, setInterval: () => ({unref() {}}),
        Math: Object.assign(Object.create(Math), {random: () => 0}),
    };
    vm.createContext(sandbox);
    vm.runInContext(fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8') + '\nglobalThis.e={newPlayer,newTiles,newCardDecks,resolveLanding,drawCard,invokeGameAction,prepareCardDecks,getRoom};', sandbox);
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

test('all Chance squares and all players share one queue; Chest has its own queue', () => {
    const e=engine(), s=room(e); s.phase='playing';
    const card=n=>({title:'Carte '+n,text:'Test',effect:'cash',value:n});
    s.decks={chance:[card(1),card(2),card(3)],chest:[card(4),card(5),card(6)]};
    s.cardShuffleVersion=3;
    const chestOrder=s.decks.chest.slice();
    for (const [turn,index] of [7,22,36].entries()) {const p=s.players[turn%2];p.pos=index;e.resolveLanding(s,p);}
    assert.deepEqual(Array.from(s.events.filter(x=>x.type==='card'),x=>x.title),['Carte 1','Carte 2','Carte 3']);
    assert.deepEqual(s.decks.chest,chestOrder);
    assert.deepEqual(Array.from(s.decks.chance,c=>c.title),['Carte 1','Carte 2','Carte 3']);
    for (const [turn,index] of [2,17,33].entries()) {const p=s.players[turn%2];p.pos=index;e.resolveLanding(s,p);}
    assert.deepEqual(Array.from(s.events.filter(x=>x.type==='card').slice(3),x=>x.title),['Carte 4','Carte 5','Carte 6']);
    assert.equal(e.shuffleCount(),0); // Normal draws do not reshuffle either queue.
});

test('rooms have independent decks and restored games keep their existing order', () => {
    const e=engine(), a=room(e), b=room(e);
    e.invokeGameAction(a,a.players[0],{type:'start'});
    e.invokeGameAction(b,b.players[0],{type:'start'});
    assert.notEqual(a.decks.chance,b.decks.chance);
    const previous=b.decks.chance.slice();a.phase='playing';
    a.decks.chance=[{title:'Restored first',text:'Test',effect:'cash',value:1},{title:'Restored next',text:'Test',effect:'cash',value:2}];
    e.drawCard(a,a.players[0],'chance');assert.equal(a.events.at(-1).title,'Restored first');
    assert.equal(a.decks.chance[0].title,'Restored next');assert.deepEqual(b.decks.chance,previous);assert.equal(e.shuffleCount(),4);
});

test('a prison-release card stays out of the deck until used, then returns to the bottom', () => {
    const e=engine(), s=room(e), p=s.players[0];s.phase='playing';
    const free={title:'Liberté',text:'Test',effect:'free',value:0}, cash={title:'Prime',text:'Test',effect:'cash',value:20};
    s.decks={chance:[],chest:[free,cash]};s.cardShuffleVersion=3;e.drawCard(s,p,'chest');
    assert.equal(p.jailCards.length,1); assert.deepEqual(s.decks.chest,[cash]);
    p.jail=true;p.pos=10;e.invokeGameAction(s,p,{type:'usejail'});
    assert.equal(p.jailCards.length,0);assert.equal(s.decks.chest[0],cash);assert.equal(s.decks.chest[1],free);
});


test('legacy saved queues are reshuffled once, preserving held cards, balances and positions', () => {
    const e=engine(),s=room(e),p=s.players[0];s.phase='playing';
    const original=e.newCardDecks();
    p.pos=22;p.money=777;p.jailCards=[{deck:'chance',card:original.chance.find(c=>c.effect==='free')}];
    s.decks={chance:original.chance.filter(c=>c.effect!=='free'),chest:original.chest};
    const prior=Array.from(s.decks.chance,c=>c.title),count=e.shuffleCount();
    e.prepareCardDecks(s);
    assert.equal(s.cardShuffleVersion,3);assert.equal(e.shuffleCount(),count+2);
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
    assert.equal(s.decks.chest[0].title,'Remaining chest card');
});

test('the actual first card comes from the prepared shared deck at every Chance square', () => {
    const e=engine(),firstCards=new Set();
    for(let match=0;match<16;match++)for(const position of [7,22,36]){
        const s=room(e);e.invokeGameAction(s,s.players[0],{type:'start'});
        const top=s.decks.chance[0].title;firstCards.add(top);
        s.phase='playing';s.players[0].pos=position;
        e.resolveLanding(s,s.players[0]);
        assert.equal(s.events.find(event=>event.type==='card').title,top);
        assert.equal(s.cardShuffleVersion,3);
    }
    assert(firstCards.size>3,'new matches must not have one fixed first card');
});


test('loading an active legacy save migrates both queues before the first client request', () => {
    const first=engine(),s=room(first);s.phase='playing';s.decks=first.newCardDecks();
    const balance=s.players[0].money,position=s.players[0].pos;
    const loaded=engine({SAVED1:s}),restored=loaded.getRoom('SAVED1');
    assert.equal(restored.cardShuffleVersion,3);assert.equal(loaded.shuffleCount(),2);
    assert.equal(restored.players[0].money,balance);assert.equal(restored.players[0].pos,position);
    loaded.prepareCardDecks(restored);assert.equal(loaded.shuffleCount(),2);
});
