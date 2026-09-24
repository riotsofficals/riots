import { Router } from 'express';
import { z } from 'zod';
import { store } from '../store.js';
import { requireAuth, requireAdmin } from '../auth.js';
import { getProvider, DEFAULT_PROVIDER } from '../providers/index.js';

const router = Router();

const signupSchema = z.object({
  code: z.string().trim().max(20).optional(),
  email: z.string().email().max(200).optional().or(z.literal('')),
  payout: z.string().trim().max(200).optional(),
});

const KEY_THRESHOLD = 5; // Number of referrals needed to unlock a key

router.get('/me', requireAuth, (req, res) => {
  const ref = store.getReferralByDiscord(req.user.discordId);
  res.json({ success: true, referral: ref });
});

router.post('/signup', requireAuth, (req, res) => {
  const data = signupSchema.parse(req.body);
  const ref = store.addReferral({
    discordId: req.user.discordId,
    username: req.user.username || req.user.globalName || '',
    email: data.email || '',
    payout: data.payout || '',
    code: data.code || req.user.username || '',
  });
  res.json({ success: true, referral: ref });
});

// User requests key redemption from their referral earnings
router.post('/redeem', requireAuth, async (req, res) => {
  const ref = store.getReferralByDiscord(req.user.discordId);
  if (!ref) {
    return res.status(404).json({ success: false, message: 'No referral account found.' });
  }
  
  const keysEarned = Math.floor((ref.signups || 0) / KEY_THRESHOLD);
  if (keysEarned < 1) {
    return res.status(400).json({ success: false, message: `You need at least ${KEY_THRESHOLD} referrals to redeem a key.` });
  }
  
  // Mark as pending redemption (admin will review)
  const pending = store.addPendingRedemption({
    discordId: req.user.discordId,
    referralId: ref.id,
    keysRequested: keysEarned,
  });
  
  res.json({ success: true, message: 'Redemption request submitted. An admin will review and issue your key(s).', pending });
});

router.post('/track', (req, res) => {
  const code = String(req.body.code || '').trim().slice(0, 40);
  if (!code) return res.status(400).json({ success: false, message: 'Code required.' });
  // De-dupe clicks by a coarse visitor token: client-sent id + IP, hashed.
  const vid = String(req.body.vid || '').slice(0, 64);
  const ip = (req.ip || '').slice(0, 64);
  const visitorToken = (vid || ip) ? `${vid}|${ip}` : '';
  const ref = store.trackReferralClick(code, visitorToken);
  res.json({ success: true, tracked: !!ref });
});

router.get('/', requireAdmin, (req, res) => {
  res.json({ success: true, referrals: store.getReferrals() });
});

// Admin: Get pending redemptions
router.get('/pending', requireAdmin, (req, res) => {
  res.json({ success: true, pending: store.getPendingRedemptions() });
});

// Admin: Approve/reject a redemption and issue keys
router.post('/pending/:id/approve', requireAdmin, async (req, res) => {
  const pending = store.getPendingRedemption(req.params.id);
  if (!pending) {
    return res.status(404).json({ success: false, message: 'Redemption not found.' });
  }
  
  try {
    const provider = getProvider(DEFAULT_PROVIDER);
    
    // Generate keys for the user
    for (let i = 0; i < pending.keysRequested; i++) {
      await provider.addKey({
        discordId: pending.discordId,
        note: `Referral reward (${i + 1}/${pending.keysRequested})`,
      });
    }
    
    // Mark redemption as completed
    store.completeRedemption(req.params.id);
    
    res.json({ success: true, message: `Issued ${pending.keysRequested} key(s) to user.` });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// Admin: Reject a redemption
router.post('/pending/:id/reject', requireAdmin, (req, res) => {
  const reason = String(req.body.reason || '').trim().slice(0, 200);
  store.rejectRedemption(req.params.id, reason);
  res.json({ success: true, message: 'Redemption rejected.' });
});

router.delete('/:id', requireAdmin, (req, res) => {
  const referrals = store.removeReferral(req.params.id);
  res.json({ success: true, referrals });
});

export default router;
