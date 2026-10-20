const RESPONSE_MS = 15000;
function next(room, now) {
  const a = room.auction;
  // A passed player leaves this auction; the leader waits for challengers.
  const candidates = room.players.filter(p => !p.out && !a.passed.includes(p.id) && p.id !== a.leader && p.money > a.amount);
  if (!candidates.length) return finish(room);
  const count = room.players.length;
  for (let step = 1; step <= count; step++) {
    const index = (a.cursor + step) % count;
    if (candidates.some(p => p.id === room.players[index].id)) {
      a.cursor = index;
      a.respondent = room.players[index].id;
      a.deadline = now + (room.players[index].bot ? 2000 : RESPONSE_MS);
      return;
    }
  }
}
function finish(room) {
  const a = room.auction;
  const tile = room.tiles[a.index];
  const winner = room.players.find(p => p.id === a.leader);
  let message = 'Aucune offre pour ' + tile.name + ' : le bien reste à la banque.';
  if (winner && !winner.out && winner.money >= a.amount && !tile.owner) {
    winner.money -= a.amount;
    tile.owner = winner.id;
    message = winner.name + ' remporte ' + tile.name + ' aux enchères pour ' + a.amount + ' DH.';
  }
  room.auction = null;
  return message;
}
function start(room, player, now = Date.now()) {
  const tile = room.tiles[player.pos];
  if (room.phase !== 'playing' || room.players[room.turn].id !== player.id || !room.rolled ||
      player.out || player.jail || room.auction || room.auctioned || room.offer || room.debts?.length ||
      !tile || tile.price <= 0 || tile.owner) throw Error('Enchère impossible.');
  room.auctioned = true;
  room.auction = {index: player.pos, amount: 0, leader: null, passed: [], cursor: (room.turn + room.players.length - 1) % room.players.length};
  return next(room, now);
}
function respond(room, player, type, amount, now = Date.now()) {
  const a = room.auction;
  if (!a || a.respondent !== player.id || player.out) throw Error('Ce n’est pas votre tour d’enchérir.');
  if (now >= a.deadline) throw Error('Le délai pour cette offre est dépassé.');
  if (type === 'bid') {
    if (!Number.isSafeInteger(amount) || amount <= a.amount || amount > player.money) throw Error('Proposez un montant entier supérieur à l’offre et dans votre budget.');
    a.amount = amount;
    a.leader = player.id;
  } else if (type === 'auctionpass') {
    a.passed.push(player.id);
  } else throw Error('Action d’enchère invalide.');
  return next(room, now);
}
function tick(room, now = Date.now()) {
  const a = room.auction;
  if (!a) return;
  const player = room.players.find(p => p.id === a.respondent);
  if (!player || player.out || now >= a.deadline) {
    a.passed.push(a.respondent);
    return next(room, now);
  }
  if (player.bot && now >= a.deadline - 1500) {
    const limit = Math.min(player.money, Math.floor(room.tiles[a.index].price * 0.9));
    const amount = Math.min(limit, a.amount + Math.max(1, Math.floor(room.tiles[a.index].price / 10)));
    return respond(room, player, amount > a.amount && amount <= limit ? 'bid' : 'auctionpass', amount, now);
  }
}
module.exports = {start, respond, tick, RESPONSE_MS};
