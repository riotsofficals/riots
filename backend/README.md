# riots.wtf — Backend API

Node/Express API that powers the dashboard, key management (multi-provider,
LuaProt first), Discord login, devlog and status. **Runs on Railway** (or any
Node host). It is never meant to run permanently on your local machine.

## Why a backend exists

The LuaProt API key must be sent in an `Authorization` header and LuaProt only
accepts requests from **whitelisted IPs**. Neither can live in browser code, so
the frontend (Vercel) talks to this API, and this API talks to LuaProt/Komerza
using secrets that only exist server-side.

```
Dashboard (Vercel, static) ──► This API (Railway) ──► LuaProt / Komerza
Discord bot (Railway)      ──► This API / LuaProt
```

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/health` | – | Health check |
| GET | `/auth/discord` | – | Start Discord login |
| GET | `/auth/discord/callback` | – | OAuth callback |
| GET | `/auth/me` | cookie | Current user |
| POST | `/auth/logout` | cookie | Log out |
| GET | `/api/keys/mine` | user | Your linked key(s) |
| POST | `/api/keys/register` | user | Link an unassigned key to you |
| POST | `/api/keys/reset-hwid` | user | Reset your own HWID |
| GET | `/api/keys/admin/list` | admin | Fetch keys (filters) |
| POST | `/api/keys/admin/generate` | admin | Generate batch |
| POST | `/api/keys/admin/add` | admin | Assign key to a Discord ID |
| PATCH | `/api/keys/admin/update` | admin | Update a key |
| POST | `/api/keys/admin/blacklist` | admin | Blacklist / un-blacklist |
| DELETE | `/api/keys/admin/delete` | admin | Delete a key |
| POST | `/api/keys/admin/reset-hwid` | admin | Force HWID reset |
| GET | `/api/keys/admin/hubs` | admin | Hubs + scripts |
| GET | `/api/content/devlog` | – | Read updates feed |
| POST | `/api/content/devlog` | admin | Add update |
| DELETE | `/api/content/devlog/:id` | admin | Delete update |
| GET | `/api/content/status` | – | Read status |
| PUT | `/api/content/status` | admin | Set status |
| POST | `/webhook/komerza` | signature | Purchase webhook |

- **user** = valid Discord session cookie (from OAuth).
- **admin** = correct `x-admin-key` header (equals `ADMIN_KEY`).

## Local dev

```bash
cd backend
npm install
cp .env.example .env   # fill in values
npm run dev            # http://localhost:8080
```

## Deploy to Railway

1. Push this repo to GitHub.
2. Railway → **New Project → Deploy from GitHub** → pick the repo, set the root
   directory to `backend/`.
3. Railway → your service → **Variables**: add everything from `.env.example`
   with real values.
4. Railway generates a public domain (e.g. `https://riots-api.up.railway.app`).
5. **Whitelist Railway's egress IP on the LuaProt dashboard.** Find it via a
   quick request from the service (or Railway's static outbound IP feature).
6. In your Discord app (developers portal) add the redirect:
   `https://YOUR_RAILWAY_DOMAIN/auth/discord/callback` and set the same value in
   `DISCORD_REDIRECT_URI`.
7. Set `CORS_ORIGINS` to your Vercel URLs and `DASHBOARD_URL` to your dashboard.
8. On the frontend, set `API_BASE` (in `script.js`) to the Railway domain.

## Security notes

- Secrets only live in env vars (never in the repo / frontend).
- Session is an httpOnly, Secure, SameSite=None JWT cookie.
- Admin key is compared in constant time and never returned to the client.
- Helmet, CORS allowlist, global + strict rate limits, zod input validation.
- Webhook verifies an HMAC signature over the raw body.
- User key views are masked (no raw HWID, no internal IDs).

## Storage

Devlog / status / Discord→key links use a small JSON file store in `DATA_DIR`.
For higher volume, add a Railway **Postgres** or **Redis** plugin and swap
`src/store.js` — the exported API stays the same.
