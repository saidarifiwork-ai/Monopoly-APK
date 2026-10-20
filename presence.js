// Presence belongs to authenticated sessions; an AI replacement keeps the same player.
const DISCONNECTED_MS = 30_000;
const TAKEOVER_MS = 60_000;
function touch(room, player, now = Date.now()) {
  room.lastSeen ??= {};
  room.lastSeen[player.id] = now;
  if (player.temporaryBot && !player.autoPlay) {
    player.bot = false;
    delete player.temporaryBot;
    return true;
  }
  return false;
}
function setAuto(room, player, enabled, now = Date.now()) {
  if (typeof enabled !== 'boolean' || player.out || !['opening', 'playing'].includes(room.phase)) throw Error('Mode auto indisponible.');
  const changed = !!player.autoPlay !== enabled;
  if (enabled) {
    player.autoPlay = true;
    player.temporaryBot = true;
    player.bot = true;
  } else {
    delete player.autoPlay;
    if (player.temporaryBot) { player.bot = false; delete player.temporaryBot; }
  }
  touch(room, player, now);
  if (changed && room.players[room.turn]?.id === player.id) {
    room.botPhase = 'buy';
    room.botNext = now + 1800;
  }
  if (changed && room.auction?.respondent === player.id) room.auction.deadline = now + (enabled ? 2000 : 15000);
  return changed;
}
function replace(player) {
  if (player.out || player.bot) return false;
  player.temporaryBot = true;
  player.bot = true;
  return true;
}
function sweep(room, now = Date.now()) {
  room.lastSeen ??= {};
  const replaced = [];
  if (room.phase === 'finished') return replaced;
  for (const player of room.players) {
    if (player.bot || player.out) continue;
    // Older saved rooms may have no heartbeat for a player yet.
    room.lastSeen[player.id] ??= now;
    if (now - room.lastSeen[player.id] >= TAKEOVER_MS && replace(player)) {
      if (room.players[room.turn]?.id === player.id) {
        room.botPhase = 'buy';
        room.botNext = 0;
      }
      replaced.push(player);
    }
  }
  return replaced;
}
function status(room, player, now = Date.now()) {
  if (player.out) return 'out';
  if (player.temporaryBot) return 'replaced';
  if (player.bot) return 'bot';
  return now - (room.lastSeen?.[player.id] ?? now) >= DISCONNECTED_MS ? 'disconnected' : 'online';
}
module.exports = { setAuto, touch, replace, sweep, status, DISCONNECTED_MS, TAKEOVER_MS };
