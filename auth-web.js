/* Google Identity Services stays on the website; Android authenticates natively. */
window.QuartiersAuth = {allowed: document.documentElement.classList.contains('quartiers-mobile'), account: null, pending: false};
if (window.QuartiersAuth.allowed) {
  window.QuartiersAuth.ready = Promise.resolve();
} else {
  const auth = window.QuartiersAuth;
  const message = document.querySelector('#google-message');
  const fields = document.querySelector('#game-entry');
  const profile = document.querySelector('#google-profile');
  let retryTimer, retries = 0, running = false;
  async function request(path, data) {
    const response = await fetch(path, {method: data ? 'POST' : 'GET', credentials: 'same-origin',
      headers: data ? {'Content-Type': 'application/json'} : {}, body: data ? JSON.stringify(data) : undefined,
      signal: AbortSignal.timeout(15000)});
    const result = await response.json();
    if (!response.ok) {const error = Error(result.error || 'Connexion impossible.');error.status = response.status;error.code = result.code;throw error;}
    return result;
  }
  function update(account) {
    auth.account = account;auth.allowed = !!account;auth.pending = false;
    fields.hidden = !account;fields.disabled = !account;
    document.querySelector('#google-login').hidden = !!account;
    profile.hidden = !account;
    if (account) {
      localStorage.setItem('quartiers-google-known', account.id);
      document.querySelector('#google-name').textContent = account.name;
      const avatar = document.querySelector('#google-picture');avatar.hidden = !account.picture;avatar.src = account.picture || '';
      document.querySelector('#name').value = account.name.slice(0, 20);
      message.textContent = 'Connecté avec Google.';
      retries = 0;clearTimeout(retryTimer);
    }
    window.dispatchEvent(new CustomEvent('quartiers-account', {detail: account}));
  }
  async function setup() {
    if (running) return;
    running = true;clearTimeout(retryTimer);auth.pending = true;
    message.textContent = 'Reprise de votre connexion…';
    document.querySelector('#google-button').hidden = true;
    document.querySelector('#google-retry').hidden = true;
    try {
      // Restore the first-party cookie before loading Google or requesting a
      // fresh login. A timeout is not proof that the account has signed out.
      try {update((await request('/api/auth/me')).account);return;}
      catch (error) {if (error.code === 'AUTH_CONFIGURATION') {auth.pending = false;message.textContent = 'La connexion Google doit encore être configurée par le propriétaire du jeu.';return;}if (error.status !== 401) throw error;update(null);}
      const configuration = await request('/api/auth/config');
      if (!configuration.configured) {message.textContent = 'La connexion Google est en cours de configuration par le propriétaire du jeu.';return;}
      message.textContent = 'Votre compte de jeu est créé automatiquement à la connexion.';
      if (!window.google?.accounts?.id) await new Promise((resolve, reject) => {
        const script = document.createElement('script');script.src = 'https://accounts.google.com/gsi/client';script.async = true;
        const timer = setTimeout(() => reject(Error('Google est inaccessible. Réessayez.')), 15000);
        script.onload = () => {clearTimeout(timer);resolve();};script.onerror = () => {clearTimeout(timer);reject(Error('Google est inaccessible. Réessayez.'));};document.head.append(script);
      });
      google.accounts.id.initialize({client_id: configuration.clientId, nonce: configuration.nonce, auto_select: true,
        callback: async ({credential}) => {
          message.textContent = 'Connexion…';
          try {update((await request('/api/auth/google', {credential, nonce: configuration.nonce, platform: 'web'})).account);}
          catch (error) {message.textContent = error.message;document.querySelector('#google-retry').hidden = false;}
        }});
      const button = document.querySelector('#google-button');button.replaceChildren();button.hidden = false;
      google.accounts.id.renderButton(button, {type: 'standard', theme: 'outline', size: 'large', text: 'continue_with', locale: 'fr', width: 280});
      // A previous successful sign-in can use Google's automatic account
      // selection when the browser permits it. Explicit logout clears this hint.
      if (localStorage.getItem('quartiers-google-known')) google.accounts.id.prompt?.();
    } catch (error) {
      auth.pending = true;
      message.textContent = 'Connexion temporairement indisponible. Votre compte enregistré est conservé. Réessayez dans un instant.';
      document.querySelector('#google-retry').hidden = false;
      if (retries++ < 2) retryTimer = setTimeout(() => {auth.ready = setup();}, 5000);
    } finally {running = false;}
  }
  auth.expire = () => {update(null);auth.ready = setup();};
  document.querySelector('#google-retry').onclick = () => {retries = 0;auth.ready = setup();};
  window.addEventListener('online', () => {if (auth.pending) {retries = 0;auth.ready = setup();}});
  document.querySelector('#google-logout').onclick = async () => {
    try {
      clearTimeout(retryTimer);
      await window.quartiersLeaveForLogout?.();
      await request('/api/auth/logout', {});
      localStorage.removeItem('quartiers-google-known');
      window.dispatchEvent(new Event('quartiers-before-logout'));update(null);
      window.google?.accounts?.id.disableAutoSelect();location.reload();
    } catch (error) {message.textContent = error.message;}
  };
  auth.ready = setup();
}
