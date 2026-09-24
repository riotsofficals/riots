import { Router } from 'express';
import { z } from 'zod';
import { requireAuth, requireAdmin } from '../auth.js';
import { store } from '../store.js';

const router = Router();
const asyncH = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// Validation schemas
const productSchema = z.object({
  name: z.string().min(1).max(100),
  category: z.string().max(100).optional().default('General'),
  description: z.string().max(1000).optional().default(''),
  price: z.string().max(50).optional().default(''),
  priceMonthly: z.string().max(50).optional(),
  image: z.string().max(500).optional().or(z.literal('')),
  badge: z.string().max(100).optional(),
  featured: z.boolean().optional(),
  order: z.number().optional(),
});

const featureSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional().default(''),
  category: z.string().max(100).optional().default('General'),
});

const categorySchema = z.object({
  name: z.string().min(1).max(100),
  slug: z.string().max(100).optional(),
  icon: z.string().max(50).optional(),
  image: z.string().max(500).optional().or(z.literal('')),
  description: z.string().max(500).optional().default(''),
});

/* ============================================================
   DASHBOARD STATS (declared first to avoid :id collisions)
   ============================================================ */

router.get(
  '/dashboard/stats',
  requireAdmin,
  asyncH(async (req, res) => {
    const stats = store.getDashboardStats();
    res.json({ success: true, stats });
  })
);

/* ============================================================
   CATEGORY ROUTES (/api/products/categories)
   ============================================================ */

router.get(
  '/categories',
  asyncH(async (req, res) => {
    const categories = store.getCategories();
    res.json({ success: true, categories });
  })
);

router.post(
  '/categories',
  requireAdmin,
  asyncH(async (req, res) => {
    const data = categorySchema.parse(req.body);
    const category = store.addCategory(data);
    res.status(201).json({ success: true, category });
  })
);

router.patch(
  '/categories/:id',
  requireAdmin,
  asyncH(async (req, res) => {
    const data = categorySchema.partial().parse(req.body);
    const updated = store.updateCategory(req.params.id, data);
    if (!updated) return res.status(404).json({ success: false, message: 'Category not found.' });
    res.json({ success: true, category: updated });
  })
);

router.delete(
  '/categories/:id',
  requireAdmin,
  asyncH(async (req, res) => {
    store.removeCategory(req.params.id);
    res.json({ success: true, message: 'Category deleted.' });
  })
);

/* ============================================================
   FEATURE ROUTES (/api/products/all and /api/products/features)
   ============================================================ */

const getFeaturesHandler = asyncH(async (req, res) => {
  const features = store.getFeatures();
  res.json({ success: true, features });
});

const addFeatureHandler = asyncH(async (req, res) => {
  const data = featureSchema.parse(req.body);
  const feature = store.addFeature(data);
  res.status(201).json({ success: true, feature });
});

const updateFeatureHandler = asyncH(async (req, res) => {
  const data = featureSchema.partial().parse(req.body);
  const updated = store.updateFeature(req.params.id, data);
  if (!updated) return res.status(404).json({ success: false, message: 'Feature not found.' });
  res.json({ success: true, feature: updated });
});

const deleteFeatureHandler = asyncH(async (req, res) => {
  store.removeFeature(req.params.id);
  res.json({ success: true, message: 'Feature deleted.' });
});

router.get('/all', getFeaturesHandler);
router.get('/features', getFeaturesHandler);
router.post('/all', requireAdmin, addFeatureHandler);
router.post('/features', requireAdmin, addFeatureHandler);
router.patch('/all/:id', requireAdmin, updateFeatureHandler);
router.patch('/features/:id', requireAdmin, updateFeatureHandler);
router.delete('/all/:id', requireAdmin, deleteFeatureHandler);
router.delete('/features/:id', requireAdmin, deleteFeatureHandler);

/* ============================================================
   PRODUCT CATALOG ROUTES
   ============================================================ */

// GET /api/products — list all products
router.get(
  '/',
  asyncH(async (req, res) => {
    const products = store.getProducts();
    const enriched = products.map((p) => ({
      ...p,
      features: store.getProductFeatures(p.id),
    }));
    res.json({ success: true, products: enriched });
  })
);

// POST /api/products — create product (admin only)
router.post(
  '/',
  requireAdmin,
  asyncH(async (req, res) => {
    const data = productSchema.parse(req.body);
    const product = store.addProduct(data);
    res.status(201).json({ success: true, product });
  })
);

// PUT /api/products/:id/features — set all features for product (admin only)
router.put(
  '/:id/features',
  requireAdmin,
  asyncH(async (req, res) => {
    const { featureIds } = z.object({ featureIds: z.array(z.string()) }).parse(req.body);
    const features = store.setProductFeatures(req.params.id, featureIds);
    res.json({ success: true, features });
  })
);

// POST /api/products/:id/features — add feature to product (admin only)
router.post(
  '/:id/features',
  requireAdmin,
  asyncH(async (req, res) => {
    const { featureId } = z.object({ featureId: z.string() }).parse(req.body);
    const features = store.addProductFeature(req.params.id, featureId);
    res.json({ success: true, features });
  })
);

// DELETE /api/products/:id/features/:featureId — remove feature (admin only)
router.delete(
  '/:id/features/:featureId',
  requireAdmin,
  asyncH(async (req, res) => {
    const features = store.removeProductFeature(req.params.id, req.params.featureId);
    res.json({ success: true, features });
  })
);

// GET /api/products/:id — get single product with features (after fixed routes)
router.get(
  '/:id',
  asyncH(async (req, res) => {
    const products = store.getProducts();
    const product = products.find((p) => p.id === req.params.id);
    if (!product) return res.status(404).json({ success: false, message: 'Product not found.' });
    res.json({
      success: true,
      product: {
        ...product,
        features: store.getProductFeatures(product.id),
      },
    });
  })
);

// PATCH /api/products/:id — update product (admin only)
router.patch(
  '/:id',
  requireAdmin,
  asyncH(async (req, res) => {
    const data = productSchema.partial().parse(req.body);
    const updated = store.updateProduct(req.params.id, data);
    if (!updated) return res.status(404).json({ success: false, message: 'Product not found.' });
    res.json({
      success: true,
      product: {
        ...updated,
        features: store.getProductFeatures(updated.id),
      },
    });
  })
);

// DELETE /api/products/:id — delete product (admin only)
router.delete(
  '/:id',
  requireAdmin,
  asyncH(async (req, res) => {
    store.removeProduct(req.params.id);
    res.json({ success: true, message: 'Product deleted.' });
  })
);

export default router;
