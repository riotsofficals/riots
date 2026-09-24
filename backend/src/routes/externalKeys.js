import { Router } from 'express';
import { z } from 'zod';
import { requireAuth, requireAdmin } from '../auth.js';
import { store } from '../store.js';
import { getProvider, DEFAULT_PROVIDER } from '../providers/index.js';

const router = Router();
const asyncH = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/* ============================================================
   EXTERNAL KEY VERIFICATION (for RiotsSeige C++ client)
   POST /api/external-keys/verify
   ============================================================ */

const verifySchema = z.object({
  key: z.string().trim().min(3).max(128),
  hwid: z.string().trim().max(128).optional(),
});

router.post(
  '/verify',
  asyncH(async (req, res) => {
    const { key, hwid } = verifySchema.parse(req.body);

    // 1. Check our dedicated externalKeys store first
    let found = store.getExternalKey(key);
    let isExternalStore = true;

    // 2. If not found in external store, check LuaProt provider as fallback
    if (!found) {
      try {
        const provider = getProvider(DEFAULT_PROVIDER);
        const info = await provider.keyInfo({ key });
        if (info && info.key) {
          found = info.key;
          isExternalStore = false;
        }
      } catch (_) {}
    }

    if (!found) {
      store.addLog({
        type: 'verification',
        keyId: null,
        hwid: hwid || null,
        message: 'Key verification failed — key not found',
        details: { key: key.substring(0, 10) + '...' },
      });
      return res.status(404).json({ valid: false, message: 'Key not found.' });
    }

    // Check blacklist
    if (found.blacklisted) {
      store.addLog({
        type: 'verification',
        keyId: found.key,
        hwid: hwid || null,
        message: 'Key verification failed — blacklisted',
        details: { reason: found.blacklistReason || 'Blacklisted' },
      });
      return res.status(403).json({ valid: false, message: 'Key is blacklisted.' });
    }

    // Check expiration
    const nowSec = Math.floor(Date.now() / 1000);
    if (found.expire && found.expire < nowSec) {
      store.addLog({
        type: 'verification',
        keyId: found.key,
        hwid: hwid || null,
        message: 'Key verification failed — expired',
      });
      return res.status(403).json({ valid: false, message: 'Key has expired.' });
    }

    // Check HWID
    if (found.hwid && hwid && found.hwid.toLowerCase() !== hwid.toLowerCase()) {
      store.addLog({
        type: 'verification',
        keyId: found.key,
        hwid: hwid,
        message: 'Key verification failed — HWID mismatch',
        details: { expectedHwid: found.hwid.substring(0, 12) + '...' },
      });
      return res.status(403).json({ valid: false, message: 'HWID mismatch. Reset your HWID from the dashboard.' });
    }

    // First activation / HWID binding
    const firstActivation = !found.activated || !found.hwid;
    if (isExternalStore) {
      const patch = {
        executionCount: (found.executionCount || 0) + 1,
        lastExecution: new Date().toISOString(),
      };
      if (firstActivation && hwid) {
        patch.activated = true;
        patch.activatedAt = new Date().toISOString();
        patch.hwid = hwid;
      }
      store.updateExternalKey(found.key, patch);
    } else {
      // LuaProt provider update
      try {
        const provider = getProvider(DEFAULT_PROVIDER);
        if (firstActivation && hwid) {
          await provider.updateKey({ key }, { hwid, activated: true });
        }
        await provider.incrementExecutionCount({ key });
      } catch (_) {}
    }

    store.addLog({
      type: 'verification',
      keyId: found.key,
      hwid: hwid || found.hwid || null,
      message: firstActivation ? 'External key activated for the first time' : 'External key verified successfully',
      details: { product: found.product || 'RiotsSeige' },
    });

    res.json({
      valid: true,
      firstActivation,
      key: {
        product: found.product || 'RiotsSeige',
        expire: found.expire || null,
        executionCount: (found.executionCount || 0) + 1,
      },
    });
  })
);

/* ============================================================
   USER ROUTES (require Discord auth)
   ============================================================ */

router.get(
  '/mine',
  requireAuth,
  asyncH(async (req, res) => {
    const keys = store.getExternalKeys({ discordId: req.user.discordId });
    res.json({
      success: true,
      keys: keys.map((k) => ({
        key: k.key,
        product: k.product || 'RiotsSeige',
        note: k.note,
        expire: k.expire,
        created: k.created,
        activated: k.activated,
        blacklisted: k.blacklisted,
        hwid: !!k.hwid,
        hwidResetCount: k.hwidResetCount,
        executionCount: k.executionCount,
        lastExecution: k.lastExecution,
      })),
    });
  })
);

router.post(
  '/register',
  requireAuth,
  asyncH(async (req, res) => {
    const { key } = z.object({ key: z.string().trim().min(3).max(128) }).parse(req.body);
    const found = store.getExternalKey(key);

    if (!found) {
      return res.status(404).json({ success: false, message: 'External key not found.' });
    }
    if (found.discordId && found.discordId !== req.user.discordId) {
      return res.status(409).json({ success: false, message: 'This key is already linked to another Discord account.' });
    }

    store.updateExternalKey(key, {
      discordId: req.user.discordId,
      discordData: {
        id: req.user.discordId,
        username: req.user.username,
        global_name: req.user.globalName,
        avatar: req.user.avatar,
      },
    });

    res.json({ success: true, message: 'External key linked to your account.' });
  })
);

router.post(
  '/reset-hwid',
  requireAuth,
  asyncH(async (req, res) => {
    const userKeys = store.getExternalKeys({ discordId: req.user.discordId });
    if (!userKeys.length) {
      return res.status(404).json({ success: false, message: 'No external keys found for your account.' });
    }

    // Reset HWID for all user's external keys
    userKeys.forEach((k) => store.resetExternalHwid(k.key));
    res.json({ success: true, message: 'HWID reset successfully for your external software key.' });
  })
);

/* ============================================================
   ADMIN ROUTES (require admin key)
   ============================================================ */

router.get(
  '/admin/list',
  requireAdmin,
  asyncH(async (req, res) => {
    const { key, discordId, hwid, blacklisted, expired, unassigned, product } = req.query;
    const keys = store.getExternalKeys({ key, discordId, hwid, blacklisted, expired, unassigned, product });
    res.json({ success: true, keys, total: keys.length });
  })
);

const genSchema = z.object({
  amount: z.number().int().min(1).max(300).default(1),
  expire: z.number().int().min(60).optional(),
  note: z.string().max(200).optional(),
  product: z.string().max(100).default('RiotsSeige'),
  prefix: z.string().max(30).default('RIOTS-EXT'),
});

router.post(
  '/admin/generate',
  requireAdmin,
  asyncH(async (req, res) => {
    const body = genSchema.parse(req.body);
    const created = store.generateExternalKeys(body);
    res.json({
      success: true,
      count: created.length,
      keys: created.map((k) => k.key),
      items: created,
    });
  })
);

const assignSchema = z.object({
  discordId: z.string().regex(/^\d{5,25}$/),
  expire: z.number().int().min(60).optional(),
  note: z.string().max(200).optional(),
  product: z.string().max(100).default('RiotsSeige'),
  prefix: z.string().max(30).default('RIOTS-EXT'),
});

router.post(
  '/admin/assign',
  requireAdmin,
  asyncH(async (req, res) => {
    const body = assignSchema.parse(req.body);
    const link = store.getLink(body.discordId);
    const created = store.assignExternalKey({
      ...body,
      discordData: link?.discordData || null,
    });
    res.json({ success: true, key: created.key, item: created });
  })
);

router.patch(
  '/admin/update',
  requireAdmin,
  asyncH(async (req, res) => {
    const { key, ...patch } = req.body;
    if (!key) return res.status(400).json({ success: false, message: 'Key is required.' });
    const updated = store.updateExternalKey(key, patch);
    if (!updated) return res.status(404).json({ success: false, message: 'Key not found.' });
    res.json({ success: true, item: updated });
  })
);

router.post(
  '/admin/blacklist',
  requireAdmin,
  asyncH(async (req, res) => {
    const { key, blacklisted, reason } = req.body;
    if (!key) return res.status(400).json({ success: false, message: 'Key is required.' });
    const updated = blacklisted === false
      ? store.unblacklistExternalKey(key)
      : store.blacklistExternalKey(key, reason || 'Blacklisted by admin');
    if (!updated) return res.status(404).json({ success: false, message: 'Key not found.' });
    res.json({ success: true, item: updated });
  })
);

router.post(
  '/admin/reset-hwid',
  requireAdmin,
  asyncH(async (req, res) => {
    const { key } = req.body;
    if (!key) return res.status(400).json({ success: false, message: 'Key is required.' });
    const updated = store.resetExternalHwid(key);
    if (!updated) return res.status(404).json({ success: false, message: 'Key not found.' });
    res.json({ success: true, item: updated });
  })
);

router.delete(
  '/admin/delete',
  requireAdmin,
  asyncH(async (req, res) => {
    const key = req.query.key || req.body?.key;
    if (!key) return res.status(400).json({ success: false, message: 'Key is required.' });
    store.deleteExternalKey(key);
    res.json({ success: true, message: 'External key deleted.' });
  })
);

export default router;
