# Security overview — riots.wtf

This project is split so that **secrets never touch the browser**. The static
site (Vercel) only ever talks to the backend API (Railway). Only the backend
holds the LuaProt key, Discord client secret, admin key, and webhook secret.

```
Browser (Vercel static)  ──fetch, credentials──►  API (Railway)  ──►  LuaProt / Komerza / Discord
   dashboard.js                                     secrets live here only
```

## Golden rules

1. **No backend runs on your local machine in production.** The API and bot run
   on Railway (or another host). Local is for development only.
2. **No secret ever appears in frontend code.** `dashboard.js` / `script.js`
   contain zero API keys — only the public API base URL.
3. Every `.env` is git-ignored. Only `.env.example` (no real values) is committed.

## What protects each surface

### Backend API (`backend/`)
- **Helmet** security headers; `x-powered-by` disabled.
- **CORS allowlist** — only your Vercel origins may call the API with credentials.
- **API interference guard** (`/api/*` only): in production, requests with no
  `Origin` and no `Referer` (curl / scripts) are rejected, and if
  `FRONTEND_TOKEN` is set the request must carry a matching `x-client-token`
  header. This is a friction layer, not real auth — the session cookie and admin
  key are the actual security — but it stops casual scraping and direct poking.
- **Rate limiting** — 120 req/min global, 20 req/min on `/auth` and
  `/api/keys/admin` to slow brute force.
- **Sessions** — httpOnly + Secure + SameSite=None JWT cookie. JS cannot read it,
  so it can't be stolen by XSS.
- **Admin key** — compared in constant time, accepted only via the `x-admin-key`
  header, never logged, never returned to the client.
- **Input validation** — every write route validated with zod.
- **Output masking** — normal users get a masked key view (no raw HWID, no
  internal IDs). Only admins see the raw provider objects.
- **Webhook** — verifies an HMAC-SHA256 signature over the raw request body.
- **Error handler** — 500s never leak stack traces in production.

### Dashboard (`dashboard.html` / `dashboard.js`)
- The whole page is blurred and non-interactive until authentication succeeds.
- Login is Discord OAuth handled entirely by the backend.
- Admin key is held only in memory for the tab session and sent per request.

### Discord bot (`bot/`)
- Token and IDs come from env only.
- Staff/admin gating on every sensitive command.
- Role-hierarchy checks so staff can't action higher roles.

## Things YOU must do to be secure

- [ ] Generate strong random values for `JWT_SECRET` and `ADMIN_KEY`
      (`openssl rand -hex 32`).
- [ ] Set `ADMIN_KEY` in **both** Railway (backend) and, for reference, keep it
      secret — you type it into the dashboard to unlock admin mode.
- [ ] Whitelist the Railway egress IP on the LuaProt dashboard.
- [ ] Set `CORS_ORIGINS` to your exact Vercel URLs (no wildcard).
- [ ] Add the Discord OAuth redirect URL in the Developer Portal.
- [ ] Set `KOMERZA_WEBHOOK_SECRET` and confirm the signature header name/shape
      against Komerza's dashboard, then adjust `webhook.js` if needed.
- [ ] (Optional) Set `FRONTEND_TOKEN` on Railway and the same value as
      `window.RIOTS_CLIENT_TOKEN` in `dashboard.html` to add the friction layer.
- [ ] Never commit a real `.env`. Rotate any secret that leaks.

## How stock works

**Stock is managed entirely by Komerza — not by this codebase.** Each
product/variant has a stock count on your Komerza dashboard. Komerza decrements
it on a completed purchase and blocks checkout when it hits zero, so you can't
over-sell. The "In stock / Low stock" labels on the site are just static display
text; the real enforcement happens at Komerza checkout. If you want the site to
show *live* counts, you'd poll Komerza's API — but the guarantee (no sale when
sold out) is Komerza's job.

## Reporting

Found a vulnerability? Report it privately in the Discord
(https://discord.gg/m7Z9Jyp6pf) rather than opening a public issue.
