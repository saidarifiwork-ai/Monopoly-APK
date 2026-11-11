const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const net = require('node:net');
const {spawn} = require('node:child_process');
const express = require('express');
const {Pool} = require('pg');
const {openDatabase, unavailable} = require('../database');
const {createAuth} = require('../auth');
const address = process.env.POSTGRES_TEST_URL;
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

async function isolatedDatabase(t) {
    const admin = new Pool({connectionString: address});
    const schema = 'quartiers_test_' + crypto.randomBytes(6).toString('hex');
    await admin.query(`CREATE SCHEMA ${schema}`);
    const url = new URL(address);
    url.searchParams.set('options', '-csearch_path=' + schema);
    const pool = new Pool({connectionString: url.href});
    t.after(async () => {await pool.end();await admin.query(`DROP SCHEMA ${schema} CASCADE`);await admin.end();});
    return {url: url.href, pool};
}
async function serverHarness(t, databaseURL) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'quartiers-postgres-'));
    const files = {ACCOUNTS_FILE: path.join(dir, 'accounts.json'), SESSIONS_FILE: path.join(dir, 'sessions.json'), ROOMS_FILE: path.join(dir, 'rooms.json')};
    let child, base, output = '';
    async function stop(signal = 'SIGTERM') {
        if (!child || child.exitCode !== null) return;
        const exiting = new Promise(resolve => child.once('exit', resolve));
        child.kill(signal);await exiting;
    }
    t.after(async () => {await stop('SIGKILL');fs.rmSync(dir, {recursive: true, force: true});});
    async function start(useDatabase = true) {
        const socket = net.createServer();socket.listen(0, '127.0.0.1');await new Promise(r => socket.once('listening', r));
        const port = socket.address().port;await new Promise(r => socket.close(r));
        base = 'http://127.0.0.1:' + port;output = '';
        child = spawn(process.execPath, ['--require', './test/fixtures/google-auth-server.cjs', 'server.js'], {
            cwd: path.resolve(__dirname, '..'), env: {...process.env, ...files, PORT: String(port), NODE_ENV: 'test', GOOGLE_CLIENT_ID: 'test-client.apps.googleusercontent.com',
                DATABASE_URL: useDatabase ? databaseURL : '', REQUIRE_DATABASE: useDatabase ? 'true' : 'false'}, stdio: ['ignore', 'pipe', 'pipe']});
        child.stdout.on('data', chunk => output += chunk);child.stderr.on('data', chunk => output += chunk);
        for (let i = 0; i < 150; i++) {
            if (child.exitCode !== null) throw Error('Test server did not start: ' + output);
            try {const response = await fetch(base + '/api/health');if (response.ok) return;} catch (_) {}
            await pause(100);
        }
        throw Error('Server startup timed out: ' + output);
    }
    async function call(route, data, auth) {
        const response = await fetch(base + route, {method: data ? 'POST' : 'GET', headers: {
            ...(data ? {'Content-Type': 'application/json'} : {}), ...(auth?.token ? {Authorization: 'Bearer ' + auth.token} : auth?.cookie ? {Cookie: auth.cookie} : {})}, body: data ? JSON.stringify(data) : undefined});
        return {status: response.status, body: await response.json(), cookie: response.headers.get('set-cookie')};
    }
    async function login(identity, platform = 'android') {
        const {nonce} = (await call('/api/auth/config')).body;
        const response = await call('/api/auth/google', {credential: 'fixture:' + identity + ':' + nonce, nonce, platform});
        assert.equal(response.status, 200);
        return {...response.body, ...(response.cookie ? {cookie: response.cookie.split(';')[0]} : {})};
    }
    const state = (seat, auth) => call('/api/state?code=' + seat.code + '&token=' + seat.token, null, auth);
    return {files, start, stop, call, login, state};
}

test('database authentication failures return 503 without issuing or clearing credentials', async t => {
    const app = express();app.use(express.json());
    let fail = true;
    createAuth({clientId: 'test.apps.googleusercontent.com', persistence: {
        auth: {accounts: {}, sessions: {version: 1, sessions: []}}, save: async () => {if (fail) throw unavailable();}
    }, verifyIdToken: async () => ({getPayload: () => ({sub: 'said', name: 'Said', aud: 'test.apps.googleusercontent.com', iss: 'https://accounts.google.com', exp: Date.now()/1000 + 3600})})}).install(app);
    const server = app.listen(0, '127.0.0.1');await new Promise(r => server.once('listening', r));
    t.after(() => {server.closeAllConnections();server.close();});
    const base = 'http://127.0.0.1:' + server.address().port;
    const config = await (await fetch(base + '/api/auth/config')).json();
    const login = await fetch(base + '/api/auth/google', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({credential: 'verified', nonce: config.nonce, platform: 'android'})});
    assert.equal(login.status, 503);assert.equal((await login.json()).code, 'STORAGE_UNAVAILABLE');assert.equal(login.headers.get('set-cookie'), null);
    fail = false;
    const secondConfig = await (await fetch(base + '/api/auth/config')).json();
    const successful = await fetch(base + '/api/auth/google', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({credential:'verified',nonce:secondConfig.nonce,platform:'android'})});
    const valid = await successful.json();assert.equal(successful.status,200);
    fail = true;
    const logout = await fetch(base + '/api/auth/logout', {method: 'POST', headers: {'Content-Type': 'application/json',Authorization:'Bearer '+valid.token}, body: '{}'});
    assert.equal(logout.status, 503);assert.equal(logout.headers.get('set-cookie'), null);
    assert.equal((await fetch(base+'/api/auth/me',{headers:{Authorization:'Bearer '+valid.token}})).status,200,'a rejected database write must preserve the committed login');
    fail = false;
    assert.equal((await fetch(base+'/api/auth/logout',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+valid.token},body:'{}'})).status,200);
    assert.equal((await fetch(base+'/api/auth/me',{headers:{Authorization:'Bearer '+valid.token}})).status,401);

});

test('PostgreSQL imports local data once and restores Google sessions and game state after file loss and a hard restart', {skip: !address, timeout: 45000}, async t => {
    const db = await isolatedDatabase(t), h = await serverHarness(t, db.url);
    await h.start(false);
    const native = await h.login('said'), web = await h.login('said', 'web'), friend = await h.login('abdo');
    let seat = (await h.call('/api/create', {name: 'Said'}, web)).body;
    const guest = (await h.call('/api/join', {code: seat.code, name: 'Abdo'}, friend)).body;
    await h.call('/api/action', {...seat, type: 'start'}, web);
    for (let i = 0; i < 40; i++) {
        const state = (await h.state(seat, web)).body;if (state.phase === 'playing') break;
        await h.call('/api/action', {...(state.players[state.turn].id === state.me ? seat : guest), type: 'orderroll'}, state.players[state.turn].id === state.me ? web : friend);
    }
    const before = (await h.state(seat, web)).body;
    const stable = s => ({me: s.me, tiles: s.tiles, dice: s.dice, turn: s.turn, phase: s.phase, rolled: s.rolled,
        players: s.players.map(p => ({id: p.id, name: p.name, money: p.money, pos: p.pos, jail: p.jail}))});
    await h.stop();
    await h.start();
    assert.equal((await h.call('/api/health')).body.storage, 'postgresql');
    assert.equal((await h.call('/api/auth/me', null, native)).body.account.id, native.account.id);
    assert.equal((await h.call('/api/auth/me', null, web)).body.account.createdAt, web.account.createdAt);
    assert.deepEqual(stable((await h.state(seat, web)).body), stable(before));
    const persisted = (await db.pool.query("SELECT value FROM quartiers_documents WHERE key='auth'")).rows[0].value;
    assert(!JSON.stringify(persisted).includes(native.token));assert(!JSON.stringify(persisted).includes(web.cookie.split('=')[1]));
    const moved = (await h.call('/api/resume', {code: seat.code}, native)).body;
    assert.equal((await h.state(seat, web)).status, 409);
    seat = moved;
    const current = (await h.state(seat, native)).body;
    const actingSeat = current.players[current.turn].id === current.me ? seat : guest;
    const actingAuth = current.players[current.turn].id === current.me ? native : friend;
    assert.equal((await h.call('/api/action', {...actingSeat, type: 'roll'}, actingAuth)).status, 200);
    const afterAction = (await h.state(seat, native)).body;
    await h.stop('SIGKILL');
    for (const file of Object.values(h.files)) fs.rmSync(file, {force: true});
    await h.start();
    assert.equal((await h.call('/api/auth/me', null, native)).status, 200);
    assert.equal((await h.call('/api/auth/me', null, web)).status, 200);
    assert.deepEqual(stable((await h.state(seat, native)).body), stable(afterAction));
    assert(Object.values(h.files).every(file => !fs.existsSync(file)), 'database mode must not recreate temporary storage');
    assert((await h.call('/api/my-games', null, native)).body.games.some(g => g.code === seat.code));
    assert.equal((await h.call('/api/auth/logout', {}, native)).status, 200);
    await h.stop('SIGKILL');await h.start();
    assert.equal((await h.call('/api/auth/me', null, native)).status, 401);
    assert.equal((await h.call('/api/auth/me', null, web)).status, 200);
    // An outage is not a Google logout. Recovery reuses the existing cookie.
    await db.pool.query('ALTER TABLE quartiers_writer RENAME TO temporarily_unavailable');
    for (let i=0;i<60;i++) {if ((await h.call('/api/health')).status===503) break;await pause(100);}
    const offline = await h.call('/api/auth/me', null, web);
    assert.equal(offline.status, 503);assert.equal(offline.body.code, 'STORAGE_UNAVAILABLE');assert.equal(offline.cookie, null);
    await db.pool.query('ALTER TABLE temporarily_unavailable RENAME TO quartiers_writer');
    for (let i=0;i<80;i++) {if ((await h.call('/api/health')).status===200) break;await pause(100);}
    assert.equal((await h.call('/api/auth/me', null, web)).status, 200);
});

test('PostgreSQL snapshots are ordered, capture values immediately, and fence a superseded Render process', {skip: !address}, async t => {
    const db = await isolatedDatabase(t);
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'quartiers-legacy-'));
    t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
    const files = {connectionString: db.url, accountsFile: path.join(dir,'accounts'), sessionsFile: path.join(dir,'sessions'), roomsFile: path.join(dir,'rooms')};
    const first = await openDatabase(files);t.after(() => first.close());
    const room = {code:'ABCDEF', players:[], marker:1};
    const a = first.save('rooms', {ABCDEF:room});room.marker=2;
    const b = first.save('rooms', {ABCDEF:room});room.marker=99;
    await Promise.all([a,b]);
    assert.equal((await db.pool.query("SELECT value FROM quartiers_documents WHERE key='rooms'")).rows[0].value.ABCDEF.marker, 2);
    // Existing database documents win over stale or corrupt temporary files.
    fs.writeFileSync(files.accountsFile, 'broken');fs.writeFileSync(files.roomsFile, '{"stale":true}');
    const newest = await openDatabase(files);t.after(() => newest.close());
    assert.equal(newest.rooms.ABCDEF.marker, 2);
    await assert.rejects(first.save('rooms', {ABCDEF:{...room,marker:0}}), {code:'STORAGE_UNAVAILABLE'});
    await assert.rejects(first.save('auth', first.auth), {code:'STORAGE_UNAVAILABLE'});
    assert.equal(first.healthy, false);
    assert.equal((await db.pool.query("SELECT value FROM quartiers_documents WHERE key='rooms'")).rows[0].value.ABCDEF.marker, 2);
});

test('a configured database failure refuses startup without silently creating local data', {timeout: 15000}, async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'quartiers-no-fallback-'));
    t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
    const child = spawn(process.execPath, ['server.js'], {cwd:path.resolve(__dirname,'..'),env:{...process.env,DATABASE_URL:'postgresql://nobody:never-print-this-secret@127.0.0.1:1/no_database',ACCOUNTS_FILE:path.join(dir,'accounts'),ROOMS_FILE:path.join(dir,'rooms')},stdio:['ignore','pipe','pipe']});
    let output='';child.stdout.on('data',v=>output+=v);child.stderr.on('data',v=>output+=v);
    const code = await new Promise(resolve => child.once('exit', resolve));
    assert.equal(code,1);assert(!output.includes('never-print-this-secret'));assert(!output.includes('http://localhost:'));
    assert.deepEqual(fs.readdirSync(dir),[]);
});


test('PostgreSQL renews remembered devices without Google and retains renewal after a fresh process store', {skip: !address}, async t => {
 const db=await isolatedDatabase(t);let clock=Date.now(),verified=0,persistence,server;
 const files={connectionString:db.url,accountsFile:'/tmp/nonexistent-quartiers-renewal-accounts',sessionsFile:'/tmp/nonexistent-quartiers-renewal-sessions',roomsFile:'/tmp/nonexistent-quartiers-renewal-rooms'};
 async function boot(){
  persistence=await openDatabase(files);
  const app=express();app.use(express.json());
  createAuth({clientId:'test.apps.googleusercontent.com',persistence,now:()=>clock,verifyIdToken:async credential=>{
   verified++;const [identity,nonce]=credential.split(':');return {getPayload:()=>({sub:identity,name:identity,aud:'test.apps.googleusercontent.com',iss:'https://accounts.google.com',exp:clock/1000+3600,nonce})};
  }}).install(app);
  server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
  return 'http://127.0.0.1:'+server.address().port;
 }
 async function stop(){server.closeAllConnections();await new Promise(r=>server.close(r));await persistence.close();}
 let base=await boot();t.after(stop);
 async function login(platform){
  const config=await(await fetch(base+'/api/auth/config')).json();
  const response=await fetch(base+'/api/auth/google',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({credential:'said:'+config.nonce,nonce:config.nonce,platform})});
  return {body:await response.json(),cookie:response.headers.get('set-cookie')};
 }
 const native=await login('android'),web=await login('web');
 const headers=[{Authorization:'Bearer '+native.body.token},{Cookie:web.cookie.split(';')[0]}];
 clock+=60*24*60*60*1000;
 for(const auth of headers)assert.equal((await fetch(base+'/api/auth/me',{headers:auth})).status,200);
 await stop();base=await boot();clock+=40*24*60*60*1000;
 for(const auth of headers)assert.equal((await fetch(base+'/api/auth/me',{headers:auth})).status,200);
 assert.equal(verified,2,'restoration and renewal never ask Google to authenticate again');
 assert.equal((await fetch(base+'/api/auth/logout',{method:'POST',headers:{...headers[0],'Content-Type':'application/json'},body:'{}'})).status,200);
 await stop();base=await boot();
 assert.equal((await fetch(base+'/api/auth/me',{headers:headers[0]})).status,401);
 assert.equal((await fetch(base+'/api/auth/me',{headers:headers[1]})).status,200);
});

test('earned solo levels persist in PostgreSQL across device changes, sign-in and file loss', {skip:!address,timeout:30000},async t=>{
 const db=await isolatedDatabase(t),h=await serverHarness(t,db.url);
 await h.start(false);
 const web=await h.login('said','web'),phone=await h.login('said'),other=await h.login('abdo');
 const seat=(await h.call('/api/create',{mode:'solo',botLevel:'beginner'},web)).body;
 assert.equal((await h.call('/api/create',{mode:'solo',botLevel:'easy'},phone)).status,403);
 await h.stop();
 // Fixture a verified completed room on the private server disk, never through an API bypass.
 const rooms=JSON.parse(fs.readFileSync(h.files.ROOMS_FILE,'utf8')),room=rooms[seat.code];
 room.phase='finished';room.turn=0;room.players[1].out=true;room.players[1].money=0;
 fs.writeFileSync(h.files.ROOMS_FILE,JSON.stringify(rooms));
 await h.start();
 const win=await h.state(seat,web);assert.equal(win.status,200);assert.equal(win.body.soloUnlock.nextLevel,'easy');
 assert.deepEqual((await h.call('/api/progression',null,phone)).body.progression.unlockedLevels,['beginner','easy']);
 assert.deepEqual((await h.call('/api/progression',null,other)).body.progression.unlockedLevels,['beginner']);
 await h.stop('SIGKILL');for(const file of Object.values(h.files))fs.rmSync(file,{force:true});await h.start();
 assert.deepEqual((await h.call('/api/auth/me',null,phone)).body.account.soloProgress.completedLevels,['beginner']);
 const fresh=await h.login('said');assert.deepEqual(fresh.account.soloProgress.completedLevels,['beginner']);
 assert.equal((await h.call('/api/create',{mode:'solo',botLevel:'easy'},fresh)).status,200);
 assert.equal((await h.call('/api/create',{mode:'solo',botLevel:'normal'},fresh)).status,403);
});

test('PostgreSQL repairs old and current truncated card decks once and keeps repaired order on restart', {skip:!address,timeout:30000},async t=>{
    const db=await isolatedDatabase(t),h=await serverHarness(t,db.url);
    await h.start();
    const web=await h.login('said','web'),phone=await h.login('said'),friend=await h.login('abdo');
    let seat=(await h.call('/api/create',{},web)).body;
    await h.call('/api/join',{code:seat.code},friend);
    assert.equal((await h.call('/api/action',{...seat,type:'start'},web)).status,200);
    await h.stop();
    const readRooms=async()=>(await db.pool.query("SELECT value FROM quartiers_documents WHERE key='rooms'")).rows[0].value;
    for(const version of [3,4]) {
        const rooms=await readRooms(),room=rooms[seat.code],p=room.players[0];
        room.phase='playing';room.cardShuffleVersion=version;
        room.decks.chance=room.decks.chance.filter(c=>[39,24].includes(c.value));
        room.decks.chest=room.decks.chest.slice(0,2);
        p.jailCards=[{deck:'chance',card:{effect:'free'}}];p.money=777;p.pos=19;room.tiles[19].owner=p.id;
        await db.pool.query("UPDATE quartiers_documents SET value=$1::jsonb WHERE key='rooms'",[JSON.stringify(rooms)]);
        await h.start();
        assert.equal((await h.call('/api/health')).body.cardShuffle,4);
        const resuming=await h.call('/api/resume',{code:seat.code},phone);assert.equal(resuming.status,200);seat=resuming.body;
        const state=await h.state(seat,phone);assert.equal(state.status,200);
        assert.equal(state.body.cardShuffleVersion,4);assert(!('decks' in state.body),'future cards stay private');
        assert.equal(state.body.players[0].money,777);assert.equal(state.body.players[0].pos,19);assert.equal(state.body.tiles[19].owner,p.id);
        const repaired=(await readRooms())[seat.code];
        assert.equal(repaired.decks.chance.length,15);assert.equal(repaired.decks.chest.length,16);
        assert.equal(repaired.players[0].jailCards[0].card.id,'chance-9');
        for(const kind of ['chance','chest'])assert.equal(new Set(repaired.decks[kind].map(c=>c.id)).size,repaired.decks[kind].length);
        await h.stop('SIGKILL');await h.start();
        const again=await h.call('/api/resume',{code:seat.code},web);assert.equal(again.status,200);seat=again.body;
        const restored=(await readRooms())[seat.code];
        assert.deepEqual(restored.decks,repaired.decks,'valid queues must not change on a device switch or server restart');
        await h.stop();
    }
});
