import { Router } from 'express';
import crypto from 'crypto';
import { config } from '../config.js';
import { getProvider, DEFAULT_PROVIDER } from '../providers/index.js';
import { store } from '../store.js';

const router = Router();

/**
 * Komerza purchase webhook.
 *
 * Mount with a RAW body parser (see server.js) so we can verify the HMAC
 * signature over the exact bytes Komerza sent. If KOMERZA_WEBHOOK_SECRET is
 * set, unsigned/invalid requests are rejected.
 *
 * NOTE: Confirm the exact signature header name + payload shape in your
 * Komerza dashboard's webhook docs, then adjust HEADER / event parsing below.
 * This is intentionally defensive: it verifies, logs, and no-ops safely for
 * event types it doesn't recognise.
 */

const SIG_HEADER = 'x-komerza-signature';

function verifySignature(req) {
  if (!config.komerza.webhookSecret) return true; // not enforced if unset (dev)
  const sig = req.get(SIG_HEADER) || '';
  const expected = crypto
    .createHmac('sha256', config.komerza.webhookSecret)
    .update(req.body) // Buffer (raw)
    .digest('hex');
  if (sig.length !== expected.length) return false;
  return crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
}

router.post('/komerza', async (req, res) => {
  if (!verifySignature(req)) {
    return res.status(401).json({ success: false, message: 'Invalid signature.' });
  }

  let event;
  try {
    event = JSON.parse(req.body.toString('utf8'));
  } catch {
    return res.status(400).json({ success: false, message: 'Bad JSON.' });
  }

  // Acknowledge fast; do work but don't let errors cause retries storms.
  try {
    const type = event.type || event.event || '';
    const isPaid =
      type.includes('completed') ||
      type.includes('paid') ||
      event.status === 'completed' ||
      event.status === 'paid';

    if (isPaid) {
      // Pull the buyer's Discord ID from metadata if you passed it at checkout
      // (Komerza supports data-kmrza-metadata / metadata on the embed).
      const meta = event.metadata || event.data?.metadata || {};
      const discordId =
        meta.discordId ||
        event.customer?.discordId ||
        null;

      // Credit a referral conversion if a code rode along at checkout.
      // We accept either our internal referral code or Komerza's affiliate code.
      const refCode =
        meta.ref || meta.referral || meta.referralCode || meta.affiliateCode ||
        event.affiliateCode || event.data?.affiliateCode || null;
      if (refCode) {
        const orderId = event.id || event.orderId || event.data?.id || null;
        const amount =
          Number(event.total ?? event.amount ?? event.data?.total ?? event.data?.amount ?? 0) || 0;
        try {
          const credited = store.creditReferralConversion(refCode, { orderId, amount });
          if (credited) console.log('[webhook] Credited referral', refCode, 'order', orderId);
        } catch (e) { console.warn('[webhook] referral credit failed:', e.message); }
      }

      const provider = getProvider(DEFAULT_PROVIDER);

      if (discordId) {
        // Auto-provision a key for the buyer and link it.
        const created = await provider.addKey({
          discordId,
          note: `Komerza order ${event.id || event.orderId || ''}`.trim(),
        });
        const key = created?.key?.key;
        if (key) store.linkDiscord(discordId, DEFAULT_PROVIDER, key);
        console.log('[webhook] Provisioned key for discord', discordId);
      } else {
        // No Discord ID: generate an unassigned key for manual/self-serve linking.
        await provider.generateKeys({ amount: 5, note: 'Komerza auto-batch' });
        console.log('[webhook] Paid order without discordId — generated unassigned batch.');
      }
    }
  } catch (err) {
    console.error('[webhook] processing error:', err.message);
    // Still 200 so Komerza doesn't hammer retries; we logged it.
  }

  res.json({ success: true });
});

export default router;
