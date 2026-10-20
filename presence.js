// Presence belongs to authenticated sessions; an AI replacement keeps the same player.
const DISCONNECTED_MS = 30_000;
const TAKEOVER_MS = 120_000;
function touch(room, player, now = Date.now()) {
  room.lastSeen ??= {};
  room.lastSeen[player.id] = now;
  if (player.temporaryBot) {
    player.bot = false;
    delete player.temporaryBot;
    return true;
  }
  return false;
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
module.exports = { touch, replace, sweep, status, DISCONNECTED_MS, TAKEOVER_MS };
