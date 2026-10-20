const {test} = require('node:test');
const assert = require('node:assert/strict');
const presence = require('../presence');

test('30s warning, 120s takeover and return preserve the player and assets', () => {
  const player = {id:'human', token:'private', money:980, pos:12, jail:true, bot:false};
  const room = {phase:'playing', players:[player], tiles:[{owner:'human',level:2}], debts:[{player:'human'}]};
  presence.touch(room, player, 1000);
  assert.equal(presence.status(room, player, 30999), 'online');
  assert.equal(presence.status(room, player, 31000), 'disconnected');
  assert.deepEqual(presence.sweep(room, 120999), []);
  assert.deepEqual(presence.sweep(room, 121000), [player]);
  assert.equal(presence.status(room, player, 121000), 'replaced');
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
  assert.deepEqual(presence.sweep(room, 1120000), [p]);
  room.phase='finished';p.bot=false;delete p.temporaryBot;
  assert.deepEqual(presence.sweep(room, 2000000), []);
});
