// Local integration tests only. The normal production entry point never loads
// this file and contains no test-token or anonymous-authentication bypass.
if (process.env.NODE_ENV !== 'test' || process.env.GOOGLE_CLIENT_ID !== 'test-client.apps.googleusercontent.com') throw Error('Test Google verifier requires the isolated test environment');
const {OAuth2Client} = require('google-auth-library');
OAuth2Client.prototype.verifyIdToken = async function ({idToken, audience}) {
    const match = /^fixture:([a-z]+)(?::([A-Za-z0-9_-]+))?$/.exec(idToken);
    if (!match) throw Error('Invalid test credential');
    return {getPayload: () => ({sub: 'test-' + match[1], name: match[1] === 'said' ? 'Said Google' : 'Ami Google',
        aud: audience, iss: 'https://accounts.google.com', exp: Math.floor(Date.now() / 1000) + 3600,
        nonce: match[2], picture: 'https://lh3.googleusercontent.com/test-photo'})};
};
