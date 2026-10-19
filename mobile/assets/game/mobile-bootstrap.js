/* Native welcome + the unmodified original game renderer. */
window.startQuartiers = async function (configuration) {
  if (window.quartiersStarted) return;
  window.quartiersStarted = true;
  window.API_URL = configuration.server;
  sessionStorage.setItem('quartiers', JSON.stringify(configuration.session));
  // Keep networking in Android/Flutter: local file content needs no insecure
  // universal file-origin access, and the real session token stays native.
  let requestSequence = 0;
  const requests = new Map();
  window.quartiersResolve = (id, result) => {
    const pending = requests.get(id);
    if (!pending) return;
    requests.delete(id);
    pending.cleanup();
    pending.resolve(new Response(result.body, {status: result.status,
      headers: {'Content-Type': 'application/json; charset=utf-8'}}));
  };
  window.fetch = (url, options = {}) => new Promise((resolve, reject) => {
    const id = ++requestSequence;
    const signal = options.signal;
    const abort = () => {
      requests.delete(id);
      reject(new DOMException('Requête interrompue', 'AbortError'));
    };
    if (signal?.aborted) { abort(); return; }
    signal?.addEventListener('abort', abort, {once: true});
    requests.set(id, {resolve, cleanup: () => signal?.removeEventListener('abort', abort)});
    QuartiersNative.postMessage(JSON.stringify({type: 'request', id,
      url: String(url), method: options.method || 'GET', body: options.body || null}));
  });
  if (!AbortSignal.timeout) AbortSignal.timeout = milliseconds => {
    const controller = new AbortController();
    setTimeout(() => controller.abort(), milliseconds);
    return controller.signal;
  };
  const originalInterval = window.setInterval.bind(window);
  let pollTimer;
  window.setInterval = function (callback, delay, ...args) {
    const timer = originalInterval(callback, delay, ...args);
    if (delay === 800) pollTimer = timer;
    return timer;
  };
  const script = document.createElement('script');
  script.src = 'app.js';
  script.onerror = () => QuartiersNative.postMessage(JSON.stringify({type: 'error'}));
  script.onload = () => {
    window.setInterval = originalInterval;
    const post = data => QuartiersNative.postMessage(JSON.stringify(data));
    document.documentElement.classList.add('quartiers-mobile');
    const toolbar = document.createElement('div');
    toolbar.className = 'mobile-toolbar';
    document.body.prepend(toolbar);
    const home = document.querySelector('#home');
    home.onclick = () => post({type: 'home'});
    const invite = document.querySelector('#invite');
    invite.textContent = 'Inviter';
    invite.onclick = () => post({type: 'invite', code: configuration.session.code});
    toolbar.append(home, document.querySelector('.room-chip'), invite);
    fullscreen.remove();
    const sound = document.createElement('section');
    sound.className = 'panel';
    sound.append(audioControls);
    document.querySelector('#property-panel').prepend(manage);
    document.querySelector('.table-tools').remove();
    toolbar.after(document.querySelector('#connection'));

    const panels = document.createElement('section');
    panels.className = 'mobile-panels';
    const nav = document.createElement('nav');
    nav.className = 'mobile-tabs';
    nav.setAttribute('aria-label', 'Navigation de la partie');
    const definitions = [
      ['Plateau', null],
      ['Biens', document.querySelector('#property-panel')],
      ['Joueurs', document.querySelector('#players').closest('.panel')],
      ['Journal', document.querySelector('.journal')],
      ['Son', sound],
    ];
    let active = 0;
    const show = index => {
      active = index;
      definitions.forEach(([, panel], i) => { if (panel) panel.hidden = i !== index; });
      [...nav.children].forEach((button, i) => button.setAttribute('aria-pressed', String(i === index)));
      panels.hidden = index === 0;
      if (index) panels.scrollIntoView({block: 'nearest', behavior: 'smooth'});
    };
    definitions.forEach(([label, panel], index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = label;
      button.className = 'secondary';
      button.onclick = () => show(index);
      nav.append(button);
      if (panel) panels.append(panel);
    });
    const area = document.querySelector('.board-area');
    area.after(nav, panels);
    nav.after(offerPanel);
    const dock = document.querySelector('.action-panel');
    dock.classList.add('mobile-dock');
    document.querySelector('main').append(dock);
    new ResizeObserver(() => document.documentElement.style.setProperty(
      '--dock-height', dock.getBoundingClientRect().height + 'px')).observe(dock);
    document.querySelector('aside').remove();
    show(0);
    const nativeToast = toast;
    toast = message => nativeToast(message.replace('Vérifiez Lancer.cmd.', 'Vérifiez Internet et le serveur de jeu.'));

    // Keep the original selection/finance logic; expose its panel after a tap.
    document.querySelector('#board').addEventListener('click', event => {
      if (event.target.closest('.tile')) show(1);
    });
    const oldRenderDebt = renderDebt;
    renderDebt = function () {
      oldRenderDebt();
      document.querySelectorAll('#actions button').forEach(button => {
        const original = button.onclick;
        if (button.textContent.includes('hypothèque') || button.textContent.includes('bâtiments')) {
          button.onclick = event => { original?.(event); show(1); };
        }
      });
    };
    const originalSelection = renderSelection;
    renderSelection = function () {
      originalSelection();
      document.querySelector('#property-panel').hidden = active !== 1;
    };
    const watch = originalInterval(() => {
      if (session === null) {
        clearInterval(watch);
        post({type: 'expired'});
      }
    }, 1000);
    window.quartiersMobilePause = () => {
      clearInterval(pollTimer);
      gameSound.ctx?.suspend();
    };
    window.quartiersMobileResume = () => {
      clearInterval(pollTimer);
      pollTimer = originalInterval(() => poll(), 800);
      poll(true);
      gameSound.sync();
    };
    post({type: 'loaded'});
  };
  document.body.append(script);
};
QuartiersNative.postMessage(JSON.stringify({type: 'ready'}));
