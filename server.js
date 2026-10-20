const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 8787;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(__dirname));

// Game state storage with persistence
const STORAGE_FILE = '/tmp/monopoly-rooms.json';
let rooms = new Map();

// Load rooms from storage on startup
function loadRooms() {
    try {
        if (fs.existsSync(STORAGE_FILE)) {
            const data = fs.readFileSync(STORAGE_FILE, 'utf8');
            const parsed = JSON.parse(data);
            rooms = new Map(Object.entries(parsed));
            console.log(`Loaded ${rooms.size} rooms from storage`);
        }
    } catch (error) {
        console.error('Error loading rooms:', error);
        rooms = new Map();
    }
}

// Save rooms to storage
function saveRooms() {
    try {
        const obj = Object.fromEntries(rooms);
        fs.writeFileSync(STORAGE_FILE, JSON.stringify(obj), 'utf8');
    } catch (error) {
        console.error('Error saving rooms:', error);
    }
}

// Auto-save every 5 seconds
setInterval(saveRooms, 5000);

// Load on startup
loadRooms();

// Utility functions
function newTiles() {
    const names = ['Départ','Chefchaouen','Caisse commune','Tétouan','Impôts','Gare de Fès','Oujda','Chance','Nador','Al Hoceïma','Prison','Meknès','Électricité','Fès','Ifrane','Gare de Marrakech','El Jadida','Caisse commune','Safi','Essaouira','Parc gratuit','Agadir','Chance','Marrakech','Ouarzazate','Gare de Tanger','Tanger','Kénitra','Compagnie des eaux','Larache','Allez en prison','Rabat','Salé','Caisse commune','Témara','Gare de Bouskoura','Chance','Casablanca','Taxe de luxe','Victoria'];
    const groups = [[1,3],[6,8,9],[11,13,14],[16,18,19],[21,23,24],[26,27,29],[31,32,34],[37,39]];
    const prices = [[60,60],[100,100,120],[140,140,160],[180,180,200],[220,220,240],[260,260,280],[300,300,320],[350,400]];
    const palette = ['#905b42','#91cbdc','#d54b94','#ed9136','#d94343','#efd352','#29905b','#3164ab'];
    
    const tiles = [];
    for (let i = 0; i < 40; i++) {
        const t = {name: names[i], kind: 'special', price: 0, rent: 0, build: 0, level: 0, owner: '', group: -1, color: '', symbol: '', mortgaged: false};
        
        for (let g = 0; g < 8; g++) {
            if (groups[g].includes(i)) {
                t.kind = 'property';
                t.price = prices[g][groups[g].indexOf(i)];
                t.rent = 8 + 5 * g;
                t.build = 50 + 50 * Math.floor(g / 2);
                t.group = g;
                t.color = palette[g];
            }
        }
        
        if ([5,15,25,35].includes(i)) { t.kind = 'station'; t.price = 200; t.rent = 25; }
        if ([12,28].includes(i)) { t.kind = 'utility'; t.price = 150; t.rent = 4; }
        if ([7,22,36].includes(i)) { t.kind = 'chance'; }
        if ([2,17,33].includes(i)) { t.kind = 'chest'; }
        if ([4,38].includes(i)) { t.kind = 'tax'; t.taxAmount = i === 4 ? 200 : 100; t.symbol = '−' + t.taxAmount; }
        
        tiles.push(t);
    }
    
    setClassicRents(tiles);
    return tiles;
}

function setClassicRents(tiles) {
    const r = {
        1: [2,10,30,90,160,250], 3: [4,20,60,180,320,450],
        6: [6,30,90,270,400,550], 8: [6,30,90,270,400,550], 9: [8,40,100,300,450,600],
        11: [10,50,150,450,625,750], 13: [10,50,150,450,625,750], 14: [12,60,180,500,700,900],
        16: [14,70,200,550,750,950], 18: [14,70,200,550,750,950], 19: [16,80,220,600,800,1000],
        21: [18,90,250,700,875,1050], 23: [18,90,250,700,875,1050], 24: [20,100,300,750,925,1100],
        26: [22,110,330,800,975,1150], 27: [22,110,330,800,975,1150], 29: [24,120,360,850,1025,1200],
        31: [26,130,390,900,1100,1275], 32: [26,130,390,900,1100,1275], 34: [28,150,450,1000,1200,1400],
        37: [35,175,500,1100,1300,1500], 39: [50,200,600,1400,1700,2000]
    };
    
    for (const i in r) {
        tiles[i].rents = r[i];
        tiles[i].rent = r[i][0];
    }
}

function generateId() {
    return Array.from({length: 32}, () => Math.floor(Math.random() * 16).toString(16)).join('');
}

function generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return Array.from({length: 6}, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}

function newPlayer(name) {
    if (!name || !name.trim() || name.trim().length > 20) {
        throw new Error('Prénom requis (20 caractères maximum).');
    }
    return {
        id: generateId(),
        token: generateId(),
        name: name.trim(),
        money: 1500,
        pos: 0,
        jail: false,
        jailTurns: 0,
        jailDouble: false,
        out: false,
        doubles: 0,
        bot: false,
        jailCards: []
    };
}

function getRoom(code) {
    if (!code || !rooms.has(code)) {
        throw new Error('Salon introuvable');
    }
    return rooms.get(code);
}

function getPlayer(s, token) {
    const p = s.players.filter(player => player.token === token);
    if (p.length !== 1) {
        throw new Error('Session invalide.');
    }
    return p[0];
}

function addEvent(s, type, details) {
    if (!s.eventSeq) { s.eventSeq = 0; s.events = []; }
    s.eventSeq++;
    const e = {id: s.eventSeq, type, ...details};
    s.events.push(e);
    if (s.events.length > 160) {
        s.events = s.events.slice(-160);
    }
}

function addLog(s, message) {
    s.log.push(message);
    if (s.log.length > 60) {
        s.log = s.log.slice(-60);
    }
}

function announce(s, p, message, kind = 'notice') {
    addLog(s, message);
    addEvent(s, kind, {playerId: p.id, text: message});
}

function getRent(s, t) {
    if (t.mortgaged) return 0;
    
    if (t.kind === 'station') {
        const n = s.tiles.filter(x => x.kind === 'station' && x.owner === t.owner).length;
        return Math.floor(25 * Math.pow(2, n - 1));
    }
    
    if (t.kind === 'utility') {
        const n = s.tiles.filter(x => x.kind === 'utility' && x.owner === t.owner).length;
        const m = n === 2 ? 10 : 4;
        return (s.dice[0] + s.dice[1]) * m;
    }
    
    if (t.level > 0) return t.rents[t.level];
    
    if (t.owner && s.tiles.filter(x => x.group === t.group && x.owner !== t.owner).length === 0) {
        return 2 * t.rent;
    }
    
    return t.rent;
}

function movePlayer(s, p, steps) {
    const from = p.pos;
    const path = [];
    for (let i = 1; i <= steps; i++) {
        path.push((from + i) % s.tiles.length);
    }
    p.pos = (from + steps) % s.tiles.length;
    
    addEvent(s, 'move', {playerId: p.id, from, to: p.pos, path, jump: false});
    
    if (from + steps >= s.tiles.length) {
        p.money += 200;
        announce(s, p, p.name + ' passe le départ : +200 DH.');
    }
}

function jumpPlayer(s, p, destination) {
    const from = p.pos;
    p.pos = destination;
    addEvent(s, 'move', {playerId: p.id, from, to: destination, path: [destination], jump: true});
}

function sendToJail(s, p) {
    jumpPlayer(s, p, 10);
    p.jail = true;
    p.jailTurns = 0;
    p.jailDouble = false;
    p.doubles = 0;
    announce(s, p, p.name + ' va en prison.');
}

function pay(s, p, amount, receiver) {
    if (amount <= 0) return;
    if (!s.debts) s.debts = [];
    
    const receiverId = receiver ? receiver.id : '';
    s.debts.push({player: p.id, receiver: receiverId, amount: Math.floor(amount)});
    settleDebts(s);
}

function settleDebts(s) {
    while (s.debts.length > 0) {
        const d = s.debts[0];
        const payer = s.players.find(p => p.id === d.player);
        
        if (payer.money < d.amount) return;
        
        payer.money -= d.amount;
        
        if (d.receiver) {
            const creditor = s.players.find(p => p.id === d.receiver);
            creditor.money += d.amount;
        }
        
        s.debts.shift();
    }
}

function newCardDecks() {
    const newCard = (title, text, effect, value = 0) => ({title, text, effect, value});
    
    const chance = [
        newCard('Cap sur le depart', 'Retournez au depart et recevez 200 DH.', 'go'),
        newCard('Voyage sur la cote', 'Avancez a Victoria. Recevez 200 DH si vous passez le depart.', 'move', 39),
        newCard('Rendez-vous au sud', 'Avancez a Ouarzazate. Recevez 200 DH si vous passez le depart.', 'move', 24),
        newCard('Visite imperiale', 'Avancez a Meknes. Recevez 200 DH si vous passez le depart.', 'move', 11),
        newCard('Train express', 'Rejoignez la prochaine gare. Si elle appartient a un adversaire, payez le double du loyer.', 'station'),
        newCard('Correspondance ferroviaire', 'Rejoignez la prochaine gare. Si elle appartient a un adversaire, payez le double du loyer.', 'station'),
        newCard('Visite technique', 'Rejoignez la prochaine compagnie. Si elle est adverse, relancez les des et payez 10 fois leur total.', 'utility'),
        newCard('Benefice bancaire', 'Votre placement vous rapporte 50 DH.', 'cash', 50),
        newCard('Bon de liberation', 'Gardez cette carte. Vous choisissez quand utiliser cette carte.', 'free'),
        newCard('Demi-tour', 'Reculez de trois cases et appliquez la case arrivee.', 'back'),
        newCard('Convocation', 'Allez en prison sans prime de depart.', 'jail'),
        newCard('Entretien des logements', 'Payez 25 DH par maison et 100 DH par hotel.', 'repairs', 25),
        newCard('Exces de vitesse', 'Payez une amende de 15 DH.', 'cash', -15),
        newCard('Billet pour Fes', 'Rejoignez la gare de Fes. Recevez 200 DH si vous passez le depart.', 'move', 5),
        newCard('Participation collective', 'Versez 50 DH a chaque autre joueur encore en partie.', 'payall', 50),
        newCard('Placement arrive a terme', 'Recevez 150 DH de la banque.', 'cash', 150)
    ];
    
    const chest = [
        newCard('Nouveau depart', 'Rejoignez le depart et recevez 200 DH.', 'go'),
        newCard('Regularisation bancaire', 'La banque vous rembourse 200 DH.', 'cash', 200),
        newCard('Consultation medicale', 'Payez 50 DH de frais de consultation.', 'cash', -50),
        newCard('Petite vente', 'Une vente vous rapporte 50 DH.', 'cash', 50),
        newCard('Autorisation de sortie', 'Gardez cette carte pour sortir gratuitement de prison. Choisissez cette carte ou tentez un double.', 'free'),
        newCard('Passage au commissariat', 'Allez en prison sans recevoir la prime de depart.', 'jail'),
        newCard('Epargne debloquee', 'Recevez 100 DH de votre epargne.', 'cash', 100),
        newCard('Trop-percu rembourse', 'Recuperez 20 DH.', 'cash', 20),
        newCard('Votre anniversaire', 'Chaque autre joueur encore en partie vous verse 10 DH.', 'collectall', 10),
        newCard('Assurance versee', 'Recevez 100 DH de votre assurance.', 'cash', 100),
        newCard('Soins hospitaliers', 'Payez 100 DH de frais de soins.', 'cash', -100),
        newCard('Frais de scolarite', 'Payez 50 DH pour les frais scolaires.', 'cash', -50),
        newCard('Mission accomplie', 'Un service rendu vous rapporte 25 DH.', 'cash', 25),
        newCard('Travaux dans le quartier', 'Payez 40 DH par maison et 115 DH par hotel.', 'repairs', 40),
        newCard('Prix du quartier', 'Recevez un prix de 10 DH.', 'cash', 10),
        newCard('Heritage familial', 'Recevez un heritage de 100 DH.', 'cash', 100)
    ];
    
    const shuffle = arr => arr.sort(() => Math.random() - 0.5);
    
    return {
        chance: shuffle(chance),
        chest: shuffle(chest)
    };
}

function resolveLanding(s, p, multiplier = 1, utilityRoll = false) {
    const t = s.tiles[p.pos];
    
    if (t.price > 0 && t.owner && t.owner !== p.id && !t.mortgaged) {
        const owner = s.players.find(x => x.id === t.owner);
        let rent = getRent(s, t) * multiplier;
        
        if (utilityRoll) {
            const roll = [Math.floor(Math.random() * 6) + 1, Math.floor(Math.random() * 6) + 1];
            rent = 10 * (roll[0] + roll[1]);
            addEvent(s, 'dice', {playerId: p.id, dice: roll, text: 'Des de la compagnie (sans deplacement)'});
        }
        
        pay(s, p, rent, owner);
        announce(s, p, p.name + ' verse ' + rent + ' DH a ' + owner.name + '.');
    } else if (t.kind === 'tax') {
        pay(s, p, t.taxAmount, null);
        announce(s, p, p.name + ' paie ' + t.taxAmount + ' DH de taxes.');
    } else if (p.pos === 30) {
        sendToJail(s, p);
    } else if (['chance', 'chest'].includes(t.kind)) {
        drawCard(s, p, t.kind);
    }
}

function drawCard(s, p, deck) {
    if (!s.decks) s.decks = newCardDecks();
    
    const card = s.decks[deck][0];
    s.decks[deck] = s.decks[deck].slice(1);
    
    if (card.effect !== 'free') {
        s.decks[deck].push(card);
    }
    
    addEvent(s, 'card', {playerId: p.id, deck, title: card.title, text: card.text});
    addLog(s, p.name + ' : ' + card.title + ' — ' + card.text);
    
    switch (card.effect) {
        case 'cash':
            if (card.value >= 0) {
                p.money += card.value;
            } else {
                pay(s, p, -card.value, null);
            }
            break;
            
        case 'go':
            jumpPlayer(s, p, 0);
            p.money += 200;
            break;
            
        case 'jail':
            sendToJail(s, p);
            break;
            
        case 'free':
            p.jailCards.push({deck, card});
            break;
            
        case 'repairs':
            let houses = 0, hotels = 0;
            for (const t of s.tiles) {
                if (t.owner === p.id) {
                    if (t.level === 5) hotels++;
                    else houses += t.level;
                }
            }
            const hotelRate = deck === 'chest' ? 115 : 100;
            const bill = houses * card.value + hotels * hotelRate;
            pay(s, p, bill, null);
            announce(s, p, houses + ' maisons et ' + hotels + ' hotels : ' + bill + ' DH de travaux.');
            break;
            
        case 'payall':
            for (const other of s.players.filter(x => !x.out && x.id !== p.id)) {
                if (p.out || s.phase !== 'playing') break;
                pay(s, p, card.value, other);
            }
            break;
            
        case 'collectall':
            for (const other of s.players.filter(x => !x.out && x.id !== p.id)) {
                if (s.phase !== 'playing') break;
                pay(s, other, card.value, p);
            }
            break;
            
        case 'back':
            const from = p.pos;
            const path = [1, 2, 3].map(i => (from - i + 40) % 40);
            p.pos = path[path.length - 1];
            addEvent(s, 'move', {playerId: p.id, from, to: p.pos, path, jump: false});
            resolveLanding(s, p);
            break;
            
        case 'move':
        case 'station':
        case 'utility':
            let destination = card.value;
            
            if (card.effect !== 'move') {
                const targets = card.effect === 'station' ? [5, 15, 25, 35] : [12, 28];
                const next = targets.filter(x => x > p.pos);
                destination = next.length > 0 ? next[0] : targets[0];
            }
            
            const steps = (destination - p.pos + 40) % 40;
            movePlayer(s, p, steps);
            
            const mult = card.effect === 'station' ? 2 : 1;
            resolveLanding(s, p, mult, card.effect === 'utility');
            break;
    }
    
    s.botNext = Date.now() + 15000;
}

function nextTurn(s) {
    if (s.phase !== 'playing') return;
    
    const order = s.turnOrder || Array.from({length: s.players.length}, (_, i) => i);
    let slot = order.indexOf(s.turn);
    
    do {
        slot = (slot + 1) % order.length;
        s.turn = order[slot];
    } while (s.players[s.turn].out);
    
    s.rolled = false;
    s.botPhase = 'buy';
    s.botNext = Date.now() + 1800;
}

function startOpening(s) {
    s.phase = 'opening';
    s.turn = 0;
    s.rolled = false;
    s.openingGroups = [{ids: s.players.map(p => p.id)}];
    s.openingPending = s.players.map(p => p.id);
    s.openingScores = {};
    s.openingHistory = {};
    s.openingRound = 1;
    s.botNext = Date.now() + 2000;
    addLog(s, 'Tirage de l\'ordre : chacun lance deux dés. Le plus grand total commence.');
}

function invokeOpeningRoll(s, p) {
    if (s.phase !== 'opening' || s.players[s.turn].id !== p.id) {
        throw new Error('Attendez votre tour pour le tirage.');
    }
    
    const a = Math.floor(Math.random() * 6) + 1;
    const b = Math.floor(Math.random() * 6) + 1;
    const total = a + b;
    
    s.dice = [a, b];
    s.openingScores[p.id] = total;
    
    if (!s.openingHistory[p.id]) s.openingHistory[p.id] = [];
    s.openingHistory[p.id].push(total);
    
    addEvent(s, 'dice', {playerId: p.id, dice: [a, b], text: p.name + ' : tirage de l\'ordre'});
    addLog(s, p.name + ' obtient ' + a + ' + ' + b + ' = ' + total + ' pour l\'ordre de jeu.');
    
    s.openingPending = s.openingPending.slice(1);
    
    if (s.openingPending.length === 0) {
        const groups = [];
        
        for (const group of s.openingGroups) {
            if (group.ids.length === 1) {
                groups.push(group);
                continue;
            }
            
            const scores = [...new Set(group.ids.map(id => s.openingScores[id]))].sort((a, b) => b - a);
            for (const score of scores) {
                groups.push({ids: group.ids.filter(id => s.openingScores[id] === score)});
            }
        }
        
        s.openingGroups = groups;
        s.openingPending = groups.filter(g => g.ids.length > 1).flatMap(g => g.ids);
        
        if (s.openingPending.length === 0) {
            const ids = groups.flatMap(g => g.ids);
            s.turnOrder = ids.map(id => s.players.findIndex(p => p.id === id));
            s.turn = s.turnOrder[0];
            s.phase = 'playing';
            s.rolled = false;
            s.botPhase = 'buy';
            s.botNext = Date.now() + 5000;
            
            const names = ids.map(id => s.players.find(p => p.id === id).name);
            announce(s, s.players[s.turn], 'Ordre de jeu : ' + names.join(' > ') + '. La partie commence !');
            return;
        }
        
        s.openingRound++;
        announce(s, p, 'Égalité : seuls les joueurs à départager relancent. Les autres places sont conservées.');
    }
    
    s.turn = s.players.findIndex(p => p.id === s.openingPending[0]);
    s.botNext = Date.now() + 3000;
}

function assertTradable(s, t) {
    if (t.price <= 0 || !t.owner) {
        throw new Error('Propriete indisponible.');
    }
    if (t.kind === 'property' && s.tiles.filter(x => x.group === t.group && x.level > 0).length > 0) {
        throw new Error('Revendez toutes les maisons du groupe de couleur avant la vente.');
    }
}

function validateOfferedTiles(s, buyer, indices) {
    const seen = new Set();
    
    for (const i of indices) {
        if (i === null || i === undefined || typeof i !== 'number' || i >= s.tiles.length || seen.has(i)) {
            throw new Error('Liste de proprietes invalide.');
        }
        seen.add(i);
        
        const t = s.tiles[i];
        if (t.owner !== buyer || t.mortgaged) {
            throw new Error('Offrez uniquement vos biens non hypotheques.');
        }
        assertTradable(s, t);
    }
}

function invokeTradeAction(s, p, data) {
    if (s.phase !== 'playing' || p.out) {
        throw new Error('Negociation impossible.');
    }
    
    if (data.type === 'sellhouse') {
        if (data.index === null || data.index === undefined || data.index >= s.tiles.length) {
            throw new Error('Case invalide.');
        }
        
        const t = s.tiles[data.index];
        if (t.owner !== p.id || t.level < 1) {
            throw new Error('Aucune maison a vendre.');
        }
        
        if (s.tiles.filter(x => x.group === t.group && x.level > t.level).length > 0) {
            throw new Error('Revendez les maisons de facon equilibree : commencez par les terrains les plus construits.');
        }
        
        t.level--;
        p.money += Math.floor(t.build / 2);
        announce(s, p, p.name + ' revend une maison de ' + t.name + '.');
        settleDebts(s);
        return;
    }
    
    if (data.type === 'offer') {
        if (s.offer) throw new Error('Terminez la negociation en cours.');
        if (data.index === null || data.index === undefined || data.index >= s.tiles.length) {
            throw new Error('Case invalide.');
        }
        
        const t = s.tiles[data.index];
        assertTradable(s, t);
        
        if (t.owner === p.id) throw new Error('Cette propriete vous appartient deja.');
        if (t.mortgaged) throw new Error('Levez l\'hypotheque avant cet echange.');
        if (!data.amount || data.amount > p.money) throw new Error('Montant invalide ou argent insuffisant.');
        
        const offered = data.offered || [];
        validateOfferedTiles(s, p.id, offered);
        
        s.offer = {
            index: data.index,
            buyer: p.id,
            seller: t.owner,
            respondent: t.owner,
            amount: data.amount,
            offered
        };
        
        addLog(s, p.name + ' propose ' + data.amount + ' DH pour ' + t.name + '.');
        return;
    }
    
    const o = s.offer;
    if (!o) throw new Error('Cette offre est terminee.');
    if (![o.buyer, o.seller].includes(p.id)) throw new Error('Cette offre ne vous concerne pas.');
    
    if (data.type === 'canceloffer') {
        s.offer = null;
        addLog(s, p.name + ' annule la negociation.');
        return;
    }
    
    if (p.id !== o.respondent) throw new Error('Attendez la reponse de votre partenaire.');
    
    if (data.type === 'rejectoffer') {
        s.offer = null;
        addLog(s, p.name + ' refuse l\'offre.');
        return;
    }
    
    const buyer = s.players.find(x => x.id === o.buyer);
    const seller = s.players.find(x => x.id === o.seller);
    const t = s.tiles[o.index];
    
    if (buyer.out || seller.out || t.owner !== seller.id || t.mortgaged) {
        s.offer = null;
        throw new Error('La propriete a change de proprietaire.');
    }
    
    assertTradable(s, t);
    validateOfferedTiles(s, buyer.id, o.offered);
    
    if (data.type === 'counteroffer') {
        if (!data.amount) throw new Error('Montant invalide.');
        if (data.offered !== undefined) {
            validateOfferedTiles(s, buyer.id, data.offered);
            o.offered = data.offered;
        }
        o.amount = data.amount;
        o.respondent = p.id === o.buyer ? o.seller : o.buyer;
        addLog(s, p.name + ' propose maintenant ' + o.amount + ' DH.');
        return;
    }
    
    if (buyer.money < o.amount) {
        throw new Error('L\'acheteur n\'a plus assez d\'argent. Refusez ou negociez un autre montant.');
    }
    
    buyer.money -= o.amount;
    seller.money += o.amount;
    t.owner = buyer.id;
    
    for (const i of o.offered) {
        s.tiles[i].owner = seller.id;
    }
    
    s.offer = null;
    settleDebts(s);
    announce(s, buyer, buyer.name + ' achete ' + t.name + ' a ' + seller.name + ' pour ' + o.amount + ' DH.', 'purchase');
}

function invokeFinanceAction(s, p, data) {
    if (s.phase !== 'playing' || p.out || s.offer) {
        throw new Error('Gestion indisponible.');
    }
    
    if (data.type === 'bankrupt') {
        const d = s.debts.find(x => x.player === p.id);
        if (!d) throw new Error('Aucune dette.');
        
        const creditor = d.receiver ? s.players.find(x => x.id === d.receiver) : null;
        
        for (const t of s.tiles) {
            if (t.owner === p.id) {
                p.money += Math.floor(t.level * t.build / 2);
                t.level = 0;
                
                if (creditor) {
                    t.owner = creditor.id;
                } else {
                    t.owner = '';
                    t.mortgaged = false;
                }
            }
        }
        
        if (creditor) creditor.money += p.money;
        p.money = 0;
        p.out = true;
        
        for (const held of p.jailCards) {
            s.decks[held.deck].push(held.card);
        }
        p.jailCards = [];
        
        s.debts = s.debts.filter(x => x.player !== p.id);
        
        for (const claim of s.debts) {
            if (claim.receiver === p.id) {
                claim.receiver = creditor ? creditor.id : '';
            }
        }
        
        announce(s, p, p.name + ' declare faillite.');
        
        const alive = s.players.filter(x => !x.out);
        if (alive.length === 1) {
            s.phase = 'finished';
            s.turn = s.players.indexOf(alive[0]);
            s.debts = [];
            announce(s, alive[0], alive[0].name + ' gagne !', 'win');
        } else if (s.players[s.turn].out) {
            nextTurn(s);
        }
        
        settleDebts(s);
        return;
    }
    
    if (data.index === null || data.index === undefined || data.index >= s.tiles.length) {
        throw new Error('Case invalide.');
    }
    
    const t = s.tiles[data.index];
    if (t.owner !== p.id || t.price <= 0) {
        throw new Error('Ce bien ne vous appartient pas.');
    }
    
    const value = Math.floor(t.price / 2);
    
    if (data.type === 'mortgage') {
        if (t.mortgaged) throw new Error('Bien deja hypotheque.');
        assertTradable(s, t);
        
        t.mortgaged = true;
        p.money += value;
        announce(s, p, p.name + ' hypotheque ' + t.name + ' : +' + value + ' DH.');
    } else {
        if (s.debts.length > 0) throw new Error('Reglez les dettes avant de lever une hypotheque.');
        
        const cost = value + Math.ceil(value / 10);
        if (!t.mortgaged || p.money < cost) throw new Error('Remboursement impossible.');
        
        p.money -= cost;
        t.mortgaged = false;
        announce(s, p, p.name + ' leve l\'hypotheque de ' + t.name + ' : ' + cost + ' DH.');
    }
    
    settleDebts(s);
}

function invokeGameAction(s, p, data) {
    if (['mortgage', 'unmortgage', 'bankrupt'].includes(data.type)) {
        invokeFinanceAction(s, p, data);
        return;
    }
    
    if (s.debts && s.debts.length > 0 && !['sellhouse', 'offer', 'acceptoffer', 'rejectoffer', 'counteroffer', 'canceloffer'].includes(data.type)) {
        throw new Error('Reglez les dettes avant de continuer.');
    }
    
    if (['offer', 'acceptoffer', 'rejectoffer', 'counteroffer', 'canceloffer', 'sellhouse'].includes(data.type)) {
        invokeTradeAction(s, p, data);
        return;
    }
    
    if (data.type === 'addbot') {
        if (s.phase !== 'lobby' || p.id !== s.host || s.players.length >= 6) {
            throw new Error('Ajout du robot impossible.');
        }
        const bot = newPlayer('Robot ' + (s.players.filter(x => x.bot).length + 1));
        bot.bot = true;
        s.players.push(bot);
        addLog(s, bot.name + ' rejoint la table.');
        return;
    }
    
    if (data.type === 'start') {
        if (p.id !== s.host || s.phase !== 'lobby' || s.players.length < 2) {
            throw new Error('Il faut être l\'hôte et avoir au moins 2 joueurs.');
        }
        startOpening(s);
        return;
    }
    
    if (data.type === 'orderroll') {
        invokeOpeningRoll(s, p);
        return;
    }
    
    if (s.phase !== 'playing' || s.players[s.turn].id !== p.id || p.out) {
        throw new Error('Ce n\'est pas votre tour.');
    }
    
    if (s.offer) {
        throw new Error('Terminez ou annulez la negociation avant de continuer le tour.');
    }
    
    switch (data.type) {
        case 'roll':
        case 'payjail':
        case 'usejail':
            if (s.rolled) throw new Error('Vous avez déjà lancé les dés.');
            if (data.type === 'usejail' && p.jailCards.length === 0) {
                throw new Error('Aucune carte de sortie de prison.');
            }
            if (['payjail', 'usejail'].includes(data.type) && !p.jail) {
                throw new Error('Vous n\'etes pas en prison.');
            }
            
            s.rolled = true;
            s.botPhase = 'buy';
            p.jailDouble = false;
            let tryDouble = false;
            
            if (p.jail) {
                if (data.type === 'usejail') {
                    const held = p.jailCards[0];
                    p.jailCards = p.jailCards.slice(1);
                    s.decks[held.deck].push(held.card);
                    p.jail = false;
                    announce(s, p, p.name + ' utilise sa carte de sortie de prison.');
                } else if (data.type === 'payjail' || p.jailTurns >= 2) {
                    pay(s, p, 50, null);
                    p.jail = false;
                    announce(s, p, p.name + ' doit 50 DH pour sortir de prison.');
                    if (s.debts.length > 0) {
                        s.rolled = false;
                        p.jailTurns = 0;
                        return;
                    }
                } else {
                    tryDouble = true;
                    p.jailTurns++;
                }
                
                if (!p.jail) p.jailTurns = 0;
            }
            
            const a = Math.floor(Math.random() * 6) + 1;
            const b = Math.floor(Math.random() * 6) + 1;
            s.dice = [a, b];
            
            addEvent(s, 'dice', {playerId: p.id, dice: [a, b], text: p.name + ' lance les dés : ' + a + ' + ' + b});
            s.botNext = Date.now() + 6000;
            
            if (tryDouble) {
                if (a !== b) {
                    p.doubles = 0;
                    announce(s, p, p.name + ' reste en prison (tentative ' + p.jailTurns + '/2).');
                    return;
                }
                
                p.jail = false;
                p.jailTurns = 0;
                p.jailDouble = true;
                p.doubles = 0;
                s.rolled = false;
                announce(s, p, p.name + ' sort gratuitement avec un double. Relancez les des pour avancer.');
                return;
            }
            
            if (a === b && !p.jailDouble) {
                p.doubles++;
            } else {
                p.doubles = 0;
            }
            
            if (p.doubles >= 3) {
                announce(s, p, 'Trois doubles de suite !');
                sendToJail(s, p);
                return;
            }
            
            movePlayer(s, p, a + b);
            const t = s.tiles[p.pos];
            addLog(s, p.name + ' lance ' + a + ' + ' + b + ' et arrive à ' + t.name + '.');
            
            if (t.price > 0 && t.owner && t.owner !== p.id) {
                const owner = s.players.find(x => x.id === t.owner);
                const rent = getRent(s, t);
                pay(s, p, rent, owner);
                announce(s, p, p.name + ' verse ' + rent + ' DH de loyer à ' + owner.name + '.');
            } else if (t.kind === 'tax') {
                pay(s, p, t.taxAmount, null);
                announce(s, p, p.name + ' paie ' + t.taxAmount + ' DH de taxes.');
            } else if (p.pos === 30) {
                sendToJail(s, p);
            } else if (['chance', 'chest'].includes(t.kind)) {
                drawCard(s, p, t.kind);
            }
            
            if (p.out) nextTurn(s);
            break;
            
        case 'buy':
            if (!s.rolled) throw new Error('Lancez les dés avant d\'acheter.');
            const tile = s.tiles[p.pos];
            if (tile.price <= 0 || tile.owner || p.money < tile.price) {
                throw new Error('Achat impossible.');
            }
            p.money -= tile.price;
            tile.owner = p.id;
            announce(s, p, p.name + ' achète ' + tile.name + ' pour ' + tile.price + ' DH.', 'purchase');
            break;
            
        case 'end':
            if (!s.rolled) throw new Error('Lancez les dés avant de terminer.');
            if (s.dice[0] === s.dice[1] && !p.jail && !p.jailDouble) {
                s.rolled = false;
                s.botNext = Date.now() + 2000;
                announce(s, p, p.name + ' a fait un double et rejoue.');
            } else {
                p.doubles = 0;
                nextTurn(s);
            }
            break;
            
        case 'build':
            if (data.index === null || data.index === undefined || data.index >= s.tiles.length) {
                throw new Error('Case invalide.');
            }
            
            const buildTile = s.tiles[data.index];
            if (buildTile.owner !== p.id) {
                throw new Error('Cette propriété ne vous appartient pas.');
            }
            
            if (buildTile.kind !== 'property' || buildTile.level >= 5 || p.money < buildTile.build) {
                throw new Error('Construction impossible.');
            }
            
            const group = s.tiles.filter(x => x.group === buildTile.group);
            if (group.filter(x => x.owner !== p.id || x.mortgaged || x.level < buildTile.level).length > 0) {
                throw new Error('Possédez tout le groupe et construisez de façon équilibrée.');
            }
            
            p.money -= buildTile.build;
            buildTile.level++;
            announce(s, p, p.name + ' construit à ' + buildTile.name + ' (niveau ' + buildTile.level + ').', 'build');
            break;
            
        default:
            throw new Error('Action inconnue.');
    }
}

function invokeDebtBot(s) {
    if (!s.debts || s.debts.length === 0) return;
    
    const d = s.debts[0];
    const p = s.players.find(x => x.id === d.player);
    if (!p || !p.bot) return;
    
    // Try to sell houses first
    for (let i = 0; i < s.tiles.length; i++) {
        const t = s.tiles[i];
        if (t.owner === p.id && t.level > 0) {
            const higher = s.tiles.filter(x => x.group === t.group && x.level > t.level);
            if (higher.length === 0) {
                invokeTradeAction(s, p, {type: 'sellhouse', index: i});
                return;
            }
        }
    }
    
    // Try to mortgage
    for (let i = 0; i < s.tiles.length; i++) {
        const t = s.tiles[i];
        if (t.owner === p.id && !t.mortgaged) {
            invokeFinanceAction(s, p, {type: 'mortgage', index: i});
            return;
        }
    }
    
    // Bankrupt
    invokeFinanceAction(s, p, {type: 'bankrupt'});
}

function invokeBotStep(s) {
    if (s.phase === 'opening') {
        const p = s.players[s.turn];
        if (p.bot && Date.now() >= s.botNext) {
            invokeOpeningRoll(s, p);
        }
        return;
    }
    
    if (s.debts && s.debts.length > 0 && !s.offer) {
        invokeDebtBot(s);
        return;
    }
    
    if (s.phase === 'playing' && s.offer) {
        const o = s.offer;
        const bot = s.players.filter(p => p.id === o.respondent && p.bot);
        
        if (bot.length > 0) {
            const t = s.tiles[o.index];
            const group = s.tiles.filter(x => x.group === t.group && x.owner === bot[0].id);
            let factor = 1.4;
            
            if (t.kind === 'property' && group.length > 1) {
                factor = 2.5;
            }
            
            const target = Math.ceil(t.price * factor);
            let extras = 0;
            for (const i of o.offered) {
                extras += s.tiles[i].price;
            }
            
            if (o.amount + extras >= target) {
                invokeTradeAction(s, bot[0], {type: 'acceptoffer'});
            } else if (o.amount + extras < t.price * 0.5) {
                invokeTradeAction(s, bot[0], {type: 'rejectoffer'});
            } else {
                invokeTradeAction(s, bot[0], {type: 'counteroffer', amount: Math.max(0, target - extras)});
            }
        }
        return;
    }
    
    if (s.phase !== 'playing') return;
    
    const p = s.players[s.turn];
    if (!p.bot) return;
    
    if (s.botNext && Date.now() < s.botNext) return;
    s.botNext = Date.now() + 1800;
    
    if (!s.rolled) {
        let type = 'roll';
        if (p.jail && p.jailCards.length > 0) {
            type = 'usejail';
        }
        invokeGameAction(s, p, {type});
        return;
    }
    
    if (s.botPhase === 'buy') {
        s.botPhase = 'build';
        const t = s.tiles[p.pos];
        if (t.price > 0 && !t.owner && p.money >= t.price + 150) {
            invokeGameAction(s, p, {type: 'buy'});
            return;
        }
    }
    
    if (s.botPhase === 'build') {
        s.botPhase = 'end';
        
        for (let i = 0; i < s.tiles.length; i++) {
            const t = s.tiles[i];
            if (t.kind !== 'property' || t.owner !== p.id || t.level >= 5 || p.money < t.build + 300) {
                continue;
            }
            
            const group = s.tiles.filter(x => x.group === t.group);
            if (group.filter(x => x.owner !== p.id || x.mortgaged || x.level < t.level).length === 0) {
                invokeGameAction(s, p, {type: 'build', index: i});
                return;
            }
        }
    }
    
    invokeGameAction(s, p, {type: 'end'});
}

// API Routes
app.get('/api/health', (req, res) => {
    res.json({app: 'quartiers', version: 10});
});

app.post('/api/create', (req, res) => {
    try {
        if (rooms.size >= 50) {
            throw new Error('Limite de salons atteinte : redémarrez le serveur.');
        }
        
        const p = newPlayer(req.body.name);
        let code;
        
        do {
            code = generateCode();
        } while (rooms.has(code));
        
        const s = {
            code,
            host: p.id,
            players: [p],
            tiles: newTiles(),
            turn: 0,
            phase: 'lobby',
            rolled: false,
            dice: [5, 3],
            log: [p.name + ' ouvre la table.'],
            events: [],
            eventSeq: 0,
            botPhase: 'buy',
            botNext: 0,
            debts: [],
            offer: null
        };
        
        rooms.set(code, s);
        
        if (req.body.mode === 'solo') {
            invokeGameAction(s, p, {type: 'addbot'});
            invokeGameAction(s, p, {type: 'start'});
        }
        
        res.json({code, token: p.token});
    } catch (error) {
        res.status(400).json({error: error.message});
    }
});

app.post('/api/join', (req, res) => {
    try {
        const s = getRoom(req.body.code);
        
        if (s.phase !== 'lobby' || s.players.length >= 6) {
            throw new Error('Partie commencée ou salon complet.');
        }
        
        const p = newPlayer(req.body.name);
        s.players.push(p);
        addLog(s, p.name + ' rejoint la table.');
        
        res.json({code: s.code, token: p.token});
    } catch (error) {
        res.status(400).json({error: error.message});
    }
});

app.get('/api/state', (req, res) => {
    try {
        const s = getRoom(req.query.code);
        const p = getPlayer(s, req.query.token);
        
        // Mark player as active (last seen time)
        if (!s.lastSeen) s.lastSeen = {};
        s.lastSeen[p.id] = Date.now();

        // Check for disconnected players (inactive for more than 2 minutes)
        if (s.phase === 'playing' && !s.checkingDisconnect) {
            s.checkingDisconnect = true;
            const timeout = 120000; // 2 minutes

            for (const player of s.players) {
                if (!player.out && !player.bot && s.lastSeen[player.id]) {
                    const inactive = Date.now() - s.lastSeen[player.id];

                    if (inactive > timeout) {
                        // Player disconnected - return properties to bank
                        announce(s, player, player.name + ' a quitté la partie. Ses biens retournent à la banque.');

                        for (const t of s.tiles) {
                            if (t.owner === player.id) {
                                t.owner = '';
                                t.level = 0;
                                t.mortgaged = false;
                            }
                        }

                        player.out = true;
                        player.money = 0;

                        // Remove from debts
                        if (s.debts) {
                            s.debts = s.debts.filter(d => d.player !== player.id);
                        }

                        // Cancel offers involving this player
                        if (s.offer && (s.offer.buyer === player.id || s.offer.seller === player.id)) {
                            s.offer = null;
                            addLog(s, 'Négociation annulée : un joueur a quitté.');
                        }

                        // Next turn if it was their turn
                        if (s.players[s.turn].id === player.id) {
                            nextTurn(s);
                        }

                        // Check if game is over
                        const alive = s.players.filter(x => !x.out);
                        if (alive.length === 1) {
                            s.phase = 'finished';
                            s.turn = s.players.indexOf(alive[0]);
                            announce(s, alive[0], alive[0].name + ' gagne !', 'win');
                        }
                    }
                }
            }

            s.checkingDisconnect = false;
        }

        invokeBotStep(s);
        
        const publicState = {};
        for (const k in s) {
            if (!['botNext', 'botPhase', 'decks', 'lastSeen', 'checkingDisconnect'].includes(k)) {
                publicState[k] = s[k];
            }
        }
        
        publicState.players = s.players.map(player => {
            const copy = {};
            for (const k in player) {
                if (k !== 'token') {
                    copy[k] = player[k];
                }
            }

            // Add inactivity timer for non-bot players
            if (!player.bot && !player.out && s.lastSeen[player.id]) {
                const inactive = Date.now() - s.lastSeen[player.id];
                const timeout = 120000; // 2 minutes
                const remaining = Math.max(0, timeout - inactive);
                copy.inactiveSeconds = Math.floor(inactive / 1000);
                copy.timeoutSeconds = Math.floor(remaining / 1000);
            }

            return copy;
        });
        
        publicState.me = p.id;
        res.json(publicState);
    } catch (error) {
        res.status(400).json({error: error.message});
    }
});

app.post('/api/action', (req, res) => {
    try {
        const s = getRoom(req.body.code);
        const p = getPlayer(s, req.body.token);
        
        invokeGameAction(s, p, req.body);
        
        res.json({ok: true});
    } catch (error) {
        res.status(400).json({error: error.message});
    }
});

// Start server
app.listen(PORT, () => {
    console.log(`🎲 QUARTIERS : http://localhost:${PORT}`);
    console.log(`Serveur prêt pour déploiement sur Render`);
});
