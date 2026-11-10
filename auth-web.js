/* Google Identity Services stays on the website; Android authenticates natively. */
window.QuartiersAuth = {allowed: document.documentElement.classList.contains('quartiers-mobile'), account: null};
if (window.QuartiersAuth.allowed) {
  window.QuartiersAuth.ready = Promise.resolve();
} else {
  const auth = window.QuartiersAuth;
  const message = document.querySelector('#google-message');
  const fields = document.querySelector('#game-entry');
  const profile = document.querySelector('#google-profile');
  async function request(path, data) {
    const response = await fetch(path, {method: data ? 'POST' : 'GET', credentials: 'same-origin',
      headers: data ? {'Content-Type': 'application/json'} : {}, body: data ? JSON.stringify(data) : undefined,
      signal: AbortSignal.timeout(15000)});
    const result = await response.json();
    if (!response.ok) throw Error(result.error || 'Connexion impossible.');
    return result;
  }
  function update(account) {
    auth.account = account;auth.allowed = !!account;
    fields.hidden = !account;fields.disabled = !account;
    document.querySelector('#google-login').hidden = !!account;
    profile.hidden = !account;
    if (account) {
      document.querySelector('#google-name').textContent = account.name;
      const avatar = document.querySelector('#google-picture');avatar.hidden = !account.picture;avatar.src = account.picture || '';
      document.querySelector('#name').value = account.name.slice(0, 20);
      message.textContent = 'Connecté avec Google.';
    }
    window.dispatchEvent(new CustomEvent('quartiers-account', {detail: account}));
  }
  auth.expire = () => {update(null);message.textContent = 'Reconnectez-vous avec Google pour jouer.';auth.ready = setup();};
  async function setup() {
    try {
      const configuration = await request('/api/auth/config');
      if (!configuration.configured) {message.textContent = 'La connexion Google est en cours de configuration par le propriétaire du jeu.';return;}
      try {update((await request('/api/auth/me')).account);} catch (_) {update(null);}
      if (auth.allowed) return;
      message.textContent = 'Votre compte de jeu est créé automatiquement à la connexion.';
      if (!window.google?.accounts?.id) await new Promise((resolve, reject) => {
        const script = document.createElement('script');script.src = 'https://accounts.google.com/gsi/client';script.async = true;
        script.onload = resolve;script.onerror = () => reject(Error('Google est inaccessible. Vérifiez votre connexion puis réessayez.'));document.head.append(script);
      });
      google.accounts.id.initialize({client_id: configuration.clientId, nonce: configuration.nonce, auto_select: false,
        callback: async ({credential}) => {
          message.textContent = 'Connexion…';
          try {update((await request('/api/auth/google', {credential, nonce: configuration.nonce, platform: 'web'})).account);}
          catch (error) {message.textContent = error.message;document.querySelector('#google-retry').hidden = false;}
        }});
      const button = document.querySelector('#google-button');button.replaceChildren();
      google.accounts.id.renderButton(button, {type: 'standard', theme: 'outline', size: 'large', text: 'continue_with', locale: 'fr', width: 280});
    } catch (error) {message.textContent = error.message;document.querySelector('#google-retry').hidden = false;}
  }
  document.querySelector('#google-retry').onclick = () => {document.querySelector('#google-retry').hidden = true;setup();};
  document.querySelector('#google-logout').onclick = async () => {
    try {
      await window.quartiersLeaveForLogout?.();
      window.dispatchEvent(new Event('quartiers-before-logout'));
      await request('/api/auth/logout', {});update(null);
      window.google?.accounts?.id.disableAutoSelect();location.reload();
    } catch (error) {message.textContent = error.message;}
  };
  auth.ready = setup();
}
