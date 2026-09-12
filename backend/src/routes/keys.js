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
   USER ROUTES (require Discord login)
   ============================================================ */

// GET /api/keys/mine — this user's key(s), if their Discord ID is linked
router.get(
  '/mine',
  requireAuth,
  asyncH(async (req, res) => {
    const provider = getProvider(DEFAULT_PROVIDER);
    const result = await provider.fetchKeys({ discordId: req.user.discordId });
    const keys = (result.keys || []).map(publicKeyView);
    res.json({
      success: true,
      linked: keys.length > 0,
      discord: {
        id: req.user.discordId,
        username: req.user.username,
        globalName: req.user.globalName,
        avatar: req.user.avatar,
      },
      keys,
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
    store.linkDiscord(req.user.discordId, DEFAULT_PROVIDER, key);

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
    res.json({ success: true, ...result }); // admin sees the raw provider shape
  })
);

const genSchema = z.object({
  amount: z.number().int().min(5).max(300),
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
