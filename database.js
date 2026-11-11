const fs = require('node:fs');
const path = require('node:path');
const {Pool} = require('pg');

function unavailable() {
    const error = new Error('La sauvegarde est temporairement indisponible. Réessayez dans un instant.');
    error.status = 503;
    error.code = 'STORAGE_UNAVAILABLE';
    return error;
}
function readLegacy(file, fallback) {
    return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : fallback;
}
function validDocument(key, value) {
    const object = x => x && typeof x === 'object' && !Array.isArray(x);
    if (key === 'auth') return object(value) && object(value.accounts) && value.sessions?.version === 1 && Array.isArray(value.sessions.sessions);
    if (key === 'rooms') return object(value) && Object.values(value).every(room => object(room) && typeof room.code === 'string' && Array.isArray(room.players));
    return false;
}
class Database {
    constructor(pool) {
        this.pool = pool;
        this.healthy = true;
        this.tail = Promise.resolve();
        this.saved = new Map();
        pool.on('error', () => {this.healthy = false;});
    }
    async load(key, legacy, client = this.pool) {
        let result = await client.query('SELECT value FROM quartiers_documents WHERE key = $1', [key]);
        if (!result.rows.length) {
            const initial = legacy();
            if (!validDocument(key, initial)) throw Error('Données de migration invalides : ' + key);
            await client.query('INSERT INTO quartiers_documents(key, value) VALUES ($1, $2::jsonb) ON CONFLICT (key) DO NOTHING', [key, JSON.stringify(initial)]);
            result = await client.query('SELECT value FROM quartiers_documents WHERE key = $1', [key]);
        }
        const value = result.rows[0].value;
        if (!validDocument(key, value)) throw Error('Sauvegarde PostgreSQL invalide : ' + key);
        this.saved.set(key, JSON.stringify(value));
        return value;
    }
    save(key, value) {
        // Capture now, before another action changes the objects in memory.
        const snapshot = JSON.stringify(value);
        const work = this.tail.then(async () => {
            try {
                if (this.healthy && this.saved.get(key) === snapshot) {
                    const owner = await this.pool.query('SELECT generation FROM quartiers_writer WHERE id = true AND generation = $1', [this.generation]);
                    if (!owner.rowCount) throw unavailable();
                    return;
                }
                // The row lock fences writes from an older process after a new
                // server has loaded this database during a rolling deployment.
                const result = await this.pool.query(`WITH owner AS (
                    SELECT generation FROM quartiers_writer WHERE id = true AND generation = $3 FOR SHARE
                ) INSERT INTO quartiers_documents(key, value) SELECT $1, $2::jsonb FROM owner
                  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now() RETURNING key`, [key, snapshot, this.generation]);
                if (!result.rowCount) throw unavailable();
                this.saved.set(key, snapshot);
                this.healthy = true;
            } catch (_) {
                this.healthy = false;
                throw unavailable();
            }
        });
        this.tail = work.catch(() => {});
        return work;
    }
    async close() {await this.tail;await this.pool.end();}
}
async function openDatabase({connectionString = process.env.DATABASE_URL,
    accountsFile = process.env.ACCOUNTS_FILE || '/tmp/quartiers-accounts.json',
    sessionsFile = process.env.SESSIONS_FILE || accountsFile + '.sessions',
    roomsFile = process.env.ROOMS_FILE || '/tmp/monopoly-rooms.json'} = {}) {
    const url = new URL(connectionString);
    if (!['postgres:', 'postgresql:'].includes(url.protocol)) throw Error('DATABASE_URL doit désigner une base PostgreSQL.');
    // Verify the server certificate for hosted databases. Never disable verification.
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
    for (const key of ['ssl', 'sslmode', 'sslcert', 'sslkey', 'sslrootcert', 'uselibpqcompat']) url.searchParams.delete(key);
    const pool = new Pool({connectionString: url.href, max: 3, connectionTimeoutMillis: 10000,
        query_timeout: 10000, idleTimeoutMillis: 30000, application_name: 'quartiers-maroc',
        ssl: local ? false : {rejectUnauthorized: true, ...(process.env.DATABASE_SSL_CA ? {ca: process.env.DATABASE_SSL_CA} : {})}});
    const database = new Database(pool);
    let client;
    try {
        await pool.query(fs.readFileSync(path.join(__dirname, 'migrations/001-durable-storage.sql'), 'utf8'));
        client = await pool.connect();
        await client.query('BEGIN');
        const writer = await client.query('INSERT INTO quartiers_writer(id, generation) VALUES (true, 1) ON CONFLICT (id) DO UPDATE SET generation = quartiers_writer.generation + 1 RETURNING generation');
        database.generation = writer.rows[0].generation;
        database.auth = await database.load('auth', () => ({accounts: readLegacy(accountsFile, {}), sessions: readLegacy(sessionsFile, {version: 1, sessions: []})}), client);
        database.rooms = await database.load('rooms', () => readLegacy(roomsFile, {}), client);
        await client.query('COMMIT');
        client.release();client = null;
        return database;
    } catch (_) {
        if (client) {try {await client.query('ROLLBACK');} catch (_) {}client.release();}
        await database.close();
        throw Error('Initialisation PostgreSQL impossible. Vérifiez DATABASE_URL et les droits de la base ; aucun stockage temporaire de secours n’a été activé.');
    }
}
module.exports = {openDatabase, Database, unavailable};
