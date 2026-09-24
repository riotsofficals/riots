import { Router } from 'express';
import { z } from 'zod';
import { requireAdmin } from '../auth.js';
import { store } from '../store.js';

const router = Router();

const asyncH = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// Validation schema for cracks (supports RiotsSeige C++ report_crack_simple and admin reports)
const crackSchema = z.object({
  type: z.string().max(100).optional(),
  severity: z.enum(['low', 'medium', 'high', 'critical']).optional(),
  status: z.enum(['open', 'investigating', 'resolved', 'false_positive']).optional(),
  keyId: z.string().optional(),
  hwid: z.string().optional(),
  tool: z.string().max(200).optional(), // sent by RiotsSeige
  tool_name: z.string().max(200).optional(),
  description: z.string().max(1000).optional(),
  evidence: z.record(z.any()).optional(),
  notes: z.string().max(1000).optional(),
  timestamp: z.any().optional(),
});

/* ============================================================
   CRACK / SECURITY EVENT ROUTES (/api/cracks)
   ============================================================ */

// POST /api/cracks — report a crack/security event (called by RiotsSeige C++ or admin)
router.post(
  '/',
  asyncH(async (req, res) => {
    const data = crackSchema.parse(req.body);

    const toolName = data.tool || data.tool_name || '';
    const desc = data.description || (toolName ? `Detected crack/tamper tool: ${toolName}` : 'Security event detected');
    const crackType = data.type === 'crack_attempt' ? 'tamper' : (data.type || 'suspicious');

    const crack = store.addCrack({
      type: crackType,
      severity: data.severity || 'high',
      keyId: data.keyId || null,
      hwid: data.hwid || null,
      ip: req.ip || null,
      source: 'client',
      description: desc,
      evidence: {
        toolName: toolName || null,
        clientTimestamp: data.timestamp || null,
        ...(data.evidence || {}),
      },
    });

    res.status(201).json({ success: true, crack });
  })
);

// GET /api/cracks/stats/summary — crack statistics (admin only)
router.get(
  '/stats/summary',
  requireAdmin,
  asyncH(async (req, res) => {
    const cracks = store.getCracks({});
    const total = cracks.length;
    const open = cracks.filter((c) => c.status === 'open').length;
    const criticalCount = cracks.filter((c) => c.severity === 'critical' || c.severity === 'high').length;
    const byType = {};
    cracks.forEach((c) => {
      byType[c.type] = (byType[c.type] || 0) + 1;
    });

    res.json({
      success: true,
      stats: {
        total,
        open,
        criticalCount,
        byType,
        newest: cracks[0]?.timestamp || null,
      },
    });
  })
);

// GET /api/cracks — retrieve cracks (admin only, paginated, filterable)
router.get(
  '/',
  requireAdmin,
  asyncH(async (req, res) => {
    const filter = {
      status: req.query.status || undefined,
      type: req.query.type || undefined,
      from: req.query.from || undefined,
      to: req.query.to || undefined,
      limit: parseInt(req.query.limit || 50),
      skip: parseInt(req.query.skip || 0),
    };

    const cracks = store.getCracks(filter);
    res.json({ success: true, cracks, total: store.getCracks({ status: filter.status, type: filter.type }).length });
  })
);

// GET /api/cracks/:id — retrieve single crack (admin only)
router.get(
  '/:id',
  requireAdmin,
  asyncH(async (req, res) => {
    const cracks = store.getCracks({});
    const crack = cracks.find((c) => c.id === req.params.id);
    if (!crack) return res.status(404).json({ success: false, message: 'Crack not found.' });
    res.json({ success: true, crack });
  })
);

// PATCH /api/cracks/:id — update crack status/notes (admin only)
router.patch(
  '/:id',
  requireAdmin,
  asyncH(async (req, res) => {
    const patch = {};
    if (req.body.status) patch.status = req.body.status;
    if (req.body.notes !== undefined) patch.notes = req.body.notes;
    if (req.body.severity) patch.severity = req.body.severity;

    const crack = store.updateCrack(req.params.id, patch);
    if (!crack) return res.status(404).json({ success: false, message: 'Crack not found.' });
    res.json({ success: true, crack });
  })
);

export default router;
