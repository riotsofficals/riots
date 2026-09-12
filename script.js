/* ============================================================
   riots.wtf — site scripts (multi-page)
   ============================================================ */

/* ---------- Lucide icons ---------- */
function renderIcons() {
  if (window.lucide && typeof window.lucide.createIcons === 'function') {
    window.lucide.createIcons();
  }
}

/* ---------- PAGE LOAD ANIMATION (no preloader) ---------- */
function initLoad() {
  renderIcons();
  requestAnimationFrame(() => document.body.classList.add('loaded'));
  // fire the intersection reveals
  const io = new IntersectionObserver((entries) => {
    entries.forEach(en => {
      if (en.isIntersecting) { en.target.classList.add('in-view'); io.unobserve(en.target); }
    });
  }, { threshold: 0.1 });
  document.querySelectorAll('.reveal').forEach(el => io.observe(el));
}

/* ---------- NAVBAR scroll shadow ---------- */
function initNavbar() {
  const navbar = document.getElementById('navbar');
  if (!navbar) return;
  const onScroll = () => navbar.classList.toggle('scrolled', window.scrollY > 30);
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });
}

/* ---------- HERO: typewriter + mouse glow (home only) ---------- */
function initHero() {
  const el = document.getElementById('typewriter');
  if (el) {
    const target = el.dataset.text || '';
    const out = el.querySelector('.tw-text');
    let i = 0;
    const type = () => {
      if (i <= target.length) { out.textContent = target.slice(0, i); i++; setTimeout(type, 85); }
    };
    setTimeout(type, 500);
  }

  const hero = document.querySelector('.hero');
  const heroGlow = document.getElementById('heroGlow');
  const heroGrad = document.getElementById('typewriter');
  if (hero && heroGlow) {
    // Perf: cache the rect (recompute only on resize/scroll), throttle pointer
    // updates to one per animation frame, and move the glow with `transform`
    // (GPU compositor — no layout/paint) instead of left/top.
    let rect = hero.getBoundingClientRect();
    const refreshRect = () => { rect = hero.getBoundingClientRect(); };
    window.addEventListener('resize', refreshRect, { passive: true });
    window.addEventListener('scroll', refreshRect, { passive: true });

    let px = 0, py = 0, queued = false;
    const apply = () => {
      queued = false;
      // glow is margin-centered on its origin; a pure translate() moves its
      // center to (px,py) with zero layout cost.
      heroGlow.style.transform = `translate(${px}px, ${py}px)`;
      if (heroGrad) {
        heroGrad.style.backgroundPosition =
          `${(px / rect.width) * 100}% ${(py / rect.height) * 100}%`;
      }
    };
    hero.addEventListener('mousemove', (e) => {
      px = e.clientX - rect.left;
      py = e.clientY - rect.top;
      if (heroGrad) heroGrad.classList.add('glow');
      if (!queued) { queued = true; requestAnimationFrame(apply); }
    }, { passive: true });
    hero.addEventListener('mouseleave', () => {
      // rest near the hero's upper-center
      heroGlow.style.transform = `translate(${rect.width * 0.5}px, ${rect.height * 0.4}px)`;
      if (heroGrad) { heroGrad.classList.remove('glow'); heroGrad.style.backgroundPosition = '0% 50%'; }
    });
  }
}

/* ---------- FEATURED PRODUCT (home preview) ---------- */
const FEATURED = {
  name: 'riots.wtf rivals script',
  sub: 'Roblox · Rivals',
  price: 'from $4',
  stock: 'In stock',
  tag: 'Best Seller',
  in: true,
};
function initHomeProducts() {
  const grid = document.getElementById('homeProductGrid');
  if (!grid) return;
  grid.classList.add('single');
  grid.innerHTML = `
    <a href="products.html" class="product-card reveal in-view">
      <div class="product-media">
        <span class="tag">${FEATURED.tag}</span>
        <img src="product1.png" alt="${FEATURED.name}" />
      </div>
      <div class="product-info">
        <div class="product-name">${FEATURED.name}<small>${FEATURED.sub}</small></div>
        <div class="product-meta">
          <div class="product-price">${FEATURED.price}</div>
          <div class="product-stock ${FEATURED.in ? 'in' : ''}">${FEATURED.stock}</div>
        </div>
      </div>
    </a>`;
}

/* ---------- Q&A accordion ---------- */
function initQA() {
  document.querySelectorAll('.qa-item').forEach(item => {
    const q = item.querySelector('.qa-q');
    const a = item.querySelector('.qa-a');
    q.addEventListener('click', () => {
      const open = item.classList.contains('open');
      document.querySelectorAll('.qa-item').forEach(o => { o.classList.remove('open'); o.querySelector('.qa-a').style.maxHeight = null; });
      if (!open) { item.classList.add('open'); a.style.maxHeight = a.scrollHeight + 'px'; }
    });
  });
}

/* ---------- MATRIX rain + star sparkles (home) ---------- */
function initEffects() {
  const matrix = document.getElementById('matrix');
  if (matrix) {
    const chars = '01', cols = 16;
    for (let c = 0; c < cols; c++) {
      const col = document.createElement('div');
      col.className = 'col';
      col.style.left = (c / cols) * 100 + '%';
      col.style.animationDuration = (2 + Math.random() * 3).toFixed(2) + 's';
      col.style.animationDelay = (-Math.random() * 4).toFixed(2) + 's';
      let str = '';
      for (let r = 0; r < 22; r++) str += `<span>${chars[Math.floor(Math.random() * 2)]}</span>`;
      col.innerHTML = str;
      matrix.appendChild(col);
    }
    setInterval(() => {
      const spans = matrix.querySelectorAll('span');
      if (!spans.length) return;
      const s = spans[Math.floor(Math.random() * spans.length)];
      s.textContent = chars[Math.floor(Math.random() * 2)];
      s.style.color = '#7CFFA0';
      setTimeout(() => (s.style.color = ''), 120);
    }, 90);
  }
  document.querySelectorAll('.stat-card').forEach(card => {
    for (let i = 0; i < 6; i++) {
      const star = document.createElement('span');
      star.className = 'star'; star.textContent = '✦';
      star.style.left = Math.random() * 90 + '%';
      star.style.top = Math.random() * 80 + '%';
      star.style.animationDelay = (Math.random() * 2.4).toFixed(2) + 's';
      star.style.fontSize = (8 + Math.random() * 8).toFixed(0) + 'px';
      card.appendChild(star);
    }
  });
}

/* ============================================================
   PRODUCTS PAGE — feature categories, plan selector, checkout
   ============================================================ */

/* Real feature set, pulled from the riots.wtf rivals script (script.lua),
   grouped by the in-menu categories. */
const FEATURE_CATEGORIES = [
  {
    name: 'Aimbot', desc: 'Camera & mouse aim', icon: 'crosshair',
    items: [
      'Camera + mouse aim modes', 'Sticky aim', 'Smoothing (1–30)',
      'Prediction (X / Y)', 'Miss chance %', 'Hit part selector (head → limbs)',
      'FOV circle + full customization', 'Instant zoom (keybindable)',
      'Checks: wall / team / melee / dead',
    ],
  },
  {
    name: 'Silent Aim', desc: 'Server-side hit routing', icon: 'target',
    items: [
      'Silent aim with hit chance %', 'Hit part selector (25+ parts)',
      'Anti-katana (deflect aware)', 'Backshoot / behind-target', 'Follow-muzzle FOV',
      'Animated + spinning FOV circle', 'Restricted-weapon safeguards',
    ],
  },
  {
    name: 'Guns & Combat', desc: 'Weapon modifiers', icon: 'swords',
    items: [
      'Rapid fire', 'No spread', 'No recoil', 'Max accuracy',
      'Rapid melee attack', 'Spinbot (speed slider)',
    ],
  },
  {
    name: 'ESP & Visuals', desc: 'Full player + NPC ESP', icon: 'eye',
    items: [
      'Boxes + fill + glow', 'Health bar (color lerp)', 'Names / distance / weapon',
      'Gradient + flow text', 'Skeleton ESP', 'Tracers', 'Chams + glow chams',
      'Full NPC / shooting-range ESP', 'Throwable ESP', 'Per-element color pickers',
    ],
  },
  {
    name: 'Hit Effects & Feedback', desc: 'Damage feel', icon: 'zap',
    items: [
      'Hit chams (flash)', 'Damage numbers (gradient rise)', 'Hit notify feed',
      'Hit sounds (11 presets, volume/pitch)', 'Hit effects (particles, shockwave, fire, ice, …)',
      'Bullet tracers (textures + spring expand)', 'Trajectory prediction arc',
    ],
  },
  {
    name: 'Viewmodel & World', desc: 'Scene control', icon: 'sun',
    items: [
      'Gun chams + arm chams (10 materials)', 'Invisible arms', 'Viewmodel hide / transparency',
      'No animations (per-type)', 'Lighting + color correction', 'Skybox (40+ presets, rotate)',
      'Atmosphere + ambience sounds',
    ],
  },
  {
    name: 'Character & Spoofers', desc: 'Profile + skins', icon: 'user-round',
    items: [
      'Level & win-streak spoof', 'Display name / username spoof', 'Spoof others + dev spoof',
      'Verified / premium badges', 'Avatar changer (by UserId)',
      'Skin changer + unlock all cosmetics', 'Unlock all weapons', 'Unlock all emotes',
    ],
  },
  {
    name: 'Movement', desc: 'Mobility', icon: 'wind',
    items: [
      'Velocity walkspeed (keybind)', 'Velocity fly (keybind)', 'Infinite double jump',
      'Auto slide', 'Slide boost (speed slider)',
    ],
  },
  {
    name: 'Target Tools', desc: 'Lock-on utilities', icon: 'locate-fixed',
    items: [
      'Target HUD (avatar, hp, distance, weapon)', 'Spectate target', 'TP to target',
      'Orbit target (radius/speed)', 'Spam TP', 'One-shot teleport',
    ],
  },
  {
    name: 'Misc & Optimization', desc: 'Performance + QoL', icon: 'gauge',
    items: [
      'FPS boost (no textures)', 'Smooth / dark textures', 'No particles / shadows / post-fx',
      'Low quality + FPS cap', 'Device spoof (mobile/console/VR/PC)', 'Emote player (custom IDs)',
      'Player list (tp / spectate / copy)',
    ],
  },
  {
    name: 'Menu & Configs', desc: 'UI + persistence', icon: 'settings',
    items: [
      'Draggable menu (RightShift)', 'Config save / load / autoload', 'Theme presets + custom accent',
      'Watermark (fps + ping)', 'Animated text watermark', 'Keybind list', 'Anti-detection / anti-cheat neutralize',
      'Daily updated & UD',
    ],
  },
];

function initFeatureAccordion() {
  const wrap = document.getElementById('featureAccordion');
  if (!wrap) return;
  const check = '<i data-lucide="check"></i>';
  const chev = '<i data-lucide="chevron-down" class="facc-chev"></i>';
  wrap.innerHTML = FEATURE_CATEGORIES.map((cat, idx) => `
    <div class="facc${idx === 0 ? ' open' : ''}">
      <button class="facc-head" type="button">
        <span class="facc-ico"><i data-lucide="${cat.icon}"></i></span>
        <span class="facc-titles"><strong>${cat.name}</strong><small>${cat.desc} · ${cat.items.length} features</small></span>
        ${chev}
      </button>
      <div class="facc-body">
        <ul class="facc-list">
          ${cat.items.map(i => `<li>${check}<span>${i}</span></li>`).join('')}
        </ul>
      </div>
    </div>`).join('');
  renderIcons();

  const items = wrap.querySelectorAll('.facc');
  items.forEach(item => {
    const head = item.querySelector('.facc-head');
    const body = item.querySelector('.facc-body');
    head.addEventListener('click', () => {
      const open = item.classList.contains('open');
      items.forEach(o => { o.classList.remove('open'); o.querySelector('.facc-body').style.maxHeight = null; });
      if (!open) { item.classList.add('open'); body.style.maxHeight = body.scrollHeight + 'px'; }
    });
  });
  // open the first one visually
  const first = items[0];
  if (first) first.querySelector('.facc-body').style.maxHeight = first.querySelector('.facc-body').scrollHeight + 'px';
}

/* ============================================================
   STORE — data-driven catalog, filters, detail view, checkout
   ============================================================ */
const CFG = window.RIOTS_CONFIG || {};
const KMRZA = CFG.KOMERZA || {};
const API_BASE = CFG.API_BASE || 'http://localhost:8080';
const CLIENT_TOKEN = CFG.CLIENT_TOKEN || '';
const isReal = (v) => v && !String(v).startsWith('REPLACE');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function apiHeaders(extra = {}) {
  const h = { ...extra };
  if (CLIENT_TOKEN) h['x-client-token'] = CLIENT_TOKEN;
  return h;
}

// Fallback product shown if the backend has no catalog yet (uses config Komerza IDs).
const DEFAULT_PRODUCT = {
  id: 'default',
  name: 'riots.wtf rivals script',
  category: 'Roblox',
  description: "The most complete Rivals script on the market — aimbot, silent aim, a full ESP suite, hit effects, skin/cosmetic unlocker, spoofers and more, all in one clean draggable menu. Anti-detection built in and updated & UD every single day.",
  price: '$10',
  priceMonthly: '$4',
  image: 'product1.png',
  badge: 'Best Seller',
  komerzaProductId: KMRZA.productId || '',
  komerzaVariants: KMRZA.variants || {},
  featured: true,
};

let STORE_PRODUCTS = [];
let storeState = { category: 'all', sort: 'featured', search: '' };

async function initStore() {
  const grid = document.getElementById('storeGrid');
  if (!grid) return; // not the products page

  // fetch catalog from backend; fall back to the default product
  try {
    const res = await fetch(API_BASE + '/api/store/products', { headers: apiHeaders(), credentials: 'include' });
    if (res.ok) {
      const data = await res.json();
      STORE_PRODUCTS = (data.products || []).map(normalizeProduct);
    }
  } catch (_) { /* backend not up yet */ }
  if (!STORE_PRODUCTS.length) STORE_PRODUCTS = [DEFAULT_PRODUCT];

  buildFilters();
  renderStoreGrid();

  document.getElementById('storeSearch')?.addEventListener('input', (e) => {
    storeState.search = e.target.value.toLowerCase();
    renderStoreGrid();
  });
  document.getElementById('storeSort')?.addEventListener('change', (e) => {
    storeState.sort = e.target.value;
    renderStoreGrid();
  });
  document.getElementById('detailBack')?.addEventListener('click', showStore);

  // deep-link: ?p=<id> opens a product directly
  const pid = new URLSearchParams(location.search).get('p');
  if (pid) { const p = STORE_PRODUCTS.find(x => x.id === pid); if (p) openProduct(p); }
}

function normalizeProduct(p) {
  return {
    id: p.id,
    name: p.name,
    category: p.category || 'General',
    description: p.description || '',
    price: p.price || '',
    priceMonthly: p.priceMonthly || '',
    image: p.image || 'product1.png',
    badge: p.badge || '',
    komerzaProductId: p.komerzaProductId || '',
    komerzaVariants: p.komerzaVariants || {},
    featured: !!p.featured,
    order: p.order || 0,
  };
}

function buildFilters() {
  const wrap = document.getElementById('storeFilters');
  if (!wrap) return;
  const cats = ['all', ...new Set(STORE_PRODUCTS.map(p => p.category).filter(Boolean))];
  wrap.innerHTML = cats.map(c =>
    `<button class="store-chip${c === storeState.category ? ' active' : ''}" data-cat="${esc(c)}">${c === 'all' ? 'All' : esc(c)}</button>`
  ).join('');
  wrap.querySelectorAll('.store-chip').forEach(chip => {
    chip.addEventListener('click', () => {
      storeState.category = chip.dataset.cat;
      wrap.querySelectorAll('.store-chip').forEach(c => c.classList.toggle('active', c === chip));
      renderStoreGrid();
    });
  });
}

function priceNum(p) {
  const n = parseFloat(String(p.price).replace(/[^\d.]/g, ''));
  return isNaN(n) ? 0 : n;
}

function renderStoreGrid() {
  const grid = document.getElementById('storeGrid');
  const empty = document.getElementById('storeEmpty');
  if (!grid) return;

  let list = STORE_PRODUCTS.slice();
  if (storeState.category !== 'all') list = list.filter(p => p.category === storeState.category);
  if (storeState.search) list = list.filter(p =>
    (p.name + ' ' + p.category + ' ' + p.description).toLowerCase().includes(storeState.search));

  list.sort((a, b) => {
    switch (storeState.sort) {
      case 'price-asc': return priceNum(a) - priceNum(b);
      case 'price-desc': return priceNum(b) - priceNum(a);
      case 'name': return a.name.localeCompare(b.name);
      default: return (b.featured - a.featured) || (a.order - b.order);
    }
  });

  if (empty) empty.hidden = list.length > 0;
  grid.innerHTML = list.map((p, i) => `
    <article class="store-card" data-id="${esc(p.id)}" style="animation-delay:${i * 60}ms">
      <div class="store-card-media">
        ${p.badge ? `<span class="tag">${esc(p.badge)}</span>` : ''}
        <img src="${esc(p.image)}" alt="${esc(p.name)}" loading="lazy" />
      </div>
      <div class="store-card-info">
        <div class="store-card-name">${esc(p.name)}<small>${esc(p.category)}</small></div>
        <div class="store-card-meta">
          <div class="store-card-price">${esc(p.price || (p.priceMonthly ? 'from ' + p.priceMonthly : ''))}</div>
          <div class="store-card-stock in">In stock</div>
        </div>
      </div>
    </article>`).join('');
  grid.querySelectorAll('.store-card').forEach(card => {
    card.addEventListener('click', () => {
      const p = STORE_PRODUCTS.find(x => x.id === card.dataset.id);
      if (p) openProduct(p);
    });
  });
  renderIcons();
}

/* ---------- product detail ---------- */
let currentPlan = 'lifetime';

function showStore() {
  document.getElementById('detailView').hidden = true;
  document.getElementById('storeView').hidden = false;
  window.scrollTo({ top: 0, behavior: 'smooth' });
  history.replaceState(null, '', location.pathname);
}

function openProduct(p) {
  const $ = (id) => document.getElementById(id);
  $('storeView').hidden = true;
  $('detailView').hidden = false;
  window.scrollTo({ top: 0, behavior: 'smooth' });

  $('pdImage').src = p.image;
  $('pdImage').alt = p.name;
  $('pdName').textContent = p.name;
  $('pdCat').textContent = p.category;
  $('pdDesc').textContent = p.description;
  const badge = $('pdBadge');
  if (p.badge) { badge.textContent = p.badge; badge.hidden = false; } else { badge.hidden = true; }
  if (p.price) $('pdPriceLife').innerHTML = `${esc(p.price)}<span>/ one-time</span>`;
  if (p.priceMonthly) $('pdPriceMonth').innerHTML = `${esc(p.priceMonthly)}<span>/ month</span>`;

  bindCheckout(p);
  loadLiveStock(p);
  history.replaceState(null, '', location.pathname + '?p=' + encodeURIComponent(p.id));
  renderIcons();
}

function bindCheckout(p) {
  const plansWrap = document.getElementById('pdPlans');
  const buyBtn = document.getElementById('buyBtn');
  const buyLabel = document.getElementById('buyLabel');
  if (!plansWrap || !buyBtn) return;

  const productId = p.komerzaProductId || KMRZA.productId;
  const variants = (p.komerzaVariants && Object.keys(p.komerzaVariants).length) ? p.komerzaVariants : (KMRZA.variants || {});
  const labels = {
    lifetime: `Buy Lifetime — ${p.price || ''}`.trim(),
    monthly: `Buy Monthly — ${p.priceMonthly || ''}`.trim(),
  };
  currentPlan = 'lifetime';
  if (isReal(productId)) buyBtn.setAttribute('data-kmrza-product-id', productId);

  const selectPlan = (plan) => {
    currentPlan = plan;
    plansWrap.querySelectorAll('.plan').forEach(pl => {
      const on = pl.dataset.plan === plan;
      pl.classList.toggle('selected', on);
      const radio = pl.querySelector('input'); if (radio) radio.checked = on;
    });
    if (buyLabel) buyLabel.textContent = labels[plan] || 'Buy';
    const vid = variants[plan];
    if (isReal(vid)) buyBtn.setAttribute('data-kmrza-variant-id', vid);
  };
  // rebind cleanly by cloning nodes to drop old listeners
  plansWrap.querySelectorAll('.plan').forEach(pl => {
    const clone = pl.cloneNode(true); pl.replaceWith(clone);
    clone.addEventListener('click', () => selectPlan(clone.dataset.plan));
  });
  selectPlan('lifetime');

  const newBtn = buyBtn.cloneNode(true); buyBtn.replaceWith(newBtn);
  newBtn.addEventListener('click', (e) => {
    const vid = variants[currentPlan];
    if (window.Komerza && typeof window.Komerza.open === 'function' && isReal(productId)) {
      e.preventDefault();
      const item = { productId };
      if (isReal(vid)) item.variantId = vid;
      window.Komerza.open({ items: [item], theme: KMRZA.theme || 'dark' });
    } else if (!isReal(productId)) {
      e.preventDefault();
      alert('Checkout goes live once the Komerza product ID is set (config.js / product settings).');
    }
  });

  if (window.Komerza && typeof window.Komerza.init === 'function') {
    try { window.Komerza.init(); } catch (_) {}
  }
}

/* ---------- Live stock (backend reads Komerza securely) ---------- */
async function loadLiveStock(product) {
  const el = document.getElementById('pdStock');
  if (!el) return;
  const pid = product && isReal(product.komerzaProductId) ? product.komerzaProductId : '';
  try {
    const url = API_BASE + '/api/store/stock' + (pid ? ('?productId=' + encodeURIComponent(pid)) : '');
    const res = await fetch(url, { headers: apiHeaders(), credentials: 'include' });
    if (!res.ok) return;
    const { stock } = await res.json();
    if (!stock) return;
    el.hidden = false;
    if (stock.hideStock) { el.className = 'pd-stock in'; el.innerHTML = '<span class="dot"></span> In stock'; return; }
    if (!stock.inStock) { el.className = 'pd-stock out'; el.innerHTML = '<span class="dot"></span> Out of stock'; return; }
    const counts = (stock.variants || []).map(v => v.stock).filter(n => typeof n === 'number');
    const total = counts.reduce((a, b) => a + b, 0);
    el.className = 'pd-stock in';
    el.innerHTML = counts.length ? `<span class="dot"></span> ${total} in stock` : '<span class="dot"></span> In stock';
  } catch (_) { /* leave hidden */ }
}

/* ============================================================
   STATUS PAGE
   ============================================================ */
const SERVICES = [
  { name: 'riots.wtf rivals script', desc: 'Core script & loader', state: 'up' },
  { name: 'Checkout & delivery', desc: 'Komerza payments + auto key delivery', state: 'up' },
  { name: 'Update pipeline', desc: 'Daily UD builds', state: 'up' },
  { name: 'Discord bot', desc: 'Support & role sync', state: 'up' },
  { name: 'Website & dashboard', desc: 'Store front + My Keys', state: 'up' },
];
function initStatus() {
  const grid = document.getElementById('statusGrid');
  if (!grid) return;
  const bars = (state) => {
    let out = '';
    for (let i = 0; i < 30; i++) {
      let cls = '';
      if (state === 'warn' && i > 26) cls = 'warn';
      out += `<span class="${cls}"></span>`;
    }
    return out;
  };
  grid.innerHTML = SERVICES.map(s => `
    <div class="status-row">
      <div class="status-name"><strong>${s.name}</strong><small>${s.desc}</small></div>
      <div class="status-bars">${bars(s.state)}</div>
      <span class="status-pill ${s.state}"><span class="dot"></span>${s.state === 'up' ? 'Operational' : 'Degraded'}</span>
    </div>`).join('');
}

/* ============================================================
   REFERRAL PAGE — notify form
   ============================================================ */
function initReferral() {
  const form = document.getElementById('refNotify');
  const note = document.getElementById('refNote');
  if (!form) return;
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    form.style.display = 'none';
    if (note) note.hidden = false;
  });
}

/* ---------- BOOT ---------- */
document.addEventListener('DOMContentLoaded', () => {
  initLoad();
  initNavbar();
  initHero();
  initHomeProducts();
  initQA();
  initEffects();
  initFeatureAccordion();
  initStore();
  initStatus();
  initReferral();
});
