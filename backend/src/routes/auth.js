import { Router } from 'express';
import crypto from 'crypto';
import { config } from '../config.js';
import {
  discordAuthUrl,
  exchangeDiscordCode,
  fetchDiscordUser,
  signSession,
  setSessionCookie,
  clearSessionCookie,
  readSession,
} from '../auth.js';

const router = Router();

// CSRF state store (short-lived, in-memory). For multi-instance, use Redis.
const stateStore = new Map();
function newState(returnUrl) {
  const s = crypto.randomBytes(16).toString('hex');
  stateStore.set(s, { t: Date.now(), returnUrl: returnUrl || '' });
  // cleanup old
  const cutoff = Date.now() - 10 * 60 * 1000;
  for (const [k, v] of stateStore) if ((v?.t || 0) < cutoff) stateStore.delete(k);
  return s;
}

// Only allow returning to one of our own configured frontend origins.
function safeReturnUrl(raw) {
  if (!raw) return '';
  try {
    const u = new URL(raw);
    const ok = config.corsOrigins.some((o) => {
      try { return new URL(o).origin === u.origin; } catch { return false; }
    });
    return ok ? u.toString() : '';
  } catch { return ''; }
}

// Step 1: send user to Discord
router.get('/discord', (req, res) => {
  if (!config.discord.clientId) {
    return res.status(503).json({ success: false, message: 'Discord OAuth not configured.' });
  }
  const state = newState(safeReturnUrl(req.query.return));
  res.redirect(discordAuthUrl(state));
});

// Step 2: Discord redirects back with ?code&state
router.get('/discord/callback', async (req, res) => {
  const { code, state } = req.query;
  if (!code || !state || !stateStore.has(state)) {
    return res.status(400).send('Invalid OAuth state. Please try logging in again.');
  }
  const stateData = stateStore.get(state);
  stateStore.delete(state);

  try {
    const token = await exchangeDiscordCode(code);
    const user = await fetchDiscordUser(token.access_token);

    const session = signSession({
      discordId: user.id,
      username: user.username,
      globalName: user.global_name || user.username,
      avatar: user.avatar
        ? `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.png`
        : null,
    });
    setSessionCookie(res, session);

    // Also hand the token back in the URL fragment so the frontend can store it
    // and send it as a Bearer header. This is the fallback for browsers that
    // block third-party cookies (Vercel <-> Railway are different sites).
    // Return to the page the user started from (if allowed), else the dashboard.
    const base = (stateData && stateData.returnUrl) || config.discord.dashboardUrl || '/';
    const sep = base.includes('#') ? '&' : '#';
    res.redirect(`${base}${sep}token=${encodeURIComponent(session)}`);
  } catch (err) {
    console.error('[auth] Discord callback error:', err.message);
    res.status(500).send('Login failed. Please try again.');
  }
});

// Who am I (dashboard hydration)
router.get('/me', (req, res) => {
  const session = readSession(req);
  if (!session?.discordId) {
    return res.json({ authenticated: false });
  }
  res.json({
    authenticated: true,
    user: {
      discordId: session.discordId,
      username: session.username,
      globalName: session.globalName,
      avatar: session.avatar,
    },
  });
});

router.post('/logout', (req, res) => {
  clearSessionCookie(res);
  res.json({ success: true });
});

export default router;
