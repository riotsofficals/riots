import { Router } from 'express';
import { z } from 'zod';
import { komerza } from '../komerza.js';
import { store } from '../store.js';
import { requireAdmin, requireAuth } from '../auth.js';

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
  image: z.string().url().max(500).optional().or(z.literal('')),
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
