# riots.wtf — Full Setup Guide (start here)

This walks you through **everything**, in order, in plain language. If you follow
it top to bottom you'll have the site, dashboard, key system, checkout, and bot
all working.

There are 3 pieces:

| Piece | Folder | Where it's hosted | Holds secrets? |
|---|---|---|---|
| Website + dashboard | root (`index.html`, etc.) | **Vercel** (static) | ❌ no |
| Backend API | `backend/` | **Railway** | ✅ yes (env vars) |
| Discord bot | `bot/` | **Railway** | ✅ yes (env vars) |

**The golden rule:** secrets (API keys, Discord secret, admin key) ONLY go into
Railway's Variables tab. The website (Vercel) never holds a secret — anything in
the frontend is visible to everyone, and that's fine because only public things
(your backend URL, Komerza product IDs) live there.

---

## Part 0 — What you need accounts for

- **GitHub** (to host the code so Railway/Vercel can deploy it)
- **Railway** (backend + bot) — railway.app
- **Vercel** (website) — vercel.com
- **Discord Developer app** (login + bot) — discord.com/developers
- **LuaProt** (keys) — you already have this
- **Komerza** (checkout + stock) — you already have this
- **Cloudinary** (product images) — cloudinary.com (free)

Push this whole folder to a GitHub repo first. The `.gitignore` files already
stop your real `.env` from being uploaded.

---

## Part 1 — Backend API (Railway)

The backend is the brain. It talks to LuaProt/Komerza/Discord using secrets that
only it can see.

1. Railway → **New Project → Deploy from GitHub** → pick your repo.
2. Settings → set **Root Directory** to `backend`.
3. Go to the **Variables** tab and add each of these (from `backend/.env.example`).
   Here's what each one is:

   | Variable | What to put | Needed for |
   |---|---|---|
   | `JWT_SECRET` | random string (`openssl rand -hex 32`) | login sessions |
   | `ADMIN_KEY` | a strong random string you invent | admin dashboard |
   | `CORS_ORIGINS` | your Vercel URL(s), comma-separated | letting the site call the API |
   | `DISCORD_CLIENT_ID` | from your Discord app | dashboard login |
   | `DISCORD_CLIENT_SECRET` | from your Discord app | dashboard login |
   | `DISCORD_REDIRECT_URI` | `https://YOUR_RAILWAY_URL/auth/discord/callback` | dashboard login |
   | `DASHBOARD_URL` | `https://YOUR_VERCEL_URL/dashboard.html` | where login returns to |
   | `LUAPROT_API_KEY` | from LuaProt | key management |
   | `LUAPROT_HUB_ID` | from LuaProt | key management |
   | `KOMERZA_API_KEY` | from Komerza (SECRET) | live stock |
   | `KOMERZA_STORE_ID` | `e2f2de20-0a61-4634-aaba-a2e4d476bcd9` | live stock |
   | `FRONTEND_TOKEN` | (optional) random string | anti-scraping |

4. Deploy. Railway gives you a URL like `https://riots-api.up.railway.app`.
   **Copy it — you'll need it in Part 3.**
5. **Whitelist Railway's IP on LuaProt.** LuaProt blocks any IP that isn't
   whitelisted. In Railway, enable a static outbound IP (Settings → Networking),
   then add that IP on your LuaProt dashboard.

Test it: open `https://YOUR_RAILWAY_URL/health` — you should see `{"ok":true}`.

---

## Part 2 — Discord app (login + bot)

You need ONE Discord application for login, and a bot token for the bot.

**For dashboard login (OAuth):**
1. discord.com/developers → **New Application**.
2. **OAuth2** → copy the **Client ID** and **Client Secret** → put them in
   Railway (`DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`).
3. OAuth2 → **Redirects** → add `https://YOUR_RAILWAY_URL/auth/discord/callback`.

**For the bot:**
1. Same app → **Bot** → **Reset Token** → copy it (this is `DISCORD_TOKEN`).
2. Turn ON **Server Members Intent** and **Message Content Intent**.
3. **OAuth2 → URL Generator** → scopes `bot` + `applications.commands`, tick
   permissions (Manage Channels/Roles, Ban/Kick, Moderate Members, Manage
   Messages, Read/Send Messages, Embed Links, Attach Files) → open the URL →
   invite the bot to your server.

Deploy the bot on Railway:
- New service → deploy from GitHub, **Root Directory** `bot`.
- Start command: `python bot.py`
- Variables tab → fill in from `bot/.env.example` (token, GUILD_ID, role IDs,
  channel IDs). Right-click things in Discord with Developer Mode on to copy IDs.

---

## Part 3 — Website (Vercel) + config.js

The website is static files. It only needs to know your backend URL and your
public Komerza/Cloudinary IDs — all set in ONE file: **`config.js`**.

1. Open **`config.js`** in the project root and fill it in:
   ```js
   window.RIOTS_CONFIG = {
     API_BASE: "https://YOUR_RAILWAY_URL",   // from Part 1
     CLIENT_TOKEN: "",                        // match FRONTEND_TOKEN if you set one
     CLOUDINARY: {
       cloudName: "your-cloud-name",          // from Part 4
       uploadPreset: "your-unsigned-preset",  // from Part 4
     },
     KOMERZA: {
       storeId: "e2f2de20-0a61-4634-aaba-a2e4d476bcd9",
       productId: "PASTE-YOUR-KOMERZA-PRODUCT-ID",   // ← you still need this
       variants: {
         lifetime: "b5b90fd3-db55-4f73-943a-3a6625edee46",
         monthly:  "3a1b2e3a-4151-4ccb-859e-f0803ef09cc9",
       },
       theme: "dark",
     },
   };
   ```
   These are all **public/safe** to commit.
2. Vercel → **Add New → Project** → import the repo. No framework, no build step
   (it's plain HTML). Deploy.
3. Do **NOT** add any secret env vars in Vercel.
4. After it's live, copy your Vercel URL and put it in Railway's `CORS_ORIGINS`
   and `DASHBOARD_URL` (Part 1), then redeploy the backend.

> Where's my Komerza **product** ID? Komerza dashboard → open the product → it's
> in the page URL / product details. (You already have the store id and the two
> variant ids.)

---

## Part 4 — Cloudinary (product images)

So the admin panel can upload product pictures.

1. cloudinary.com → sign up → note your **Cloud name** (top of the console).
2. Settings → **Upload** → **Add upload preset** → Signing mode **Unsigned** →
   save → copy the **preset name**.
3. Put both into `config.js` → `CLOUDINARY` (see Part 3). Done.

An unsigned preset is safe to be public — it can only upload images, nothing else.

---

## Part 5 — Using the admin dashboard

1. Go to `https://YOUR_VERCEL_URL/dashboard.html`.
2. The page is blurred behind an "Authenticate" box. Click **I have an admin key**
   and enter the `ADMIN_KEY` you set in Railway. (Normal users log in with Discord
   instead.)
3. Open the **Admin** tab. You can:
   - **Products** — create/edit/delete products. For each product you enter:
     - name, category, prices, badge, description
     - an **image** (click the box → uploads to Cloudinary)
     - its **Komerza product id** and **variant ids** (lifetime/monthly)

     👉 **Yes — every product you add has its own Komerza product id + variant ids.**
     That's how each product checks out to the right Komerza product. (The IDs in
     `config.js` are only the fallback for the built-in default product.)
   - **Manage keys / users**, **Generate keys**, **Status updater**, **Devlog**.

Products you create show up automatically on `products.html` with sorting/search.

---

## Quick checklist

- [ ] Repo pushed to GitHub
- [ ] Backend deployed to Railway, all Variables set, `/health` returns ok
- [ ] Railway IP whitelisted on LuaProt
- [ ] Discord app: OAuth redirect added, client id/secret in Railway
- [ ] Bot deployed to Railway with its own variables
- [ ] Cloudinary cloud name + unsigned preset in `config.js`
- [ ] `config.js` has your Railway URL + Komerza **product id**
- [ ] Site deployed to Vercel; its URL added to `CORS_ORIGINS` + `DASHBOARD_URL`
- [ ] Logged into dashboard with `ADMIN_KEY`, added a product

## If something doesn't work
- **Login does nothing / errors** → check the Discord redirect URI matches
  `DISCORD_REDIRECT_URI` exactly, and `CORS_ORIGINS` includes your Vercel URL.
- **Keys won't load** → LuaProt IP not whitelisted, or `LUAPROT_API_KEY`/`HUB_ID`
  wrong.
- **Stock/checkout missing** → set the Komerza product id in `config.js`; live
  stock also needs `KOMERZA_API_KEY` on Railway.
- **Image upload fails** → Cloudinary cloud name / unsigned preset not set in
  `config.js`.
- **CORS / 403 errors** → `CORS_ORIGINS` must contain your exact site URL.

See `SECURITY.md` for a breakdown of what's public vs secret.
