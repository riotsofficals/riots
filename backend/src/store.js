import fs from 'fs';
import path from 'path';
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
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, file(name)); // atomic-ish
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
      signups: 0,
      earnings: 0,
      createdAt: new Date().toISOString(),
    };
    list.push(item);
    write('referrals', list);
    return item;
  },
  trackReferralClick(code) {
    const list = read('referrals', []);
    const r = list.find((x) => x.code === String(code || '').trim().toUpperCase());
    if (!r) return null;
    r.clicks = (r.clicks || 0) + 1;
    write('referrals', list);
    return r;
  },
  removeReferral(id) {
    const list = read('referrals', []).filter((x) => x.id !== id);
    write('referrals', list);
    return list;
  },

  // --- Discord ID -> key link cache (source of truth is the provider) ---
  getLinks() {
    return read('links', {});
  },
  linkDiscord(discordId, provider, key) {
    const links = read('links', {});
    links[discordId] = { provider, key, linkedAt: new Date().toISOString() };
    write('links', links);
    return links[discordId];
  },
  getLink(discordId) {
    return read('links', {})[discordId] || null;
  },
};
