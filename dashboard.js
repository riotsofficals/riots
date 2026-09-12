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

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

function renderIcons() {
  if (window.lucide && typeof window.lucide.createIcons === 'function') {
    window.lucide.createIcons();
  }
}

async function api(path, { method = 'GET', body, admin = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (admin && ADMIN_KEY) headers['x-admin-key'] = ADMIN_KEY;
  if (CLIENT_TOKEN) headers['x-client-token'] = CLIENT_TOKEN;
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
    if (view === 'admin') loadAdmin();
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
            <span class="status-pill ${s.state === 'up' ? 'up' : 'warn'}"><span class="dot"></span>${s.state === 'up' ? 'Operational' : (s.state === 'down' ? 'Down' : 'Degraded')}</span>
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
    <div class="admin-grid">
      <!-- My key settings -->
      <div class="admin-card">
        <h3>My key settings</h3>
        <p class="admin-hint">Paste one of your own keys to inspect / manage it.</p>
        <input type="text" id="adMyKey" placeholder="Your key" />
        <button class="btn btn-bw" id="adLookup"><span>Look up</span></button>
        <div id="adMyKeyResult"></div>
      </div>

      <!-- Manage users -->
      <div class="admin-card">
        <h3>Manage keys / users</h3>
        <div class="admin-row">
          <input type="text" id="adFilter" placeholder="Filter by Discord ID or key (blank = all)" />
          <button class="btn btn-bw" id="adSearch"><span>Search</span></button>
        </div>
        <div id="adKeyList" class="admin-list"></div>
      </div>

      <!-- Generate / add -->
      <div class="admin-card">
        <h3>Generate keys</h3>
        <div class="admin-row">
          <input type="number" id="adAmount" placeholder="Amount (5-300)" min="5" max="300" value="5" />
          <input type="number" id="adExpire" placeholder="Expire seconds (blank=lifetime)" />
        </div>
        <button class="btn btn-gradient" id="adGenerate"><span>Generate</span></button>
        <div id="adGenResult"></div>
      </div>

      <!-- Status updater -->
      <div class="admin-card">
        <h3>Status updater</h3>
        <select id="adOverall">
          <option value="operational">Operational</option>
          <option value="degraded">Degraded</option>
          <option value="partial">Partial outage</option>
          <option value="down">Down</option>
          <option value="maintenance">Maintenance</option>
        </select>
        <p class="admin-hint">Products / services (one per line: <code>Name | description | up|warn|down</code>)</p>
        <textarea id="adServices" rows="5" placeholder="riots.wtf rivals script | Roblox Rivals | up"></textarea>
        <button class="btn btn-gradient" id="adSaveStatus"><span>Publish status</span></button>
        <div id="adStatusResult"></div>
      </div>

      <!-- Product manager -->
      <div class="admin-card wide">
        <h3>Products</h3>
        <p class="admin-hint">Create, edit and delete the products shown in the store. Images upload to Cloudinary.</p>
        <div id="adProdList" class="admin-products"></div>

        <h3 style="margin-top:18px">Add / edit product</h3>
        <label class="img-drop" id="adImgDrop">
          <i data-lucide="image-plus"></i> <span>Click to upload image</span>
          <input type="file" id="adImgFile" accept="image/*" hidden />
        </label>
        <img id="adImgPreview" class="img-preview" hidden />
        <input type="hidden" id="adProdId" />
        <input type="hidden" id="adProdImage" />
        <div class="admin-row">
          <input type="text" id="adProdName" placeholder="Product name" />
          <input type="text" id="adProdCategory" placeholder="Category (e.g. Roblox)" />
        </div>
        <div class="admin-row">
          <input type="text" id="adProdPrice" placeholder="Lifetime price (e.g. $10)" />
          <input type="text" id="adProdPriceMonthly" placeholder="Monthly price (e.g. $4)" />
        </div>
        <div class="admin-row">
          <input type="text" id="adProdBadge" placeholder="Badge (e.g. Best Seller)" />
          <input type="text" id="adProdKmrzaProduct" placeholder="Komerza product id" />
        </div>
        <div class="admin-row">
          <input type="text" id="adProdKmrzaLife" placeholder="Komerza lifetime variant id" />
          <input type="text" id="adProdKmrzaMonth" placeholder="Komerza monthly variant id" />
        </div>
        <textarea id="adProdDesc" rows="3" placeholder="Description"></textarea>
        <label class="admin-hint" style="display:flex;align-items:center;gap:8px">
          <input type="checkbox" id="adProdFeatured" style="width:auto;margin:0" /> Featured
        </label>
        <button class="btn btn-gradient" id="adProdSave"><span>Save product</span></button>
        <button class="btn btn-bw" id="adProdReset"><span>Clear form</span></button>
        <div id="adProdResult"></div>
      </div>

      <!-- Devlog editor -->
      <div class="admin-card wide">
        <h3>Post an update (devlog)</h3>
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
    </div>`;

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

  // Status
  $('#adSaveStatus').addEventListener('click', async () => {
    const overall = $('#adOverall').value;
    const services = $('#adServices').value.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => {
      const [name, desc, state] = l.split('|').map((x) => (x || '').trim());
      return { name, desc: desc || '', state: ['up', 'warn', 'down', 'maintenance'].includes(state) ? state : 'up' };
    });
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

  loadAdminProducts();
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
  window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
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
      showGate('key');
    }
  } catch (e) {
    showGate('start');
  }
})();
