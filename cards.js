const {randomInt} = require('node:crypto');

// Fisher–Yates: each permutation is equally likely with uniform integer draws.
// Work on a copy so a new room cannot reorder another room's deck.
function shuffle(cards, nextInt = randomInt) {
    const deck = cards.slice();
    for (let i = deck.length - 1; i > 0; i--) {
        const j = nextInt(i + 1);
        [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    return deck;
}

module.exports = {shuffle};
