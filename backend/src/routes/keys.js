import { Router } from 'express';
import { z } from 'zod';
import { requireAuth, requireAdmin } from '../auth.js';
import { getProvider, listProviders, DEFAULT_PROVIDER } from '../providers/index.js';
import { store } from '../store.js';

const router = Router();

const asyncH = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/** Strip anything sensitive before sending a key object to a normal user. */
function publicKeyView(k) {
  if (!k) return null;
  return {
    key: k.key,
    hubName: k.hubName,
    note: k.note,
    expire: k.expire,
    created: k.created,
    activated: k.activated,
    blacklisted: k.blacklisted,
    hwid: k.hwid ? true : false, // just whether an HWID is linked, not the value
    hwidResetCount: k.hwidResetCount,
    executionCount: k.executionCount,
    lastExecution: k.lastExecution,
    discord: k.discordData
      ? { id: k.discordData.id, username: k.discordData.username, globalName: k.discordData.global_name }
      : null,
  };
}

// List available providers (for admin UI dropdown)
router.get('/providers', (req, res) => {
  res.json({ success: true, providers: listProviders(), default: DEFAULT_PROVIDER });
});

/* ============================================================
   EXTERNAL KEY VERIFICATION (for RiotsSeige C++ client)
   ============================================================ */

const externalVerifySchema = z.object({
  key: z.string().trim().min(6).max(128),
  hwid: z.string().trim().max(128).optional(),
});

// POST /api/external-keys/verify — Verify key for external loader
// Checks our external store first, falls back to LuaProt
router.post(
  '/external-keys/verify',
  asyncH(async (req, res) => {
    const { key, hwid } = externalVerifySchema.parse(req.body);
    
    // Check external store first
    let found = store.getExternalKey(key);
    let isExternalStore = true;

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
        message: 'Key verification failed - key not found',
        details: { key: key.substring(0, 8) + '...' },
      });
      return res.status(404).json({ valid: false, message: 'Key not found.' });
    }
    
    if (found.blacklisted) {
      store.addLog({
        type: 'verification',
        keyId: found.key,
        hwid: hwid || null,
        message: 'Key verification failed - blacklisted',
        details: { reason: found.blacklistReason },
      });
      return res.status(403).json({ valid: false, message: 'Key is blacklisted.' });
    }
    
    // Check expiry
    const nowSec = Math.floor(Date.now() / 1000);
    if (found.expire && found.expire < nowSec) {
      store.addLog({
        type: 'verification',
        keyId: found.key,
        hwid: hwid || null,
        message: 'Key verification failed - expired',
      });
      return res.status(403).json({ valid: false, message: 'Key has expired.' });
    }
    
    // HWID check
    if (found.hwid && hwid && found.hwid.toLowerCase() !== hwid.toLowerCase()) {
      store.addLog({
        type: 'verification',
        keyId: found.key,
        hwid: hwid,
        message: 'Key verification failed - HWID mismatch',
        details: { expectedHwid: found.hwid.substring(0, 12) + '...' },
      });
      return res.status(403).json({ valid: false, message: 'HWID mismatch. Reset your HWID from the dashboard.' });
    }
    
    // First activation - link HWID
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
      message: firstActivation ? 'External key activated for first time' : 'External key verified successfully',
      details: { product: found.product || found.hubName || 'RiotsSeige' },
    });
    
    res.json({
      valid: true,
      firstActivation,
      key: {
        hubName: found.product || found.hubName || 'RiotsSeige',
        expire: found.expire || null,
        executionCount: (found.executionCount || 0) + 1,
      },
    });
  })
);

/* ============================================================
   USER ROUTES (require Discord login)
   ============================================================ */

// GET /api/keys/mine — this user's key(s), if their Discord ID is linked
router.get(
  '/mine',
  requireAuth,
  asyncH(async (req, res) => {
    let scriptKeys = [];
    try {
      const provider = getProvider(DEFAULT_PROVIDER);
      const result = await provider.fetchKeys({ discordId: req.user.discordId });
      scriptKeys = (result.keys || []).map(publicKeyView);
    } catch (_) {}

    // Also include user's external keys
    const extKeys = store.getExternalKeys({ discordId: req.user.discordId }).map((k) => ({
      key: k.key,
      hubName: k.product || 'RiotsSeige',
      note: k.note,
      expire: k.expire,
      created: k.created,
      activated: k.activated,
      blacklisted: k.blacklisted,
      hwid: !!k.hwid,
      hwidResetCount: k.hwidResetCount,
      executionCount: k.executionCount,
      lastExecution: k.lastExecution,
      isExternal: true,
      discord: { id: req.user.discordId, username: req.user.username, globalName: req.user.globalName },
    }));

    const allKeys = [...scriptKeys, ...extKeys];

    res.json({
      success: true,
      linked: allKeys.length > 0,
      discord: {
        id: req.user.discordId,
        username: req.user.username,
        globalName: req.user.globalName,
        avatar: req.user.avatar,
      },
      keys: allKeys,
    });
  })
);

// POST /api/keys/register — link an existing (unassigned) key to this Discord user
const registerSchema = z.object({
  key: z.string().trim().min(6).max(128),
});
router.post(
  '/register',
  requireAuth,
  asyncH(async (req, res) => {
    const { key } = registerSchema.parse(req.body);
    const provider = getProvider(DEFAULT_PROVIDER);

    // Make sure key exists and isn't already assigned to someone else.
    const info = await provider.keyInfo({ key });
    const found = info.key;
    if (!found) {
      return res.status(404).json({ success: false, message: 'Key not found.' });
    }
    if (found.discordId && found.discordId !== req.user.discordId) {
      return res.status(409).json({ success: false, message: 'This key is already linked to another account.' });
    }

    // Link by updating the key's discordId.
    await provider.updateKey({ key }, { discordId: req.user.discordId });
    
    // Store Discord profile data with the link
    store.linkDiscord(req.user.discordId, DEFAULT_PROVIDER, key, {
      id: req.user.discordId,
      username: req.user.username,
      global_name: req.user.globalName,
      avatar: req.user.avatar,
    });

    res.json({ success: true, message: 'Key linked to your account.' });
  })
);

// POST /api/keys/reset-hwid — user resets their own HWID (respects cooldown)
router.post(
  '/reset-hwid',
  requireAuth,
  asyncH(async (req, res) => {
    const provider = getProvider(DEFAULT_PROVIDER);
    const result = await provider.resetHwid({
      discordId: req.user.discordId,
      enforceCooldown: true,
    });
    res.json({ success: true, message: result.message || 'HWID reset.' });
  })
);

/* ============================================================
   ADMIN ROUTES (require admin key)
   ============================================================ */

const providerParam = (req) => getProvider(req.query.provider || req.body?.provider || DEFAULT_PROVIDER);

// GET /api/keys/admin/list — full fetch with filters
router.get(
  '/admin/list',
  requireAdmin,
  asyncH(async (req, res) => {
    const provider = providerParam(req);
    const { discordId, key, hwid, blacklisted, expired, unassigned, active, page } = req.query;
    const result = await provider.fetchKeys({
      discordId, key, hwid, blacklisted, expired, unassigned, active, page,
    });
    
    // Enrich keys with Discord profile data from our store
    const keys = (result.keys || []).map(k => {
      // If the key has a discordId, try to get Discord profile from our links store
      if (k.discordId) {
        const link = store.getLink(k.discordId);
        if (link && link.discordData) {
          k.discordData = link.discordData;
        } else {
          // Create a basic discordData object even without full profile
          k.discordData = {
            id: k.discordId,
            username: '',
            global_name: '',
            avatar: null
          };
        }
      }
      return k;
    });
    
    res.json({ success: true, keys, ...(result.total !== undefined ? { total: result.total } : {}) });
  })
);

const genSchema = z.object({
  amount: z.number().int().min(1).max(300),
  expire: z.number().int().min(3600).optional(),
  note: z.string().max(200).optional(),
  limitedScripts: z.array(z.string()).optional(),
  provider: z.string().optional(),
});
router.post(
  '/admin/generate',
  requireAdmin,
  asyncH(async (req, res) => {
    const body = genSchema.parse(req.body);
    const provider = getProvider(body.provider || DEFAULT_PROVIDER);
    const result = await provider.generateKeys(body);
    res.json({ success: true, ...result });
  })
);

const addSchema = z.object({
  discordId: z.string().regex(/^\d{5,25}$/),
  expire: z.number().int().min(3600).optional(),
  note: z.string().max(200).optional(),
  limitedScripts: z.array(z.string()).optional(),
  provider: z.string().optional(),
});
router.post(
  '/admin/add',
  requireAdmin,
  asyncH(async (req, res) => {
    const body = addSchema.parse(req.body);
    const provider = getProvider(body.provider || DEFAULT_PROVIDER);
    const result = await provider.addKey(body);
    res.json({ success: true, ...result });
  })
);

const targetSchema = z.object({
  discordId: z.string().optional(),
  key: z.string().optional(),
}).refine((d) => d.discordId || d.key, { message: 'discordId or key is required' });

router.patch(
  '/admin/update',
  requireAdmin,
  asyncH(async (req, res) => {
    const target = targetSchema.parse({ discordId: req.body.discordId, key: req.body.key });
    const provider = providerParam(req);
    const patch = {};
    for (const f of ['expire', 'note', 'blacklisted', 'blacklistReason', 'limitedScripts', 'discordId']) {
      if (req.body[f] !== undefined && f !== 'key') patch[f] = req.body[f];
    }
    const result = await provider.updateKey(target, patch);
    res.json({ success: true, ...result });
  })
);

router.post(
  '/admin/blacklist',
  requireAdmin,
  asyncH(async (req, res) => {
    const target = targetSchema.parse({ discordId: req.body.discordId, key: req.body.key });
    const provider = providerParam(req);
    const result = req.body.blacklisted === false
      ? await provider.unblacklistKey(target)
      : await provider.blacklistKey(target, req.body.reason);
    res.json({ success: true, ...result });
  })
);

router.delete(
  '/admin/delete',
  requireAdmin,
  asyncH(async (req, res) => {
    const target = targetSchema.parse({ discordId: req.query.discordId, key: req.query.key });
    const provider = providerParam(req);
    const result = await provider.deleteKey(target);
    res.json({ success: true, ...result });
  })
);

router.post(
  '/admin/reset-hwid',
  requireAdmin,
  asyncH(async (req, res) => {
    const target = targetSchema.parse({ discordId: req.body.discordId, key: req.body.key });
    const provider = providerParam(req);
    const result = await provider.resetHwid({ ...target, enforceCooldown: !!req.body.enforceCooldown });
    res.json({ success: true, ...result });
  })
);

// GET /api/keys/admin/hubs — hubs + scripts (used to pick limitedScripts)
router.get(
  '/admin/hubs',
  requireAdmin,
  asyncH(async (req, res) => {
    const provider = providerParam(req);
    const result = await provider.getHubs();
    res.json({ success: true, ...result });
  })
);

export default router;
