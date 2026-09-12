# riots.wtf

The full riots.wtf stack: marketing site + dashboard (static), a key-management
API, and a Discord bot.

## 👉 Setup

**Read [`SETUP.md`](./SETUP.md)** — it walks you through deploying and configuring
everything step by step (Railway, Vercel, Discord, LuaProt, Komerza, Cloudinary).

## Layout

```
website/
├─ index.html / products.html / status.html / referral.html   # marketing site
├─ dashboard.html + dashboard.js                               # customer + admin dashboard
├─ config.js                                                   # PUBLIC frontend config (edit this)
├─ styles.css / script.js                                      # shared styles + JS
├─ gui.png (logo) / product1.png (fallback image)
├─ backend/     # Node/Express API  → deploy to Railway (holds secrets)
└─ bot/         # Python Discord bot → deploy to Railway (holds secrets)
```

## The three pieces

| Piece | Tech | Hosts on | Secrets? |
|---|---|---|---|
| Site + Dashboard | static HTML/CSS/JS | **Vercel** | no |
| API | Node/Express | **Railway** | yes (env vars) |
| Discord bot | Python (discord.py) | **Railway** | yes (env vars) |

## Security model

Secrets live **only** in the backend/bot environment variables on Railway. The
website (Vercel) holds nothing sensitive — only public values (your backend URL,
Komerza product IDs, Cloudinary upload preset). See `SECURITY.md`.

## Products

Products are managed from **Dashboard → Admin → Products** (not hardcoded). Each
product has its own Komerza product + variant IDs, image (Cloudinary upload),
price, category, etc. The store page reads them from the backend.
