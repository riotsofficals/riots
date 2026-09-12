/* ============================================================
   riots.wtf — PUBLIC frontend config
   ------------------------------------------------------------
   IMPORTANT: everything in this file is PUBLIC. It ships to the
   browser and anyone can read it in "view source". That is fine —
   none of these are secrets:
     • API_BASE          = the address of your backend (public)
     • CLIENT_TOKEN      = optional friction token (not real security)
     • KOMERZA product/variant IDs = public by design (checkout needs them)

   SECRETS (LuaProt key, Komerza API key, Discord secret, admin key)
   live ONLY in the backend's environment variables on Railway —
   never here, never on Vercel. See SETUP.md.
   ============================================================ */
window.RIOTS_CONFIG = {
  // Your deployed backend (Railway). Change after you deploy.
  API_BASE: "http://localhost:8080",

  // Optional: set the SAME value as the backend FRONTEND_TOKEN to require it.
  // Leave "" to disable. (Not a real secret — just blocks casual scraping.)
  CLIENT_TOKEN: "",

  // Cloudinary (PUBLIC — unsigned upload preset). The admin dashboard uploads
  // product images straight to Cloudinary from the browser. An unsigned preset
  // is safe to expose; it can only upload, not read/delete your account.
  CLOUDINARY: {
    cloudName: "",     // e.g. "riotswtf"
    uploadPreset: "",  // your UNSIGNED upload preset name
  },

  // Komerza PUBLIC ids (safe to expose — checkout needs them client-side).
  KOMERZA: {
    storeId: "e2f2de20-0a61-4634-aaba-a2e4d476bcd9",
    // TODO: paste your Komerza PRODUCT id here (dashboard → product → it's in the URL / details).
    productId: "REPLACE_WITH_PRODUCT_ID",
    variants: {
      lifetime: "b5b90fd3-db55-4f73-943a-3a6625edee46",
      monthly:  "3a1b2e3a-4151-4ccb-859e-f0803ef09cc9",
    },
    theme: "dark",
  },
};

// Back-compat aliases used by dashboard.js
window.RIOTS_API_BASE = window.RIOTS_CONFIG.API_BASE;
window.RIOTS_CLIENT_TOKEN = window.RIOTS_CONFIG.CLIENT_TOKEN;
