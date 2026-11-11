const {LEVELS, soloOpponents} = require('./bot-ai');
function progress(account) {
    const completedLevels = [];
    for (const {id} of LEVELS) {
        const victory = account?.soloVictories?.[id];
        if (!victory || !Number.isFinite(victory.wonAt) || typeof victory.gameId !== 'string') break;
        completedLevels.push(id);
    }
    const unlockedLevels = LEVELS.slice(0, Math.min(LEVELS.length, completedLevels.length + 1)).map(level => level.id);
    return {completedLevels, unlockedLevels, highestUnlocked: unlockedLevels.at(-1), allCompleted: completedLevels.length === LEVELS.length};
}
function requireUnlocked(accountProgress, level) {
    if (accountProgress.unlockedLevels.includes(level)) return;
    const index = LEVELS.findIndex(entry => entry.id === level);
    const current = LEVELS.find(entry => entry.id === accountProgress.highestUnlocked);
    const error = new Error('Le niveau ' + LEVELS[index].name + ' est verrouillé. Gagnez d’abord ' + current.name + '.');
    error.status = 403;error.code = 'LEVEL_LOCKED';throw error;
}
function result(room) {
    const challenge = room.soloChallenge;
    if (room.phase !== 'finished' || challenge?.version !== 1 || typeof challenge.accountId !== 'string' || !Array.isArray(challenge.opponentIds) || !room.players[room.turn]) return null;
    const winner = room.players[room.turn], level = LEVELS.find(entry => entry.id === challenge.level);
    if (!level || winner.out || winner.accountId !== challenge.accountId) return null;
    const opponents = room.players.filter(player => player.id !== winner.id);
    if (opponents.length !== soloOpponents(level.id) || opponents.length !== challenge.opponentIds.length ||
        !opponents.every(player => player.bot && !player.temporaryBot && !player.accountId && player.botLevel === level.id && challenge.opponentIds.includes(player.id))) return null;
    if (!opponents.every(player => player.out)) return null;
    return {accountId: winner.accountId, level: level.id, gameId: room.code + ':' + (room.gameRound || 0)};
}
module.exports = {progress, requireUnlocked, result};
