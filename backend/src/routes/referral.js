import { Router } from 'express';
import { z } from 'zod';
import { store } from '../store.js';
import { requireAuth, requireAdmin } from '../auth.js';

const router = Router();

const signupSchema = z.object({
  code: z.string().trim().max(20).optional(),
  email: z.string().email().max(200).optional().or(z.literal('')),
  payout: z.string().trim().max(200).optional(),
});

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

router.post('/track', (req, res) => {
  const code = String(req.body.code || '').trim().slice(0, 40);
  if (!code) return res.status(400).json({ success: false, message: 'Code required.' });
  const ref = store.trackReferralClick(code);
  res.json({ success: true, tracked: !!ref });
});

router.get('/', requireAdmin, (req, res) => {
  res.json({ success: true, referrals: store.getReferrals() });
});

router.delete('/:id', requireAdmin, (req, res) => {
  const referrals = store.removeReferral(req.params.id);
  res.json({ success: true, referrals });
});

export default router;
