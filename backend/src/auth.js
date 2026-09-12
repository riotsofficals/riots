import jwt from 'jsonwebtoken';
import { config, isProd } from './config.js';

/**
 * Auth utilities.
 *
 * Two independent trust signals:
 *  1) Discord session (JWT cookie) — proves "this browser is this Discord user".
 *  2) Admin key — a separate secret the user types into the dashboard. If it
 *     matches ADMIN_KEY, the request is elevated to admin. The admin key is
 *     verified server-side ONLY and never returned to the client.
 */

const COOKIE_NAME = 'riots_session';

export function signSession(payload) {
  return jwt.sign(payload, config.jwtSecret, { expiresIn: '7d' });
}

export function setSessionCookie(res, token) {
  res.cookie(COOKIE_NAME, token, {
    httpOnly: true,
    secure: isProd, // HTTPS only in prod
    sameSite: isProd ? 'none' : 'lax', // cross-site (Vercel <-> Railway) needs None+Secure
    maxAge: 7 * 24 * 60 * 60 * 1000,
    path: '/',
  });
}

export function clearSessionCookie(res) {
  res.clearCookie(COOKIE_NAME, {
    httpOnly: true,
    secure: isProd,
    sameSite: isProd ? 'none' : 'lax',
    path: '/',
  });
}

export function readSession(req) {
  const token = req.cookies?.[COOKIE_NAME];
  if (!token) return null;
  try {
    return jwt.verify(token, config.jwtSecret);
  } catch {
    return null;
  }
}

/** Require a logged-in Discord session. Attaches req.user. */
export function requireAuth(req, res, next) {
  const session = readSession(req);
  if (!session?.discordId) {
    return res.status(401).json({ success: false, message: 'Not authenticated.' });
  }
  req.user = session;
  next();
}

/**
 * Timing-safe-ish admin key check. The admin key can arrive via:
 *   - Header:  x-admin-key
 *   - Body:    { adminKey }
 * We never log it and never echo it back.
 */
export function isAdminRequest(req) {
  if (!config.adminKey) return false; // admin disabled if unset
  const provided =
    req.get('x-admin-key') ||
    req.body?.adminKey ||
    '';
  if (!provided || provided.length !== config.adminKey.length) return false;
  // constant-time compare
  let mismatch = 0;
  for (let i = 0; i < config.adminKey.length; i++) {
    mismatch |= provided.charCodeAt(i) ^ config.adminKey.charCodeAt(i);
  }
  return mismatch === 0;
}

/** Require the admin key. Use for all admin-only routes. */
export function requireAdmin(req, res, next) {
  if (!isAdminRequest(req)) {
    return res.status(403).json({ success: false, message: 'Admin authorization required.' });
  }
  req.isAdmin = true;
  next();
}

// ---- Discord OAuth helpers ----

export function discordAuthUrl(state) {
  const params = new URLSearchParams({
    client_id: config.discord.clientId,
    redirect_uri: config.discord.redirectUri,
    response_type: 'code',
    scope: 'identify',
    state,
    prompt: 'consent',
  });
  return `https://discord.com/oauth2/authorize?${params.toString()}`;
}

export async function exchangeDiscordCode(code) {
  const body = new URLSearchParams({
    client_id: config.discord.clientId,
    client_secret: config.discord.clientSecret,
    grant_type: 'authorization_code',
    code,
    redirect_uri: config.discord.redirectUri,
  });
  const res = await fetch('https://discord.com/api/oauth2/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) throw new Error('Discord token exchange failed.');
  return res.json();
}

export async function fetchDiscordUser(accessToken) {
  const res = await fetch('https://discord.com/api/users/@me', {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error('Failed to fetch Discord user.');
  return res.json();
}
