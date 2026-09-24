import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { config } from './config.js';

/**
 * Tiny JSON file store. Good enough for devlog, status and Discord->key
 * link mappings. For higher volume, swap this module for a Railway
 * Postgres/Redis plugin — the exported API stays the same.
 */

const dir = path.resolve(config.dataDir);
try {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  // Write test so we fail loud in logs if the data dir isn't persistent/writable.
  fs.accessSync(dir, fs.constants.W_OK);
  console.log(`[store] data dir ready: ${dir}`);
} catch (e) {
  console.warn(`[store] ! data dir "${dir}" not writable (${e.message}). Data will NOT persist. On Railway attach a Volume and set DATA_DIR to its mount path.`);
}

function file(name) {
  return path.join(dir, `${name}.json`);
}

function read(name, fallback) {
  try {
    const raw = fs.readFileSync(file(name), 'utf8');
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

function write(name, data) {
  const tmp = file(name) + '.tmp';
  try {
    fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
    fs.renameSync(tmp, file(name)); // atomic-ish
  } catch (e) {
    console.error(`[store] ! FAILED to write ${name}.json to ${dir}: ${e.message}. If on Railway, attach a Volume and set DATA_DIR to its mount path.`);
    throw e;
  }
}

// Lightweight self-check used by the diagnostics endpoint.
export function storeHealth() {
  const probe = '_healthcheck';
  const stamp = Date.now();
  let writable = false;
  let error = null;
  try {
    write(probe, { stamp });
    const back = read(probe, null);
    writable = !!back && back.stamp === stamp;
    try { fs.unlinkSync(file(probe)); } catch (_) {}
  } catch (e) { error = e.message; }
  return {
    dataDir: dir,
    writable,
    persistentHint: dir.startsWith('/data') || /volume/i.test(dir),
    files: (() => { try { return fs.readdirSync(dir).filter((f) => f.endsWith('.json')); } catch { return []; } })(),
    error,
  };
}

export const store = {
  // --- Devlog / updates ---
  getDevlog() {
    return read('devlog', []);
  },
  setDevlog(entries) {
    write('devlog', entries);
    return entries;
  },
  addDevlog(entry) {
    const list = read('devlog', []);
    const item = {
      id: Date.now().toString(36),
      title: entry.title,
      body: entry.body,
      tag: entry.tag || 'update',
      createdAt: new Date().toISOString(),
    };
    list.unshift(item);
    write('devlog', list);
    return item;
  },
  removeDevlog(id) {
    const list = read('devlog', []).filter((e) => e.id !== id);
    write('devlog', list);
    return list;
  },

  // --- Status of products/services ---
  getStatus() {
    return read('status', {
      overall: 'operational',
      updatedAt: new Date().toISOString(),
      services: [],
    });
  },
  setStatus(status) {
    const payload = { ...status, updatedAt: new Date().toISOString() };
    write('status', payload);
    return payload;
  },

  // --- Analytics (page views) ---
  // Shape: { total, pages: {name:count}, daily: {'YYYY-MM-DD': count},
  //          referrers: {host:count}, updatedAt }
  trackPageView({ page, referrer } = {}) {
    const a = read('analytics', { total: 0, pages: {}, daily: {}, referrers: {} });
    const day = new Date().toISOString().slice(0, 10);
    const p = String(page || 'unknown').slice(0, 120);
    a.total = (a.total || 0) + 1;
    a.pages[p] = (a.pages[p] || 0) + 1;
    a.daily[day] = (a.daily[day] || 0) + 1;
    if (referrer) {
      let host = 'direct';
      try { host = new URL(referrer).hostname || 'direct'; } catch { host = 'other'; }
      host = host.slice(0, 120);
      a.referrers[host] = (a.referrers[host] || 0) + 1;
    }
    // keep only the last 90 days to bound file size
    const days = Object.keys(a.daily).sort();
    if (days.length > 90) {
      for (const d of days.slice(0, days.length - 90)) delete a.daily[d];
    }
    a.updatedAt = new Date().toISOString();
    write('analytics', a);
    return true;
  },
  getAnalytics() {
    return read('analytics', { total: 0, pages: {}, daily: {}, referrers: {}, updatedAt: null });
  },

  // --- Bio / link pages (real views + likes, shared across all visitors) ---
  // Shape: { <slug>: { views, likes } }
  getBio(slug) {
    const all = read('bio', {});
    const s = String(slug || 'default').slice(0, 60).toLowerCase();
    return all[s] || { views: 0, likes: 0 };
  },
  bumpBioView(slug) {
    const all = read('bio', {});
    const s = String(slug || 'default').slice(0, 60).toLowerCase();
    const b = all[s] || { views: 0, likes: 0 };
    b.views = (b.views || 0) + 1;
    all[s] = b;
    write('bio', all);
    return b;
  },
  setBioLike(slug, liked) {
    const all = read('bio', {});
    const s = String(slug || 'default').slice(0, 60).toLowerCase();
    const b = all[s] || { views: 0, likes: 0 };
    b.likes = Math.max(0, (b.likes || 0) + (liked ? 1 : -1));
    all[s] = b;
    write('bio', all);
    return b;
  },

  // --- Products (admin-managed catalog) ---
  getProducts() {
    return read('products', []);
  },
  addProduct(p) {
    const list = read('products', []);
    const item = {
      id: 'p_' + Date.now().toString(36),
      name: p.name,
      category: p.category || 'General',
      description: p.description || '',
      price: p.price || '',            // display string e.g. "$10"
      priceMonthly: p.priceMonthly || '',
      image: p.image || '',            // Cloudinary URL
      badge: p.badge || '',            // e.g. "Best Seller"
      komerzaProductId: p.komerzaProductId || '',
      komerzaVariants: p.komerzaVariants || {},
      featured: !!p.featured,
      order: typeof p.order === 'number' ? p.order : (list.length + 1),
      createdAt: new Date().toISOString(),
    };
    list.push(item);
    write('products', list);
    return item;
  },
  updateProduct(id, patch) {
    const list = read('products', []);
    const idx = list.findIndex((x) => x.id === id);
    if (idx === -1) return null;
    // whitelist updatable fields
    for (const f of ['name', 'category', 'description', 'price', 'priceMonthly', 'image', 'badge', 'komerzaProductId', 'komerzaVariants', 'featured', 'order']) {
      if (patch[f] !== undefined) list[idx][f] = patch[f];
    }
    write('products', list);
    return list[idx];
  },
  removeProduct(id) {
    const list = read('products', []).filter((x) => x.id !== id);
    write('products', list);
    return list;
  },
  // Ensure the default rivals-script product exists (idempotent upsert by id).
  // Runs on every boot: creates p_rivals if missing, and refreshes its Komerza
  // IDs from config if they were previously blank. Never clobbers admin edits
  // to name/price/description/image once those have been changed.
  seedProducts(seed) {
    const list = read('products', []);
    const existing = list.find((p) => p.id === 'p_rivals');
    if (existing) {
      // Backfill Komerza IDs if the admin hasn't set them yet.
      let changed = false;
      if (!existing.komerzaProductId && seed.komerzaProductId) {
        existing.komerzaProductId = seed.komerzaProductId; changed = true;
      }
      if ((!existing.komerzaVariants || !Object.keys(existing.komerzaVariants).length) && seed.komerzaVariants) {
        existing.komerzaVariants = seed.komerzaVariants; changed = true;
      }
      if (changed) write('products', list);
      return list;
    }
    const item = {
      id: 'p_rivals',
      name: seed.name || 'riots.wtf rivals script',
      category: seed.category || 'Roblox',
      description: seed.description || "The most complete Rivals script on the market — aimbot, silent aim, a full ESP suite, hit effects, skin/cosmetic unlocker, spoofers and more, all in one clean draggable menu. Anti-detection built in and updated & UD every single day.",
      price: seed.price || '$10',
      priceMonthly: seed.priceMonthly || '$4',
      image: seed.image || '',
      badge: seed.badge || 'Best Seller',
      komerzaProductId: seed.komerzaProductId || '',
      komerzaVariants: seed.komerzaVariants || {},
      featured: true,
      order: 1,
      createdAt: new Date().toISOString(),
    };
    list.push(item);
    write('products', list);
    return list;
  },

  // --- Discount codes (admin-managed) ---
  getDiscounts() {
    return read('discounts', []);
  },
  addDiscount(d) {
    const list = read('discounts', []);
    const item = {
      id: 'd_' + Date.now().toString(36),
      code: String(d.code || '').trim().toUpperCase(),
      type: d.type === 'fixed' ? 'fixed' : 'percent', // percent | fixed
      amount: Number(d.amount) || 0,
      note: d.note || '',
      active: d.active !== false,
      createdAt: new Date().toISOString(),
    };
    // replace existing code if duplicate
    const filtered = list.filter((x) => x.code !== item.code);
    filtered.push(item);
    write('discounts', filtered);
    return item;
  },
  removeDiscount(id) {
    const list = read('discounts', []).filter((x) => x.id !== id);
    write('discounts', list);
    return list;
  },

  // --- Tickets (support) ---
  getTickets(discordId) {
    const all = read('tickets', []);
    return discordId ? all.filter((t) => t.discordId === discordId) : all;
  },
  addTicket(t) {
    const list = read('tickets', []);
    const item = {
      id: 't_' + Date.now().toString(36),
      discordId: t.discordId || '',
      username: t.username || '',
      subject: t.subject || 'Support request',
      message: t.message || '',
      status: 'open',
      createdAt: new Date().toISOString(),
      replies: [],
    };
    list.unshift(item);
    write('tickets', list);
    return item;
  },
  replyTicket(id, reply) {
    const list = read('tickets', []);
    const t = list.find((x) => x.id === id);
    if (!t) return null;
    t.replies.push({ from: reply.from || 'user', message: reply.message || '', at: new Date().toISOString() });
    if (reply.status) t.status = reply.status;
    write('tickets', list);
    return t;
  },
  setTicketStatus(id, status) {
    const list = read('tickets', []);
    const t = list.find((x) => x.id === id);
    if (!t) return null;
    t.status = status;
    write('tickets', list);
    return t;
  },

  // --- Referral program ---
  getReferrals() {
    return read('referrals', []);
  },
  getReferralByDiscord(discordId) {
    return read('referrals', []).find((r) => r.discordId === discordId) || null;
  },
  getReferralByCode(code) {
    const c = String(code || '').trim().toUpperCase();
    return read('referrals', []).find((r) => r.code === c) || null;
  },
  addReferral(r) {
    const list = read('referrals', []);
    // one referral account per Discord user
    const existing = list.find((x) => x.discordId === r.discordId);
    if (existing) return existing;
    // generate a unique code from the requested handle (or random)
    const base = String(r.code || r.username || 'ref')
      .toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 10) || 'REF';
    let code = base;
    let n = 1;
    while (list.some((x) => x.code === code)) { code = base + n; n++; }
    const item = {
      id: 'r_' + Date.now().toString(36),
      discordId: r.discordId,
      username: r.username || '',
      email: r.email || '',
      payout: r.payout || '',
      code,
      clicks: 0,
      signups: 0,      // completed referred orders
      earnings: 0,     // commission accrued
      orders: [],      // [{orderId, amount, commission, at}] — prevents double credit
      createdAt: new Date().toISOString(),
    };
    list.push(item);
    write('referrals', list);
    return item;
  },
  // Count a link click, de-duped by a visitor token (session/IP hash) so the
  // number reflects unique visits rather than every page load.
  trackReferralClick(code, visitorToken) {
    const list = read('referrals', []);
    const r = list.find((x) => x.code === String(code || '').trim().toUpperCase());
    if (!r) return null;
    r.clickTokens = Array.isArray(r.clickTokens) ? r.clickTokens : [];
    if (visitorToken) {
      if (r.clickTokens.includes(visitorToken)) { return r; } // already counted
      r.clickTokens.push(visitorToken);
      if (r.clickTokens.length > 5000) r.clickTokens = r.clickTokens.slice(-5000);
    }
    r.clicks = (r.clicks || 0) + 1;
    write('referrals', list);
    return r;
  },
  // Credit a completed referred purchase to the code owner. Idempotent by
  // orderId so webhook retries never double-count.
  creditReferralConversion(code, { orderId, amount, commissionRate } = {}) {
    const list = read('referrals', []);
    const r = list.find((x) => x.code === String(code || '').trim().toUpperCase());
    if (!r) return null;
    r.orders = Array.isArray(r.orders) ? r.orders : [];
    if (orderId && r.orders.some((o) => o.orderId === orderId)) return r; // already credited
    const amt = Number(amount) || 0;
    const rate = typeof commissionRate === 'number' ? commissionRate : 0.10; // default 10%
    const commission = Math.round(amt * rate * 100) / 100;
    r.signups = (r.signups || 0) + 1;
    r.earnings = Math.round(((r.earnings || 0) + commission) * 100) / 100;
    r.orders.push({ orderId: orderId || null, amount: amt, commission, at: new Date().toISOString() });
    if (r.orders.length > 1000) r.orders = r.orders.slice(-1000);
    write('referrals', list);
    return r;
  },
  removeReferral(id) {
    const list = read('referrals', []).filter((x) => x.id !== id);
    write('referrals', list);
    return list;
  },

  // --- Pending Redemptions (referral -> key conversion) ---
  getPendingRedemptions() {
    return read('pendingRedemptions', []);
  },
  getPendingRedemption(id) {
    return read('pendingRedemptions', []).find((r) => r.id === id) || null;
  },
  addPendingRedemption(r) {
    const list = read('pendingRedemptions', []);
    // Check if already pending
    const existing = list.find((x) => x.discordId === r.discordId && x.status === 'pending');
    if (existing) return existing;
    
    const item = {
      id: 'pr_' + Date.now().toString(36),
      discordId: r.discordId,
      referralId: r.referralId,
      keysRequested: r.keysRequested,
      status: 'pending',
      createdAt: new Date().toISOString(),
    };
    list.push(item);
    write('pendingRedemptions', list);
    return item;
  },
  completeRedemption(id) {
    const list = read('pendingRedemptions', []);
    const idx = list.findIndex((x) => x.id === id);
    if (idx === -1) return null;
    list[idx].status = 'completed';
    list[idx].completedAt = new Date().toISOString();
    write('pendingRedemptions', list);
    return list[idx];
  },
  rejectRedemption(id, reason) {
    const list = read('pendingRedemptions', []);
    const idx = list.findIndex((x) => x.id === id);
    if (idx === -1) return null;
    list[idx].status = 'rejected';
    list[idx].rejectedAt = new Date().toISOString();
    list[idx].rejectReason = reason || '';
    write('pendingRedemptions', list);
    return list[idx];
  },

  // --- Discord ID -> key link cache (source of truth is the provider) ---
  getLinks() {
    return read('links', {});
  },
  linkDiscord(discordId, provider, key, discordData = null) {
    const links = read('links', {});
    links[discordId] = { 
      provider, 
      key, 
      linkedAt: new Date().toISOString(),
      discordData: discordData || null
    };
    write('links', links);
    return links[discordId];
  },
  getLink(discordId) {
    return read('links', {})[discordId] || null;
  },
  updateDiscordData(discordId, discordData) {
    const links = read('links', {});
    if (links[discordId]) {
      links[discordId].discordData = discordData;
      links[discordId].updatedAt = new Date().toISOString();
      write('links', links);
      return links[discordId];
    }
    return null;
  },

  // --- Features (shared across products) ---
  getFeatures() {
    return read('features', []);
  },
  addFeature(f) {
    const list = read('features', []);
    const item = {
      id: 'f_' + Date.now().toString(36),
      name: f.name || 'Feature',
      description: f.description || '',
      category: f.category || 'General', // e.g., "Aimbot", "Visuals", "Utility"
      createdAt: new Date().toISOString(),
    };
    list.push(item);
    write('features', list);
    return item;
  },
  updateFeature(id, patch) {
    const list = read('features', []);
    const idx = list.findIndex((x) => x.id === id);
    if (idx === -1) return null;
    for (const f of ['name', 'description', 'category']) {
      if (patch[f] !== undefined) list[idx][f] = patch[f];
    }
    write('features', list);
    return list[idx];
  },
  removeFeature(id) {
    const list = read('features', []).filter((x) => x.id !== id);
    write('features', list);
    return list;
  },

  // --- Product Features (many-to-many relationship) ---
  getProductFeatures(productId) {
    const links = read('productFeatures', {});
    return links[productId] || [];
  },
  setProductFeatures(productId, featureIds) {
    const links = read('productFeatures', {});
    links[productId] = Array.isArray(featureIds) ? featureIds : [];
    write('productFeatures', links);
    return links[productId];
  },
  addProductFeature(productId, featureId) {
    const links = read('productFeatures', {});
    if (!links[productId]) links[productId] = [];
    if (!links[productId].includes(featureId)) {
      links[productId].push(featureId);
    }
    write('productFeatures', links);
    return links[productId];
  },
  removeProductFeature(productId, featureId) {
    const links = read('productFeatures', {});
    if (links[productId]) {
      links[productId] = links[productId].filter((x) => x !== featureId);
    }
    write('productFeatures', links);
    return links[productId];
  },

  // --- Products Catalog ---
  getProducts() {
    let list = read('products', null);
    if (!list || list.length === 0) {
      list = [
        {
          id: 'prod_rivals',
          name: 'riots.wtf rivals script',
          category: 'Roblox',
          description: "The most complete Rivals script on the market — aimbot, silent aim, a full ESP suite, hit effects, skin/cosmetic unlocker, spoofers and more, all in one clean draggable menu. Anti-detection built in and updated & UD every single day.",
          price: '$10',
          priceMonthly: '$4',
          image: 'product1.png',
          badge: 'Undetected',
          featured: true,
          order: 1,
          createdAt: new Date().toISOString(),
        },
        {
          id: 'prod_siege',
          name: 'riots.wtf siege script',
          category: 'Rainbow Six Siege',
          description: "Premium Rainbow Six Siege private software. Featuring recoil compensation, stream-proof visual ESP, customizable smoothing aimbot, and internal kernel protection.",
          price: '$15',
          priceMonthly: '$7',
          image: 'seige.png',
          badge: 'Undetected',
          featured: true,
          order: 2,
          createdAt: new Date().toISOString(),
        }
      ];
      write('products', list);
    }
    return list;
  },
  getProduct(id) {
    return this.getProducts().find((p) => p.id === id) || null;
  },
  addProduct(p) {
    const list = this.getProducts();
    const item = {
      id: 'prod_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      name: p.name || 'Product',
      category: p.category || 'General',
      description: p.description || '',
      price: p.price || '',
      priceMonthly: p.priceMonthly || '',
      image: p.image || '',
      badge: p.badge || 'In stock',
      featured: p.featured ?? true,
      order: p.order ?? list.length,
      createdAt: new Date().toISOString(),
    };
    list.push(item);
    write('products', list);
    return item;
  },
  updateProduct(id, patch) {
    const list = this.getProducts();
    const idx = list.findIndex((x) => x.id === id);
    if (idx === -1) return null;
    const allowed = ['name', 'category', 'description', 'price', 'priceMonthly', 'image', 'badge', 'featured', 'order'];
    for (const f of allowed) {
      if (patch[f] !== undefined) list[idx][f] = patch[f];
    }
    list[idx].updatedAt = new Date().toISOString();
    write('products', list);
    return list[idx];
  },
  removeProduct(id) {
    const list = this.getProducts().filter((x) => x.id !== id);
    write('products', list);
    return list;
  },

  // --- Categories ---
  getCategories() {
    let list = read('categories', null);
    if (!list || list.length === 0) {
      list = [
        {
          id: 'cat_r6siege',
          name: 'Rainbow Six Siege',
          slug: 'r6siege',
          icon: '🎯',
          image: 'seige.png',
          description: 'Rainbow Six Siege scripts, bypasses and tools',
          createdAt: new Date().toISOString(),
        },
        {
          id: 'cat_roblox',
          name: 'Roblox',
          slug: 'roblox',
          icon: '🎮',
          image: 'roblox.png',
          description: 'Roblox scripts, executors and exploits',
          createdAt: new Date().toISOString(),
        },
        {
          id: 'cat_eft',
          name: 'Escape from Tarkov',
          slug: 'eft',
          icon: '🎖️',
          image: 'seige.png',
          description: 'Tarkov tools, radar & external software',
          createdAt: new Date().toISOString(),
        },
        {
          id: 'cat_rust',
          name: 'Rust',
          slug: 'rust',
          icon: '🛡️',
          image: 'roblox.png',
          description: 'Rust recoil, scripts and external software',
          createdAt: new Date().toISOString(),
        }
      ];
      write('categories', list);
    }
    return list;
  },
  addCategory(c) {
    const list = this.getCategories();
    const item = {
      id: 'cat_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      name: c.name || 'Category',
      slug: (c.slug || c.name || '').toLowerCase().replace(/[^a-z0-9]/g, ''),
      icon: c.icon || '📦',
      image: c.image || '',
      description: c.description || '',
      createdAt: new Date().toISOString(),
    };
    list.push(item);
    write('categories', list);
    return item;
  },
  updateCategory(id, patch) {
    const list = this.getCategories();
    const idx = list.findIndex((x) => x.id === id);
    if (idx === -1) return null;
    for (const f of ['name', 'slug', 'icon', 'image', 'description']) {
      if (patch[f] !== undefined) list[idx][f] = patch[f];
    }
    list[idx].updatedAt = new Date().toISOString();
    write('categories', list);
    return list[idx];
  },
  removeCategory(id) {
    const list = this.getCategories().filter((x) => x.id !== id);
    write('categories', list);
    return list;
  },

  // --- Client Logs (from RiotsSeige: key verifications, logins, usage) ---
  getLogs(filter = {}) {
    const all = read('logs', []);
    let result = all;
    if (filter.type) result = result.filter((l) => l.type === filter.type);
    if (filter.keyId) result = result.filter((l) => l.keyId === filter.keyId);
    if (filter.from) result = result.filter((l) => new Date(l.timestamp) >= new Date(filter.from));
    if (filter.to) result = result.filter((l) => new Date(l.timestamp) <= new Date(filter.to));
    // Most recent first, with pagination support
    result = result.reverse();
    if (filter.limit) result = result.slice(0, filter.limit);
    if (filter.skip) result = result.slice(filter.skip);
    return result;
  },
  addLog(log) {
    const list = read('logs', []);
    const item = {
      id: 'log_' + Date.now().toString(36),
      type: log.type || 'info', // 'info', 'verification', 'login', 'execution', 'error'
      keyId: log.keyId || null,
      hwid: log.hwid || null,
      message: log.message || '',
      details: log.details || {},
      timestamp: new Date().toISOString(),
    };
    list.unshift(item);
    // Keep only last 10000 logs to bound file size
    if (list.length > 10000) list.splice(10000);
    write('logs', list);
    return item;
  },

  // --- Cracks / Security Events ---
  getCracks(filter = {}) {
    const all = read('cracks', []);
    let result = all;
    if (filter.status) result = result.filter((c) => c.status === filter.status);
    if (filter.type) result = result.filter((c) => c.type === filter.type);
    if (filter.from) result = result.filter((c) => new Date(c.timestamp) >= new Date(filter.from));
    if (filter.to) result = result.filter((c) => new Date(c.timestamp) <= new Date(filter.to));
    result = result.reverse();
    if (filter.limit) result = result.slice(0, filter.limit);
    if (filter.skip) result = result.slice(filter.skip);
    return result;
  },
  addCrack(crack) {
    const list = read('cracks', []);
    const item = {
      id: 'crk_' + Date.now().toString(36),
      type: crack.type || 'suspicious', // 'tamper', 'unauthorized_mod', 'key_reuse', 'suspicious', 'injection', 'memory_mod'
      severity: crack.severity || 'medium', // 'low', 'medium', 'high', 'critical'
      status: crack.status || 'open', // 'open', 'investigating', 'resolved', 'false_positive'
      keyId: crack.keyId || null,
      hwid: crack.hwid || null,
      ip: crack.ip || null,
      source: crack.source || 'client', // 'client', 'server', 'manual'
      description: crack.description || '',
      evidence: crack.evidence || {}, // fingerprints, file hashes, process names, etc.
      notes: crack.notes || '',
      resolvedAt: null,
      timestamp: new Date().toISOString(),
    };
    list.unshift(item);
    // Keep only last 5000 crack records
    if (list.length > 5000) list.splice(5000);
    write('cracks', list);
    return item;
  },
  updateCrack(id, patch) {
    const list = read('cracks', []);
    const idx = list.findIndex((x) => x.id === id);
    if (idx === -1) return null;
    for (const f of ['status', 'notes', 'severity']) {
      if (patch[f] !== undefined) list[idx][f] = patch[f];
    }
    if (patch.status === 'resolved' && !list[idx].resolvedAt) {
      list[idx].resolvedAt = new Date().toISOString();
    }
    write('cracks', list);
    return list[idx];
  },

  // --- Statistics / Dashboard summary ---
  getDashboardStats() {
    const products = read('products', []);
    const logs = read('logs', []);
    const cracks = read('cracks', []);
    const features = read('features', []);
    const categories = read('categories', []);

    const now = new Date();
    const oneDay = 24 * 60 * 60 * 1000;
    const today = new Date(now.getTime() - (now.getHours() * 60 * 60 * 1000));
    
    const todaysLogs = logs.filter((l) => new Date(l.timestamp) >= today).length;
    const openCracks = cracks.filter((c) => c.status === 'open').length;
    const highSevCracks = cracks.filter((c) => c.severity === 'high' || c.severity === 'critical').length;

    return {
      totalProducts: products.length,
      totalFeatures: features.length,
      totalCategories: categories.length,
      totalLogs: logs.length,
      todaysLogs,
      totalCracks: cracks.length,
      openCracks,
      highSeverityCracks: highSevCracks,
      lastLogTime: logs[0]?.timestamp || null,
      lastCrackTime: cracks[0]?.timestamp || null,
    };
  },

  // --- External Keys (for RiotsSeige and other C++ / desktop tools) ---
  getExternalKeys(filter = {}) {
    let list = read('externalKeys', []);
    if (filter.key) {
      const q = String(filter.key).trim().toLowerCase();
      list = list.filter((k) => k.key.toLowerCase().includes(q));
    }
    if (filter.discordId) {
      list = list.filter((k) => k.discordId === filter.discordId);
    }
    if (filter.hwid) {
      list = list.filter((k) => k.hwid && k.hwid.toLowerCase().includes(String(filter.hwid).toLowerCase()));
    }
    if (filter.blacklisted !== undefined && filter.blacklisted !== '') {
      const b = String(filter.blacklisted) === 'true';
      list = list.filter((k) => (k.blacklisted ? true : false) === b);
    }
    if (filter.expired !== undefined && filter.expired !== '') {
      const now = Math.floor(Date.now() / 1000);
      const isExp = String(filter.expired) === 'true';
      list = list.filter((k) => isExp ? (k.expire && k.expire < now) : (!k.expire || k.expire >= now));
    }
    if (filter.unassigned !== undefined && filter.unassigned !== '') {
      const isUn = String(filter.unassigned) === 'true';
      list = list.filter((k) => isUn ? !k.discordId : !!k.discordId);
    }
    if (filter.product) {
      list = list.filter((k) => (k.product || 'RiotsSeige').toLowerCase() === String(filter.product).toLowerCase());
    }
    return list;
  },
  getExternalKey(key) {
    const list = read('externalKeys', []);
    const k = String(key || '').trim().toUpperCase();
    return list.find((x) => x.key.toUpperCase() === k) || null;
  },
  generateExternalKeys({ amount = 1, expire, note = '', product = 'RiotsSeige', prefix = 'RIOTS-EXT' }) {
    const list = read('externalKeys', []);
    const count = Math.max(1, Math.min(300, Number(amount) || 1));
    const now = Math.floor(Date.now() / 1000);
    const expireTimestamp = expire ? (now + Number(expire)) : null;
    const generated = [];

    for (let i = 0; i < count; i++) {
      const rand1 = crypto.randomBytes(3).toString('hex').toUpperCase();
      const rand2 = crypto.randomBytes(3).toString('hex').toUpperCase();
      const rand3 = crypto.randomBytes(3).toString('hex').toUpperCase();
      const keyStr = `${prefix}-${rand1}-${rand2}-${rand3}`;
      
      const item = {
        key: keyStr,
        product: product || 'RiotsSeige',
        discordId: null,
        discordData: null,
        note: note || '',
        created: now,
        expire: expireTimestamp,
        activated: false,
        activatedAt: null,
        hwid: null,
        hwidResetCount: 0,
        lastHwidReset: null,
        executionCount: 0,
        lastExecution: null,
        blacklisted: false,
        blacklistReason: '',
      };
      list.push(item);
      generated.push(item);
    }
    write('externalKeys', list);
    return generated;
  },
  assignExternalKey({ discordId, expire, note = '', product = 'RiotsSeige', discordData = null, prefix = 'RIOTS-EXT' }) {
    const list = read('externalKeys', []);
    const now = Math.floor(Date.now() / 1000);
    const expireTimestamp = expire ? (now + Number(expire)) : null;
    const rand1 = crypto.randomBytes(3).toString('hex').toUpperCase();
    const rand2 = crypto.randomBytes(3).toString('hex').toUpperCase();
    const rand3 = crypto.randomBytes(3).toString('hex').toUpperCase();
    const keyStr = `${prefix}-${rand1}-${rand2}-${rand3}`;

    const item = {
      key: keyStr,
      product: product || 'RiotsSeige',
      discordId: String(discordId).trim(),
      discordData: discordData || null,
      note: note || '',
      created: now,
      expire: expireTimestamp,
      activated: false,
      activatedAt: null,
      hwid: null,
      hwidResetCount: 0,
      lastHwidReset: null,
      executionCount: 0,
      lastExecution: null,
      blacklisted: false,
      blacklistReason: '',
    };
    list.push(item);
    write('externalKeys', list);
    return item;
  },
  updateExternalKey(key, patch) {
    const list = read('externalKeys', []);
    const k = String(key || '').trim().toUpperCase();
    const idx = list.findIndex((x) => x.key.toUpperCase() === k);
    if (idx === -1) return null;
    for (const f of ['expire', 'note', 'blacklisted', 'blacklistReason', 'discordId', 'discordData', 'hwid', 'activated', 'activatedAt', 'executionCount', 'lastExecution', 'hwidResetCount', 'lastHwidReset', 'product']) {
      if (patch[f] !== undefined) list[idx][f] = patch[f];
    }
    write('externalKeys', list);
    return list[idx];
  },
  resetExternalHwid(key) {
    const list = read('externalKeys', []);
    const k = String(key || '').trim().toUpperCase();
    const idx = list.findIndex((x) => x.key.toUpperCase() === k);
    if (idx === -1) return null;
    list[idx].hwid = null;
    list[idx].hwidResetCount = (list[idx].hwidResetCount || 0) + 1;
    list[idx].lastHwidReset = new Date().toISOString();
    write('externalKeys', list);
    return list[idx];
  },
  blacklistExternalKey(key, reason = 'Blacklisted by admin') {
    return this.updateExternalKey(key, { blacklisted: true, blacklistReason: reason });
  },
  unblacklistExternalKey(key) {
    return this.updateExternalKey(key, { blacklisted: false, blacklistReason: '' });
  },
  deleteExternalKey(key) {
    const k = String(key || '').trim().toUpperCase();
    const list = read('externalKeys', []).filter((x) => x.key.toUpperCase() !== k);
    write('externalKeys', list);
    return true;
  },
};
