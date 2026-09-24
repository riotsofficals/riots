import { Router } from 'express';
import { z } from 'zod';
import { komerza } from '../komerza.js';
import { store } from '../store.js';
import { requireAdmin, requireAuth } from '../auth.js';
import { getProvider, DEFAULT_PROVIDER } from '../providers/index.js';

const router = Router();
const asyncH = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/* ============================================================
   LIVE STOCK (public) — backend reads Komerza with the secret key
   ============================================================ */
router.get(
  '/stock',
  asyncH(async (req, res) => {
    const stock = await komerza.getStock(req.query.productId);
    res.json({ success: true, stock });
  })
);

/* ============================================================
   PRODUCTS — public read, admin write
   ============================================================ */

// Public: the store catalog
router.get('/products', (req, res) => {
  const products = store.getProducts().sort((a, b) => (a.order || 0) - (b.order || 0));
  res.json({ success: true, products });
});

const productSchema = z.object({
  name: z.string().trim().min(1).max(120),
  category: z.string().trim().max(60).optional(),
  description: z.string().max(2000).optional(),
  price: z.string().max(40).optional(),
  priceMonthly: z.string().max(40).optional(),
  image: z.string().max(500).optional().or(z.literal('')),
  badge: z.string().max(40).optional(),
  komerzaProductId: z.string().max(80).optional(),
  komerzaVariants: z.record(z.string()).optional(),
  featured: z.boolean().optional(),
  order: z.number().int().optional(),
});

router.post('/products', requireAdmin, (req, res) => {
  const data = productSchema.parse(req.body);
  const item = store.addProduct(data);
  res.json({ success: true, product: item });
});

router.patch('/products/:id', requireAdmin, (req, res) => {
  const data = productSchema.partial().parse(req.body);
  const updated = store.updateProduct(req.params.id, data);
  if (!updated) return res.status(404).json({ success: false, message: 'Product not found.' });
  res.json({ success: true, product: updated });
});

router.delete('/products/:id', requireAdmin, (req, res) => {
  const products = store.removeProduct(req.params.id);
  res.json({ success: true, products });
});

/* ============================================================
   SCRIPTS — fully automatic from LuaProt. No admin catalog.
   We read the account's hubs (script id + name) and the user's
   keys, then return exactly the scripts each key unlocks with a
   ready-to-run loader. The loader URL uses the LuaProt script id.
   ============================================================ */

const LOADER_BASE = 'https://luaprot.net/api/v2/loaders/get/';

// Admin: read-only view of every hub + script on the account.
router.get(
  '/scripts',
  requireAdmin,
  asyncH(async (req, res) => {
    const provider = getProvider(DEFAULT_PROVIDER);
    const hubs = (await provider.getHubs())?.hubs || [];
    res.json({ success: true, hubs });
  })
);

// User: the scripts THIS user can load, scoped by their key(s).
// A key with no limitedScripts unlocks every script in its hub.
router.get(
  '/scripts/mine',
  requireAuth,
  asyncH(async (req, res) => {
    const provider = getProvider(DEFAULT_PROVIDER);

    let keys = [];
    try {
      const result = await provider.fetchKeys({ discordId: req.user.discordId });
      keys = result.keys || [];
    } catch (_) { keys = []; }

    const active = keys.filter((k) => k && !k.blacklisted);
    if (!active.length) {
      return res.json({ success: true, scripts: [], hasKey: false });
    }

    // Pull hubs+scripts so we can resolve names and enumerate hub scripts.
    let hubs = [];
    try { hubs = (await provider.getHubs())?.hubs || []; } catch (_) { hubs = []; }
    const hubById = new Map(hubs.map((h) => [String(h.id), h]));
    const scriptById = new Map();
    for (const h of hubs) {
      for (const s of (h.scripts || [])) {
        scriptById.set(String(s.id), { id: String(s.id), name: s.name, hubId: String(h.id), hubName: h.name });
      }
    }

    // Build a de-duped list of {scriptId -> key} the user can run.
    const out = new Map(); // scriptId -> { ...script, key }
    for (const k of active) {
      const hub = hubById.get(String(k.hubId));
      const hubScripts = hub ? (hub.scripts || []) : [];
      const limited = Array.isArray(k.limitedScripts) && k.limitedScripts.length;
      const grantedIds = limited
        ? k.limitedScripts.map(String)
        : hubScripts.map((s) => String(s.id)); // unrestricted = all scripts in the key's hub
      for (const sid of grantedIds) {
        if (out.has(sid)) continue;
        const meta = scriptById.get(sid) || { id: sid, name: 'Script ' + sid, hubId: String(k.hubId), hubName: k.hubName || '' };
        out.set(sid, {
          id: meta.id,
          name: meta.name,
          hubName: meta.hubName,
          key: k.key || '',
          loaderUrl: LOADER_BASE + meta.id,
        });
      }
    }

    const scripts = [...out.values()];
    res.json({ success: true, scripts, hasKey: true });
  })
);

/* ============================================================
   DISCOUNT CODES — admin only
   ============================================================ */
router.get('/discounts', requireAdmin, (req, res) => {
  res.json({ success: true, discounts: store.getDiscounts() });
});

const discountSchema = z.object({
  code: z.string().trim().min(3).max(32),
  type: z.enum(['percent', 'fixed']).optional(),
  amount: z.number().min(0).max(100000),
  note: z.string().max(120).optional(),
  active: z.boolean().optional(),
});
router.post('/discounts', requireAdmin, (req, res) => {
  const data = discountSchema.parse(req.body);
  const item = store.addDiscount(data);
  res.json({ success: true, discount: item });
});
router.delete('/discounts/:id', requireAdmin, (req, res) => {
  const discounts = store.removeDiscount(req.params.id);
  res.json({ success: true, discounts });
});

/* ============================================================
   SALES (admin) — real orders pulled live from Komerza
   ============================================================ */
router.get(
  '/sales',
  requireAdmin,
  asyncH(async (req, res) => {
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 100, 1), 250);
    const summary = await komerza.getSalesSummary({ limit });
    res.json({ success: true, sales: summary });
  })
);

/* ============================================================
   TICKETS — users create/view their own; admin sees all
   ============================================================ */
const ticketSchema = z.object({
  subject: z.string().trim().min(1).max(120),
  message: z.string().trim().min(1).max(4000),
});

// user: my tickets
router.get('/tickets/mine', requireAuth, (req, res) => {
  res.json({ success: true, tickets: store.getTickets(req.user.discordId) });
});
// user: open a ticket
router.post('/tickets', requireAuth, (req, res) => {
  const data = ticketSchema.parse(req.body);
  const t = store.addTicket({
    discordId: req.user.discordId,
    username: req.user.username || req.user.globalName || '',
    subject: data.subject,
    message: data.message,
  });
  res.json({ success: true, ticket: t });
});
// user: reply to own ticket
router.post('/tickets/:id/reply', requireAuth, (req, res) => {
  const owned = store.getTickets(req.user.discordId).some((t) => t.id === req.params.id);
  if (!owned) return res.status(404).json({ success: false, message: 'Ticket not found.' });
  const message = String(req.body.message || '').trim();
  if (!message) return res.status(400).json({ success: false, message: 'Message required.' });
  const t = store.replyTicket(req.params.id, { from: 'user', message });
  res.json({ success: true, ticket: t });
});

// admin: all tickets
router.get('/tickets', requireAdmin, (req, res) => {
  res.json({ success: true, tickets: store.getTickets() });
});
// admin: reply / set status
router.post('/tickets/:id/admin-reply', requireAdmin, (req, res) => {
  const message = String(req.body.message || '').trim();
  const status = req.body.status;
  const t = store.replyTicket(req.params.id, { from: 'staff', message, status });
  if (!t) return res.status(404).json({ success: false, message: 'Ticket not found.' });
  res.json({ success: true, ticket: t });
});
router.patch('/tickets/:id/status', requireAdmin, (req, res) => {
  const t = store.setTicketStatus(req.params.id, req.body.status === 'closed' ? 'closed' : 'open');
  if (!t) return res.status(404).json({ success: false, message: 'Ticket not found.' });
  res.json({ success: true, ticket: t });
});

export default router;
