/* ============================================================
   riots.wtf — Dashboard
   Talks to the backend API (Railway). NEVER put secrets here.
   ============================================================ */

// >>> SET THIS to your Railway backend URL after deploy <<<
const API_BASE = window.RIOTS_API_BASE || 'http://localhost:8080';

// Optional shared token that must match the backend's FRONTEND_TOKEN.
const CLIENT_TOKEN = window.RIOTS_CLIENT_TOKEN || '';

// Admin key is held only in memory for the session, sent as a header.
let ADMIN_KEY = null;
let ME = null;

// Session token (fallback for when third-party cookies are blocked). Captured
// from the OAuth redirect fragment (#token=...) and reused as a Bearer header.
const SESSION_KEY = 'riots_session_token';
(function captureSessionToken() {
  const m = location.hash.match(/[#&]token=([^&]+)/);
  if (m) {
    try { localStorage.setItem(SESSION_KEY, decodeURIComponent(m[1])); } catch (_) {}
    // strip the token from the URL so it isn't left in the address bar
    history.replaceState(null, '', location.pathname + location.search);
  }
})();
function getSessionToken() {
  try { return localStorage.getItem(SESSION_KEY) || ''; } catch (_) { return ''; }
}

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

function renderIcons() {
  if (window.lucide && typeof window.lucide.createIcons === 'function') {
    window.lucide.createIcons();
  }
}

/* ---------------- Custom dropdowns ----------------
   Wraps every native <select> in a styled widget while keeping the real
   <select> hidden and in sync, so existing .value reads/writes keep working. */
function closeAllSelects(except) {
  document.querySelectorAll('.csel.open').forEach((c) => { if (c !== except) c.classList.remove('open'); });
}
document.addEventListener('click', () => closeAllSelects(null));

function enhanceSelect(sel) {
  if (!sel || sel.dataset.enhanced === '1') return;
  sel.dataset.enhanced = '1';
  const wrap = document.createElement('div');
  wrap.className = 'csel';
  const trigger = document.createElement('button');
  trigger.type = 'button';
  trigger.className = 'csel-trigger';
  const label = document.createElement('span');
  label.className = 'csel-label';
  const caret = document.createElement('i');
  caret.setAttribute('data-lucide', 'chevron-down');
  trigger.appendChild(label);
  trigger.appendChild(caret);
  const menu = document.createElement('div');
  menu.className = 'csel-menu';

  const opts = [...sel.options];
  const syncLabel = () => {
    const o = sel.options[sel.selectedIndex];
    label.textContent = o ? o.textContent : '';
    menu.querySelectorAll('.csel-opt').forEach((el) => el.classList.toggle('sel', el.dataset.value === sel.value));
  };
  opts.forEach((o) => {
    const item = document.createElement('button');
    item.type = 'button';
    item.className = 'csel-opt';
    item.dataset.value = o.value;
    item.textContent = o.textContent;
    item.addEventListener('click', (e) => {
      e.stopPropagation();
      sel.value = o.value;
      sel.dispatchEvent(new Event('change', { bubbles: true }));
      syncLabel();
      wrap.classList.remove('open');
    });
    menu.appendChild(item);
  });

  trigger.addEventListener('click', (e) => {
    e.stopPropagation();
    const willOpen = !wrap.classList.contains('open');
    closeAllSelects(wrap);
    wrap.classList.toggle('open', willOpen);
  });

  // Insert the widget right after the (now hidden) native select.
  sel.classList.add('csel-native');
  sel.parentNode.insertBefore(wrap, sel.nextSibling);
  wrap.appendChild(trigger);
  wrap.appendChild(menu);
  syncLabel();
  // keep label in sync if code sets .value programmatically then fires change
  sel.addEventListener('change', syncLabel);
}

function enhanceSelects(root = document) {
  root.querySelectorAll('select:not([data-enhanced])').forEach(enhanceSelect);
  renderIcons();
}

async function api(path, { method = 'GET', body, admin = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (admin && ADMIN_KEY) headers['x-admin-key'] = ADMIN_KEY;
  if (CLIENT_TOKEN) headers['x-client-token'] = CLIENT_TOKEN;
  const st = getSessionToken();
  if (st) headers['Authorization'] = 'Bearer ' + st;
  const res = await fetch(API_BASE + path, {
    method,
    headers,
    credentials: 'include', // send the session cookie
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = {};
  try { data = await res.json(); } catch { /* noop */ }
  if (!res.ok) throw new Error(data.message || `Request failed (${res.status})`);
  return data;
}

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function fmtDate(unixOrIso) {
  if (!unixOrIso) return '—';
  const d = typeof unixOrIso === 'number' ? new Date(unixOrIso * 1000) : new Date(unixOrIso);
  return d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

/* ---------------- AUTH GATE (key-first flow) ----------------
   1. "I need to register my key"  -> enter key
   2. key saved locally, dashboard shows BLURRED behind an
      "Auth my Discord" overlay
   3. Auth my Discord -> OAuth -> on return we link the saved key
      to that Discord id and save. Then it's unlocked.
   Admin sign-in is a small secondary option.
------------------------------------------------------------- */
const gate = $('#authGate');
const dashMain = $('#dashMain');
const linkGate = $('#linkGate');
const PENDING_KEY = 'riots_pending_key';

function showGate(step) {
  gate.classList.remove('hidden');
  linkGate.hidden = true;
  dashMain.classList.add('blurred');
  $('#agStepStart').hidden = step !== 'start';
  $('#agStepKey').hidden = step !== 'key';
  $('#agStepAdmin').hidden = step !== 'admin';
  // Back arrow shows on any step except the first.
  const back = $('#agBack');
  if (back) back.hidden = step === 'start';
  renderIcons();
}
function hideGate() {
  gate.classList.add('hidden');
  linkGate.hidden = true;
  dashMain.classList.remove('blurred');
}
// dashboard visible but blurred, with only the "Auth my Discord" overlay
function showLinkGate() {
  gate.classList.add('hidden');
  dashMain.classList.add('blurred');
  linkGate.hidden = false;
  renderIcons();
}

// Step 1 -> 2
$('#agRegisterBtn').addEventListener('click', () => showGate('key'));
$('#agKeyBack').addEventListener('click', () => showGate('start'));
// Continue with Discord — straight to OAuth (no key required first)
$('#agDiscordBtn').addEventListener('click', () => {
  window.location.href = API_BASE + '/auth/discord';
});
// Top-left back arrow always returns to the start step
$('#agBack').addEventListener('click', () => showGate('start'));

// Step 2: save the key locally, then show the blurred dashboard + link button
$('#agKeyContinue').addEventListener('click', () => {
  const key = $('#agKeyInput').value.trim();
  const err = $('#agKeyError');
  err.hidden = true;
  if (!key) { err.textContent = 'Enter your key.'; err.hidden = false; return; }
  localStorage.setItem(PENDING_KEY, key);
  showLinkGate();
});

// "Auth my Discord" — go link the saved key to a Discord account
$('#authDiscordBtn').addEventListener('click', () => {
  window.location.href = API_BASE + '/auth/discord';
});
$('#linkCancel').addEventListener('click', () => {
  localStorage.removeItem(PENDING_KEY);
  showGate('key');
});

// Admin path (secondary)
$('#agAdminToggle').addEventListener('click', () => showGate('admin'));
$('#agAdminBack').addEventListener('click', () => showGate('start'));
$('#agAdminSubmit').addEventListener('click', async () => {
  const val = $('#agAdminInput').value.trim();
  const err = $('#agAdminError');
  err.hidden = true;
  if (!val) return;
  ADMIN_KEY = val;
  try {
    await api('/api/keys/admin/hubs', { admin: true });
    enterAdminMode();
  } catch (e) {
    ADMIN_KEY = null;
    err.textContent = 'Invalid admin key.';
    err.hidden = false;
  }
});

$('#logoutBtn').addEventListener('click', async () => {
  try { await api('/auth/logout', { method: 'POST' }); } catch {}
  ADMIN_KEY = null; ME = null;
  localStorage.removeItem(PENDING_KEY);
  try { localStorage.removeItem(SESSION_KEY); } catch (_) {}
  location.reload();
});

/* ---------------- TABS ---------------- */
$$('#dashTabs .dtab[data-view]').forEach((btn) => {
  btn.addEventListener('click', () => {
    const view = btn.dataset.view;
    $$('#dashTabs .dtab').forEach((b) => b.classList.toggle('active', b === btn));
    $$('.dview').forEach((v) => (v.hidden = v.dataset.view !== view));
    if (view === 'updates') loadUpdates();
    if (view === 'status') loadStatus();
    if (view === 'tickets') loadTickets();
    if (view === 'referral') loadReferral();
    if (view === 'admin') loadAdmin();
  });
});

/* ---------------- TICKETS (user) ---------------- */
async function loadTickets() {
  const area = $('#ticketsArea');
  if (!area) return;
  area.innerHTML = `
    <div class="ticket-new">
      <h3>Open a support ticket</h3>
      <input type="text" id="tkSubject" placeholder="Subject" />
      <textarea id="tkMessage" rows="4" placeholder="Describe your issue..."></textarea>
      <button class="btn btn-gradient" id="tkCreate"><i data-lucide="send"></i><span>Submit ticket</span></button>
      <p class="cart-note" id="tkMsg"></p>
    </div>
    <div id="tkList" class="ticket-list"><div class="dash-loading"><span></span><span></span><span></span></div></div>`;
  renderIcons();

  $('#tkCreate').addEventListener('click', async () => {
    const subject = $('#tkSubject').value.trim();
    const message = $('#tkMessage').value.trim();
    const msg = $('#tkMsg');
    if (!subject || !message) { msg.textContent = 'Subject and message are required.'; return; }
    try {
      await api('/api/store/tickets', { method: 'POST', body: { subject, message } });
      $('#tkSubject').value = ''; $('#tkMessage').value = '';
      msg.textContent = 'Ticket submitted.';
      renderTicketList();
    } catch (e) { msg.textContent = e.message; }
  });

  renderTicketList();
}

async function renderTicketList() {
  const list = $('#tkList');
  if (!list) return;
  try {
    const r = await api('/api/store/tickets/mine');
    const items = r.tickets || [];
    if (!items.length) { list.innerHTML = `<div class="empty">No tickets yet.</div>`; return; }
    list.innerHTML = items.map((t) => `
      <div class="ticket-card" data-id="${esc(t.id)}">
        <div class="tc-head">
          <strong>${esc(t.subject)}</strong>
          <span class="ticket-status ${t.status === 'open' ? 'open' : 'closed'}">${esc(t.status)}</span>
        </div>
        <p class="at-msg">${esc(t.message)}</p>
        ${(t.replies || []).map((rp) => `<p class="at-reply ${rp.from === 'staff' ? 'staff' : ''}"><b>${rp.from === 'staff' ? 'Staff' : 'You'}:</b> ${esc(rp.message)}</p>`).join('')}
        ${t.status === 'open' ? `
        <div class="at-actions">
          <input type="text" placeholder="Reply..." data-reply />
          <button class="mini" data-send>Reply</button>
        </div>` : ''}
      </div>`).join('');
    list.querySelectorAll('.ticket-card').forEach((row) => {
      const send = row.querySelector('[data-send]');
      if (send) send.addEventListener('click', async () => {
        const message = row.querySelector('[data-reply]').value.trim();
        if (!message) return;
        try { await api('/api/store/tickets/' + row.dataset.id + '/reply', { method: 'POST', body: { message } }); renderTicketList(); }
        catch (e) { alert(e.message); }
      });
    });
  } catch (e) { list.innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
}

/* ---------------- USER DASHBOARD ---------------- */
async function loadUserDashboard() {
  const data = await api('/api/keys/mine');
  ME = data;

  renderProfile(data);

  // small user card at top of My Keys tab
  const u = data.discord;
  $('#dashUser').innerHTML = `
    <div class="user-card">
      ${u.avatar ? `<img src="${esc(u.avatar)}" alt="" class="user-avatar"/>` : `<div class="user-avatar ph"></div>`}
      <div>
        <div class="user-name">${esc(u.globalName || u.username)}</div>
        <div class="user-sub">Discord ID: <code>${esc(u.id)}</code></div>
      </div>
    </div>`;

  // keys
  if (!data.linked || !data.keys.length) {
    $('#keysArea').innerHTML = `<div class="empty">No keys linked yet. <a href="products.html">Grab one here</a>.</div>`;
    return;
  }
  $('#keysArea').innerHTML = data.keys.map((k) => `
    <div class="key-card">
      <div class="key-top">
        <div>
          <div class="key-label">${esc(k.hubName || 'License Key')}</div>
          <div class="key-value"><code id="k">${esc(k.key)}</code>
            <button class="copy-btn" data-copy="${esc(k.key)}">Copy</button>
          </div>
        </div>
        <span class="key-status ${k.blacklisted ? 'bad' : (k.activated ? 'ok' : 'pending')}">
          ${k.blacklisted ? 'Blacklisted' : (k.activated ? 'Active' : 'Not activated')}
        </span>
      </div>
      <div class="key-meta">
        <span>Expires: <b>${k.expire ? fmtDate(k.expire) : 'Lifetime'}</b></span>
        <span>HWID: <b>${k.hwid ? 'Linked' : 'Not set'}</b></span>
        <span>Executions: <b>${k.executionCount ?? 0}</b></span>
        <span>Note: <b>${esc(k.note || '—')}</b></span>
      </div>
      <div class="key-actions">
        <button class="btn btn-bw" id="resetHwidBtn"><span>Reset HWID</span></button>
      </div>
    </div>`).join('');

  $$('.copy-btn').forEach((b) => b.addEventListener('click', () => {
    navigator.clipboard.writeText(b.dataset.copy);
    b.textContent = 'Copied!';
    setTimeout(() => (b.textContent = 'Copy'), 1400);
  }));
  const rh = $('#resetHwidBtn');
  if (rh) rh.addEventListener('click', async () => {
    rh.disabled = true;
    try { const r = await api('/api/keys/reset-hwid', { method: 'POST' }); alert(r.message || 'HWID reset.'); }
    catch (e) { alert(e.message); }
    rh.disabled = false;
  });
}

/* ---------------- PROFILE ---------------- */
function renderProfile(data) {
  const area = $('#profileArea');
  if (!area) return;
  const u = data.discord || {};
  const k = (data.keys && data.keys[0]) || null;

  const stat = (label, value) => `
    <div class="pstat"><div class="pstat-val">${value}</div><div class="pstat-label">${label}</div></div>`;

  const statusPill = !k ? ''
    : k.blacklisted
      ? '<span class="key-status bad">Blacklisted</span>'
      : (k.activated ? '<span class="key-status ok">Active</span>' : '<span class="key-status pending">Not activated</span>');

  area.innerHTML = `
    <div class="profile-card">
      <div class="profile-head">
        ${u.avatar ? `<img src="${esc(u.avatar)}" alt="" class="profile-avatar"/>` : `<div class="profile-avatar ph"></div>`}
        <div class="profile-id">
          <div class="profile-name">${esc(u.globalName || u.username || 'Unknown')}</div>
          <div class="profile-sub">@${esc(u.username || '—')}</div>
          <div class="profile-sub">Discord ID: <code>${esc(u.id || '—')}</code></div>
        </div>
        <div class="profile-badge">${statusPill}</div>
      </div>

      ${k ? `
      <div class="profile-key">
        <div class="key-label">Your key</div>
        <div class="key-value">
          <code>${esc(k.key)}</code>
          <button class="copy-btn" id="profCopy" data-copy="${esc(k.key)}">Copy</button>
        </div>
      </div>

      <div class="pstat-grid">
        ${stat('Status', k.blacklisted ? 'Blacklisted' : (k.activated ? 'Active' : 'Pending'))}
        ${stat('Expires', k.expire ? fmtDate(k.expire) : 'Lifetime')}
        ${stat('HWID', k.hwid ? 'Linked' : 'Not set')}
        ${stat('HWID resets', k.hwidResetCount ?? 0)}
        ${stat('Executions', k.executionCount ?? 0)}
        ${stat('Created', k.created ? fmtDate(k.created) : '—')}
      </div>

      <div class="profile-actions">
        <button class="btn btn-bw" id="profResetHwid"><i data-lucide="rotate-ccw"></i><span>Reset my HWID</span></button>
        <a class="btn btn-bw" href="https://discord.gg/m7Z9Jyp6pf" target="_blank" rel="noopener"><i data-lucide="life-buoy"></i><span>Get support</span></a>
      </div>
      <p class="profile-note">Resetting your HWID lets you run the script on a new device. It respects the cooldown set by staff.</p>
      ` : `
      <div class="empty" style="margin-top:18px">No key linked to this account yet. <a href="products.html">Grab one here</a>.</div>
      `}
    </div>`;

  const copy = $('#profCopy');
  if (copy) copy.addEventListener('click', () => {
    navigator.clipboard.writeText(copy.dataset.copy);
    copy.textContent = 'Copied!';
    setTimeout(() => (copy.textContent = 'Copy'), 1400);
  });
  const reset = $('#profResetHwid');
  if (reset) reset.addEventListener('click', async () => {
    if (!confirm('Reset your HWID? Use this only when moving to a new device.')) return;
    reset.disabled = true;
    try {
      const r = await api('/api/keys/reset-hwid', { method: 'POST' });
      alert(r.message || 'HWID reset.');
    } catch (e) { alert(e.message); }
    reset.disabled = false;
  });
  renderIcons();
}

/* ---------------- REFERRAL ---------------- */
function refLink(code) {
  const origin = location.origin.includes('file') ? 'https://riots.wtf' : location.origin;
  return origin + '/products.html?ref=' + encodeURIComponent(code);
}
async function loadReferral() {
  const panel = $('#refPanel');
  if (!panel) return;
  panel.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const { referral } = await api('/api/referral/me');
    if (referral) renderReferralDashboard(panel, referral);
    else renderReferralSignup(panel);
  } catch (e) {
    panel.innerHTML = `<div class="ref-card"><p class="ref-error">Couldn't load referral. ${esc(e.message)}</p></div>`;
  }
}
function renderReferralDashboard(panel, ref) {
  const link = refLink(ref.code);
  panel.innerHTML = `
    <div class="ref-card">
      <div class="ref-card-head"><h3>Your referral link</h3><span class="admin-badge">active</span></div>
      <span class="ref-code-label">Share this link</span>
      <div class="ref-code-row">
        <code id="refLinkVal">${esc(link)}</code>
        <button class="btn btn-bw sm" id="refCopy" type="button"><i data-lucide="copy"></i><span>Copy</span></button>
      </div>
      <div class="ref-stats">
        <div class="ref-stat"><div class="rs-val">${ref.clicks || 0}</div><div class="rs-label">Clicks</div></div>
        <div class="ref-stat"><div class="rs-val">${ref.signups || 0}</div><div class="rs-label">Signups</div></div>
        <div class="ref-stat"><div class="rs-val">$${Number(ref.earnings || 0).toFixed(2)}</div><div class="rs-label">Earned</div></div>
      </div>
      <p class="ref-note">Your code is <strong>${esc(ref.code)}</strong>. Share your link anywhere — it passes your code to checkout as the affiliate code so your sales are tracked in Komerza.</p>
    </div>`;
  renderIcons();
  const copyBtn = panel.querySelector('#refCopy');
  if (copyBtn) copyBtn.addEventListener('click', () => {
    navigator.clipboard.writeText(link).then(() => {
      const s = copyBtn.querySelector('span'); const old = s.textContent;
      s.textContent = 'Copied!'; setTimeout(() => (s.textContent = old), 1500);
    });
  });
}
function renderReferralSignup(panel) {
  panel.innerHTML = `
    <div class="ref-card">
      <div class="ref-card-head"><h3>Join the referral program</h3></div>
      <p class="ref-note">Pick a code and tell us where to send payouts. You'll get a shareable link tied to your account.</p>
      <input type="text" id="refWantedCode" placeholder="Preferred code (e.g. RIOTSVIP)" maxlength="20" />
      <input type="text" id="refPayout" placeholder="Payout method (PayPal / crypto / etc.)" maxlength="200" />
      <button class="btn btn-gradient wide" id="refJoin" type="button"><span>Create my link</span></button>
      <p class="ref-error" id="refErr" hidden></p>
    </div>`;
  renderIcons();
  panel.querySelector('#refJoin').addEventListener('click', async () => {
    const code = panel.querySelector('#refWantedCode').value.trim();
    const payout = panel.querySelector('#refPayout').value.trim();
    const errEl = panel.querySelector('#refErr');
    errEl.hidden = true;
    try {
      const { referral } = await api('/api/referral/signup', { method: 'POST', body: { code, payout } });
      renderReferralDashboard(panel, referral);
    } catch (e) { errEl.textContent = e.message || 'Could not sign up.'; errEl.hidden = false; }
  });
}

/* ---------------- UPDATES / DEVLOG ---------------- */
async function loadUpdates() {
  const area = $('#updatesArea');
  area.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const { entries } = await api('/api/content/devlog');
    if (!entries.length) { area.innerHTML = `<div class="empty">No updates yet.</div>`; return; }
    area.innerHTML = entries.map((e) => `
      <article class="devlog-item">
        <div class="devlog-head">
          <span class="devlog-tag ${esc(e.tag)}">${esc(e.tag || 'update')}</span>
          <h3>${esc(e.title)}</h3>
          <time>${fmtDate(e.createdAt)}</time>
        </div>
        <p>${esc(e.body).replace(/\n/g, '<br>')}</p>
      </article>`).join('');
  } catch (e) {
    area.innerHTML = `<div class="empty">Couldn't load updates. ${esc(e.message)}</div>`;
  }
}

/* ---------------- STATUS ---------------- */
async function loadStatus() {
  const area = $('#statusArea');
  area.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const { status } = await api('/api/content/status');
    const svcs = status.services || [];
    area.innerHTML = `
      <div class="status-banner ${status.overall === 'operational' ? 'up' : 'warn'}">
        <span class="pulse-dot"></span>
        <span>${status.overall === 'operational' ? 'All systems operational' : 'Some systems affected'}</span>
      </div>
      <div class="status-grid" style="margin-top:20px">
        ${svcs.length ? svcs.map((s) => `
          <div class="status-row">
            <div class="status-name"><strong>${esc(s.name)}</strong><small>${esc(s.desc || '')}</small></div>
            <span class="status-pill ${['up','warn','down','maintenance'].includes(s.state) ? s.state : 'up'}"><span class="dot"></span>${({up:'Operational',warn:'Degraded',down:'Down',maintenance:'Maintenance'})[s.state] || 'Operational'}</span>
          </div>`).join('') : `<div class="empty">No products listed yet.</div>`}
      </div>`;
  } catch (e) {
    area.innerHTML = `<div class="empty">Couldn't load status. ${esc(e.message)}</div>`;
  }
}

/* ---------------- ADMIN ---------------- */
function enterAdminMode() {
  $$('.admin-only').forEach((el) => (el.hidden = false));
  hideGate();
  // jump to admin tab
  const adminTab = $('#dashTabs .dtab[data-view="admin"]');
  if (adminTab) adminTab.click();
  // ensure a user dashboard is present too (admin is also a user)
  loadUserDashboard().catch(() => {
    $('#dashUser').innerHTML = `<div class="user-card"><div class="user-avatar ph"></div><div><div class="user-name">Admin</div><div class="user-sub">Admin session</div></div></div>`;
  });
}

async function loadAdmin() {
  const area = $('#adminArea');
  area.innerHTML = `
    <div class="adm">
      <aside class="adm-nav">
        <div class="adm-nav-title">Admin</div>
        <button class="adm-navbtn active" data-section="overview"><i data-lucide="layout-dashboard"></i><span>Overview</span></button>
        <button class="adm-navbtn" data-section="products"><i data-lucide="package"></i><span>Products</span></button>
        <button class="adm-navbtn" data-section="keys"><i data-lucide="key-round"></i><span>Keys &amp; users</span></button>
        <button class="adm-navbtn" data-section="discounts"><i data-lucide="ticket-percent"></i><span>Discounts</span></button>
        <button class="adm-navbtn" data-section="referrals"><i data-lucide="gift"></i><span>Referrals</span></button>
        <button class="adm-navbtn" data-section="tickets"><i data-lucide="life-buoy"></i><span>Tickets</span></button>
        <button class="adm-navbtn" data-section="status"><i data-lucide="activity"></i><span>Status</span></button>
        <button class="adm-navbtn" data-section="devlog"><i data-lucide="megaphone"></i><span>Devlog</span></button>
      </aside>

      <div class="adm-main">
        <!-- OVERVIEW -->
        <section class="adm-section active" data-section="overview">
          <div class="adm-head"><h2>Overview</h2><p>Quick snapshot of your store.</p></div>
          <div class="adm-stats" id="adStats">
            <div class="adm-stat"><div class="as-ico"><i data-lucide="package"></i></div><div><div class="as-val" data-stat="products">—</div><div class="as-label">Products</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="ticket-percent"></i></div><div><div class="as-val" data-stat="discounts">—</div><div class="as-label">Discount codes</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="gift"></i></div><div><div class="as-val" data-stat="referrals">—</div><div class="as-label">Referrals</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="life-buoy"></i></div><div><div class="as-val" data-stat="tickets">—</div><div class="as-label">Open tickets</div></div></div>
          </div>
          <div class="adm-quick">
            <button class="adm-quick-btn" data-goto="products"><i data-lucide="plus"></i> Add a product</button>
            <button class="adm-quick-btn" data-goto="keys"><i data-lucide="key-round"></i> Generate keys</button>
            <button class="adm-quick-btn" data-goto="status"><i data-lucide="activity"></i> Update status</button>
            <button class="adm-quick-btn" data-goto="devlog"><i data-lucide="megaphone"></i> Post an update</button>
          </div>
        </section>

        <!-- PRODUCTS -->
        <section class="adm-section" data-section="products" hidden>
          <div class="adm-head"><h2>Products</h2><p>Create, edit and delete store products. Images upload to Cloudinary.</p></div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>Catalog</h3><button class="btn btn-bw sm" id="adProdNew" type="button"><i data-lucide="plus"></i><span>New product</span></button></div>
            <div id="adProdList" class="admin-products"></div>
          </div>
          <div class="adm-card" id="adProdFormCard">
            <div class="adm-card-head"><h3 id="adProdFormTitle">Add product</h3></div>
            <div class="adm-form-grid">
              <div class="adm-form-left">
                <label class="img-drop" id="adImgDrop">
                  <i data-lucide="image-plus"></i> <span>Click to upload image</span>
                  <input type="file" id="adImgFile" accept="image/*" hidden />
                </label>
                <img id="adImgPreview" class="img-preview" hidden />
              </div>
              <div class="adm-form-right">
                <input type="hidden" id="adProdId" />
                <input type="hidden" id="adProdImage" />
                <label class="admin-label">Name &amp; category</label>
                <div class="admin-row">
                  <input type="text" id="adProdName" placeholder="Product name" />
                  <input type="text" id="adProdCategory" placeholder="Category (e.g. Roblox)" />
                </div>
                <label class="admin-label">Pricing</label>
                <div class="admin-row">
                  <input type="text" id="adProdPrice" placeholder="Lifetime price (e.g. $10)" />
                  <input type="text" id="adProdPriceMonthly" placeholder="Monthly price (e.g. $4)" />
                </div>
                <label class="admin-label">Badge</label>
                <input type="text" id="adProdBadge" placeholder="Badge (e.g. Best Seller)" />
                <label class="admin-label">Komerza IDs</label>
                <input type="text" id="adProdKmrzaProduct" placeholder="Komerza product id" />
                <div class="admin-row">
                  <input type="text" id="adProdKmrzaLife" placeholder="Lifetime variant id" />
                  <input type="text" id="adProdKmrzaMonth" placeholder="Monthly variant id" />
                </div>
                <label class="admin-label">Description</label>
                <textarea id="adProdDesc" rows="3" placeholder="Description"></textarea>
                <label class="adm-check"><input type="checkbox" id="adProdFeatured" /> <span>Featured on homepage</span></label>
                <div class="adm-form-actions">
                  <button class="btn btn-gradient" id="adProdSave"><span>Save product</span></button>
                  <button class="btn btn-bw" id="adProdReset"><span>Clear</span></button>
                </div>
                <div id="adProdResult"></div>
              </div>
            </div>
          </div>
        </section>

        <!-- KEYS -->
        <section class="adm-section" data-section="keys" hidden>
          <div class="adm-head"><h2>Keys &amp; users</h2><p>Look up, generate and manage license keys.</p></div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>Look up a key</h3></div>
            <div class="admin-row">
              <input type="text" id="adMyKey" placeholder="Paste a key to inspect" />
              <button class="btn btn-bw" id="adLookup"><span>Look up</span></button>
            </div>
            <div id="adMyKeyResult"></div>
          </div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>All keys / users</h3></div>
            <div class="admin-row">
              <input type="text" id="adFilter" placeholder="Filter by Discord ID or key (blank = all)" />
              <button class="btn btn-bw" id="adSearch"><span>Search</span></button>
            </div>
            <div id="adKeyList" class="admin-list"></div>
          </div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>Generate keys</h3></div>
            <div class="admin-row">
              <input type="number" id="adAmount" placeholder="Amount (5-300)" min="5" max="300" value="5" />
              <input type="number" id="adExpire" placeholder="Expire seconds (blank=lifetime)" />
            </div>
            <button class="btn btn-gradient" id="adGenerate"><span>Generate</span></button>
            <div id="adGenResult"></div>
          </div>
        </section>

        <!-- DISCOUNTS -->
        <section class="adm-section" data-section="discounts" hidden>
          <div class="adm-head"><h2>Discount codes</h2><p>Mirror of your Komerza coupons. Create the same code as a coupon in your Komerza dashboard for it to actually apply at checkout.</p></div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>New code</h3></div>
            <div class="admin-row">
              <input type="text" id="adDiscCode" placeholder="CODE (e.g. SAVE20)" />
              <select id="adDiscType">
                <option value="percent">% off</option>
                <option value="fixed">$ off</option>
              </select>
            </div>
            <div class="admin-row">
              <input type="number" id="adDiscAmount" placeholder="Amount" min="0" />
              <input type="text" id="adDiscNote" placeholder="Note (optional)" />
            </div>
            <button class="btn btn-gradient" id="adDiscSave"><span>Create code</span></button>
            <div id="adDiscResult"></div>
            <div id="adDiscList" class="admin-list" style="margin-top:12px"></div>
          </div>
        </section>

        <!-- REFERRALS -->
        <section class="adm-section" data-section="referrals" hidden>
          <div class="adm-head"><h2>Referrals</h2><p>People signed up to your referral program.</p></div>
          <div class="adm-card"><div id="adRefList" class="admin-list"></div></div>
        </section>

        <!-- TICKETS -->
        <section class="adm-section" data-section="tickets" hidden>
          <div class="adm-head"><h2>Support tickets</h2><p>Tickets opened by users.</p></div>
          <div class="adm-card"><div id="adTicketList" class="admin-list"></div></div>
        </section>

        <!-- STATUS -->
        <section class="adm-section" data-section="status" hidden>
          <div class="adm-head"><h2>Status</h2><p>Publish the live status shown on your status page.</p></div>
          <div class="adm-card">
            <label class="admin-label">Overall status</label>
            <select id="adOverall">
              <option value="operational">Operational</option>
              <option value="degraded">Degraded</option>
              <option value="partial">Partial outage</option>
              <option value="down">Down</option>
              <option value="maintenance">Maintenance</option>
            </select>
            <label class="admin-label">Services</label>
            <p class="admin-hint">Add each product or service and set its state.</p>
            <div id="adStatusRows" class="status-rows"></div>
            <button class="btn btn-bw sm" id="adAddService" type="button"><i data-lucide="plus"></i><span>Add service</span></button>
            <button class="btn btn-gradient" id="adSaveStatus"><span>Publish status</span></button>
            <div id="adStatusResult"></div>
          </div>
        </section>

        <!-- DEVLOG -->
        <section class="adm-section" data-section="devlog" hidden>
          <div class="adm-head"><h2>Devlog</h2><p>Post updates shown on the Updates tab.</p></div>
          <div class="adm-card">
            <div class="admin-row">
              <input type="text" id="adDlTitle" placeholder="Update title" />
              <select id="adDlTag">
                <option value="update">update</option>
                <option value="new">new</option>
                <option value="fix">fix</option>
                <option value="notice">notice</option>
              </select>
            </div>
            <textarea id="adDlBody" rows="4" placeholder="What changed..."></textarea>
            <button class="btn btn-gradient" id="adPostDl"><span>Publish update</span></button>
            <div id="adDlResult"></div>
          </div>
        </section>
      </div>
    </div>`;

  // Section navigation
  const showSection = (name) => {
    $$('.adm-navbtn').forEach((b) => b.classList.toggle('active', b.dataset.section === name));
    $$('.adm-section').forEach((s) => (s.hidden = s.dataset.section !== name));
  };
  $$('.adm-navbtn').forEach((b) => b.addEventListener('click', () => showSection(b.dataset.section)));
  $$('.adm-quick-btn').forEach((b) => b.addEventListener('click', () => showSection(b.dataset.goto)));
  const prodNew = $('#adProdNew');
  if (prodNew) prodNew.addEventListener('click', () => { if (typeof resetProdForm === 'function') resetProdForm(); $('#adProdName').focus(); });

  // My key lookup
  $('#adLookup').addEventListener('click', async () => {
    const key = $('#adMyKey').value.trim();
    if (!key) return;
    try {
      const r = await api('/api/keys/admin/list?key=' + encodeURIComponent(key), { admin: true });
      $('#adMyKeyResult').innerHTML = renderAdminKeys(r.keys || []);
    } catch (e) { $('#adMyKeyResult').innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
  });

  // Search users
  $('#adSearch').addEventListener('click', searchAdminKeys);
  searchAdminKeys();

  // Generate
  $('#adGenerate').addEventListener('click', async () => {
    const amount = parseInt($('#adAmount').value, 10) || 5;
    const expireRaw = $('#adExpire').value.trim();
    const body = { amount };
    if (expireRaw) body.expire = parseInt(expireRaw, 10);
    try {
      const r = await api('/api/keys/admin/generate', { method: 'POST', body, admin: true });
      $('#adGenResult').innerHTML = `<div class="ok-note">Generated ${r.keys?.length || 0} keys.</div><textarea rows="4" readonly>${esc((r.keys || []).join('\n'))}</textarea>`;
    } catch (e) { $('#adGenResult').innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
  });

  // Status — editable rows
  const statusRows = $('#adStatusRows');
  const addServiceRow = (svc = { name: '', desc: '', state: 'up' }) => {
    const row = document.createElement('div');
    row.className = 'status-row';
    row.innerHTML = `
      <input type="text" class="sr-name" placeholder="Service name" value="${esc(svc.name || '')}" />
      <input type="text" class="sr-desc" placeholder="Short description" value="${esc(svc.desc || '')}" />
      <select class="sr-state">
        <option value="up">Operational</option>
        <option value="warn">Degraded</option>
        <option value="down">Down</option>
        <option value="maintenance">Maintenance</option>
      </select>
      <button type="button" class="sr-remove" aria-label="Remove"><i data-lucide="trash-2"></i></button>`;
    row.querySelector('.sr-state').value = ['up', 'warn', 'down', 'maintenance'].includes(svc.state) ? svc.state : 'up';
    row.querySelector('.sr-remove').addEventListener('click', () => { row.remove(); });
    statusRows.appendChild(row);
    enhanceSelects(row);
    renderIcons();
  };
  $('#adAddService').addEventListener('click', () => addServiceRow());

  // Prefill rows from the current published status.
  api('/api/content/status').then(({ status }) => {
    if (status && status.overall) { $('#adOverall').value = status.overall; $('#adOverall').dispatchEvent(new Event('change')); }
    const svcs = (status && status.services) || [];
    if (svcs.length) svcs.forEach(addServiceRow); else addServiceRow();
  }).catch(() => addServiceRow());

  $('#adSaveStatus').addEventListener('click', async () => {
    const overall = $('#adOverall').value;
    const services = [...statusRows.querySelectorAll('.status-row')].map((row) => ({
      name: row.querySelector('.sr-name').value.trim(),
      desc: row.querySelector('.sr-desc').value.trim(),
      state: row.querySelector('.sr-state').value,
    })).filter((s) => s.name);
    try {
      await api('/api/content/status', { method: 'PUT', body: { overall, services }, admin: true });
      $('#adStatusResult').innerHTML = `<div class="ok-note">Status published.</div>`;
    } catch (e) { $('#adStatusResult').innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
  });

  // Devlog
  $('#adPostDl').addEventListener('click', async () => {
    const title = $('#adDlTitle').value.trim();
    const bodyTxt = $('#adDlBody').value.trim();
    const tag = $('#adDlTag').value;
    if (!title || !bodyTxt) return;
    try {
      await api('/api/content/devlog', { method: 'POST', body: { title, body: bodyTxt, tag }, admin: true });
      $('#adDlResult').innerHTML = `<div class="ok-note">Update published.</div>`;
      $('#adDlTitle').value = ''; $('#adDlBody').value = '';
    } catch (e) { $('#adDlResult').innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
  });

  // ---- Products manager ----
  const setProdImage = (url) => {
    $('#adProdImage').value = url || '';
    const prev = $('#adImgPreview');
    const drop = $('#adImgDrop');
    if (url) { prev.src = url; prev.hidden = false; drop.classList.add('has-img'); }
    else { prev.hidden = true; drop.classList.remove('has-img'); }
  };
  const resetProdForm = () => {
    ['adProdId','adProdName','adProdCategory','adProdPrice','adProdPriceMonthly','adProdBadge',
     'adProdKmrzaProduct','adProdKmrzaLife','adProdKmrzaMonth','adProdDesc'].forEach(id => $('#'+id).value = '');
    $('#adProdFeatured').checked = false;
    setProdImage('');
    const title = $('#adProdFormTitle'); if (title) title.textContent = 'Add product';
  };

  $('#adImgDrop').addEventListener('click', () => $('#adImgFile').click());
  $('#adImgFile').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    $('#adProdResult').innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
    try {
      const url = await uploadToCloudinary(file);
      setProdImage(url);
      $('#adProdResult').innerHTML = `<div class="ok-note">Image uploaded.</div>`;
    } catch (err) {
      $('#adProdResult').innerHTML = `<div class="empty">${esc(err.message)}</div>`;
    }
  });

  $('#adProdSave').addEventListener('click', async () => {
    const body = {
      name: $('#adProdName').value.trim(),
      category: $('#adProdCategory').value.trim() || 'General',
      description: $('#adProdDesc').value.trim(),
      price: $('#adProdPrice').value.trim(),
      priceMonthly: $('#adProdPriceMonthly').value.trim(),
      badge: $('#adProdBadge').value.trim(),
      image: $('#adProdImage').value.trim(),
      komerzaProductId: $('#adProdKmrzaProduct').value.trim(),
      komerzaVariants: {
        lifetime: $('#adProdKmrzaLife').value.trim(),
        monthly: $('#adProdKmrzaMonth').value.trim(),
      },
      featured: $('#adProdFeatured').checked,
    };
    if (!body.name) { $('#adProdResult').innerHTML = `<div class="empty">Name is required.</div>`; return; }
    const id = $('#adProdId').value;
    try {
      if (id) await api('/api/store/products/' + id, { method: 'PATCH', body, admin: true });
      else await api('/api/store/products', { method: 'POST', body, admin: true });
      $('#adProdResult').innerHTML = `<div class="ok-note">Product saved.</div>`;
      resetProdForm();
      loadAdminProducts();
    } catch (e) { $('#adProdResult').innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
  });
  $('#adProdReset').addEventListener('click', resetProdForm);

  // Discount codes
  $('#adDiscSave').addEventListener('click', async () => {
    const code = $('#adDiscCode').value.trim();
    const type = $('#adDiscType').value;
    const amount = parseFloat($('#adDiscAmount').value);
    const note = $('#adDiscNote').value.trim();
    if (!code || isNaN(amount)) { $('#adDiscResult').innerHTML = `<div class="empty">Code + amount required.</div>`; return; }
    try {
      await api('/api/store/discounts', { method: 'POST', body: { code, type, amount, note }, admin: true });
      $('#adDiscResult').innerHTML = `<div class="ok-note">Code created.</div>`;
      $('#adDiscCode').value = ''; $('#adDiscAmount').value = ''; $('#adDiscNote').value = '';
      loadAdminDiscounts();
    } catch (e) { $('#adDiscResult').innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
  });

  renderIcons();
  enhanceSelects(area);
  loadAdminProducts();
  loadAdminDiscounts();
  loadAdminTickets();
  loadAdminReferrals();
  loadAdminStats();
}

async function loadAdminStats() {
  const setStat = (name, val) => {
    const el = document.querySelector(`#adStats [data-stat="${name}"]`);
    if (el) el.textContent = val;
  };
  // Products (public), discounts/referrals/tickets (admin). Fail soft per call.
  try { const r = await api('/api/store/products'); setStat('products', (r.products || []).length); } catch (_) {}
  try { const r = await api('/api/store/discounts', { admin: true }); setStat('discounts', (r.discounts || []).length); } catch (_) {}
  try { const r = await api('/api/referral', { admin: true }); setStat('referrals', (r.referrals || []).length); } catch (_) {}
  try {
    const r = await api('/api/store/tickets', { admin: true });
    const open = (r.tickets || []).filter((t) => t.status === 'open').length;
    setStat('tickets', open);
  } catch (_) {}
}

async function loadAdminReferrals() {
  const list = $('#adRefList');
  if (!list) return;
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const r = await api('/api/referral', { admin: true });
    const items = r.referrals || [];
    if (!items.length) { list.innerHTML = `<div class="empty">No referrals yet.</div>`; return; }
    list.innerHTML = items.map((ref) => `
      <div class="admin-key" data-id="${esc(ref.id)}">
        <div class="ak-main">
          <code>${esc(ref.code)}</code>
          <div class="ap-sub">${esc(ref.username || ref.discordId)} · ${ref.clicks || 0} clicks · ${ref.signups || 0} signups${ref.payout ? ' · ' + esc(ref.payout) : ''}</div>
        </div>
        <button class="mini danger" data-act="del">Delete</button>
      </div>`).join('');
    list.querySelectorAll('.admin-key').forEach((row) => {
      row.querySelector('[data-act="del"]').addEventListener('click', async () => {
        if (!confirm('Delete this referral?')) return;
        try { await api('/api/referral/' + row.dataset.id, { method: 'DELETE', admin: true }); loadAdminReferrals(); }
        catch (e) { alert(e.message); }
      });
    });
  } catch (e) { list.innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
}

async function loadAdminDiscounts() {
  const list = $('#adDiscList');
  if (!list) return;
  try {
    const r = await api('/api/store/discounts', { admin: true });
    const items = r.discounts || [];
    if (!items.length) { list.innerHTML = `<div class="empty">No codes yet.</div>`; return; }
    list.innerHTML = items.map((d) => `
      <div class="admin-key" data-id="${esc(d.id)}">
        <div class="ak-main">
          <code>${esc(d.code)}</code>
          <div class="ak-sub">${d.type === 'fixed' ? '$' + d.amount + ' off' : d.amount + '% off'}${d.note ? ' · ' + esc(d.note) : ''}</div>
        </div>
        <div class="ak-actions"><button class="mini danger" data-del>Delete</button></div>
      </div>`).join('');
    list.querySelectorAll('.admin-key').forEach((row) => {
      row.querySelector('[data-del]').addEventListener('click', async () => {
        try { await api('/api/store/discounts/' + row.dataset.id, { method: 'DELETE', admin: true }); loadAdminDiscounts(); }
        catch (e) { alert(e.message); }
      });
    });
  } catch (e) { list.innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
}

async function loadAdminTickets() {
  const list = $('#adTicketList');
  if (!list) return;
  try {
    const r = await api('/api/store/tickets', { admin: true });
    const items = r.tickets || [];
    if (!items.length) { list.innerHTML = `<div class="empty">No tickets.</div>`; return; }
    list.innerHTML = items.map((t) => `
      <div class="admin-ticket" data-id="${esc(t.id)}">
        <div class="at-head">
          <strong>${esc(t.subject)}</strong>
          <span class="ticket-status ${t.status === 'open' ? 'open' : 'closed'}">${esc(t.status)}</span>
        </div>
        <div class="ak-sub">@${esc(t.username || t.discordId)} · ${fmtDate(t.createdAt)}</div>
        <p class="at-msg">${esc(t.message)}</p>
        ${(t.replies || []).map((rp) => `<p class="at-reply ${rp.from === 'staff' ? 'staff' : ''}"><b>${rp.from === 'staff' ? 'Staff' : 'User'}:</b> ${esc(rp.message)}</p>`).join('')}
        <div class="at-actions">
          <input type="text" placeholder="Reply..." data-reply />
          <button class="mini" data-send>Reply</button>
          <button class="mini" data-toggle>${t.status === 'open' ? 'Close' : 'Reopen'}</button>
        </div>
      </div>`).join('');
    list.querySelectorAll('.admin-ticket').forEach((row) => {
      const id = row.dataset.id;
      row.querySelector('[data-send]').addEventListener('click', async () => {
        const msg = row.querySelector('[data-reply]').value.trim();
        if (!msg) return;
        try { await api('/api/store/tickets/' + id + '/admin-reply', { method: 'POST', body: { message: msg }, admin: true }); loadAdminTickets(); }
        catch (e) { alert(e.message); }
      });
      row.querySelector('[data-toggle]').addEventListener('click', async () => {
        const cur = row.querySelector('.ticket-status').textContent;
        try { await api('/api/store/tickets/' + id + '/status', { method: 'PATCH', body: { status: cur === 'open' ? 'closed' : 'open' }, admin: true }); loadAdminTickets(); }
        catch (e) { alert(e.message); }
      });
    });
  } catch (e) { list.innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
}

async function loadAdminProducts() {
  const list = $('#adProdList');
  if (!list) return;
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const r = await api('/api/store/products');
    const products = r.products || [];
    if (!products.length) { list.innerHTML = `<div class="empty">No products yet. Add one below.</div>`; return; }
    list.innerHTML = products.map(p => `
      <div class="admin-prod" data-id="${esc(p.id)}">
        <img src="${esc(p.image || 'product1.png')}" alt="" />
        <div class="ap-main">
          <div class="ap-name">${esc(p.name)} ${p.featured ? '⭐' : ''}</div>
          <div class="ap-sub">${esc(p.category)} · ${esc(p.price || '—')}${p.priceMonthly ? ' / ' + esc(p.priceMonthly) + 'mo' : ''}</div>
        </div>
        <div class="ap-actions">
          <button class="mini" data-act="edit">Edit</button>
          <button class="mini danger" data-act="del">Delete</button>
        </div>
      </div>`).join('');
    list.querySelectorAll('.admin-prod').forEach(row => {
      const p = products.find(x => x.id === row.dataset.id);
      row.querySelector('[data-act="edit"]').addEventListener('click', () => fillProdForm(p));
      row.querySelector('[data-act="del"]').addEventListener('click', async () => {
        if (!confirm('Delete "' + p.name + '"?')) return;
        try { await api('/api/store/products/' + p.id, { method: 'DELETE', admin: true }); loadAdminProducts(); }
        catch (e) { alert(e.message); }
      });
    });
  } catch (e) { list.innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
}

function fillProdForm(p) {
  const $ = (s) => document.querySelector(s);
  $('#adProdId').value = p.id;
  $('#adProdName').value = p.name || '';
  $('#adProdCategory').value = p.category || '';
  $('#adProdPrice').value = p.price || '';
  $('#adProdPriceMonthly').value = p.priceMonthly || '';
  $('#adProdBadge').value = p.badge || '';
  $('#adProdKmrzaProduct').value = p.komerzaProductId || '';
  $('#adProdKmrzaLife').value = (p.komerzaVariants && p.komerzaVariants.lifetime) || '';
  $('#adProdKmrzaMonth').value = (p.komerzaVariants && p.komerzaVariants.monthly) || '';
  $('#adProdDesc').value = p.description || '';
  $('#adProdFeatured').checked = !!p.featured;
  const prev = $('#adImgPreview'), drop = $('#adImgDrop');
  $('#adProdImage').value = p.image || '';
  if (p.image) { prev.src = p.image; prev.hidden = false; drop.classList.add('has-img'); }
  else { prev.hidden = true; drop.classList.remove('has-img'); }
  const title = $('#adProdFormTitle'); if (title) title.textContent = 'Edit product';
  const card = $('#adProdFormCard'); if (card) card.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

/* ---------- Cloudinary unsigned upload ---------- */
async function uploadToCloudinary(file) {
  const cfg = (window.RIOTS_CONFIG && window.RIOTS_CONFIG.CLOUDINARY) || {};
  if (!cfg.cloudName || !cfg.uploadPreset) {
    throw new Error('Cloudinary not configured (set CLOUDINARY in config.js).');
  }
  const form = new FormData();
  form.append('file', file);
  form.append('upload_preset', cfg.uploadPreset);
  const res = await fetch(`https://api.cloudinary.com/v1_1/${cfg.cloudName}/image/upload`, {
    method: 'POST',
    body: form,
  });
  const data = await res.json();
  if (!res.ok || !data.secure_url) throw new Error(data.error?.message || 'Upload failed.');
  return data.secure_url;
}

async function searchAdminKeys() {
  const list = $('#adKeyList');
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  const filter = $('#adFilter').value.trim();
  let q = '';
  if (filter) q = /^\d{5,25}$/.test(filter) ? '?discordId=' + filter : '?key=' + encodeURIComponent(filter);
  try {
    const r = await api('/api/keys/admin/list' + q, { admin: true });
    list.innerHTML = renderAdminKeys(r.keys || []);
    bindAdminKeyActions();
  } catch (e) { list.innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
}

function renderAdminKeys(keys) {
  if (!keys.length) return `<div class="empty">No keys found.</div>`;
  return keys.map((k) => `
    <div class="admin-key" data-key="${esc(k.key)}" data-discord="${esc(k.discordId || '')}">
      <div class="ak-main">
        <code>${esc(k.key)}</code>
        <div class="ak-sub">
          ${k.discordData ? `👤 ${esc(k.discordData.global_name || k.discordData.username)} (${esc(k.discordId)})` : (k.discordId ? `👤 ${esc(k.discordId)}` : '⚪ unassigned')}
          · exp ${k.expire ? fmtDate(k.expire) : '∞'}
          ${k.blacklisted ? '· <span class="bad">blacklisted</span>' : ''}
        </div>
      </div>
      <div class="ak-actions">
        <button class="mini" data-act="reset">Reset HWID</button>
        <button class="mini" data-act="blacklist">${k.blacklisted ? 'Unblacklist' : 'Blacklist'}</button>
        <button class="mini danger" data-act="delete">Delete</button>
      </div>
    </div>`).join('');
}

function bindAdminKeyActions() {
  $$('.admin-key').forEach((row) => {
    const key = row.dataset.key;
    row.querySelectorAll('.mini').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const act = btn.dataset.act;
        try {
          if (act === 'reset') {
            await api('/api/keys/admin/reset-hwid', { method: 'POST', body: { key }, admin: true });
            alert('HWID reset.');
          } else if (act === 'blacklist') {
            const isBl = btn.textContent === 'Unblacklist';
            await api('/api/keys/admin/blacklist', { method: 'POST', body: { key, blacklisted: !isBl, reason: 'Admin action' }, admin: true });
            searchAdminKeys();
          } else if (act === 'delete') {
            if (!confirm('Delete this key permanently?')) return;
            await api('/api/keys/admin/delete?key=' + encodeURIComponent(key), { method: 'DELETE', admin: true });
            searchAdminKeys();
          }
        } catch (e) { alert(e.message); }
      });
    });
  });
}

/* ---------------- BOOT ---------------- */
(async function boot() {
  renderIcons();
  document.body.classList.add('loaded');
  showGate('start');

  const pendingKey = localStorage.getItem(PENDING_KEY);

  let me;
  try {
    me = await api('/auth/me');
  } catch (e) {
    // API unreachable (not deployed yet)
    $('#agSub').textContent = 'Register your key to access your dashboard.';
    showGate('start');
    console.warn('[dashboard] API not reachable:', e.message);
    return;
  }

  if (!me.authenticated) {
    // Not logged into Discord. If they already entered a key, they just need
    // to auth Discord — show the link overlay. Otherwise start fresh.
    if (pendingKey) showLinkGate(); else showGate('start');
    return;
  }

  // Logged into Discord. If a key is pending, link it now.
  if (pendingKey) {
    try {
      await api('/api/keys/register', { method: 'POST', body: { key: pendingKey } });
      localStorage.removeItem(PENDING_KEY);
    } catch (e) {
      // link failed (bad/taken key) — surface it on the link overlay
      showLinkGate();
      const err = $('#linkError');
      err.textContent = e.message;
      err.hidden = false;
      return;
    }
  }

  // Do they have a linked key now?
  try {
    const data = await api('/api/keys/mine');
    if (data.linked && data.keys.length) {
      await loadUserDashboard();
      hideGate();
    } else {
      // authed but no key linked and nothing pending -> ask for a key
      const sub = $('#agSub');
      if (sub) sub.textContent = 'You\u2019re signed in with Discord. Register a license key to unlock your dashboard.';
      showGate('key');
    }
  } catch (e) {
    showGate('start');
  }
})();
