import fs from 'fs';
import path from 'path';
import { config } from './config.js';

/**
 * Tiny JSON file store. Good enough for devlog, status and Discord->key
 * link mappings. For higher volume, swap this module for a Railway
 * Postgres/Redis plugin — the exported API stays the same.
 */

const dir = path.resolve(config.dataDir);
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

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
