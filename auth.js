const crypto = require('node:crypto');
const fs = require('node:fs');
const {OAuth2Client} = require('google-auth-library');

const COOKIE = 'quartiers_account';
const TTL = 7 * 24 * 60 * 60 * 1000;
function createAuth({clientId = process.env.GOOGLE_CLIENT_ID || require('./google-client.json').webClientId || '', verifyIdToken,
    accountsFile = process.env.ACCOUNTS_FILE || '/tmp/quartiers-accounts.json', now = Date.now} = {}) {
    const google = new OAuth2Client();
    const verify = verifyIdToken || (token => google.verifyIdToken({idToken: token, audience: clientId}));
    const sessions = new Map(), challenges = new Map();
    let accounts = {};
    if (fs.existsSync(accountsFile)) accounts = JSON.parse(fs.readFileSync(accountsFile, 'utf8'));
    const configured = /^[\w-]+\.apps\.googleusercontent\.com$/.test(clientId);
    function cleanup() {
        for (const [key, value] of sessions) if (value.expires <= now()) sessions.delete(key);
        for (const [key, value] of challenges) if (value.expires <= now()) challenges.delete(key);
    }
    function secure(req) {return req.secure || process.env.NODE_ENV === 'production';}
    function cookie(req, token, age) {
        return `${COOKIE}=${token}; Path=/api; HttpOnly; SameSite=Lax; Max-Age=${age}${secure(req) ? '; Secure' : ''}`;
    }
    function token(req) {
        const bearer = req.headers.authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/);
        if (req.headers.authorization) return bearer?.[1] || '';
        return (req.headers.cookie || '').split(';').map(s => s.trim()).find(s => s.startsWith(COOKIE + '='))?.slice(COOKIE.length + 1) || '';
    }
    function sameOrigin(req, res, next) {
        if (req.headers.origin) {
            const expected = process.env.PUBLIC_ORIGIN || process.env.RENDER_EXTERNAL_URL || `${req.protocol}://${req.get('host')}`;
            if (req.headers.origin !== expected.replace(/\/$/, '')) return res.status(403).json({error: 'Origine non autorisée.'});
        }
        next();
    }
    function requireAccount(req, res, next) {
        cleanup();
        if (!configured) return res.status(503).json({code: 'AUTH_CONFIGURATION', error: 'La connexion Google n’est pas encore configurée par le propriétaire du jeu.'});
        const session = sessions.get(token(req));
        if (!session) return res.status(401).json({code: 'AUTH_REQUIRED', error: 'Connectez-vous avec Google pour jouer.'});
        req.account = session.account;
        next();
    }
    function install(app) {
        app.use('/api', sameOrigin);
        app.get('/api/auth/config', (req, res) => {
            cleanup();
            res.set('Cache-Control', 'no-store');
            if (!configured) return res.json({required: true, configured: false, clientId: null});
            if (challenges.size >= 2000) return res.status(429).json({error: 'Trop de connexions. Réessayez dans quelques minutes.'});
            const nonce = crypto.randomBytes(24).toString('base64url');
            challenges.set(nonce, {expires: now() + 5 * 60 * 1000});
            res.json({required: true, configured: true, clientId, nonce});
        });
        app.post('/api/auth/google', async (req, res) => {
            res.set('Cache-Control', 'no-store');
            if (!configured) return res.status(503).json({code: 'AUTH_CONFIGURATION', error: 'La connexion Google n’est pas encore configurée.'});
            cleanup();
            const {credential, nonce, platform} = req.body;
            if (typeof credential !== 'string' || credential.length > 10000 || !challenges.has(nonce)) return res.status(401).json({error: 'Connexion Google expirée. Réessayez.'});
            challenges.delete(nonce);
            try {
                const ticket = await verify(credential);
                const claims = ticket.getPayload();
                // The official library checks Google's signature and expiry. Also
                // constrain all identity fields before they enter a game session.
                if (!claims || claims.aud !== clientId || !['accounts.google.com', 'https://accounts.google.com'].includes(claims.iss) ||
                    typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 255 || !Number.isFinite(claims.exp) || claims.exp * 1000 <= now() ||
                    (platform !== 'android' && claims.nonce !== nonce)) throw Error('Invalid Google identity');
                const id = crypto.createHash('sha256').update('google:' + claims.sub).digest('hex');
                let picture = '';
                try {
                    const url = new URL(claims.picture);
                    if (url.protocol === 'https:' && (url.hostname.endsWith('.googleusercontent.com') || url.hostname.endsWith('.ggpht.com')) && !url.username && !url.password) picture = url.href;
                } catch (_) { /* A Google account can have no public photograph. */ }
                const account = {id, name: String(claims.name || claims.given_name || 'Joueur').trim().slice(0, 80), picture,
                    createdAt: accounts[id]?.createdAt || now()};
                accounts[id] = account;
                fs.writeFileSync(accountsFile + '.tmp', JSON.stringify(accounts), {mode: 0o600});
                fs.renameSync(accountsFile + '.tmp', accountsFile);
                // Limit concurrent device sessions; logout invalidates a bearer
                // immediately. Restarting the server asks everyone to log in again.
                const previous = [...sessions].filter(([, s]) => s.account.id === id);
                while (previous.length >= 8) sessions.delete(previous.shift()[0]);
                if (sessions.size >= 4000) sessions.delete(sessions.keys().next().value);
                const bearer = crypto.randomBytes(32).toString('base64url');
                sessions.set(bearer, {account, expires: now() + TTL});
                res.setHeader('Set-Cookie', cookie(req, bearer, TTL / 1000));
                res.json({account, ...(platform === 'android' ? {token: bearer} : {})});
            } catch (_) {
                res.status(401).json({error: 'Connexion Google impossible. Réessayez avec votre compte Google.'});
            }
        });
        app.get('/api/auth/me', requireAccount, (req, res) => {
            res.set('Cache-Control', 'no-store');res.json({account: req.account});
        });
        app.post('/api/auth/logout', (req, res) => {
            sessions.delete(token(req));
            res.setHeader('Set-Cookie', cookie(req, '', 0));res.json({ok: true});
        });
        for (const route of ['/api/create', '/api/join', '/api/state', '/api/action']) app.use(route, requireAccount);
    }
    return {install};
}
module.exports = {createAuth};
