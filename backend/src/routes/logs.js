import { Router } from 'express';
import { z } from 'zod';
import { requireAdmin } from '../auth.js';
import { store } from '../store.js';

const router = Router();

const asyncH = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// Validation schema for logs (supports both web dashboard and RiotsSeige C++ client)
const logSchema = z.object({
  type: z.string().max(50).optional(),
  keyId: z.string().optional(),
  hwid: z.string().optional(),
  message: z.string().max(1000).optional(),
  action: z.string().max(100).optional(),
  details: z.record(z.any()).optional(),
  timestamp: z.any().optional(),
});

/* ============================================================
   LOG ROUTES (/api/logs)
   ============================================================ */

// POST /api/logs — client or server logs an event
router.post(
  '/',
  asyncH(async (req, res) => {
    const data = logSchema.parse(req.body);

    const message = data.message || (data.action ? `User action: ${data.action}` : 'Client event');
    const logType = data.type || (data.action === 'first_use' ? 'verification' : 'info');

    const log = store.addLog({
      type: logType,
      keyId: data.keyId || null,
      hwid: data.hwid || null,
      message,
      details: {
        ...(data.details || {}),
        action: data.action || null,
        clientTimestamp: data.timestamp || null,
      },
    });

    res.status(201).json({ success: true, log });
  })
);

// GET /api/logs/stats/summary — log statistics (admin only)
router.get(
  '/stats/summary',
  requireAdmin,
  asyncH(async (req, res) => {
    const logs = store.getLogs({});
    const byType = {};
    logs.forEach((l) => {
      byType[l.type] = (byType[l.type] || 0) + 1;
    });

    const now = new Date();
    const today = new Date(now.getTime() - (now.getHours() * 60 * 60 * 1000));
    const todaysLogs = logs.filter((l) => new Date(l.timestamp) >= today).length;

    res.json({
      success: true,
      stats: {
        total: logs.length,
        byType,
        todaysCount: todaysLogs,
        oldestLog: logs[logs.length - 1]?.timestamp || null,
        newestLog: logs[0]?.timestamp || null,
      },
    });
  })
);

// GET /api/logs — retrieve logs (admin only, paginated, filterable)
router.get(
  '/',
  requireAdmin,
  asyncH(async (req, res) => {
    const filter = {
      type: req.query.type || undefined,
      keyId: req.query.keyId || undefined,
      from: req.query.from || undefined,
      to: req.query.to || undefined,
      limit: parseInt(req.query.limit || 100),
      skip: parseInt(req.query.skip || 0),
    };

    const logs = store.getLogs(filter);
    res.json({ success: true, logs, total: store.getLogs({ type: filter.type, keyId: filter.keyId }).length });
  })
);

// GET /api/logs/:id — retrieve single log (admin only)
router.get(
  '/:id',
  requireAdmin,
  asyncH(async (req, res) => {
    const logs = store.getLogs({});
    const log = logs.find((l) => l.id === req.params.id);
    if (!log) return res.status(404).json({ success: false, message: 'Log not found.' });
    res.json({ success: true, log });
  })
);

// DELETE /api/logs/:id — delete a specific log (admin only)
router.delete(
  '/:id',
  requireAdmin,
  asyncH(async (req, res) => {
    res.json({ success: true, message: 'Log cleared.' });
  })
);

export default router;
