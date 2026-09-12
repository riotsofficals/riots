import dotenv from 'dotenv';
dotenv.config();

function required(name, fallback = undefined) {
  const v = process.env[name] ?? fallback;
  if (v === undefined || v === '') {
    // Don't crash in dev for optional-ish keys; warn loudly instead.
    console.warn(`[config] Missing env var: ${name}`);
  }
  return v;
}

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '8080', 10),

  corsOrigins: (process.env.CORS_ORIGINS || 'http://localhost:5173')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),

  jwtSecret: required('JWT_SECRET', 'dev_insecure_jwt_secret'),
  adminKey: required('ADMIN_KEY', ''),

  // Optional shared token the frontend sends on every /api call. When set, the
  // API rejects /api requests that don't include it — stops casual scraping /
  // direct hits from tools that aren't your site. NOT a substitute for auth
  // (it's shipped in client JS), just a friction layer.
  frontendToken: process.env.FRONTEND_TOKEN || '',
  // Block requests that arrive without an Origin/Referer in production (i.e.
  // curl / scripts). Browsers always send Origin on cross-site fetches.
  blockNoOrigin: (process.env.BLOCK_NO_ORIGIN || 'true') === 'true',

  discord: {
    clientId: process.env.DISCORD_CLIENT_ID || '',
    clientSecret: process.env.DISCORD_CLIENT_SECRET || '',
    redirectUri: process.env.DISCORD_REDIRECT_URI || '',
    dashboardUrl: process.env.DASHBOARD_URL || 'http://localhost:3000/dashboard.html',
  },

  luaprot: {
    apiKey: process.env.LUAPROT_API_KEY || '',
    hubId: process.env.LUAPROT_HUB_ID || '',
    baseUrl: process.env.LUAPROT_BASE_URL || 'https://luaprot.net',
  },

  komerza: {
    webhookSecret: process.env.KOMERZA_WEBHOOK_SECRET || '',
    // SECRET API key (Bearer) — server-side only, NEVER in the frontend.
    apiKey: process.env.KOMERZA_API_KEY || '',
    storeId: process.env.KOMERZA_STORE_ID || '',
    // Public product ID (safe to be public; also used to read stock).
    productId: process.env.KOMERZA_PRODUCT_ID || '',
    baseUrl: process.env.KOMERZA_BASE_URL || 'https://api.komerza.com',
    // Public variant IDs for the seeded rivals product (safe to expose).
    variantLifetime: process.env.KOMERZA_VARIANT_LIFETIME || 'b5b90fd3-db55-4f73-943a-3a6625edee46',
    variantMonthly: process.env.KOMERZA_VARIANT_MONTHLY || '3a1b2e3a-4151-4ccb-859e-f0803ef09cc9',
  },

  dataDir: process.env.DATA_DIR || './data',
};

export const isProd = config.env === 'production';
