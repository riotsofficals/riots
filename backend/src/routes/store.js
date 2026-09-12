import { Router } from 'express';
import { z } from 'zod';
import { komerza } from '../komerza.js';
import { store } from '../store.js';
import { requireAdmin } from '../auth.js';

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

export default router;
