const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const {shuffle} = require('../cards');

function engine() {
    let shuffles = 0;
    const sandbox = {
        __dirname: path.resolve(__dirname, '..'),
        require(name) {
            if (name === 'express') {
                const express = require('express');
                return Object.assign(() => {const app = express(); app.listen = () => {}; return app;}, express);
            }
            if (name === 'fs') return {existsSync: () => false, writeFileSync: () => {}};
            if (name === './cards') return {shuffle(cards) {shuffles++; return shuffle(cards, n => (shuffles - 1) % n);}};
            return require(name.startsWith('.') ? path.resolve(__dirname, '..', name) : name);
        },
        process: {env: {}}, console, setInterval: () => ({unref() {}}),
        Math: Object.assign(Object.create(Math), {random: () => 0}),
    };
    vm.createContext(sandbox);
    vm.runInContext(fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8') + '\nglobalThis.e={newPlayer,newTiles,newCardDecks,resolveLanding,drawCard,invokeGameAction};', sandbox);
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
    s.decks={chance:[],chest:[free,cash]};e.drawCard(s,p,'chest');
    assert.equal(p.jailCards.length,1); assert.deepEqual(s.decks.chest,[cash]);
    p.jail=true;p.pos=10;e.invokeGameAction(s,p,{type:'usejail'});
    assert.equal(p.jailCards.length,0);assert.equal(s.decks.chest[0],cash);assert.equal(s.decks.chest[1],free);
});
