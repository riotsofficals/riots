import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import rateLimit from 'express-rate-limit';

import { config, isProd } from './config.js';
import { store } from './store.js';
import authRoutes from './routes/auth.js';
import keyRoutes from './routes/keys.js';
import contentRoutes from './routes/content.js';
import storeRoutes from './routes/store.js';
import referralRoutes from './routes/referral.js';
import webhookRoutes from './routes/webhook.js';
import productsRoutes from './routes/products.js';
import logsRoutes from './routes/logs.js';
import cracksRoutes from './routes/cracks.js';
import externalKeysRoutes from './routes/externalKeys.js';

const app = express();

// Behind Railway's proxy — needed for secure cookies + correct client IPs
app.set('trust proxy', 1);
app.disable('x-powered-by');

// ---- Security headers ----
app.use(
  helmet({
    contentSecurityPolicy: false, // this is a JSON API, not serving HTML
    crossOriginResourcePolicy: { policy: 'cross-origin' },
    referrerPolicy: { policy: 'no-referrer' },
    hsts: { maxAge: 15552000, includeSubDomains: true }, // 180d HTTPS-only
  })
);

// ---- CORS allowlist (credentials for the session cookie) ----
const corsOptions = {
  origin(origin, cb) {
    // No Origin header = same-origin, server-to-server, or a non-browser client
    // (curl/scripts). In prod we optionally reject those on the API (handled by
    // the guard below); CORS itself allows it so health/webhook still work.
    if (!origin || config.corsOrigins.includes(origin)) return cb(null, true);
    return cb(new Error('Not allowed by CORS'));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'x-admin-key', 'x-client-token', 'Authorization'],
};
app.use(cors(corsOptions));

// ---- Webhook needs the RAW body for signature verification.
//      Mount it BEFORE express.json() so the body stays a Buffer. ----
app.use('/webhook', express.raw({ type: '*/*', limit: '256kb' }), webhookRoutes);

// ---- Normal parsers for everything else ----
app.use(express.json({ limit: '128kb' }));
app.use(cookieParser());

// ---- Global rate limit ----
app.use(
  rateLimit({
    windowMs: 60 * 1000,
    max: 120, // per IP per minute
    standardHeaders: true,
    legacyHeaders: false,
    message: { success: false, message: 'Too many requests, slow down.' },
  })
);

// Tighter limit on auth + admin-sensitive endpoints (brute-force defence)
const strictLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many attempts, try again shortly.' },
});
app.use('/auth', strictLimiter);
app.use('/api/keys/admin', strictLimiter);

// Public analytics/tracking writes are cheap but abusable to inflate counts.
// Cap them per IP without hurting normal browsing.
const trackLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 40,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many requests.' },
});
app.use('/api/content/pageview', trackLimiter);
app.use('/api/referral/track', trackLimiter);

// User-content creation (tickets, referral signup) — modest cap to stop spam.
// Only throttle writes (POST/PATCH); reads (GET) are unaffected.
const writeLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 15,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Slow down — too many submissions.' },
});
const writeOnly = (limiter) => (req, res, next) => (req.method === 'GET' ? next() : limiter(req, res, next));
app.use('/api/store/tickets', writeOnly(writeLimiter));
app.use('/api/referral/signup', writeLimiter); // signup is POST-only

// ---- Health check (Railway) ----
app.get('/health', (req, res) => res.json({ ok: true, uptime: process.uptime() }));
app.get('/', (req, res) => res.json({ name: 'riots.wtf api', ok: true }));

// ---- API interference guard (only for /api/*; keeps /auth, /webhook, /health open) ----
// 1) In prod, block requests with no Origin AND no Referer (curl/scripts).
// 2) If FRONTEND_TOKEN is set, require the matching x-client-token header.
// NOTE: Desktop clients (RiotsSeige C++ client) calling external-keys, logs, or cracks
// do not send browser Origin/Referer headers, so they are exempted here.
app.use('/api', (req, res, next) => {
  if (req.method === 'OPTIONS') return next(); // let CORS preflight through

  // Endpoints used by external desktop software
  const isDesktopClientRoute =
    req.path.startsWith('/external-keys') ||
    req.path.startsWith('/keys/external-keys') ||
    req.path.startsWith('/logs') ||
    req.path.startsWith('/cracks');

  if (!isDesktopClientRoute) {
    if (isProd && config.blockNoOrigin) {
      const hasContext = req.get('origin') || req.get('referer');
      if (!hasContext) {
        return res.status(403).json({ success: false, message: 'Forbidden.' });
      }
    }

    if (config.frontendToken) {
      const provided = req.get('x-client-token') || '';
      if (provided !== config.frontendToken) {
        return res.status(403).json({ success: false, message: 'Forbidden.' });
      }
    }
  }
  next();
});

// ---- Routes ----
app.use('/auth', authRoutes);
app.use('/api/keys', keyRoutes);
app.use('/api/external-keys', externalKeysRoutes);
app.use('/api/content', contentRoutes);
app.use('/api/store', storeRoutes);
app.use('/api/referral', referralRoutes);
app.use('/api/products', productsRoutes);
app.use('/api/logs', logsRoutes);
app.use('/api/cracks', cracksRoutes);

// ---- 404 ----
app.use((req, res) => res.status(404).json({ success: false, message: 'Not found.' }));

// ---- Centralised error handler (never leak stack traces / secrets) ----
app.use((err, req, res, next) => {
  // zod validation errors
  if (err?.name === 'ZodError') {
    return res.status(400).json({ success: false, message: 'Invalid input.', issues: err.issues?.map((i) => ({ path: i.path, message: i.message })) });
  }
  if (err?.message === 'Not allowed by CORS') {
    return res.status(403).json({ success: false, message: 'Origin not allowed.' });
  }
  const status = err.status || 500;
  if (status >= 500) console.error('[error]', err);
  res.status(status).json({
    success: false,
    message: status >= 500 && isProd ? 'Internal server error.' : err.message || 'Error',
  });
});

// Seed the default rivals product on first boot (only if catalog is empty).
try {
  store.seedProducts({
    komerzaProductId: config.komerza.productId,
    komerzaVariants: {
      lifetime: config.komerza.variantLifetime,
      monthly: config.komerza.variantMonthly,
    },
  });
} catch (e) {
  console.warn('  ! product seed skipped:', e.message);
}

app.listen(config.port, () => {
  console.log(`riots.wtf api listening on :${config.port} (${config.env})`);
  if (!config.luaprot.apiKey) console.warn('  ! LUAPROT_API_KEY not set — key routes will 503');
  if (!config.discord.clientId) console.warn('  ! DISCORD_CLIENT_ID not set — login disabled');
  if (!config.adminKey) console.warn('  ! ADMIN_KEY not set — admin routes disabled');
  if (!config.frontendToken) console.warn('  · FRONTEND_TOKEN not set — API client-token check disabled (optional)');
});
