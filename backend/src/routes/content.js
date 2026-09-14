import { Router } from 'express';
import { z } from 'zod';
import { requireAdmin } from '../auth.js';
import { store, storeHealth } from '../store.js';

const router = Router();

/* ============================================================
   DEVLOG / UPDATES  — public read, admin write
   ============================================================ */

// Public: anyone on the dashboard can read the updates feed
router.get('/devlog', (req, res) => {
  res.json({ success: true, entries: store.getDevlog() });
});

const devlogSchema = z.object({
  title: z.string().trim().min(1).max(120),
  body: z.string().trim().min(1).max(4000),
  tag: z.enum(['update', 'fix', 'new', 'notice']).optional(),
});

// Admin: add a devlog entry
router.post('/devlog', requireAdmin, (req, res) => {
  const entry = devlogSchema.parse(req.body);
  const item = store.addDevlog(entry);
  res.json({ success: true, entry: item });
});

// Admin: delete a devlog entry
router.delete('/devlog/:id', requireAdmin, (req, res) => {
  const entries = store.removeDevlog(req.params.id);
  res.json({ success: true, entries });
});

/* ============================================================
   STATUS  — public read, admin write
   ============================================================ */

router.get('/status', (req, res) => {
  res.json({ success: true, status: store.getStatus() });
});

const statusSchema = z.object({
  overall: z.enum(['operational', 'degraded', 'partial', 'down', 'maintenance']),
  services: z.array(
    z.object({
      name: z.string().trim().min(1).max(80),
      desc: z.string().max(160).optional().default(''),
      state: z.enum(['up', 'warn', 'down', 'maintenance']),
    })
  ),
});

// Admin: replace the full status payload
router.put('/status', requireAdmin, (req, res) => {
  const parsed = statusSchema.parse(req.body);
  const saved = store.setStatus(parsed);
  res.json({ success: true, status: saved });
});

/* ============================================================
   ANALYTICS — public write (page view), admin read
   ============================================================ */

const pageViewSchema = z.object({
  page: z.string().trim().min(1).max(120),
  referrer: z.string().max(400).optional().or(z.literal('')),
});

// Public: record a page view. Fire-and-forget from the frontend.
router.post('/pageview', (req, res) => {
  const parsed = pageViewSchema.parse(req.body);
  store.trackPageView({ page: parsed.page, referrer: parsed.referrer || '' });
  res.json({ success: true });
});

// Admin: full analytics payload
router.get('/analytics', requireAdmin, (req, res) => {
  res.json({ success: true, analytics: store.getAnalytics() });
});

// Admin: storage diagnostics — confirms whether data actually persists.
router.get('/storage-health', requireAdmin, (req, res) => {
  res.json({ success: true, ...storeHealth() });
});

export default router;
