const {test} = require('node:test');
const assert = require('node:assert/strict');
const presence = require('../presence');

test('30s warning, 60s takeover and return preserve the player and assets', () => {
  const player = {id:'human', token:'private', money:980, pos:12, jail:true, bot:false};
  const room = {phase:'playing', players:[player], tiles:[{owner:'human',level:2}], debts:[{player:'human'}]};
  presence.touch(room, player, 1000);
  assert.equal(presence.status(room, player, 30999), 'online');
  assert.equal(presence.status(room, player, 31000), 'disconnected');
  assert.deepEqual(presence.sweep(room, 60999), []);
  assert.deepEqual(presence.sweep(room, 61000), [player]);
  assert.equal(presence.status(room, player, 61000), 'replaced');
  assert.deepEqual(presence.sweep(room, 130000), []);
  assert.equal(presence.touch(room, player, 140000), true);
  assert.deepEqual(player, {id:'human',token:'private',money:980,pos:12,jail:true,bot:false});
  assert.deepEqual(room.tiles, [{owner:'human',level:2}]);
  assert.deepEqual(room.debts, [{player:'human'}]);
});

test('voluntary leave replaces immediately and only temporary bots can return', () => {
  const human={id:'h',bot:false}, bot={id:'b',bot:true}, out={id:'o',out:true};
  assert.equal(presence.replace(human), true);
  assert.equal(presence.replace(human), false);
  assert.equal(presence.replace(bot), false);
  assert.equal(presence.replace(out), false);
  const room={players:[human,bot,out],phase:'opening'};
  assert.equal(presence.touch(room,bot,0),false);
  assert.equal(bot.bot,true);
  assert.equal(presence.touch(room,human,0),true);
  assert.equal(human.bot,false);
});

test('old saved rooms get a grace period, finished games do not change', () => {
  const p={id:'a'};const room={phase:'lobby',players:[p]};
  assert.deepEqual(presence.sweep(room, 1000000), []);
  assert.deepEqual(presence.sweep(room, 1060000), [p]);
  room.phase='finished';p.bot=false;delete p.temporaryBot;
  assert.deepEqual(presence.sweep(room, 2000000), []);
});

test('manual auto is not cancelled by polling or reconnecting; toggle restores same player',()=>{
 const player={id:'a',money:500,bot:false};const room={phase:'playing',turn:0,players:[player]};
 presence.setAuto(room,player,true,0);
 assert.equal(presence.touch(room,player,1000),false);
 assert.equal(presence.touch(room,player,100000),false);
 assert.equal(player.bot,true);assert.equal(player.autoPlay,true);assert.equal(player.money,500);
 presence.setAuto(room,player,false,100001);
 assert.equal(player.bot,false);assert.equal(player.autoPlay,undefined);assert.equal(player.temporaryBot,undefined);
 assert.equal(player.money,500);
});
test('auto cannot be set on an eliminated player, a finished game or invalid value',()=>{
 const p={id:'a',out:false};const room={phase:'playing',players:[p],turn:0};
 assert.throws(()=>presence.setAuto(room,p,'true'));
 p.out=true;assert.throws(()=>presence.setAuto(room,p,true));
 p.out=false;room.phase='finished';assert.throws(()=>presence.setAuto(room,p,true));
});
