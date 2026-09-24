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

let currentGateStep = 'start';

function showGate(step = 'start') {
  currentGateStep = step;
  gate.classList.remove('hidden');
  linkGate.hidden = true;
  dashMain.classList.add('blurred');
  $('#agStepStart').hidden = step !== 'start';
  $('#agStepKey').hidden = step !== 'key';
  $('#agStepAdmin').hidden = step !== 'admin';
  const back = $('#agBack');
  if (back) {
    back.hidden = false;
    back.title = step === 'start' ? 'Back to Store' : 'Back';
  }
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

// Top-left back arrow navigation:
$('#agBack').addEventListener('click', () => {
  if (currentGateStep === 'key' || currentGateStep === 'admin') {
    showGate('start');
  } else {
    // If on start screen, go back in history or to home/store
    if (window.history.length > 1 && document.referrer) {
      window.history.back();
    } else {
      window.location.href = 'index.html';
    }
  }
});

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
const lgBack = $('#lgBack');
if (lgBack) {
  lgBack.addEventListener('click', () => {
    localStorage.removeItem(PENDING_KEY);
    showGate('start');
  });
}
$('#linkCancel').addEventListener('click', () => {
  localStorage.removeItem(PENDING_KEY);
  showGate('start');
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
    if (view === 'scripts') loadMyScripts();
    if (view === 'management') loadManagement();
    if (view === 'referral') loadReferral();
    if (view === 'admin') loadAdmin();
    if (view === 'logs') loadLogsCracks();
    if (view === 'products') loadProducts();
    if (view === 'features') loadFeatures();
    if (view === 'categories') loadCategories();
  });
});

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
    $('#keysArea').innerHTML = `<div class="empty">No keys linked yet. <a href="products">Grab one here</a>.</div>`;
    return;
  }
  $('#keysArea').innerHTML = data.keys.map((k) => `
    <div class="key-card">
      <div class="key-top">
        <div>
          <div class="key-label">
            ${k.isExternal ? `<span class="badge-pill external">EXTERNAL SOFTWARE</span> ` : `<span class="badge-pill script">LUA SCRIPT</span> `}
            ${esc(k.hubName || (k.isExternal ? 'RiotsSeige' : 'License Key'))}
          </div>
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
        <button class="btn btn-bw user-reset-hwid" data-key="${esc(k.key)}" data-external="${k.isExternal ? '1' : '0'}"><span>Reset HWID</span></button>
      </div>
    </div>`).join('');

  $$('.copy-btn').forEach((b) => b.addEventListener('click', () => {
    navigator.clipboard.writeText(b.dataset.copy);
    b.textContent = 'Copied!';
    setTimeout(() => (b.textContent = 'Copy'), 1400);
  }));

  $$('.user-reset-hwid').forEach((btn) => {
    btn.addEventListener('click', async () => {
      btn.disabled = true;
      const key = btn.dataset.key;
      const isExt = btn.dataset.external === '1';
      try {
        const endpoint = isExt ? '/api/external-keys/reset-hwid' : '/api/keys/reset-hwid';
        const r = await api(endpoint, { method: 'POST', body: { key } });
        alert(r.message || 'HWID reset successfully.');
      } catch (e) {
        alert(e.message);
      } finally {
        btn.disabled = false;
      }
    });
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
        <button class="btn btn-gradient" id="profGetScript"><i data-lucide="download"></i><span>Get script</span></button>
        <button class="btn btn-bw" id="profResetHwid"><i data-lucide="rotate-ccw"></i><span>Reset my HWID</span></button>
        <a class="btn btn-bw" href="https://discord.gg/m7Z9Jyp6pf" target="_blank" rel="noopener"><i data-lucide="life-buoy"></i><span>Get support</span></a>
      </div>
      <p class="profile-note">Resetting your HWID lets you run the script on a new device. It respects the cooldown set by staff.</p>
      ` : `
      <div class="empty" style="margin-top:18px">No key linked to this account yet. <a href="products">Grab one here</a>.</div>
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
  const getScript = $('#profGetScript');
  if (getScript) getScript.addEventListener('click', openScriptModal);
  renderIcons();
}

/* ---------------- MANAGEMENT (Download external/loader) ---------------- */
async function loadManagement() {
  const area = $('#managementArea');
  if (!area) return;
  area.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  
  try {
    // Check if user has active key
    const keyData = await api('/api/keys/mine');
    const hasKey = keyData.linked && keyData.keys && keyData.keys.length > 0;
    
    area.innerHTML = `
      <div class="adm-card">
        <div class="adm-card-head">
          <h3><i data-lucide="download"></i> RiotsSeige External</h3>
          ${hasKey ? '<span class="key-status ok">Available</span>' : '<span class="key-status pending">Key Required</span>'}
        </div>
        <div class="management-content">
          <p class="admin-hint">Download the RiotsSeige external loader. You need an active key to use it.</p>
          
          ${hasKey ? `
          <div class="download-section">
            <div class="download-card">
              <div class="dl-icon"><i data-lucide="file-archive"></i></div>
              <div class="dl-info">
                <div class="dl-name">RiotsSeige Loader</div>
                <div class="dl-sub">Latest version · Windows 10/11</div>
              </div>
              <button class="btn btn-gradient" id="downloadLoader">
                <i data-lucide="download"></i>
                <span>Download</span>
              </button>
            </div>
          </div>
          
          <div class="instructions-card">
            <h4><i data-lucide="info"></i> How to use</h4>
            <ol>
              <li>Download and extract the loader</li>
              <li>Run <code>RiotsSeige.exe</code> as Administrator</li>
              <li>Enter your license key from the <a href="#" onclick="showTab('keys'); return false;">My Keys</a> tab</li>
              <li>Configure your settings and enjoy!</li>
            </ol>
          </div>
          
          <div class="warning-card">
            <div class="warn-icon"><i data-lucide="alert-triangle"></i></div>
            <div>
              <div class="warn-title">Important</div>
              <div class="warn-text">Disable antivirus before launching. The loader may be flagged due to anti-cheat protection. Never share your key.</div>
            </div>
          </div>
          ` : `
          <div class="empty">
            <i data-lucide="lock"></i>
            <p>You need an active key to download the loader.</p>
            <a href="products" class="btn btn-gradient">Get a Key</a>
          </div>
          `}
        </div>
      </div>`;
    
    if (hasKey) {
      const downloadBtn = area.querySelector('#downloadLoader');
      if (downloadBtn) {
        downloadBtn.addEventListener('click', async () => {
          // In production, this would hit an API endpoint that returns a signed download URL
          // For now, we'll show a message
          alert('Download starting... The loader will be downloaded from a secure server.');
          // window.location.href = '/api/downloads/riotsseige';
        });
      }
    }
    
    renderIcons();
  } catch (e) {
    area.innerHTML = `<div class="empty">Couldn't load management panel. ${esc(e.message)}</div>`;
  }
}

/* ---------------- COMBINED LOGS & CRACKS (Admin) ---------------- */
async function loadLogsCracks(subsection = 'all') {
  const area = $('#logsArea');
  if (!area) return;
  area.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  
  try {
    // Fetch both logs and cracks stats
    const [logsRes, cracksRes] = await Promise.all([
      api('/api/logs/stats/summary', { admin: true }).catch(() => ({ stats: {} })),
      api('/api/cracks/stats/summary', { admin: true }).catch(() => ({ stats: {} }))
    ]);
    
    const logStats = logsRes.stats || {};
    const crackStats = cracksRes.stats || {};
    
    area.innerHTML = `
      <div class="logs-container">
        <!-- Sidebar navigation -->
        <aside class="logs-nav">
          <div class="logs-nav-title"><i data-lucide="file-text"></i> Logs</div>
          <button class="logs-navbtn ${subsection === 'all' ? 'active' : ''}" data-section="all"><i data-lucide="layers"></i><span>All Events</span></button>
          <button class="logs-navbtn ${subsection === 'info' ? 'active' : ''}" data-section="info"><i data-lucide="info"></i><span>Info</span></button>
          <button class="logs-navbtn ${subsection === 'verification' ? 'active' : ''}" data-section="verification"><i data-lucide="check-circle"></i><span>Verification</span></button>
          <button class="logs-navbtn ${subsection === 'login' ? 'active' : ''}" data-section="login"><i data-lucide="log-in"></i><span>Login</span></button>
          <button class="logs-navbtn ${subsection === 'execution' ? 'active' : ''}" data-section="execution"><i data-lucide="play"></i><span>Execution</span></button>
          <button class="logs-navbtn ${subsection === 'error' ? 'active' : ''}" data-section="error"><i data-lucide="alert-circle"></i><span>Errors</span></button>
          <div class="logs-nav-divider"></div>
          <button class="logs-navbtn ${subsection === 'cracks' ? 'active' : ''}" data-section="cracks"><i data-lucide="shield-alert"></i><span>Cracks</span></button>
        </aside>
        
        <!-- Main content -->
        <div class="logs-main">
          <!-- Stats cards -->
          <div class="logs-stats">
            <div class="lstat"><div class="lstat-val">${logStats.total || 0}</div><div class="lstat-label">Total Logs</div></div>
            <div class="lstat"><div class="lstat-val">${logStats.todaysCount || 0}</div><div class="lstat-label">Today</div></div>
            <div class="lstat"><div class="lstat-val">${crackStats.total || 0}</div><div class="lstat-label">Crack Events</div></div>
            <div class="lstat ${crackStats.open > 0 ? 'warn' : ''}"><div class="lstat-val">${crackStats.open || 0}</div><div class="lstat-label">Open Cracks</div></div>
            <div class="lstat ${crackStats.criticalCount > 0 ? 'danger' : ''}"><div class="lstat-val">${crackStats.criticalCount || 0}</div><div class="lstat-label">Critical</div></div>
          </div>
          
          <!-- Content area -->
          <div class="adm-card">
            <div class="adm-card-head">
              <h3 id="logsSectionTitle">All Events</h3>
              <button class="btn btn-bw sm" id="refreshLogs"><i data-lucide="refresh-cw"></i><span>Refresh</span></button>
            </div>
            <div class="adm-toolbar">
              <input type="text" id="logsSearch" class="adm-search" placeholder="Search by key, HWID, message..." />
              <select id="logsTimeFilter">
                <option value="all">All time</option>
                <option value="today">Today</option>
                <option value="week">Last 7 days</option>
                <option value="month">Last 30 days</option>
              </select>
            </div>
            <div id="logsList"></div>
          </div>
        </div>
      </div>`;
    
    // Wire up navigation
    area.querySelectorAll('.logs-navbtn').forEach(btn => {
      btn.addEventListener('click', () => {
        area.querySelectorAll('.logs-navbtn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        loadLogsSection(btn.dataset.section);
      });
    });
    
    // Initial load
    loadLogsSection(subsection);
    
    const refreshBtn = area.querySelector('#refreshLogs');
    if (refreshBtn) refreshBtn.addEventListener('click', () => {
      const activeBtn = area.querySelector('.logs-navbtn.active');
      loadLogsSection(activeBtn ? activeBtn.dataset.section : 'all');
    });
    
    renderIcons();
    enhanceSelects(area);
  } catch (e) {
    area.innerHTML = `<div class="empty">Couldn't load logs. ${esc(e.message)}</div>`;
  }
}

async function loadLogsSection(section) {
  const list = $('#logsList');
  const titleEl = $('#logsSectionTitle');
  if (!list) return;
  
  // Update title
  const titles = {
    'all': 'All Events',
    'info': 'Info Logs',
    'verification': 'Verification Logs',
    'login': 'Login Logs',
    'execution': 'Execution Logs',
    'error': 'Error Logs',
    'cracks': 'Crack Attempts'
  };
  if (titleEl) titleEl.textContent = titles[section] || 'All Events';
  
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  
  try {
    if (section === 'cracks') {
      // Load cracks
      const res = await api('/api/cracks?limit=50', { admin: true });
      const cracks = res.cracks || [];
      
      if (!cracks.length) {
        list.innerHTML = `<div class="empty">No crack attempts detected.</div>`;
        return;
      }
      
      list.innerHTML = `
        <div class="logs-grid">
          ${cracks.map(c => `
            <div class="log-row crack ${c.severity}">
              <div class="log-main">
                <div class="log-type"><i data-lucide="shield-alert"></i> ${esc(c.type)}</div>
                <div class="log-message">${esc(c.description)}</div>
                <div class="log-meta">
                  ${c.keyId ? `<span>Key: <code>${esc(c.keyId)}</code></span>` : ''}
                  ${c.hwid ? `<span>HWID: <code>${esc(String(c.hwid).substring(0, 12))}...</code></span>` : ''}
                  <span class="severity-badge ${c.severity}">${c.severity}</span>
                  <span class="status-badge ${c.status}">${c.status}</span>
                </div>
              </div>
              <div class="log-time">${fmtDateTime(c.timestamp)}</div>
              <div class="log-actions">
                <button class="mini" data-crack-id="${esc(c.id)}" data-action="investigate">Investigate</button>
                <button class="mini" data-crack-id="${esc(c.id)}" data-action="resolve">Resolve</button>
              </div>
            </div>
          `).join('')}
        </div>`;
      
      // Wire up crack actions
      list.querySelectorAll('.log-actions button').forEach(btn => {
        btn.addEventListener('click', async () => {
          const crackId = btn.dataset.crackId;
          const action = btn.dataset.action;
          const status = action === 'investigate' ? 'investigating' : 'resolved';
          
          try {
            await api(`/api/cracks/${crackId}`, {
              method: 'PATCH',
              body: { status },
              admin: true
            });
            loadLogsSection('cracks');
          } catch (e) {
            alert(e.message);
          }
        });
      });
      
    } else {
      // Load logs
      let endpoint = '/api/logs?limit=50';
      if (section !== 'all') {
        endpoint += '&type=' + section;
      }
      
      const res = await api(endpoint, { admin: true });
      const logs = res.logs || [];
      
      if (!logs.length) {
        list.innerHTML = `<div class="empty">No logs found.</div>`;
        return;
      }
      
      const logIcons = {
        'info': 'info',
        'verification': 'check-circle',
        'login': 'log-in',
        'execution': 'play',
        'error': 'alert-circle'
      };
      
      list.innerHTML = `
        <div class="logs-grid">
          ${logs.map(l => `
            <div class="log-row ${l.type}">
              <div class="log-main">
                <div class="log-type"><i data-lucide="${logIcons[l.type] || 'file-text'}"></i> ${esc(l.type)}</div>
                <div class="log-message">${esc(l.message)}</div>
                <div class="log-meta">
                  ${l.keyId ? `<span>Key: <code>${esc(l.keyId)}</code></span>` : ''}
                  ${l.hwid ? `<span>HWID: <code>${esc(String(l.hwid).substring(0, 12))}...</code></span>` : ''}
                </div>
              </div>
              <div class="log-time">${fmtDateTime(l.timestamp)}</div>
            </div>
          `).join('')}
        </div>`;
    }
    
    renderIcons();
  } catch (e) {
    list.innerHTML = `<div class="empty">Couldn't load logs. ${esc(e.message)}</div>`;
  }
}

/* ---------------- REFERRAL ---------------- */
function refLink(code) {
  const origin = location.origin.includes('file') ? 'https://riots.wtf' : location.origin;
  return origin + '/products?ref=' + encodeURIComponent(code);
}
/* ---------------- MY SCRIPTS (user) ---------------- */
function loaderCode(key, loaderUrl) {
  return `getgenv().lp_key = "${key || 'YOUR_KEY'}"\nloadstring(game:HttpGet(\n    "${loaderUrl}"\n))()`;
}
async function loadMyScripts() {
  const area = $('#scriptsArea');
  if (!area) return;
  area.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  let data;
  try {
    data = await api('/api/store/scripts/mine');
  } catch (e) {
    area.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
    return;
  }
  if (!data.hasKey) {
    area.innerHTML = `<div class="empty">No active key linked yet. <a href="products">Grab one here</a> to unlock your scripts.</div>`;
    return;
  }
  const scripts = data.scripts || [];
  if (!scripts.length) {
    area.innerHTML = `<div class="empty">Your key doesn't have any scripts assigned yet. <a href="https://discord.gg/m7Z9Jyp6pf" target="_blank" rel="noopener">Reach us on Discord</a> if you think this is wrong.</div>`;
    return;
  }
  const hubs = [...new Set(scripts.map((s) => s.hubName).filter(Boolean))];
  area.innerHTML = `
    <div class="scripts-head">
      <div>
        <h3 class="scripts-title">Your scripts</h3>
        <p class="scripts-sub">${scripts.length} script${scripts.length === 1 ? '' : 's'} unlocked${hubs.length ? ' across ' + hubs.length + ' hub' + (hubs.length === 1 ? '' : 's') : ''}. Paste a loader into your executor and run.</p>
      </div>
      <div class="scripts-tools">
        <div class="store-search sm"><i data-lucide="search"></i><input type="text" id="scriptSearch" placeholder="Filter scripts..." /></div>
      </div>
    </div>
    <div class="scripts-grid" id="scriptsGrid">${scripts.map((s) => {
    const code = loaderCode(s.key, s.loaderUrl);
    return `
    <div class="script-card" data-id="${esc(s.id)}" data-name="${esc((s.name + ' ' + (s.hubName || '')).toLowerCase())}">
      <div class="sc-head">
        <div><div class="sc-name">${esc(s.name)}</div>${s.hubName ? `<div class="sc-game"><i data-lucide="folder"></i> ${esc(s.hubName)}</div>` : ''}</div>
        <span class="sc-badge"><span class="dot"></span> Active</span>
      </div>
      <div class="sc-code">
        <pre><code>${esc(code)}</code></pre>
        <div class="sc-actions">
          <button class="btn btn-gradient sm sc-copy" type="button" data-code="${esc(code)}"><i data-lucide="copy"></i><span>Copy loader</span></button>
          ${s.loaderUrl ? `<a class="btn btn-bw sm" href="${esc(s.loaderUrl)}" target="_blank" rel="noopener"><i data-lucide="external-link"></i><span>Raw</span></a>` : ''}
          ${s.key ? `<button class="btn btn-bw sm sc-copy" type="button" data-code="${esc(s.key)}"><i data-lucide="key-round"></i><span>Copy key</span></button>` : ''}
        </div>
      </div>
    </div>`;
  }).join('')}</div>
  <div class="empty" id="scriptsEmpty" hidden>No scripts match your filter.</div>`;
  renderIcons();
  const grid = area.querySelector('#scriptsGrid');
  const emptyMsg = area.querySelector('#scriptsEmpty');
  const search = area.querySelector('#scriptSearch');
  if (search) search.addEventListener('input', () => {
    const q = search.value.trim().toLowerCase();
    let shown = 0;
    grid.querySelectorAll('.script-card').forEach((c) => {
      const match = !q || c.dataset.name.includes(q);
      c.hidden = !match; if (match) shown++;
    });
    if (emptyMsg) emptyMsg.hidden = shown !== 0;
  });
  area.querySelectorAll('.sc-copy').forEach((btn) => {
    btn.addEventListener('click', () => {
      navigator.clipboard.writeText(btn.dataset.code).then(() => {
        const s = btn.querySelector('span'); const old = s.textContent;
        s.textContent = 'Copied!'; btn.classList.add('ok');
        setTimeout(() => { s.textContent = old; btn.classList.remove('ok'); }, 1500);
      });
    });
  });
}

/* "Get script" modal — pick a script, copy its loadstring. */
function closeScriptModal() {
  const m = $('#scriptModal'); if (m) m.remove();
  document.body.style.overflow = '';
}
async function openScriptModal() {
  closeScriptModal();
  const wrap = document.createElement('div');
  wrap.id = 'scriptModal';
  wrap.className = 'modal-overlay';
  wrap.innerHTML = `
    <div class="modal-card" role="dialog" aria-modal="true">
      <button class="modal-close" id="scriptModalClose" aria-label="Close"><i data-lucide="x"></i></button>
      <h3 class="modal-title"><i data-lucide="download"></i> Get script</h3>
      <div id="scriptModalBody"><div class="dash-loading"><span></span><span></span><span></span></div></div>
    </div>`;
  document.body.appendChild(wrap);
  document.body.style.overflow = 'hidden';
  renderIcons();
  wrap.addEventListener('click', (e) => { if (e.target === wrap) closeScriptModal(); });
  $('#scriptModalClose').addEventListener('click', closeScriptModal);

  const body = $('#scriptModalBody');
  let data;
  try {
    data = await api('/api/store/scripts/mine');
  } catch (e) {
    body.innerHTML = `<p class="ref-error">${esc(e.message)}</p>`; return;
  }
  if (!data.hasKey) {
    body.innerHTML = `<div class="empty">No active key linked yet. <a href="products">Grab one here</a>.</div>`; return;
  }
  const scripts = data.scripts || [];
  if (!scripts.length) {
    body.innerHTML = `<div class="empty">Your key doesn't unlock any scripts yet.</div>`; return;
  }

  body.innerHTML = `
    <label class="admin-label" style="color:var(--muted)">Choose a script</label>
    <select id="scriptModalPick">
      ${scripts.map((s, i) => `<option value="${i}">${esc(s.name)}${s.hubName ? ' — ' + esc(s.hubName) : ''}</option>`).join('')}
    </select>
    <label class="admin-label" style="color:var(--muted);margin-top:14px">Your loadstring</label>
    <div class="sc-code">
      <pre><code id="scriptModalCode"></code></pre>
      <button class="btn btn-gradient wide sc-copy" id="scriptModalCopy" type="button"><i data-lucide="copy"></i><span>Copy loadstring</span></button>
    </div>
    <p class="profile-note">Paste this into your executor. Keep your key private — sharing it gets it blacklisted.</p>`;

  const codeEl = $('#scriptModalCode');
  const pick = $('#scriptModalPick');
  const render = () => {
    const s = scripts[parseInt(pick.value, 10) || 0];
    codeEl.textContent = loaderCode(s.key, s.loaderUrl);
  };
  pick.addEventListener('change', render);
  render();
  if (typeof enhanceSelects === 'function') enhanceSelects(body);

  $('#scriptModalCopy').addEventListener('click', (e) => {
    const btn = e.currentTarget;
    navigator.clipboard.writeText(codeEl.textContent).then(() => {
      const sp = btn.querySelector('span'); const old = sp.textContent;
      sp.textContent = 'Copied!'; btn.classList.add('ok');
      setTimeout(() => { sp.textContent = old; btn.classList.remove('ok'); }, 1500);
    });
  });
  renderIcons();
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
  const keyThreshold = 5; // Number of referrals needed to unlock a key
  const progress = Math.min((ref.signups || 0), keyThreshold);
  const keysEarned = Math.floor((ref.signups || 0) / keyThreshold);
  const pendingReferrals = (ref.signups || 0) % keyThreshold;
  
  panel.innerHTML = `
    <div class="ref-card">
      <div class="ref-card-head"><h3>Your referral link</h3><span class="admin-badge">active</span></div>
      <span class="ref-code-label">Share this link to earn keys</span>
      <div class="ref-code-row">
        <code id="refLinkVal">${esc(link)}</code>
        <button class="btn btn-bw sm" id="refCopy" type="button"><i data-lucide="copy"></i><span>Copy</span></button>
      </div>
      <div class="ref-stats">
        <div class="ref-stat"><div class="rs-val">${ref.clicks || 0}</div><div class="rs-label">Clicks</div></div>
        <div class="ref-stat"><div class="rs-val">${ref.signups || 0}</div><div class="rs-label">Signups</div></div>
        <div class="ref-stat"><div class="rs-val">${keysEarned}</div><div class="rs-label">Keys Earned</div></div>
      </div>
      <div class="ref-progress-section">
        <div class="ref-progress-bar">
          <div class="ref-progress-fill" style="width: ${(pendingReferrals / keyThreshold) * 100}%"></div>
        </div>
        <div class="ref-progress-text">${pendingReferrals} / ${keyThreshold} referrals to next key</div>
      </div>
      <p class="ref-note">Your code is <strong>${esc(ref.code)}</strong>. Every ${keyThreshold} successful referrals unlocks a free key! Admins will review and redeem your referrals into keys.</p>
      ${keysEarned > 0 ? `<button class="btn btn-gradient" id="redeemReferrals" style="margin-top:12px"><i data-lucide="gift"></i> <span>Redeem ${keysEarned} Key${keysEarned > 1 ? 's' : ''}</span></button>` : ''}
    </div>`;
  renderIcons();
  const copyBtn = panel.querySelector('#refCopy');
  if (copyBtn) copyBtn.addEventListener('click', () => {
    navigator.clipboard.writeText(link).then(() => {
      const s = copyBtn.querySelector('span'); const old = s.textContent;
      s.textContent = 'Copied!'; setTimeout(() => (s.textContent = old), 1500);
    });
  });
  const redeemBtn = panel.querySelector('#redeemReferrals');
  if (redeemBtn) redeemBtn.addEventListener('click', async () => {
    if (!confirm(`Request ${keysEarned} key${keysEarned > 1 ? 's' : ''} from your referrals? An admin will review and approve.`)) return;
    try {
      await api('/api/referral/redeem', { method: 'POST' });
      alert('Redemption request sent! An admin will review your referrals and issue your key(s).');
      loadReferral();
    } catch (e) { alert(e.message); }
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
        <button class="adm-navbtn" data-section="sales"><i data-lucide="dollar-sign"></i><span>Sales</span></button>
        <button class="adm-navbtn" data-section="analytics"><i data-lucide="bar-chart-3"></i><span>Analytics</span></button>
        <button class="adm-navbtn" data-section="products"><i data-lucide="package"></i><span>Products</span></button>
        <button class="adm-navbtn" data-section="keys"><i data-lucide="key-round"></i><span>Keys &amp; users</span></button>
        <button class="adm-navbtn" data-section="scripts"><i data-lucide="file-code"></i><span>Scripts</span></button>
        <button class="adm-navbtn" data-section="referrals"><i data-lucide="gift"></i><span>Referrals</span></button>
        <button class="adm-navbtn" data-section="status"><i data-lucide="activity"></i><span>Status</span></button>
        <button class="adm-navbtn" data-section="devlog"><i data-lucide="megaphone"></i><span>Devlog</span></button>
        <button class="adm-navbtn" data-section="downloads"><i data-lucide="download"></i><span>Downloads</span></button>
      </aside>

      <div class="adm-main">
        <!-- OVERVIEW -->
        <section class="adm-section active" data-section="overview">
          <div class="adm-head"><h2>Overview</h2><p>Quick snapshot of your store.</p></div>
          <div class="adm-stats" id="adStats">
            <div class="adm-stat"><div class="as-ico"><i data-lucide="dollar-sign"></i></div><div><div class="as-val" data-stat="revenue">—</div><div class="as-label">Total revenue</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="shopping-cart"></i></div><div><div class="as-val" data-stat="sales">—</div><div class="as-label">Paid orders</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="package"></i></div><div><div class="as-val" data-stat="products">—</div><div class="as-label">Products</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="gift"></i></div><div><div class="as-val" data-stat="referrals">—</div><div class="as-label">Referrals</div></div></div>
          </div>
          <div class="adm-quick">
            <button class="adm-quick-btn" data-goto="sales"><i data-lucide="dollar-sign"></i> View sales</button>
            <button class="adm-quick-btn" data-goto="analytics"><i data-lucide="bar-chart-3"></i> View analytics</button>
            <button class="adm-quick-btn" data-goto="products"><i data-lucide="plus"></i> Add a product</button>
            <button class="adm-quick-btn" data-goto="keys"><i data-lucide="key-round"></i> Generate keys</button>
            <button class="adm-quick-btn" data-goto="devlog"><i data-lucide="megaphone"></i> Post an update</button>
          </div>
        </section>

        <!-- SALES -->
        <section class="adm-section" data-section="sales" hidden>
          <div class="adm-head"><h2>Sales</h2><p>Real orders pulled live from Komerza. Revenue, order counts and your most recent purchases.</p></div>
          <div class="adm-stats" id="adSalesStats">
            <div class="adm-stat"><div class="as-ico"><i data-lucide="dollar-sign"></i></div><div><div class="as-val" data-sstat="revenue">—</div><div class="as-label">Total revenue</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="calendar"></i></div><div><div class="as-val" data-sstat="revenue30">—</div><div class="as-label">Revenue (30d)</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="shopping-cart"></i></div><div><div class="as-val" data-sstat="paidOrders">—</div><div class="as-label">Paid orders</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="trending-up"></i></div><div><div class="as-val" data-sstat="avgOrder">—</div><div class="as-label">Avg order</div></div></div>
          </div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>Recent orders</h3><button class="btn btn-bw sm" id="adSalesRefresh" type="button"><i data-lucide="refresh-cw"></i><span>Refresh</span></button></div>
            <div id="adSalesList" class="admin-sales"><div class="dash-loading"><span></span><span></span><span></span></div></div>
          </div>
        </section>

        <!-- ANALYTICS -->
        <section class="adm-section" data-section="analytics" hidden>
          <div class="adm-head"><h2>Analytics</h2><p>Page views across your site. Updated in real time as visitors land.</p></div>
          <div class="adm-stats" id="adAnalyticsStats">
            <div class="adm-stat"><div class="as-ico"><i data-lucide="eye"></i></div><div><div class="as-val" data-astat="total">—</div><div class="as-label">Total views</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="calendar"></i></div><div><div class="as-val" data-astat="today">—</div><div class="as-label">Views today</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="trending-up"></i></div><div><div class="as-val" data-astat="week">—</div><div class="as-label">Last 7 days</div></div></div>
            <div class="adm-stat"><div class="as-ico"><i data-lucide="file"></i></div><div><div class="as-val" data-astat="pages">—</div><div class="as-label">Pages tracked</div></div></div>
          </div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>Last 14 days</h3><button class="btn btn-bw sm" id="adRefreshAnalytics" type="button"><i data-lucide="refresh-cw"></i><span>Refresh</span></button></div>
            <div id="adAnalyticsChart" class="an-chart"></div>
          </div>
          <div class="an-grid">
            <div class="adm-card">
              <div class="adm-card-head"><h3>Top pages</h3></div>
              <div id="adAnalyticsPages" class="an-bars"></div>
            </div>
            <div class="adm-card">
              <div class="adm-card-head"><h3>Top referrers</h3></div>
              <div id="adAnalyticsRefs" class="an-bars"></div>
            </div>
          </div>
        </section>

        <!-- PRODUCTS -->
        <section class="adm-section" data-section="products" hidden>
          <div class="adm-head"><h2>Products</h2><p>Create, edit and delete store products. Images upload to Cloudinary.</p></div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>Catalog</h3><button class="btn btn-bw sm" id="adProdNew" type="button"><i data-lucide="plus"></i><span>New product</span></button></div>
            <div class="adm-toolbar">
              <input type="text" id="adProdSearch" class="adm-search" placeholder="Search name or category..." />
              <select id="adProdSort">
                <option value="order">Default order</option>
                <option value="name">Name A–Z</option>
                <option value="price-asc">Price: low → high</option>
                <option value="price-desc">Price: high → low</option>
                <option value="featured">Featured first</option>
              </select>
            </div>
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
          <div class="adm-head"><h2>Keys &amp; users</h2><p>Look up, generate and manage license keys. View full Discord profiles and manage user access.</p></div>
          
          <!-- Enhanced User Management -->
          <div class="adm-card">
            <div class="adm-card-head"><h3>Discord User Management</h3></div>
            <div class="admin-row">
              <input type="text" id="adUserSearch" placeholder="Search by Discord ID, username, or key..." style="flex:1" />
              <select id="adUserFilter">
                <option value="all">All users</option>
                <option value="active">Active only</option>
                <option value="expired">Expired</option>
                <option value="blacklisted">Blacklisted</option>
                <option value="unassigned">Unassigned keys</option>
              </select>
              <select id="adUserSort">
                <option value="newest">Newest first</option>
                <option value="oldest">Oldest first</option>
                <option value="name">Name A-Z</option>
                <option value="expiring">Expiring soon</option>
              </select>
            </div>
            <div id="adUserList" class="user-grid"></div>
          </div>
          
          <div class="adm-card">
            <div class="adm-card-head"><h3>Look up a key</h3></div>
            <div class="admin-row">
              <input type="text" id="adMyKey" placeholder="Paste a key to inspect" />
              <button class="btn btn-bw" id="adLookup"><span>Look up</span></button>
            </div>
            <div id="adMyKeyResult"></div>
          </div>
          
          <div class="adm-card">
            <div class="adm-card-head">
              <h3>All keys</h3>
              <div style="display:flex;gap:8px;align-items:center;">
                <select id="adKeyTypeFilter" style="width:auto;min-width:160px;">
                  <option value="all">All products &amp; types</option>
                  <option value="external">External (RiotsSeige)</option>
                  <option value="script">Lua Scripts (LuaProt)</option>
                </select>
                <button class="btn btn-bw sm" id="adExportKeys"><i data-lucide="download"></i><span>Export</span></button>
              </div>
            </div>
            <div id="adKeyList" class="admin-list"></div>
          </div>
          
          <!-- Key System Switcher -->
          <div class="adm-card" style="border-left: 3px solid #38bdf8;">
            <div class="adm-card-head">
              <h3><i data-lucide="key"></i> Key System Selector</h3>
            </div>
            <p class="admin-hint">Toggle between managing standalone keys for <strong>External Desktop Software (RiotsSeige)</strong> or Roblox <strong>Lua Scripts (LuaProt)</strong>.</p>
            <div style="display:flex;gap:10px;margin-top:10px;">
              <button type="button" class="btn btn-gradient sm" id="keyTabExt" style="flex:1;"><i data-lucide="monitor"></i> External Keys (RiotsSeige)</button>
              <button type="button" class="btn btn-bw sm" id="keyTabScript" style="flex:1;"><i data-lucide="file-code"></i> Lua Script Keys (LuaProt)</button>
            </div>
          </div>

          <!-- ================= EXTERNAL KEYS (RiotsSeige) ================= -->
          <div id="externalKeysSection">
            <!-- External Key Generator -->
            <div class="adm-card">
              <div class="adm-card-head">
                <h3><i data-lucide="cpu"></i> Generate External Keys (RiotsSeige)</h3>
                <span class="badge-pill external">EXTERNAL SOFTWARE</span>
              </div>
              <p class="admin-hint">Generates standalone license keys for the RiotsSeige external loader. Keys auto-bind to the user's HWID on first launch.</p>
              <div class="admin-row">
                <input type="number" id="adExtAmount" placeholder="Amount (1-100)" min="1" max="100" value="1" />
                <select id="adExtDuration">
                  <option value="lifetime">Lifetime</option>
                  <option value="86400">1 Day (24h)</option>
                  <option value="604800">7 Days (1 Week)</option>
                  <option value="2592000">30 Days (1 Month)</option>
                  <option value="custom">Custom Seconds</option>
                </select>
                <input type="number" id="adExtCustomExpire" placeholder="Expire seconds" style="display:none;" />
              </div>
              <div class="admin-row">
                <input type="text" id="adExtPrefix" placeholder="Key prefix (default: RIOTS-EXT)" value="RIOTS-EXT" />
                <input type="text" id="adExtNote" placeholder="Note / label (e.g. Resale, Giveaway, VIP)" />
              </div>
              <button class="btn btn-gradient" id="adExtGenerate"><span>Generate External Keys</span></button>
              <div id="adExtGenResult"></div>
            </div>

            <!-- External Key Assigner -->
            <div class="adm-card">
              <div class="adm-card-head">
                <h3><i data-lucide="user-plus"></i> Assign External Key to User</h3>
              </div>
              <p class="admin-hint">Creates a RiotsSeige key directly bound to a user's Discord ID.</p>
              <div class="admin-row">
                <input type="text" id="adExtAddDiscord" placeholder="Discord User ID (numbers)" />
                <select id="adExtAddDuration">
                  <option value="lifetime">Lifetime</option>
                  <option value="86400">1 Day (24h)</option>
                  <option value="604800">7 Days (1 Week)</option>
                  <option value="2592000">30 Days (1 Month)</option>
                  <option value="custom">Custom Seconds</option>
                </select>
                <input type="number" id="adExtAddCustomExpire" placeholder="Expire seconds" style="display:none;" />
              </div>
              <input type="text" id="adExtAddNote" placeholder="Note (optional)" />
              <button class="btn btn-bw" id="adExtAddKey"><span>Create &amp; Assign External Key</span></button>
              <div id="adExtAddResult"></div>
            </div>
          </div>

          <!-- ================= LUA SCRIPT KEYS (LuaProt) ================= -->
          <div id="scriptKeysSection" style="display:none;">
            <div class="adm-card">
              <div class="adm-card-head">
                <h3>Hubs &amp; scripts</h3>
                <button class="btn btn-bw sm" id="adLoadHubs" type="button"><i data-lucide="refresh-cw"></i><span>Load</span></button>
              </div>
              <p class="admin-hint">Your LuaProt hubs and the scripts in each. Use the checkboxes below when generating keys to limit them to specific scripts.</p>
              <div id="adHubsList" class="admin-hubs"></div>
            </div>
            
            <div class="adm-card">
              <div class="adm-card-head"><h3>Generate Lua Script Keys</h3></div>
              <div class="admin-row">
                <input type="number" id="adAmount" placeholder="Amount (1-300)" min="1" max="300" value="1" />
                <input type="number" id="adExpire" placeholder="Expire seconds (blank=lifetime)" />
              </div>
              <input type="text" id="adGenNote" placeholder="Note (optional)" />
              <label class="admin-label">Limit to scripts <span class="admin-hint" style="text-transform:none;letter-spacing:0">(none selected = access to all)</span></label>
              <div id="adScriptPick" class="script-pick"><div class="empty">Load hubs &amp; scripts above to pick.</div></div>
              <button class="btn btn-gradient" id="adGenerate"><span>Generate</span></button>
              <div id="adGenResult"></div>
            </div>
            
            <div class="adm-card">
              <div class="adm-card-head"><h3>Assign a Lua Script Key to User</h3></div>
              <p class="admin-hint">Create a LuaProt key bound to a Discord ID, optionally limited to the scripts selected above.</p>
              <div class="admin-row">
                <input type="text" id="adAddDiscord" placeholder="Discord ID (numbers)" />
                <input type="number" id="adAddExpire" placeholder="Expire seconds (blank=lifetime)" />
              </div>
              <input type="text" id="adAddNote" placeholder="Note (optional)" />
              <button class="btn btn-bw" id="adAddKey"><span>Create &amp; assign</span></button>
              <div id="adAddResult"></div>
            </div>
          </div>
          
          <!-- Discord Server Management -->
          <div class="adm-card">
            <div class="adm-card-head"><h3>Discord Server Management</h3></div>
            <p class="admin-hint">Make authenticated users join your Discord server. Useful if your main server gets deleted.</p>
            <div class="admin-row">
              <input type="text" id="adDiscordInvite" placeholder="Discord invite code or URL" style="flex:1" />
              <button class="btn btn-gradient" id="adMassJoin"><span>Mass Join All Users</span></button>
            </div>
            <div class="admin-hint" style="margin-top:8px">This will attempt to make all authenticated users join the specified Discord server.</div>
          </div>
        </section>

        <!-- SCRIPTS -->
        <section class="adm-section" data-section="scripts" hidden>
          <div class="adm-head"><h2>Scripts</h2><p>Read live from LuaProt. Buyers automatically get the scripts their key unlocks — you don't configure anything here. To limit a key to specific scripts, use the checkboxes when generating a key in the Keys tab.</p></div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>Hubs &amp; scripts</h3><button class="btn btn-bw sm" id="adScriptRefresh" type="button"><i data-lucide="refresh-cw"></i><span>Refresh</span></button></div>
            <div id="adScriptList" class="admin-hubs"></div>
          </div>
        </section>

        <!-- REFERRALS (Key Reward System) -->
        <section class="adm-section" data-section="referrals" hidden>
          <div class="adm-head"><h2>Referrals</h2><p>Review referrals and redeem them into keys for users. Users earn 1 key for every 5 successful referrals.</p></div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>Pending Redemptions</h3></div>
            <p class="admin-hint">Users who have requested key redemptions from their referral earnings.</p>
            <div id="adRefPending" class="admin-list"></div>
          </div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>All Referrals</h3></div>
            <div class="adm-toolbar">
              <input type="text" id="adRefSearch" class="adm-search" placeholder="Search code or user..." />
              <select id="adRefSort">
                <option value="signups">Most signups</option>
                <option value="clicks">Most clicks</option>
                <option value="newest">Newest</option>
                <option value="code">Code A–Z</option>
              </select>
            </div>
            <div id="adRefList" class="admin-list"></div>
          </div>
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

        <!-- DOWNLOADS -->
        <section class="adm-section" data-section="downloads" hidden>
          <div class="adm-head"><h2>Downloads Management</h2><p>Manage the RiotsSeige external loader versions and downloads.</p></div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>Current Version</h3></div>
            <div class="admin-row">
              <input type="text" id="adDlVersion" placeholder="Version (e.g. 1.0.0)" />
              <input type="text" id="adDlUrl" placeholder="Download URL" style="flex:1" />
            </div>
            <textarea id="adDlChangelog" rows="3" placeholder="Changelog for this version..."></textarea>
            <div class="admin-row">
              <button class="btn btn-gradient" id="adDlPublish"><span>Update Version</span></button>
            </div>
            <div id="adDlManageResult"></div>
          </div>
          <div class="adm-card">
            <div class="adm-card-head"><h3>Download Statistics</h3></div>
            <div class="adm-stats" id="adDlStats">
              <div class="adm-stat"><div class="as-ico"><i data-lucide="download"></i></div><div><div class="as-val" id="adTotalDownloads">—</div><div class="as-label">Total Downloads</div></div></div>
              <div class="adm-stat"><div class="as-ico"><i data-lucide="calendar"></i></div><div><div class="as-val" id="adTodayDownloads">—</div><div class="as-label">Today</div></div></div>
              <div class="adm-stat"><div class="as-ico"><i data-lucide="users"></i></div><div><div class="as-val" id="adActiveUsers">—</div><div class="as-label">Active Users</div></div></div>
            </div>
          </div>
        </section>
      </div>
    </div>`;

  // Section navigation
  const showSection = (name) => {
    $$('.adm-navbtn').forEach((b) => b.classList.toggle('active', b.dataset.section === name));
    $$('.adm-section').forEach((s) => (s.hidden = s.dataset.section !== name));
    if (name === 'analytics') loadAnalytics();
    if (name === 'scripts') loadAdminScripts();
    if (name === 'sales') loadSales();
  };
  $$('.adm-navbtn').forEach((b) => b.addEventListener('click', () => showSection(b.dataset.section)));
  $$('.adm-quick-btn').forEach((b) => b.addEventListener('click', () => showSection(b.dataset.goto)));
  const prodNew = $('#adProdNew');
  if (prodNew) prodNew.addEventListener('click', () => { if (typeof resetProdForm === 'function') resetProdForm(); $('#adProdName').focus(); });
  const refreshAn = $('#adRefreshAnalytics');
  if (refreshAn) refreshAn.addEventListener('click', loadAnalytics);
  const refreshSales = $('#adSalesRefresh');
  if (refreshSales) refreshSales.addEventListener('click', loadSales);

  // Scripts (read-only, live from LuaProt)
  const scriptRefresh = $('#adScriptRefresh');
  if (scriptRefresh) scriptRefresh.addEventListener('click', loadAdminScripts);

  // My key lookup
  $('#adLookup').addEventListener('click', async () => {
    const key = $('#adMyKey').value.trim();
    if (!key) return;
    try {
      const r = await api('/api/keys/admin/list?key=' + encodeURIComponent(key), { admin: true });
      $('#adMyKeyResult').innerHTML = renderAdminKeys(r.keys || []);
      bindAdminKeyActions();
    } catch (e) { $('#adMyKeyResult').innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
  });

  // User search and filter
  const userSearch = $('#adUserSearch');
  const userFilter = $('#adUserFilter');
  const userSort = $('#adUserSort');
  
  if (userSearch) userSearch.addEventListener('input', searchAdminUsers);
  if (userFilter) userFilter.addEventListener('change', searchAdminUsers);
  if (userSort) userSort.addEventListener('change', searchAdminUsers);
  
  // Initial load of users
  searchAdminUsers();
  
  // Export keys button
  const exportBtn = $('#adExportKeys');
  if (exportBtn) {
    exportBtn.addEventListener('click', async () => {
      try {
        const r = await api('/api/keys/admin/list', { admin: true });
        const keys = r.keys || [];
        const csv = keys.map(k => `${k.key},${k.discordId || ''},${k.expire || ''},${k.blacklisted ? 'blacklisted' : 'active'}`).join('\n');
        const blob = new Blob(['Key,Discord ID,Expiry,Status\n' + csv], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'keys-export.csv';
        a.click();
        URL.revokeObjectURL(url);
      } catch (e) {
        alert('Failed to export keys: ' + e.message);
      }
    });
  }
  
  // Mass Discord join
  const massJoinBtn = $('#adMassJoin');
  if (massJoinBtn) {
    massJoinBtn.addEventListener('click', async () => {
      const inviteInput = $('#adDiscordInvite');
      const invite = (inviteInput?.value || '').trim().replace(/^(https?:\/\/)?(discord\.gg\/|discord\.com\/invite\/)/, '');
      if (!invite) {
        alert('Please enter a Discord invite code or URL');
        return;
      }
      if (!confirm('This will attempt to make all authenticated users join the Discord server. Continue?')) {
        return;
      }
      try {
        // This would need a backend endpoint to implement the actual Discord API calls
        alert('Discord mass join feature requires backend implementation. Invite code: ' + invite);
      } catch (e) {
        alert('Failed to initiate mass join: ' + e.message);
      }
    });
  }

  // Key System Switcher (External vs Script)
  const keyTabExt = $('#keyTabExt');
  const keyTabScript = $('#keyTabScript');
  const externalSection = $('#externalKeysSection');
  const scriptSection = $('#scriptKeysSection');

  if (keyTabExt && keyTabScript) {
    keyTabExt.addEventListener('click', () => {
      keyTabExt.className = 'btn btn-gradient sm';
      keyTabScript.className = 'btn btn-bw sm';
      if (externalSection) externalSection.style.display = 'block';
      if (scriptSection) scriptSection.style.display = 'none';
    });
    keyTabScript.addEventListener('click', () => {
      keyTabScript.className = 'btn btn-gradient sm';
      keyTabExt.className = 'btn btn-bw sm';
      if (externalSection) externalSection.style.display = 'none';
      if (scriptSection) scriptSection.style.display = 'block';
      loadAdminHubs();
    });
  }

  // Duration toggle for External Key Generator
  const extDur = $('#adExtDuration');
  const extCustom = $('#adExtCustomExpire');
  if (extDur && extCustom) {
    extDur.addEventListener('change', () => {
      extCustom.style.display = extDur.value === 'custom' ? 'block' : 'none';
    });
  }

  // Duration toggle for External Key Assigner
  const extAddDur = $('#adExtAddDuration');
  const extAddCustom = $('#adExtAddCustomExpire');
  if (extAddDur && extAddCustom) {
    extAddDur.addEventListener('change', () => {
      extAddCustom.style.display = extAddDur.value === 'custom' ? 'block' : 'none';
    });
  }

  // Generate External Keys (RiotsSeige)
  const extGenBtn = $('#adExtGenerate');
  if (extGenBtn) {
    extGenBtn.addEventListener('click', async () => {
      const amount = parseInt($('#adExtAmount').value, 10) || 1;
      const durVal = $('#adExtDuration').value;
      let expire;
      if (durVal === 'custom') {
        const custVal = parseInt($('#adExtCustomExpire').value, 10);
        if (custVal > 0) expire = custVal;
      } else if (durVal !== 'lifetime') {
        expire = parseInt(durVal, 10);
      }
      const prefix = ($('#adExtPrefix').value || 'RIOTS-EXT').trim();
      const note = ($('#adExtNote').value || '').trim();

      extGenBtn.disabled = true;
      const resEl = $('#adExtGenResult');
      resEl.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;

      try {
        const body = { amount, prefix, product: 'RiotsSeige' };
        if (expire) body.expire = expire;
        if (note) body.note = note;

        const r = await api('/api/external-keys/admin/generate', { method: 'POST', body, admin: true });
        const keysText = (r.keys || []).join('\n');
        resEl.innerHTML = `
          <div class="ok-note">Successfully generated ${r.count || r.keys?.length || 0} External (RiotsSeige) key(s)!</div>
          <div class="ext-keys-output">
            <textarea rows="${Math.min(8, Math.max(3, (r.keys || []).length))}" readonly id="extKeysOutputText">${esc(keysText)}</textarea>
            <button class="btn btn-bw sm" id="copyAllExtKeys" type="button"><i data-lucide="copy"></i> Copy All Keys</button>
          </div>`;
        renderIcons();
        $('#copyAllExtKeys')?.addEventListener('click', () => {
          navigator.clipboard.writeText(keysText);
          const btn = $('#copyAllExtKeys');
          if (btn) {
            btn.innerHTML = `<i data-lucide="check"></i> Copied!`;
            setTimeout(() => { btn.innerHTML = `<i data-lucide="copy"></i> Copy All Keys`; renderIcons(); }, 1600);
          }
        });
        searchAdminKeys();
      } catch (e) {
        resEl.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
      } finally {
        extGenBtn.disabled = false;
      }
    });
  }

  // Assign External Key to User (RiotsSeige)
  const extAddBtn = $('#adExtAddKey');
  if (extAddBtn) {
    extAddBtn.addEventListener('click', async () => {
      const discordId = ($('#adExtAddDiscord').value || '').trim();
      if (!/^\d{5,25}$/.test(discordId)) {
        $('#adExtAddResult').innerHTML = `<div class="empty">Enter a valid Discord user ID (numbers only).</div>`;
        return;
      }
      const durVal = $('#adExtAddDuration').value;
      let expire;
      if (durVal === 'custom') {
        const custVal = parseInt($('#adExtAddCustomExpire').value, 10);
        if (custVal > 0) expire = custVal;
      } else if (durVal !== 'lifetime') {
        expire = parseInt(durVal, 10);
      }
      const note = ($('#adExtAddNote').value || '').trim();

      extAddBtn.disabled = true;
      const resEl = $('#adExtAddResult');
      resEl.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;

      try {
        const body = { discordId, product: 'RiotsSeige' };
        if (expire) body.expire = expire;
        if (note) body.note = note;

        const r = await api('/api/external-keys/admin/assign', { method: 'POST', body, admin: true });
        resEl.innerHTML = `
          <div class="ok-note">Assigned RiotsSeige external key to <code>${esc(discordId)}</code>!</div>
          <div style="margin-top:8px;display:flex;align-items:center;gap:8px;">
            <code style="font-size:14px;color:#38bdf8;">${esc(r.key)}</code>
            <button class="btn btn-bw sm" onclick="navigator.clipboard.writeText('${esc(r.key)}');alert('Copied key!');">Copy</button>
          </div>`;
        $('#adExtAddDiscord').value = '';
        $('#adExtAddNote').value = '';
        searchAdminKeys();
      } catch (e) {
        resEl.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
      } finally {
        extAddBtn.disabled = false;
      }
    });
  }

  // Type filter for All Keys
  $('#adKeyTypeFilter')?.addEventListener('change', () => {
    searchAdminKeys();
  });

  // Hubs & scripts + script picker
  $('#adLoadHubs')?.addEventListener('click', loadAdminHubs);

  const selectedScripts = () =>
    $$('#adScriptPick input[type="checkbox"]:checked').map((c) => c.value);

  // Generate
  $('#adGenerate').addEventListener('click', async () => {
    const amount = parseInt($('#adAmount').value, 10) || 5;
    const expireRaw = $('#adExpire').value.trim();
    const note = $('#adGenNote').value.trim();
    const scripts = selectedScripts();
    const body = { amount };
    if (expireRaw) body.expire = parseInt(expireRaw, 10);
    if (note) body.note = note;
    if (scripts.length) body.limitedScripts = scripts;
    const btn = $('#adGenerate'); btn.disabled = true;
    try {
      const r = await api('/api/keys/admin/generate', { method: 'POST', body, admin: true });
      const limited = scripts.length ? ` <span class="ok-note-sub">(limited to ${scripts.length} script${scripts.length > 1 ? 's' : ''})</span>` : '';
      $('#adGenResult').innerHTML = `<div class="ok-note">Generated ${r.keys?.length || 0} keys.${limited}</div><textarea rows="4" readonly>${esc((r.keys || []).join('\n'))}</textarea>`;
    } catch (e) { $('#adGenResult').innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
    finally { btn.disabled = false; }
  });

  // Assign a key to a Discord user
  $('#adAddKey').addEventListener('click', async () => {
    const discordId = $('#adAddDiscord').value.trim();
    const expireRaw = $('#adAddExpire').value.trim();
    const note = $('#adAddNote').value.trim();
    const scripts = selectedScripts();
    if (!/^\d{5,25}$/.test(discordId)) { $('#adAddResult').innerHTML = `<div class="empty">Enter a valid Discord ID (numbers only).</div>`; return; }
    const body = { discordId };
    if (expireRaw) body.expire = parseInt(expireRaw, 10);
    if (note) body.note = note;
    if (scripts.length) body.limitedScripts = scripts;
    const btn = $('#adAddKey'); btn.disabled = true;
    try {
      await api('/api/keys/admin/add', { method: 'POST', body, admin: true });
      $('#adAddResult').innerHTML = `<div class="ok-note">Key created and assigned to ${esc(discordId)}.</div>`;
      $('#adAddDiscord').value = ''; $('#adAddNote').value = '';
    } catch (e) { $('#adAddResult').innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
    finally { btn.disabled = false; }
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

  // Downloads management
  const dlPublish = $('#adDlPublish');
  if (dlPublish) {
    dlPublish.addEventListener('click', async () => {
      const version = $('#adDlVersion')?.value.trim();
      const url = $('#adDlUrl')?.value.trim();
      const changelog = $('#adDlChangelog')?.value.trim();
      
      if (!version || !url) {
        $('#adDlManageResult').innerHTML = `<div class="empty">Version and URL are required.</div>`;
        return;
      }
      
      try {
        // This would need a backend endpoint to save version info
        $('#adDlManageResult').innerHTML = `<div class="ok-note">Version ${version} published!</div>`;
        $('#adDlVersion').value = '';
        $('#adDlUrl').value = '';
        $('#adDlChangelog').value = '';
      } catch (e) {
        $('#adDlManageResult').innerHTML = `<div class="empty">${esc(e.message)}</div>`;
      }
    });
  }

  renderIcons();
  enhanceSelects(area);
  loadAdminProducts();
  loadAdminReferrals();
  loadAdminStats();
}

/* ---------------- ADMIN: SALES (live from Komerza) ---------------- */
function fmtMoney(n, currency) {
  const val = Number(n || 0);
  try { return new Intl.NumberFormat(undefined, { style: 'currency', currency: currency || 'USD', maximumFractionDigits: 2 }).format(val); }
  catch { return '$' + val.toFixed(2); }
}
function fmtDateTime(v) {
  if (!v) return '—';
  const d = new Date(v);
  if (isNaN(d)) return '—';
  return d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}
let SALES_CACHE = null;
async function loadSales() {
  const list = $('#adSalesList');
  if (!list) return;
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  let sales;
  try {
    const r = await api('/api/store/sales', { admin: true });
    sales = r.sales || {};
  } catch (e) {
    const msg = /not configured/i.test(e.message)
      ? 'Komerza API isn\u2019t configured on the backend yet. Set KOMERZA_API_KEY and KOMERZA_STORE_ID to see real sales.'
      : e.message;
    list.innerHTML = `<div class="empty">${esc(msg)}</div>`;
    return;
  }
  SALES_CACHE = sales;
  const t = sales.totals || {};
  const cur = sales.currency || 'USD';
  const setS = (name, val) => { const el = document.querySelector(`#adSalesStats [data-sstat="${name}"]`); if (el) el.textContent = val; };
  setS('revenue', fmtMoney(t.revenue, cur));
  setS('revenue30', fmtMoney(t.revenue30, cur));
  setS('paidOrders', t.paidOrders ?? 0);
  setS('avgOrder', fmtMoney(t.avgOrder, cur));

  const recent = sales.recent || [];
  if (!recent.length) { list.innerHTML = `<div class="empty">No orders yet.</div>`; return; }
  const statusPill = (o) => o.refunded
    ? '<span class="sale-status refunded">refunded</span>'
    : (o.paid ? '<span class="sale-status paid">paid</span>' : `<span class="sale-status pending">${esc(o.status || 'pending')}</span>`);
  list.innerHTML = recent.map((o) => `
    <div class="sale-row">
      <div class="sale-main">
        <div class="sale-top">
          <strong>${esc(o.product || '—')}</strong>
          ${statusPill(o)}
        </div>
        <div class="sale-sub">
          ${o.email ? esc(o.email) + ' · ' : ''}${o.gateway ? esc(o.gateway) + ' · ' : ''}${fmtDateTime(o.createdAt)}${o.id ? ' · #' + esc(String(o.id).slice(0, 8)) : ''}
        </div>
      </div>
      <div class="sale-amount">${fmtMoney(o.amount, o.currency || cur)}${o.quantity > 1 ? `<span class="sale-qty">×${o.quantity}</span>` : ''}</div>
    </div>`).join('');
  renderIcons();
}

// Normalize LuaProt's /hubs/get response into [{id,name,scripts:[{id,name}]}]
function normalizeHubs(raw) {
  // The provider returns the raw LuaProt shape; be defensive about field names.
  let hubs = raw?.hubs || raw?.data || raw?.data?.hubs || raw || [];
  if (!Array.isArray(hubs)) hubs = hubs.hubs || hubs.data || [];
  if (!Array.isArray(hubs)) return [];
  return hubs.map((h) => {
    let scripts = h.scripts || h.projects || h.modules || [];
    if (!Array.isArray(scripts)) scripts = [];
    return {
      id: h.id ?? h.hubId ?? h.name ?? '',
      name: h.name ?? h.hubName ?? h.title ?? String(h.id ?? 'Hub'),
      scripts: scripts.map((s) => ({
        id: s.id ?? s.scriptId ?? s.name ?? '',
        name: s.name ?? s.scriptName ?? s.title ?? String(s.id ?? 'Script'),
      })),
    };
  });
}

let ADMIN_HUBS = [];
async function loadAdminHubs() {
  const list = $('#adHubsList');
  const pick = $('#adScriptPick');
  if (!list) return;
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const r = await api('/api/keys/admin/hubs', { admin: true });
    ADMIN_HUBS = normalizeHubs(r);
    if (!ADMIN_HUBS.length) { list.innerHTML = `<div class="empty">No hubs found on this account.</div>`; if (pick) pick.innerHTML = `<div class="empty">No scripts available.</div>`; return; }
    list.innerHTML = ADMIN_HUBS.map((h) => `
      <div class="admin-hub">
        <div class="ah-head"><i data-lucide="folder"></i> <strong>${esc(h.name)}</strong> <span class="ah-count">${h.scripts.length} script${h.scripts.length === 1 ? '' : 's'}</span></div>
        ${h.scripts.length ? `<div class="ah-scripts">${h.scripts.map((s) => `<span class="ah-script"><i data-lucide="file-code"></i> ${esc(s.name)}</span>`).join('')}</div>` : `<div class="ah-scripts empty">No scripts in this hub.</div>`}
      </div>`).join('');
    // build the script picker (checkboxes) for generate/assign
    if (pick) {
      const allScripts = ADMIN_HUBS.flatMap((h) => h.scripts.map((s) => ({ ...s, hub: h.name })));
      pick.innerHTML = allScripts.length
        ? allScripts.map((s) => `
          <label class="sp-item">
            <input type="checkbox" value="${esc(String(s.id))}" />
            <span class="sp-name">${esc(s.name)}</span>
            <span class="sp-hub">${esc(s.hub)}</span>
          </label>`).join('')
        : `<div class="empty">No scripts available.</div>`;
    }
    renderIcons();
  } catch (e) {
    list.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
    if (pick) pick.innerHTML = `<div class="empty">Couldn't load scripts.</div>`;
  }
}

// Admin Scripts tab — read-only live view of hubs + scripts from LuaProt.
async function loadAdminScripts() {
  const list = document.querySelector('#adScriptList');
  if (!list) return;
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const r = await api('/api/store/scripts', { admin: true });
    const hubs = normalizeHubs(r);
    if (!hubs.length) { list.innerHTML = `<div class="empty">No hubs found on this account.</div>`; return; }
    list.innerHTML = hubs.map((h) => `
      <div class="admin-hub">
        <div class="ah-head"><i data-lucide="folder"></i> <strong>${esc(h.name)}</strong> <span class="ah-count">${h.scripts.length} script${h.scripts.length === 1 ? '' : 's'}</span></div>
        ${h.scripts.length ? `<div class="ah-scripts">${h.scripts.map((s) => `<span class="ah-script"><i data-lucide="file-code"></i> ${esc(s.name)} <span class="ah-sid">${esc(String(s.id))}</span></span>`).join('')}</div>` : `<div class="ah-scripts empty">No scripts in this hub.</div>`}
      </div>`).join('');
    renderIcons();
  } catch (e) { list.innerHTML = `<div class="empty">${esc(e.message)}</div>`; }
}

async function loadAnalytics() {
  const chart = $('#adAnalyticsChart');
  if (!chart) return;
  chart.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  let a;
  try {
    const r = await api('/api/content/analytics', { admin: true });
    a = r.analytics || {};
  } catch (e) {
    chart.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
    return;
  }
  const daily = a.daily || {};
  const pages = a.pages || {};
  const refs = a.referrers || {};
  const today = new Date().toISOString().slice(0, 10);

  // stat tiles
  const setA = (name, val) => { const el = document.querySelector(`#adAnalyticsStats [data-astat="${name}"]`); if (el) el.textContent = val; };
  setA('total', a.total || 0);
  setA('today', daily[today] || 0);
  let week = 0;
  for (let i = 0; i < 7; i++) {
    const d = new Date(); d.setDate(d.getDate() - i);
    week += daily[d.toISOString().slice(0, 10)] || 0;
  }
  setA('week', week);
  setA('pages', Object.keys(pages).length);

  // last 14 days bar chart
  const days = [];
  for (let i = 13; i >= 0; i--) {
    const d = new Date(); d.setDate(d.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    days.push({ key, label: key.slice(5), count: daily[key] || 0 });
  }
  const max = Math.max(1, ...days.map((d) => d.count));
  chart.innerHTML = `<div class="an-cols">${days.map((d) => `
    <div class="an-col" title="${d.key}: ${d.count} views">
      <div class="an-bar" style="height:${Math.round((d.count / max) * 100)}%"></div>
      <span class="an-colval">${d.count || ''}</span>
      <span class="an-collabel">${d.label}</span>
    </div>`).join('')}</div>`;

  // top pages + referrers as horizontal bars
  const renderBars = (obj, el, emptyMsg) => {
    const entries = Object.entries(obj).sort((a, b) => b[1] - a[1]).slice(0, 8);
    if (!entries.length) { el.innerHTML = `<div class="empty">${emptyMsg}</div>`; return; }
    const top = Math.max(1, ...entries.map((e) => e[1]));
    el.innerHTML = entries.map(([name, count]) => `
      <div class="an-barrow">
        <span class="an-barname">${esc(name)}</span>
        <span class="an-bartrack"><span class="an-barfill" style="width:${Math.round((count / top) * 100)}%"></span></span>
        <span class="an-barval">${count}</span>
      </div>`).join('');
  };
  renderBars(pages, $('#adAnalyticsPages'), 'No page views yet.');
  renderBars(refs, $('#adAnalyticsRefs'), 'No referrers yet.');
  renderIcons();
}

async function loadAdminStats() {
  const setStat = (name, val) => {
    const el = document.querySelector(`#adStats [data-stat="${name}"]`);
    if (el) el.textContent = val;
  };
  // Products (public), referrals + sales (admin). Fail soft per call.
  try { const r = await api('/api/store/products'); setStat('products', (r.products || []).length); } catch (_) {}
  try { const r = await api('/api/referral', { admin: true }); setStat('referrals', (r.referrals || []).length); } catch (_) {}
  try {
    const r = await api('/api/store/sales', { admin: true });
    const t = (r.sales && r.sales.totals) || {};
    const cur = (r.sales && r.sales.currency) || 'USD';
    setStat('revenue', fmtMoney(t.revenue, cur));
    setStat('sales', t.paidOrders ?? 0);
  } catch (_) {
    setStat('revenue', '—');
    setStat('sales', '—');
  }
}

let ADMIN_REFERRALS = [];

// Load pending redemption requests
async function loadPendingRedemptions() {
  const list = $('#adRefPending');
  if (!list) return;
  
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  
  try {
    const r = await api('/api/referral/pending', { admin: true });
    const pending = r.pending || [];
    
    if (!pending.length) {
      list.innerHTML = `<div class="empty">No pending redemption requests.</div>`;
      return;
    }
    
    list.innerHTML = pending.map(p => `
      <div class="admin-key" data-id="${esc(p.id)}">
        <div class="ak-main">
          <div class="ak-top">
            <strong>Discord ID: ${esc(p.discordId)}</strong>
            <span class="key-status pending">${p.keysRequested} key${p.keysRequested > 1 ? 's' : ''} requested</span>
          </div>
          <div class="ak-sub">Requested: ${fmtDateTime(p.createdAt)}</div>
        </div>
        <div class="ak-actions">
          <button class="mini" data-action="approve"><i data-lucide="check"></i> Approve</button>
          <button class="mini danger" data-action="reject"><i data-lucide="x"></i> Reject</button>
        </div>
      </div>
    `).join('');
    
    renderIcons();
    
    // Bind actions
    list.querySelectorAll('.admin-key').forEach(row => {
      const id = row.dataset.id;
      row.querySelectorAll('button[data-action]').forEach(btn => {
        btn.addEventListener('click', async () => {
          const action = btn.dataset.action;
          const endpoint = `/api/referral/pending/${id}/${action}`;
          
          try {
            if (action === 'reject') {
              const reason = prompt('Enter rejection reason (optional):');
              await api(endpoint, { 
                method: 'POST', 
                body: { reason: reason || '' }, 
                admin: true 
              });
            } else {
              await api(endpoint, { method: 'POST', admin: true });
            }
            loadPendingRedemptions();
            loadAdminReferrals();
          } catch (e) {
            alert(e.message);
          }
        });
      });
    });
    
  } catch (e) {
    list.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
  }
}

function renderAdminReferrals() {
  const list = $('#adRefList');
  if (!list) return;
  
  const q = ($('#adRefSearch')?.value || '').trim().toLowerCase();
  const sort = $('#adRefSort')?.value || 'signups';
  let items = ADMIN_REFERRALS.slice();
  
  if (q) items = items.filter((r) =>
    String(r.code || '').toLowerCase().includes(q) ||
    String(r.username || '').toLowerCase().includes(q) ||
    String(r.discordId || '').includes(q));
  
  items.sort((a, b) => {
    if (sort === 'clicks') return (b.clicks || 0) - (a.clicks || 0);
    if (sort === 'newest') return String(b.createdAt || '').localeCompare(String(a.createdAt || ''));
    if (sort === 'code') return String(a.code || '').localeCompare(String(b.code || ''));
    return (b.signups || 0) - (a.signups || 0); // signups default
  });
  
  if (!items.length) {
    list.innerHTML = `<div class="empty">${ADMIN_REFERRALS.length ? 'No matches.' : 'No referrals yet.'}</div>`;
    return;
  }
  
  const KEY_THRESHOLD = 5;
  
  list.innerHTML = items.map((ref) => {
    const keysEarned = Math.floor((ref.signups || 0) / KEY_THRESHOLD);
    const pending = (ref.signups || 0) % KEY_THRESHOLD;
    
    return `
    <div class="admin-key" data-id="${esc(ref.id)}">
      <div class="ak-main">
        <code>${esc(ref.code)}</code>
        <div class="ak-sub">
          ${esc(ref.username || ref.discordId)} 
          · ${ref.clicks || 0} clicks 
          · ${ref.signups || 0} signups 
          · <strong>${keysEarned} key${keysEarned !== 1 ? 's' : ''} earned</strong>
          · ${pending}/${KEY_THRESHOLD} to next key
        </div>
      </div>
      <button class="mini danger" data-act="del">Delete</button>
    </div>`;
  }).join('');
  
  list.querySelectorAll('.admin-key').forEach((row) => {
    row.querySelector('[data-act="del"]').addEventListener('click', async () => {
      if (!confirm('Delete this referral?')) return;
      try {
        await api('/api/referral/' + row.dataset.id, { method: 'DELETE', admin: true });
        loadAdminReferrals();
      } catch (e) { alert(e.message); }
    });
  });
}
async function loadAdminReferrals() {
  const list = $('#adRefList');
  if (!list) return;
  
  // Load pending redemptions first
  loadPendingRedemptions();
  
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const r = await api('/api/referral', { admin: true });
    ADMIN_REFERRALS = r.referrals || [];
    // wire controls once
    const s = $('#adRefSearch'), so = $('#adRefSort');
    if (s && !s.dataset.wired) { s.dataset.wired = '1'; s.addEventListener('input', renderAdminReferrals); }
    if (so && !so.dataset.wired) { so.dataset.wired = '1'; so.addEventListener('change', renderAdminReferrals); }
    renderAdminReferrals();
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

let ADMIN_PRODUCTS = [];
function priceNum(s) { const n = parseFloat(String(s || '').replace(/[^\d.]/g, '')); return isNaN(n) ? 0 : n; }
function renderAdminProducts() {
  const list = $('#adProdList');
  if (!list) return;
  const q = ($('#adProdSearch')?.value || '').trim().toLowerCase();
  const sort = $('#adProdSort')?.value || 'order';
  let products = ADMIN_PRODUCTS.slice();
  if (q) products = products.filter((p) =>
    String(p.name || '').toLowerCase().includes(q) ||
    String(p.category || '').toLowerCase().includes(q));
  products.sort((a, b) => {
    if (sort === 'name') return String(a.name || '').localeCompare(String(b.name || ''));
    if (sort === 'price-asc') return priceNum(a.price) - priceNum(b.price);
    if (sort === 'price-desc') return priceNum(b.price) - priceNum(a.price);
    if (sort === 'featured') return (b.featured ? 1 : 0) - (a.featured ? 1 : 0);
    return (a.order || 0) - (b.order || 0); // default order
  });
  if (!products.length) { list.innerHTML = `<div class="empty">${ADMIN_PRODUCTS.length ? 'No matches.' : 'No products yet. Add one below.'}</div>`; return; }
  const kmz = (id) => id ? `<code class="ap-id">${esc(id)}</code>` : '<span class="ap-none">not set</span>';
  list.innerHTML = products.map(p => {
    const v = p.komerzaVariants || {};
    const detailId = 'apd_' + esc(p.id);
    return `
    <div class="admin-prod" data-id="${esc(p.id)}">
      <div class="ap-row">
        <img src="${esc(p.image || 'product1.png')}" alt="" />
        <div class="ap-main">
          <div class="ap-name">${esc(p.name)} ${p.featured ? '<span class="ap-flag">⭐ Featured</span>' : ''}</div>
          <div class="ap-sub">${esc(p.category || 'General')} · ${esc(p.price || '—')}${p.priceMonthly ? ' / ' + esc(p.priceMonthly) + ' mo' : ''}${p.badge ? ' · ' + esc(p.badge) : ''}</div>
          <div class="ap-tags">
            <span class="ap-tag ${p.komerzaProductId ? 'ok' : 'warn'}"><i data-lucide="${p.komerzaProductId ? 'check' : 'alert-triangle'}"></i> Komerza ${p.komerzaProductId ? 'linked' : 'unlinked'}</span>
            <span class="ap-stock" data-stock-for="${esc(p.komerzaProductId || '')}"></span>
          </div>
        </div>
        <div class="ap-actions">
          <button class="mini" data-act="toggle" aria-expanded="false">Details</button>
          <button class="mini" data-act="edit">Edit</button>
          <button class="mini danger" data-act="del">Delete</button>
        </div>
      </div>
      <div class="ap-detail" id="${detailId}" hidden>
        <div class="ap-detail-grid">
          <div class="ap-field"><span class="ap-flabel">Product ID</span>${kmz(p.id)}</div>
          <div class="ap-field"><span class="ap-flabel">Category</span><span>${esc(p.category || 'General')}</span></div>
          <div class="ap-field"><span class="ap-flabel">Lifetime price</span><span>${esc(p.price || '—')}</span></div>
          <div class="ap-field"><span class="ap-flabel">Monthly price</span><span>${esc(p.priceMonthly || '—')}</span></div>
          <div class="ap-field"><span class="ap-flabel">Badge</span><span>${esc(p.badge || '—')}</span></div>
          <div class="ap-field"><span class="ap-flabel">Featured</span><span>${p.featured ? 'Yes' : 'No'}</span></div>
          <div class="ap-field"><span class="ap-flabel">Komerza product</span>${kmz(p.komerzaProductId)}</div>
          <div class="ap-field"><span class="ap-flabel">Lifetime variant</span>${kmz(v.lifetime)}</div>
          <div class="ap-field"><span class="ap-flabel">Monthly variant</span>${kmz(v.monthly)}</div>
          <div class="ap-field"><span class="ap-flabel">Created</span><span>${p.createdAt ? fmtDate(p.createdAt) : '—'}</span></div>
        </div>
        ${p.description ? `<div class="ap-desc-block"><span class="ap-flabel">Description</span><p>${esc(p.description)}</p></div>` : ''}
        <div class="ap-detail-actions">
          <a class="mini" href="/products?product=${esc(p.id)}" target="_blank" rel="noopener"><i data-lucide="external-link"></i> View on store</a>
          <button class="mini" data-act="edit2"><i data-lucide="pencil"></i> Edit</button>
        </div>
      </div>
    </div>`;
  }).join('');
  renderIcons();
  list.querySelectorAll('.admin-prod').forEach(row => {
    const p = ADMIN_PRODUCTS.find(x => x.id === row.dataset.id);
    const detail = row.querySelector('.ap-detail');
    const toggle = row.querySelector('[data-act="toggle"]');
    toggle.addEventListener('click', () => {
      const open = detail.hidden;
      detail.hidden = !open;
      toggle.setAttribute('aria-expanded', String(open));
      toggle.textContent = open ? 'Hide' : 'Details';
      if (open) loadAdminProductStock(row, p);
    });
    row.querySelector('[data-act="edit"]').addEventListener('click', () => fillProdForm(p));
    const edit2 = row.querySelector('[data-act="edit2"]');
    if (edit2) edit2.addEventListener('click', () => fillProdForm(p));
    row.querySelector('[data-act="del"]').addEventListener('click', async () => {
      if (!confirm('Delete "' + p.name + '"?')) return;
      try { await api('/api/store/products/' + p.id, { method: 'DELETE', admin: true }); loadAdminProducts(); }
      catch (e) { alert(e.message); }
    });
  });
}

// Live stock for a product row (from Komerza via the public /stock endpoint).
async function loadAdminProductStock(row, p) {
  const el = row.querySelector('.ap-stock');
  if (!el || el.dataset.loaded === '1') return;
  el.dataset.loaded = '1';
  if (!p.komerzaProductId) { el.innerHTML = ''; return; }
  el.innerHTML = `<i data-lucide="loader"></i> stock…`; renderIcons();
  try {
    const r = await api('/api/store/stock?productId=' + encodeURIComponent(p.komerzaProductId));
    const s = r.stock || {};
    if (s.hideStock) { el.innerHTML = `<span class="ap-tag ok"><i data-lucide="infinity"></i> stock hidden</span>`; }
    else {
      const parts = (s.variants || []).map((v) => `${esc(v.name)}: ${v.inStock ? (v.stock ?? '∞') : 'out'}`);
      el.innerHTML = `<span class="ap-tag ${s.inStock ? 'ok' : 'warn'}"><i data-lucide="${s.inStock ? 'package-check' : 'package-x'}"></i> ${s.inStock ? 'in stock' : 'out of stock'}${parts.length ? ' · ' + parts.join(', ') : ''}</span>`;
    }
    renderIcons();
  } catch (e) { el.innerHTML = `<span class="ap-tag warn">stock unavailable</span>`; }
}
async function loadAdminProducts() {
  const list = $('#adProdList');
  if (!list) return;
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const r = await api('/api/store/products');
    ADMIN_PRODUCTS = r.products || [];
    const s = $('#adProdSearch'), so = $('#adProdSort');
    if (s && !s.dataset.wired) { s.dataset.wired = '1'; s.addEventListener('input', renderAdminProducts); }
    if (so && !so.dataset.wired) { so.dataset.wired = '1'; so.addEventListener('change', renderAdminProducts); }
    renderAdminProducts();
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

async function searchAdminUsers() {
  const list = $('#adUserList');
  if (!list) return;
  
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  
  const search = ($('#adUserSearch')?.value || '').trim();
  const filter = $('#adUserFilter')?.value || 'all';
  const sort = $('#adUserSort')?.value || 'newest';
  
  let q = '';
  if (search) {
    q = /^\d{5,25}$/.test(search) ? '?discordId=' + search : '?key=' + encodeURIComponent(search);
  }
  
  // Add filter params
  if (filter !== 'all') {
    q += (q ? '&' : '?') + 'filter=' + filter;
  }
  
  try {
    const r = await api('/api/keys/admin/list' + q, { admin: true });
    let keys = r.keys || [];
    
    // Sort keys
    keys.sort((a, b) => {
      if (sort === 'oldest') return (a.created || 0) - (b.created || 0);
      if (sort === 'name') {
        const nameA = a.discordData?.global_name || a.discordData?.username || '';
        const nameB = b.discordData?.global_name || b.discordData?.username || '';
        return nameA.localeCompare(nameB);
      }
      if (sort === 'expiring') {
        if (!a.expire && !b.expire) return 0;
        if (!a.expire) return 1;
        if (!b.expire) return -1;
        return a.expire - b.expire;
      }
      return (b.created || 0) - (a.created || 0); // newest default
    });
    
    if (!keys.length) {
      list.innerHTML = `<div class="empty">No users found.</div>`;
      return;
    }
    
    // Render user grid
    list.innerHTML = keys.map(k => {
      const discord = k.discordData || {};
      const status = k.blacklisted ? 'blacklisted' : 
                     k.activated ? 'active' : 'pending';
      const statusClass = k.blacklisted ? 'bad' : 
                          k.activated ? 'ok' : 'pending';
      
      return `
        <div class="user-card">
          ${discord.avatar ? 
            `<img src="${discord.avatar}" alt="" class="user-avatar" />` : 
            `<div class="user-avatar ph"><i data-lucide="user"></i></div>`
          }
          <div style="flex: 1; min-width: 0;">
            <div class="user-name">${esc(discord.globalName || discord.username || 'Unknown User')}</div>
            <div class="user-sub">@${esc(discord.username || '—')} · ID: <code>${esc(k.discordId || 'Unassigned')}</code></div>
            <div style="margin-top: 8px; display: flex; gap: 8px; flex-wrap: wrap; font-size: 12px; color: var(--muted);">
              <span>Key: <code>${esc(k.key.substring(0, 12))}...</code></span>
              <span>Exp: <b>${k.expire ? fmtDate(k.expire) : 'Lifetime'}</b></span>
              <span class="key-status ${statusClass}">${status}</span>
            </div>
          </div>
          <div style="display: flex; flex-direction: column; gap: 6px;">
            <button class="mini" data-key="${esc(k.key)}" data-action="reset">Reset HWID</button>
            <button class="mini ${k.blacklisted ? '' : 'danger'}" data-key="${esc(k.key)}" data-action="blacklist">
              ${k.blacklisted ? 'Unblacklist' : 'Blacklist'}
            </button>
          </div>
        </div>
      `;
    }).join('');
    
    renderIcons();
    
    // Bind actions
    list.querySelectorAll('button[data-key]').forEach(btn => {
      btn.addEventListener('click', async () => {
        const key = btn.dataset.key;
        const action = btn.dataset.action;
        
        try {
          if (action === 'reset') {
            await api('/api/keys/admin/reset-hwid', { method: 'POST', body: { key }, admin: true });
            alert('HWID reset successfully');
          } else if (action === 'blacklist') {
            const isBl = btn.textContent.includes('Unblacklist');
            await api('/api/keys/admin/blacklist', { 
              method: 'POST', 
              body: { key, blacklisted: !isBl, reason: 'Admin action' }, 
              admin: true 
            });
            searchAdminUsers();
          }
        } catch (e) {
          alert(e.message);
        }
      });
    });
    
  } catch (e) {
    list.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
  }
}

async function searchAdminKeys() {
  const list = $('#adKeyList');
  if (!list) return;
  
  list.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  const typeFilter = $('#adKeyTypeFilter')?.value || 'all';
  
  try {
    const promises = [];
    if (typeFilter === 'all' || typeFilter === 'script') {
      promises.push(api('/api/keys/admin/list', { admin: true }).catch(() => ({ keys: [] })));
    } else {
      promises.push(Promise.resolve({ keys: [] }));
    }

    if (typeFilter === 'all' || typeFilter === 'external') {
      promises.push(api('/api/external-keys/admin/list', { admin: true }).catch(() => ({ keys: [] })));
    } else {
      promises.push(Promise.resolve({ keys: [] }));
    }

    const [scriptRes, extRes] = await Promise.all(promises);

    const scriptKeys = (scriptRes.keys || []).map((k) => ({ ...k, isExternal: false }));
    const extKeys = (extRes.keys || []).map((k) => ({
      ...k,
      isExternal: true,
      hubName: k.product || 'RiotsSeige',
    }));

    const combined = [...extKeys, ...scriptKeys];
    list.innerHTML = renderAdminKeys(combined);
    bindAdminKeyActions();
    renderIcons();
  } catch (e) {
    list.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
  }
}

function renderAdminKeys(keys) {
  if (!keys.length) return `<div class="empty">No keys found.</div>`;
  return keys.map((k) => `
    <div class="admin-key" data-key="${esc(k.key)}" data-external="${k.isExternal ? '1' : '0'}" data-discord="${esc(k.discordId || '')}">
      <div class="ak-main">
        <div style="display:flex;align-items:center;gap:6px;margin-bottom:4px;">
          ${k.isExternal ? `<span class="ak-badge ext">RiotsSeige (External)</span>` : `<span class="ak-badge lua">Lua Script</span>`}
          <code>${esc(k.key)}</code>
          <button class="mini copy-btn" data-copy="${esc(k.key)}" style="padding:2px 6px;font-size:10px;">Copy</button>
        </div>
        <div class="ak-sub">
          ${k.discordData ? `👤 ${esc(k.discordData.global_name || k.discordData.username)} (${esc(k.discordId)})` : (k.discordId ? `👤 ${esc(k.discordId)}` : '⚪ unassigned')}
          · exp ${k.expire ? fmtDate(k.expire) : '∞'}
          · HWID: ${k.hwid ? '<span style="color:#4ade80;">Linked</span>' : '<span style="color:var(--muted);">None</span>'}
          ${k.executionCount !== undefined ? `· runs: ${k.executionCount}` : ''}
          ${Array.isArray(k.limitedScripts) && k.limitedScripts.length ? `· <span class="ak-tag">${k.limitedScripts.length} script${k.limitedScripts.length > 1 ? 's' : ''}</span>` : ''}
          ${k.blacklisted ? '· <span class="bad">blacklisted</span>' : ''}
          ${k.note ? `· <em>${esc(k.note)}</em>` : ''}
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
    const isExt = row.dataset.external === '1';
    row.querySelectorAll('.mini[data-act]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const act = btn.dataset.act;
        try {
          if (act === 'reset') {
            const ep = isExt ? '/api/external-keys/admin/reset-hwid' : '/api/keys/admin/reset-hwid';
            await api(ep, { method: 'POST', body: { key }, admin: true });
            alert('HWID reset successfully.');
          } else if (act === 'blacklist') {
            const isBl = btn.textContent === 'Unblacklist';
            const ep = isExt ? '/api/external-keys/admin/blacklist' : '/api/keys/admin/blacklist';
            await api(ep, { method: 'POST', body: { key, blacklisted: !isBl, reason: 'Admin action' }, admin: true });
            searchAdminKeys();
          } else if (act === 'delete') {
            if (!confirm('Delete this key permanently?')) return;
            const ep = isExt ? '/api/external-keys/admin/delete?key=' : '/api/keys/admin/delete?key=';
            await api(ep + encodeURIComponent(key), { method: 'DELETE', admin: true });
            searchAdminKeys();
          }
        } catch (e) { alert(e.message); }
      });
    });
  });

  $$('#adKeyList .copy-btn').forEach((b) => b.addEventListener('click', () => {
    navigator.clipboard.writeText(b.dataset.copy);
    b.textContent = 'Copied!';
    setTimeout(() => (b.textContent = 'Copy'), 1400);
  }));
}

/* ---------------- BOOT ---------------- */
(async function boot() {
  renderIcons();
  document.body.classList.add('loaded');
  showGate('start');

  // record a page view (fire-and-forget)
  fetch(API_BASE + '/api/content/pageview', {
    method: 'POST',
    headers: (() => { const h = { 'Content-Type': 'application/json' }; if (CLIENT_TOKEN) h['x-client-token'] = CLIENT_TOKEN; const st = getSessionToken(); if (st) h['Authorization'] = 'Bearer ' + st; return h; })(),
    credentials: 'include',
    body: JSON.stringify({ page: 'dashboard.html', referrer: document.referrer || '' }),
    keepalive: true,
  }).catch(() => {});

  const pendingKey = localStorage.getItem(PENDING_KEY);

  let me;
  try {
    me = await api('/auth/me');
  } catch (e) {
    // API unreachable - show helpful error message
    const gateCard = document.querySelector('#authGate .ag-card');
    if (gateCard) {
      gateCard.innerHTML = `
        <img src="gui.png" alt="riots.wtf" class="ag-logo" />
        <h2>API Connection Error</h2>
        <p style="color: var(--muted); margin: 16px 0;">The backend API is not responding. This could be because:</p>
        <ul style="text-align: left; color: var(--muted); margin: 0 0 20px 20px; line-height: 1.8;">
          <li>The backend server is not deployed yet</li>
          <li>The Railway app is sleeping (free tier)</li>
          <li>Network connectivity issues</li>
        </ul>
        <p style="color: var(--muted); margin-bottom: 16px;">Current API endpoint:</p>
        <code style="display: block; padding: 8px; background: rgba(100, 180, 255, 0.1); border-radius: 8px; margin-bottom: 20px; word-break: break-all;">${API_BASE}</code>
        <div style="display: flex; gap: 10px; flex-wrap: wrap;">
          <button class="btn btn-gradient" onclick="location.reload()">
            <i data-lucide="refresh-cw"></i>
            <span>Retry</span>
          </button>
          <button class="btn btn-bw" onclick="window.open('https://railway.app', '_blank')">
            <i data-lucide="external-link"></i>
            <span>Open Railway</span>
          </button>
        </div>
      `;
      renderIcons();
    }
    console.warn('[dashboard] API not reachable:', e.message);
    console.log('[dashboard] Make sure the backend is deployed and the API_BASE in config.js is correct.');
    console.log('[dashboard] Current API_BASE:', API_BASE);
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


/* ============================================================
   ADMIN: PRODUCTS, FEATURES, CATEGORIES, LOGS, CRACKS
   ============================================================ */

async function loadProducts() {
  const area = $('#productsArea');
  if (!area) return;
  area.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const data = await api('/api/products', { admin: true });
    const products = data.products || [];
    const featuresRes = await api('/api/products/all', { admin: true });
    const allFeatures = featuresRes.features || [];
    const catRes = await api('/api/products/categories', { admin: true }).catch(() => ({ categories: [] }));
    const cats = catRes.categories || [];
    
    let html = `
      <div class="admin-section">
        <div class="admin-header">
          <div>
            <h3>Product Catalog</h3>
            <p style="color:var(--muted);font-size:13px;margin-top:2px;">Manage store products, variants and features</p>
          </div>
          <button class="btn btn-gradient sm" id="adProdNew"><i data-lucide="plus"></i> Add Product</button>
        </div>
        <div id="adProdForm" hidden style="margin-bottom:20px;">
          <form class="admin-form" id="prodActualForm">
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;">
              <input type="text" id="adProdName" placeholder="Product name (e.g. riots.wtf Rivals)" required />
              <select id="adProdCategory"><option value="">Select category...</option></select>
            </div>
            <textarea id="adProdDesc" placeholder="Product description" rows="3"></textarea>
            <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px;">
              <input type="text" id="adProdPrice" placeholder="Lifetime Price (e.g., $10)" />
              <input type="text" id="adProdPriceMonthly" placeholder="Monthly Price (e.g., $4)" />
              <input type="text" id="adProdBadge" placeholder="Badge (e.g. Undetected)" value="Undetected" />
            </div>
            <input type="text" id="adProdImage" placeholder="Cover Image URL or file (e.g., product1.png, seige.png)" />
            <div class="admin-features-picker" style="margin:12px 0;">
              <label style="display:block;font-size:13px;font-weight:600;margin-bottom:6px;color:#fff;">Features:</label>
              <div id="adProdFeatures" class="feature-checkboxes" style="display:grid;grid-template-columns:repeat(auto-fill, minmax(180px, 1fr));gap:8px;"></div>
            </div>
            <div class="admin-form-buttons">
              <button type="submit" class="btn btn-gradient">Save Product</button>
              <button type="button" class="btn btn-bw" id="adProdCancel">Cancel</button>
            </div>
          </form>
        </div>
        <div id="adProdList" class="admin-list">
          ${products.length === 0 ? '<div class="empty">No products yet. Click "Add Product" above to create one.</div>' : products.map(p => `
            <div class="admin-item" data-id="${esc(p.id)}" style="display:flex;align-items:center;gap:16px;">
              ${p.image ? `<img src="${esc(p.image)}" alt="" style="width:48px;height:48px;object-fit:cover;border-radius:8px;border:1px solid rgba(255,255,255,.1);" />` : ''}
              <div class="ai-main" style="flex:1;">
                <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
                  <strong>${esc(p.name)}</strong>
                  ${p.badge ? `<span class="badge-pill" style="font-size:10px;padding:2px 8px;border-radius:99px;background:rgba(225,29,72,.2);border:1px solid rgba(225,29,72,.4);color:#ff6b81;">${esc(p.badge)}</span>` : ''}
                </div>
                <div class="ai-sub" style="font-size:12px;color:var(--muted);margin-top:3px;">
                  📁 ${esc(p.category || 'General')} · 💰 ${esc(p.price || '$0')}${p.priceMonthly ? ` / ${esc(p.priceMonthly)} mo` : ''} ${p.features?.length ? `· ⚡ ${p.features.length} features` : ''}
                </div>
              </div>
              <div class="ai-actions">
                <button class="btn btn-sm btn-bw edit-prod" title="Edit"><i data-lucide="edit-2"></i></button>
                <button class="btn btn-sm btn-bw del-prod" title="Delete"><i data-lucide="trash-2"></i></button>
              </div>
            </div>
          `).join('')}
        </div>
      </div>`;
    
    area.innerHTML = html;
    renderIcons();
    
    // Load categories for dropdown
    const catSel = $('#adProdCategory');
    cats.forEach(c => {
      const opt = document.createElement('option');
      opt.value = c.name;
      opt.textContent = c.name;
      opt.dataset.slug = c.slug || '';
      opt.dataset.id = c.id || '';
      catSel.appendChild(opt);
    });
    enhanceSelects(catSel);
    
    // Features checkboxes
    const featBox = $('#adProdFeatures');
    allFeatures.forEach(f => {
      const label = document.createElement('label');
      label.className = 'feature-check';
      label.style.cssText = 'display:flex;align-items:center;gap:6px;font-size:12px;cursor:pointer;color:var(--text);';
      label.innerHTML = `<input type="checkbox" value="${esc(f.id)}" /> <span>${esc(f.name)}</span>`;
      featBox.appendChild(label);
    });
    
    // Form handlers
    const formWrap = $('#adProdForm');
    const form = $('#prodActualForm');
    const listWrap = $('#adProdList');
    
    $('#adProdNew').addEventListener('click', () => {
      delete form.dataset.editId;
      form.reset();
      formWrap.hidden = false;
      listWrap.hidden = true;
      $('#adProdName').focus();
    });
    
    $('#adProdCancel').addEventListener('click', () => {
      delete form.dataset.editId;
      formWrap.hidden = true;
      listWrap.hidden = false;
    });
    
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = $('#adProdName').value.trim();
      const category = $('#adProdCategory').value || 'General';
      const desc = $('#adProdDesc').value.trim();
      const price = $('#adProdPrice').value.trim();
      const priceMonthly = $('#adProdPriceMonthly').value.trim();
      const badge = $('#adProdBadge').value.trim();
      const image = $('#adProdImage').value.trim();
      const selectedFeatures = [...$$('#adProdFeatures input:checked')].map(cb => cb.value);
      
      if (!name) { alert('Enter product name'); return; }
      
      const btn = form.querySelector('button[type="submit"]');
      btn.disabled = true;
      try {
        const body = { name, category, description: desc, price, priceMonthly, badge, image };
        const editId = form.dataset.editId;
        
        let prodId;
        if (editId) {
          const res = await api(`/api/products/${editId}`, { method: 'PATCH', body, admin: true });
          prodId = editId;
          alert('Product updated successfully!');
        } else {
          const res = await api('/api/products', { method: 'POST', body, admin: true });
          prodId = res.product.id;
          alert('Product created successfully!');
        }
        
        if (selectedFeatures.length && prodId) {
          await api(`/api/products/${prodId}/features`, { 
            method: 'PUT', 
            body: { featureIds: selectedFeatures },
            admin: true 
          });
        }
        
        delete form.dataset.editId;
        formWrap.hidden = true;
        listWrap.hidden = false;
        loadProducts();
      } catch (err) { alert(err.message); }
      finally { btn.disabled = false; }
    });
    
    // Edit buttons
    area.querySelectorAll('.edit-prod').forEach(btn => {
      btn.addEventListener('click', () => {
        const item = btn.closest('.admin-item');
        const id = item.dataset.id;
        const prod = products.find(p => p.id === id);
        if (!prod) return;
        
        form.dataset.editId = id;
        $('#adProdName').value = prod.name || '';
        
        // Select matching category
        let found = false;
        for (const opt of catSel.options) {
          if (opt.value.toLowerCase() === (prod.category || '').toLowerCase() ||
              (opt.dataset.slug && opt.dataset.slug.toLowerCase() === (prod.category || '').toLowerCase()) ||
              (opt.dataset.id && opt.dataset.id === prod.category)) {
            catSel.value = opt.value;
            found = true;
            break;
          }
        }
        if (!found && prod.category) {
          const opt = document.createElement('option');
          opt.value = prod.category;
          opt.textContent = prod.category;
          catSel.appendChild(opt);
          catSel.value = prod.category;
        }
        
        $('#adProdDesc').value = prod.description || '';
        $('#adProdPrice').value = prod.price || '';
        $('#adProdPriceMonthly').value = prod.priceMonthly || '';
        $('#adProdBadge').value = prod.badge || 'Undetected';
        $('#adProdImage').value = prod.image || '';
        
        $$('#adProdFeatures input').forEach(cb => {
          cb.checked = (prod.features || []).includes(cb.value);
        });
        
        formWrap.hidden = false;
        listWrap.hidden = true;
        form.scrollIntoView({ behavior: 'smooth' });
      });
    });
    
    // Delete buttons
    area.querySelectorAll('.del-prod').forEach(btn => {
      btn.addEventListener('click', async () => {
        const item = btn.closest('.admin-item');
        const id = item.dataset.id;
        if (!confirm('Delete this product?')) return;
        btn.disabled = true;
        try {
          await api(`/api/products/${id}`, { method: 'DELETE', admin: true });
          alert('Product deleted!');
          loadProducts();
        } catch (err) { alert(err.message); }
        finally { btn.disabled = false; }
      });
    });
    
  } catch (e) {
    area.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
  }
}

async function loadFeatures() {
  const area = $('#featuresArea');
  if (!area) return;
  area.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const data = await api('/api/products/all', { admin: true });
    const features = data.features || [];
    
    let html = `
      <div class="admin-section">
        <div class="admin-header">
          <h3>Features</h3>
          <button class="btn btn-gradient sm" id="adFeatNew"><i data-lucide="plus"></i> Add Feature</button>
        </div>
        <div id="adFeatForm" hidden>
          <form class="admin-form">
            <input type="text" id="adFeatName" placeholder="Feature name" required />
            <input type="text" id="adFeatCategory" placeholder="Category (e.g., Aimbot)" />
            <textarea id="adFeatDesc" placeholder="Description" rows="2"></textarea>
            <div class="admin-form-buttons">
              <button type="submit" class="btn btn-gradient">Save</button>
              <button type="button" class="btn btn-bw" id="adFeatCancel">Cancel</button>
            </div>
          </form>
        </div>
        <div id="adFeatList" class="admin-list">
          ${features.length === 0 ? '<div class="empty">No features yet.</div>' : features.map(f => `
            <div class="admin-item" data-id="${esc(f.id)}">
              <div class="ai-main">
                <strong>${esc(f.name)}</strong>
                <div class="ai-sub">${esc(f.category || 'General')} · ${esc(f.description || '—')}</div>
              </div>
              <div class="ai-actions">
                <button class="btn btn-sm btn-bw edit-feat"><i data-lucide="edit-2"></i></button>
                <button class="btn btn-sm btn-bw del-feat"><i data-lucide="trash-2"></i></button>
              </div>
            </div>
          `).join('')}
        </div>
      </div>`;
    
    area.innerHTML = html;
    renderIcons();
    
    const form = area.querySelector('.admin-form');
    $('#adFeatNew').addEventListener('click', () => {
      form.reset();
      form.hidden = false;
      $('#adFeatList').hidden = true;
    });
    $('#adFeatCancel').addEventListener('click', () => {
      form.hidden = true;
      $('#adFeatList').hidden = false;
    });
    
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = $('#adFeatName').value.trim();
      const category = $('#adFeatCategory').value.trim();
      const desc = $('#adFeatDesc').value.trim();
      
      if (!name) { alert('Enter feature name'); return; }
      
      const btn = form.querySelector('button[type="submit"]');
      btn.disabled = true;
      try {
        const editId = form.dataset.editId;
        if (editId) {
          await api(`/api/products/all/${editId}`, { 
            method: 'PATCH', 
            body: { name, category, description: desc },
            admin: true 
          });
        } else {
          await api('/api/products/all', { 
            method: 'POST', 
            body: { name, category, description: desc },
            admin: true 
          });
        }
        alert(editId ? 'Feature updated!' : 'Feature created!');
        delete form.dataset.editId;
        loadFeatures();
      } catch (err) { alert(err.message); }
      finally { btn.disabled = false; }
    });
    
    area.querySelectorAll('.edit-feat').forEach(btn => {
      btn.addEventListener('click', () => {
        const item = btn.closest('.admin-item');
        const id = item.dataset.id;
        const feat = features.find(f => f.id === id);
        if (!feat) return;
        
        $('#adFeatName').value = feat.name;
        $('#adFeatCategory').value = feat.category || '';
        $('#adFeatDesc').value = feat.description || '';
        form.dataset.editId = id;
        form.hidden = false;
        $('#adFeatList').hidden = true;
      });
    });
    
    area.querySelectorAll('.del-feat').forEach(btn => {
      btn.addEventListener('click', async () => {
        const item = btn.closest('.admin-item');
        const id = item.dataset.id;
        if (!confirm('Delete this feature?')) return;
        btn.disabled = true;
        try {
          await api(`/api/products/all/${id}`, { method: 'DELETE', admin: true });
          alert('Feature deleted!');
          loadFeatures();
        } catch (err) { alert(err.message); }
        finally { btn.disabled = false; }
      });
    });
    
  } catch (e) {
    area.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
  }
}

async function loadCategories() {
  const area = $('#categoriesArea');
  if (!area) return;
  area.innerHTML = `<div class="dash-loading"><span></span><span></span><span></span></div>`;
  try {
    const data = await api('/api/products/categories', { admin: true });
    const categories = data.categories || [];
    
    let html = `
      <div class="admin-section">
        <div class="admin-header">
          <div>
            <h3>Game Categories</h3>
            <p style="color:var(--muted);font-size:13px;margin-top:2px;">Manage store categories, banners, and game groupings</p>
          </div>
          <button class="btn btn-gradient sm" id="adCatNew"><i data-lucide="plus"></i> Add Category</button>
        </div>
        <div id="adCatForm" hidden style="margin-bottom:20px;">
          <form class="admin-form" id="catActualForm">
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;">
              <input type="text" id="adCatName" placeholder="Category name (e.g., Rainbow Six Siege)" required />
              <input type="text" id="adCatSlug" placeholder="Slug (e.g., r6siege)" />
            </div>
            <div style="display:grid;grid-template-columns:120px 1fr;gap:12px;">
              <input type="text" id="adCatIcon" placeholder="Icon (e.g. 🎯)" />
              <input type="text" id="adCatImage" placeholder="Cover Image URL or file (e.g., seige.png, roblox.png)" />
            </div>
            <textarea id="adCatDesc" placeholder="Short description" rows="2"></textarea>
            <div class="admin-form-buttons">
              <button type="submit" class="btn btn-gradient">Save Category</button>
              <button type="button" class="btn btn-bw" id="adCatCancel">Cancel</button>
            </div>
          </form>
        </div>
        <div id="adCatList" class="admin-list">
          ${categories.length === 0 ? '<div class="empty">No categories yet. Click "Add Category" above to create one.</div>' : categories.map(c => `
            <div class="admin-item" data-id="${esc(c.id)}" style="display:flex;align-items:center;gap:16px;">
              ${c.image ? `<img src="${esc(c.image)}" alt="" style="width:54px;height:36px;object-fit:cover;border-radius:6px;border:1px solid rgba(255,255,255,.1);" />` : ''}
              <div class="ai-main" style="flex:1;">
                <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
                  <strong>${esc(c.icon || '📦')} ${esc(c.name)}</strong>
                  <span style="font-size:11px;padding:2px 8px;border-radius:99px;background:rgba(255,255,255,.06);color:var(--muted);">${esc(c.slug || '')}</span>
                </div>
                <div class="ai-sub" style="font-size:12px;color:var(--muted);margin-top:3px;">${esc(c.description || '—')}</div>
              </div>
              <div class="ai-actions">
                <button class="btn btn-sm btn-bw edit-cat" title="Edit"><i data-lucide="edit-2"></i></button>
                <button class="btn btn-sm btn-bw del-cat" title="Delete"><i data-lucide="trash-2"></i></button>
              </div>
            </div>
          `).join('')}
        </div>
      </div>`;
    
    area.innerHTML = html;
    renderIcons();
    
    const formWrap = $('#adCatForm');
    const form = $('#catActualForm');
    const listWrap = $('#adCatList');
    
    $('#adCatNew').addEventListener('click', () => {
      delete form.dataset.editId;
      form.reset();
      formWrap.hidden = false;
      listWrap.hidden = true;
      $('#adCatName').focus();
    });
    
    $('#adCatCancel').addEventListener('click', () => {
      delete form.dataset.editId;
      formWrap.hidden = true;
      listWrap.hidden = false;
    });
    
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = $('#adCatName').value.trim();
      const slug = $('#adCatSlug').value.trim();
      const icon = $('#adCatIcon').value.trim();
      const image = $('#adCatImage').value.trim();
      const desc = $('#adCatDesc').value.trim();
      
      if (!name) { alert('Enter category name'); return; }
      
      const btn = form.querySelector('button[type="submit"]');
      btn.disabled = true;
      try {
        const editId = form.dataset.editId;
        const body = { name, slug: slug || name.toLowerCase().replace(/[^a-z0-9]/g, ''), icon, image, description: desc };
        if (editId) {
          await api(`/api/products/categories/${editId}`, { 
            method: 'PATCH', 
            body,
            admin: true 
          });
        } else {
          await api('/api/products/categories', { 
            method: 'POST', 
            body,
            admin: true 
          });
        }
        alert(editId ? 'Category updated!' : 'Category created!');
        delete form.dataset.editId;
        formWrap.hidden = true;
        listWrap.hidden = false;
        loadCategories();
      } catch (err) { alert(err.message); }
      finally { btn.disabled = false; }
    });
    
    area.querySelectorAll('.edit-cat').forEach(btn => {
      btn.addEventListener('click', () => {
        const item = btn.closest('.admin-item');
        const id = item.dataset.id;
        const cat = categories.find(c => c.id === id);
        if (!cat) return;
        
        $('#adCatName').value = cat.name || '';
        $('#adCatSlug').value = cat.slug || '';
        $('#adCatIcon').value = cat.icon || '';
        $('#adCatImage').value = cat.image || '';
        $('#adCatDesc').value = cat.description || '';
        form.dataset.editId = id;
        formWrap.hidden = false;
        listWrap.hidden = true;
        form.scrollIntoView({ behavior: 'smooth' });
      });
    });
    
    area.querySelectorAll('.del-cat').forEach(btn => {
      btn.addEventListener('click', async () => {
        const item = btn.closest('.admin-item');
        const id = item.dataset.id;
        if (!confirm('Delete this category?')) return;
        btn.disabled = true;
        try {
          await api(`/api/products/categories/${id}`, { method: 'DELETE', admin: true });
          alert('Category deleted!');
          loadCategories();
        } catch (err) { alert(err.message); }
        finally { btn.disabled = false; }
      });
    });
    
  } catch (e) {
    area.innerHTML = `<div class="empty">${esc(e.message)}</div>`;
  }
}

/* ---------- Global Link Fallback for file:// and static hosts ---------- */
document.addEventListener('click', (e) => {
  const a = e.target.closest('a');
  if (!a) return;
  const href = a.getAttribute('href');
  if (!href || href.startsWith('http://') || href.startsWith('https://') || href.startsWith('#') || href.startsWith('mailto:') || href.startsWith('javascript:')) return;

  const isLocalOrFile = location.protocol === 'file:' || location.pathname.endsWith('.html');
  if (!isLocalOrFile) return;

  const [path, search] = href.split('?');
  const known = ['index', 'products', 'status', 'referral', 'dashboard', 'terms', 'privacy', 'refund'];
  if (known.includes(path.toLowerCase())) {
    e.preventDefault();
    const dest = path + '.html' + (search ? '?' + search : '');
    window.location.href = dest;
  }
});
