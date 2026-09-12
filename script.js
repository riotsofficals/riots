/* ============================================================
   riots.wtf — site scripts (multi-page)
   ============================================================ */

/* ---------- Lucide icons ---------- */
function renderIcons() {
  if (window.lucide && typeof window.lucide.createIcons === 'function') {
    window.lucide.createIcons();
  }
}

/* ---------- Custom dropdowns (public pages) ----------
   Wraps native <select> in a styled widget, keeps the real select in sync. */
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
  trigger.type = 'button'; trigger.className = 'csel-trigger';
  const label = document.createElement('span'); label.className = 'csel-label';
  const caret = document.createElement('i'); caret.setAttribute('data-lucide', 'chevron-down');
  trigger.appendChild(label); trigger.appendChild(caret);
  const menu = document.createElement('div'); menu.className = 'csel-menu';
  const syncLabel = () => {
    const o = sel.options[sel.selectedIndex];
    label.textContent = o ? o.textContent : '';
    menu.querySelectorAll('.csel-opt').forEach((el) => el.classList.toggle('sel', el.dataset.value === sel.value));
  };
  [...sel.options].forEach((o) => {
    const item = document.createElement('button');
    item.type = 'button'; item.className = 'csel-opt'; item.dataset.value = o.value; item.textContent = o.textContent;
    item.addEventListener('click', (e) => {
      e.stopPropagation();
      sel.value = o.value;
      sel.dispatchEvent(new Event('change', { bubbles: true }));
      syncLabel(); wrap.classList.remove('open');
    });
    menu.appendChild(item);
  });
  trigger.addEventListener('click', (e) => {
    e.stopPropagation();
    const willOpen = !wrap.classList.contains('open');
    closeAllSelects(wrap); wrap.classList.toggle('open', willOpen);
  });
  sel.classList.add('csel-native');
  sel.parentNode.insertBefore(wrap, sel.nextSibling);
  wrap.appendChild(trigger); wrap.appendChild(menu);
  syncLabel();
  sel.addEventListener('change', syncLabel);
}
function enhanceSelects(root = document) {
  root.querySelectorAll('select:not([data-enhanced])').forEach(enhanceSelect);
  renderIcons();
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

(function captureSessionToken() {
  const m = location.hash.match(/[#&]token=([^&]+)/);
  if (m) {
    try { localStorage.setItem('riots_session_token', decodeURIComponent(m[1])); } catch (_) {}
    history.replaceState(null, '', location.pathname + location.search);
  }
})();
function getSessionToken() {
  try { return localStorage.getItem('riots_session_token') || ''; } catch (_) { return ''; }
}
function apiHeaders(extra = {}) {
  const h = { ...extra };
  if (CLIENT_TOKEN) h['x-client-token'] = CLIENT_TOKEN;
  const st = getSessionToken();
  if (st) h['Authorization'] = 'Bearer ' + st;
  return h;
}

/* ---------- Komerza Embed SDK ----------
   Loaded from checkout.komerza.com/embed/embed.iife.js — exposes window.Komerza
   with init() and open({items, theme, couponCode}). Opens a modal, no email
   prompt needed (Komerza collects it). */
function komerzaSDK() { return window.Komerza || null; }
let _komerzaInited = false;
function komerzaInit() {
  const k = komerzaSDK();
  if (k && !_komerzaInited && typeof k.init === 'function') {
    try { k.init(); _komerzaInited = true; } catch (_) {}
  }
  return k;
}
// Remember a ?ref= affiliate code so it rides along to Komerza checkout.
function storedAffiliateCode() {
  try {
    const fromUrl = new URLSearchParams(location.search).get('ref');
    if (fromUrl) localStorage.setItem('riots_ref_code', fromUrl);
    return localStorage.getItem('riots_ref_code') || '';
  } catch (_) { return ''; }
}
// Open the checkout modal for a set of items. Each item: {productId, variantId, quantity}.
// opts may include couponCode (discount) — affiliateCode (referral) is auto-attached.
function komerzaOpen(items, opts = {}) {
  const k = komerzaInit();
  if (!k || typeof k.open !== 'function') {
    alert('Checkout is still loading — try again in a second.');
    return false;
  }
  const payload = { items, theme: (KMRZA && KMRZA.theme) || 'dark', ...opts };
  const ref = storedAffiliateCode();
  if (ref && !payload.affiliateCode) payload.affiliateCode = ref;
  k.open(payload);
  return true;
}
function isValidEmail(e) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e); }

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
      <button class="store-card-add" data-add aria-label="Add to cart"><i data-lucide="shopping-cart"></i> Add to cart</button>
    </article>`).join('');
  grid.querySelectorAll('.store-card').forEach(card => {
    const p = STORE_PRODUCTS.find(x => x.id === card.dataset.id);
    card.addEventListener('click', (e) => {
      if (e.target.closest('[data-add]')) return; // add button handled below
      if (p) openProduct(p);
    });
    const addBtn = card.querySelector('[data-add]');
    if (addBtn) addBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!p) return;
      const vid = (p.komerzaVariants && (p.komerzaVariants.lifetime || p.komerzaVariants.monthly)) || '';
      const pid = p.komerzaProductId || KMRZA.productId;
      if (!isReal(pid) || !isReal(vid)) {
        alert('This product isn\u2019t connected to Komerza yet.');
        return;
      }
      addToCart({
        id: pid + ':' + vid,
        productId: pid, variantId: vid,
        name: p.name + (p.komerzaVariants && p.komerzaVariants.lifetime ? ' \u2014 Lifetime' : ''),
        price: p.price || p.priceMonthly,
        image: p.image,
      });
      openCart();
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
  let buyBtn = document.getElementById('buyBtn');
  if (!plansWrap || !buyBtn) return;

  const productId = p.komerzaProductId || KMRZA.productId;
  const variants = (p.komerzaVariants && Object.keys(p.komerzaVariants).length) ? p.komerzaVariants : (KMRZA.variants || {});
  const labels = {
    lifetime: `Buy Lifetime — ${p.price || ''}`.trim(),
    monthly: `Buy Monthly — ${p.priceMonthly || ''}`.trim(),
  };

  // Clone the buy button FIRST to drop old listeners, THEN query the label
  // from the live button (fixes the label not updating after re-render).
  const freshBtn = buyBtn.cloneNode(true);
  buyBtn.replaceWith(freshBtn);
  buyBtn = freshBtn;
  const getLabel = () => buyBtn.querySelector('#buyLabel');

  currentPlan = 'lifetime';

  const selectPlan = (plan) => {
    currentPlan = plan;
    plansWrap.querySelectorAll('.plan').forEach(pl => {
      const on = pl.dataset.plan === plan;
      pl.classList.toggle('selected', on);
      const radio = pl.querySelector('input'); if (radio) radio.checked = on;
    });
    const lbl = getLabel();
    if (lbl) lbl.textContent = labels[plan] || 'Buy';
  };

  // rebind plan cards cleanly
  plansWrap.querySelectorAll('.plan').forEach(pl => {
    const clone = pl.cloneNode(true); pl.replaceWith(clone);
    clone.addEventListener('click', () => selectPlan(clone.dataset.plan));
  });
  // hide the monthly plan if the product has no monthly variant
  const monthlyCard = plansWrap.querySelector('.plan[data-plan="monthly"]');
  if (monthlyCard) monthlyCard.hidden = !isReal(variants.monthly);

  selectPlan('lifetime');

  buyBtn.addEventListener('click', (e) => {
    e.preventDefault();
    const vid = variants[currentPlan];
    if (!isReal(productId) || !isReal(vid)) {
      alert('This product isn\u2019t connected to Komerza yet. Add its product + variant IDs in the admin dashboard (or config.js).');
      return;
    }
    komerzaOpen([{ productId, variantId: vid, quantity: 1 }]);
  });

  komerzaInit();
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
   CART
   ============================================================ */
const CART_KEY = 'riots_cart';
let CART = [];
function cartLoad() { try { CART = JSON.parse(localStorage.getItem(CART_KEY)) || []; } catch { CART = []; } }
function cartSave() { localStorage.setItem(CART_KEY, JSON.stringify(CART)); updateCartBadge(); }
function cartCount() { return CART.reduce((n, i) => n + (i.qty || 1), 0); }
function priceNumOf(s) { const n = parseFloat(String(s).replace(/[^\d.]/g, '')); return isNaN(n) ? 0 : n; }

function addToCart(item) {
  const found = CART.find((i) => i.id === item.id);
  if (found) found.qty = (found.qty || 1) + 1;
  else CART.push({ ...item, qty: 1 });
  cartSave();
  renderCart();
}
function removeFromCart(id) { CART = CART.filter((i) => i.id !== id); cartSave(); renderCart(); }
function setQty(id, qty) {
  const it = CART.find((i) => i.id === id);
  if (!it) return;
  it.qty = Math.max(1, qty);
  cartSave(); renderCart();
}

function ensureCartUI() {
  if (document.getElementById('cartDrawer')) return;
  const wrap = document.createElement('div');
  wrap.innerHTML = `
    <div class="cart-overlay" id="cartOverlay" hidden></div>
    <aside class="cart-drawer" id="cartDrawer" hidden aria-label="Cart">
      <div class="cart-head">
        <h3>Your cart</h3>
        <button class="cart-close" id="cartClose" aria-label="Close"><i data-lucide="x"></i></button>
      </div>
      <div class="cart-items" id="cartItems"></div>
      <div class="cart-foot">
        <div class="cart-total-row"><span>Total</span><span id="cartTotal">$0.00</span></div>
        <input type="text" id="cartCoupon" placeholder="Discount code (optional)" />
        <button class="btn btn-gradient wide" id="cartCheckout"><i data-lucide="lock"></i><span>Checkout</span></button>
        <p class="cart-note" id="cartMsg"></p>
      </div>
    </aside>`;
  document.body.appendChild(wrap);
  document.getElementById('cartClose').addEventListener('click', closeCart);
  document.getElementById('cartOverlay').addEventListener('click', closeCart);
  document.getElementById('cartCheckout').addEventListener('click', cartCheckout);
  renderIcons();
}
function openCart() { ensureCartUI(); renderCart(); document.getElementById('cartOverlay').hidden = false; document.getElementById('cartDrawer').hidden = false; document.body.style.overflow = 'hidden'; }
function closeCart() { const d = document.getElementById('cartDrawer'), o = document.getElementById('cartOverlay'); if (d) d.hidden = true; if (o) o.hidden = true; document.body.style.overflow = ''; }

function renderCart() {
  ensureCartUI();
  const box = document.getElementById('cartItems');
  const totalEl = document.getElementById('cartTotal');
  if (!CART.length) {
    box.innerHTML = `<div class="cart-empty">Your cart is empty.</div>`;
    totalEl.textContent = '$0.00';
  } else {
    box.innerHTML = CART.map((i) => `
      <div class="cart-item" data-id="${esc(i.id)}">
        <img src="${esc(i.image || 'product1.png')}" alt="" />
        <div class="ci-main">
          <div class="ci-name">${esc(i.name)}</div>
          <div class="ci-price">${esc(i.price || '')}</div>
        </div>
        <div class="ci-qty">
          <button data-act="dec">-</button><span>${i.qty || 1}</span><button data-act="inc">+</button>
        </div>
        <button class="ci-remove" data-act="rm" aria-label="Remove"><i data-lucide="trash-2"></i></button>
      </div>`).join('');
    const total = CART.reduce((s, i) => s + priceNumOf(i.price) * (i.qty || 1), 0);
    totalEl.textContent = '$' + total.toFixed(2);
    box.querySelectorAll('.cart-item').forEach((row) => {
      const id = row.dataset.id;
      row.querySelector('[data-act="inc"]').addEventListener('click', () => setQty(id, (CART.find(x => x.id === id).qty || 1) + 1));
      row.querySelector('[data-act="dec"]').addEventListener('click', () => setQty(id, (CART.find(x => x.id === id).qty || 1) - 1));
      row.querySelector('[data-act="rm"]').addEventListener('click', () => removeFromCart(id));
    });
  }
  renderIcons();
}

function cartCheckout() {
  const msg = document.getElementById('cartMsg');
  const coupon = document.getElementById('cartCoupon').value.trim();
  msg.textContent = '';
  if (!CART.length) { msg.textContent = 'Your cart is empty.'; return; }
  const items = CART
    .filter((i) => isReal(i.productId) && isReal(i.variantId))
    .map((i) => ({ productId: i.productId, variantId: i.variantId, quantity: i.qty || 1 }));
  if (!items.length) { msg.textContent = 'These items aren\u2019t connected to Komerza yet.'; return; }
  const opts = coupon ? { couponCode: coupon } : {};
  const ok = komerzaOpen(items, opts);
  if (ok) { msg.textContent = 'Opening secure checkout...'; closeCart(); }
}

function updateCartBadge() {
  document.querySelectorAll('[data-cart-badge]').forEach((b) => {
    const n = cartCount();
    b.textContent = n;
    b.hidden = n === 0;
  });
}
function initCart() {
  cartLoad();
  updateCartBadge();
  // wire any nav cart buttons to open the drawer
  document.querySelectorAll('[data-open-cart]').forEach((el) => {
    el.addEventListener('click', (e) => { e.preventDefault(); openCart(); });
  });
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
function statusBars(state) {
  let out = '';
  for (let i = 0; i < 30; i++) {
    let cls = '';
    if (state === 'warn' && i > 26) cls = 'warn';
    if (state === 'down' && i > 20) cls = 'down';
    out += `<span class="${cls}"></span>`;
  }
  return out;
}
function statusPillLabel(state) {
  return { up: 'Operational', warn: 'Degraded', down: 'Down', maintenance: 'Maintenance' }[state] || 'Operational';
}
function renderStatusGrid(grid, services) {
  grid.innerHTML = services.map((s) => {
    const state = ['up', 'warn', 'down', 'maintenance'].includes(s.state) ? s.state : 'up';
    return `
    <div class="status-row">
      <div class="status-name"><strong>${esc(s.name)}</strong><small>${esc(s.desc || '')}</small></div>
      <div class="status-bars">${statusBars(state)}</div>
      <span class="status-pill ${state}"><span class="dot"></span>${statusPillLabel(state)}</span>
    </div>`;
  }).join('');
}
async function initStatus() {
  const grid = document.getElementById('statusGrid');
  if (!grid) return;
  // Render the static baseline immediately, then hydrate from the backend so
  // admin-published status shows publicly.
  renderStatusGrid(grid, SERVICES);
  try {
    const res = await fetch(API_BASE + '/api/content/status', { headers: apiHeaders(), credentials: 'include' });
    if (!res.ok) return;
    const { status } = await res.json();
    if (status && Array.isArray(status.services) && status.services.length) {
      renderStatusGrid(grid, status.services);
    }
  } catch (_) { /* keep the static baseline */ }
}

/* ============================================================
   REFERRAL PAGE — real signup + dashboard
   ============================================================ */
async function refApi(path, opts = {}) {
  const res = await fetch(API_BASE + path, {
    method: opts.method || 'GET',
    headers: apiHeaders(opts.body ? { 'Content-Type': 'application/json' } : {}),
    credentials: 'include',
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.success === false) {
    const err = new Error(data.message || 'Request failed'); err.status = res.status; throw err;
  }
  return data;
}

function refLink(code) {
  return location.origin + '/products.html?ref=' + encodeURIComponent(code);
}

function renderReferralDashboard(panel, ref) {
  const link = refLink(ref.code);
  panel.innerHTML = `
    <div class="ref-card">
      <div class="ref-card-head">
        <h3>Your referral link</h3>
        <span class="admin-badge">active</span>
      </div>
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
      <p class="ref-note">Share your link anywhere. Your code is <strong>${esc(ref.code)}</strong>.</p>
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
      <div class="ref-card-head"><h3>Join the program</h3></div>
      <p class="ref-note">Pick a code (letters/numbers) and add where we should send payouts.</p>
      <input type="text" id="refWantedCode" placeholder="Preferred code (e.g. RIOTSVIP)" maxlength="20" />
      <input type="text" id="refPayout" placeholder="Payout method (PayPal / crypto / etc.)" maxlength="200" />
      <button class="btn btn-gradient wide" id="refJoin" type="button"><span>Create my link</span><i data-lucide="arrow-right"></i></button>
      <p class="ref-error" id="refErr" hidden></p>
    </div>`;
  renderIcons();
  panel.querySelector('#refJoin').addEventListener('click', async () => {
    const code = panel.querySelector('#refWantedCode').value.trim();
    const payout = panel.querySelector('#refPayout').value.trim();
    const errEl = panel.querySelector('#refErr');
    errEl.hidden = true;
    try {
      const { referral } = await refApi('/api/referral/signup', { method: 'POST', body: { code, payout } });
      renderReferralDashboard(panel, referral);
    } catch (e) {
      errEl.textContent = e.message || 'Could not sign up.'; errEl.hidden = false;
    }
  });
}

function renderReferralLogin(panel) {
  panel.innerHTML = `
    <div class="ref-card">
      <div class="ref-card-head"><h3>Sign in to join</h3></div>
      <p class="ref-note">Connect your Discord to get a referral link tied to your account.</p>
      <a class="btn btn-gradient wide" href="${API_BASE}/auth/discord?return=${encodeURIComponent(location.href.split('#')[0])}">
        <svg class="brand" viewBox="0 0 127.14 96.36" fill="currentColor" style="width:18px;height:18px"><path d="M107.7 8.07A105.15 105.15 0 0 0 81.47 0a72.06 72.06 0 0 0-3.36 6.83 97.68 97.68 0 0 0-29.11 0A72.37 72.37 0 0 0 45.64 0a105.89 105.89 0 0 0-26.25 8.09C2.79 32.65-1.71 56.6.54 80.21a105.73 105.73 0 0 0 32.17 16.15 77.7 77.7 0 0 0 6.89-11.11 68.42 68.42 0 0 1-10.85-5.18c.91-.66 1.8-1.34 2.66-2a75.57 75.57 0 0 0 64.32 0c.87.71 1.76 1.39 2.66 2a68.68 68.68 0 0 1-10.87 5.19 77 77 0 0 0 6.89 11.1 105.25 105.25 0 0 0 32.19-16.14c2.64-27.38-4.51-51.11-18.9-72.15ZM42.45 65.69C36.18 65.69 31 60 31 53s5-12.74 11.43-12.74S54 46 53.89 53s-5.05 12.69-11.44 12.69Zm42.24 0C78.41 65.69 73.25 60 73.25 53s5-12.74 11.44-12.74S96.23 46 96.12 53s-5.04 12.69-11.43 12.69Z"/></svg>
        <span>Sign up with Discord</span>
      </a>
    </div>`;
  renderIcons();
}

async function initReferral() {
  const panel = document.getElementById('refPanel');
  if (!panel) return;
  try {
    const { referral } = await refApi('/api/referral/me');
    if (referral) renderReferralDashboard(panel, referral);
    else renderReferralSignup(panel);
  } catch (e) {
    if (e.status === 401) renderReferralLogin(panel);
    else panel.innerHTML = `<div class="ref-card"><p class="ref-error">Couldn't reach the referral service. ${esc(e.message)}</p></div>`;
  }
}

/* Track a ?ref=CODE visit once per browser session (any page). */
function trackReferralVisit() {
  const code = new URLSearchParams(location.search).get('ref');
  if (!code) return;
  const key = 'riots_ref_tracked';
  try { if (sessionStorage.getItem(key) === code) return; sessionStorage.setItem(key, code); } catch (_) {}
  refApi('/api/referral/track', { method: 'POST', body: { code } }).catch(() => {});
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
  initCart();
  initStatus();
  initReferral();
  trackReferralVisit();
  enhanceSelects();
});
