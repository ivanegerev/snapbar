# SnapBar store — payment setup

Everything is wired except the two things only the account owner can create:
a **Stripe account** and a **Cloudflare account** (both free to open; Stripe
takes 2.9% + 30¢ per sale). Total setup is ~20 minutes.

## How it works

1. Buyer clicks Buy on the site → `docs/buy.html` redirects to a **Stripe
   Payment Link** (one for $14.99 one-time, one for $1.99/mo).
2. Stripe redirects back to `docs/thanks.html?session_id={CHECKOUT_SESSION_ID}`.
3. The page calls the **Cloudflare Worker** (`worker.js`) `/redeem` endpoint,
   which verifies the session is paid with the Stripe API and derives the
   license key (HMAC of the session id — deterministic, no database).
4. Buyer pastes the key into SnapBar → `LicenseManager` validates offline.

Stripe also emails a receipt; the thank-you page is the key delivery. Refreshing
it always re-shows the same key.

## Setup steps

1. **Stripe** (dashboard.stripe.com):
   - Create two Products: "SnapBar Pro — Lifetime" $14.99 one-time,
     "SnapBar Pro — Monthly" $1.99/month recurring.
   - Create a **Payment Link** for each. In the link settings, set
     *After payment → redirect to*:
     `https://ivanegerev.github.io/snapbar/thanks.html?session_id={CHECKOUT_SESSION_ID}`
   - Create a **restricted API key** with read access to Checkout Sessions.

2. **Cloudflare Worker**:
   ```sh
   cd store
   npx wrangler login
   npx wrangler secret put STRIPE_SECRET_KEY   # the restricted key
   npx wrangler secret put LICENSE_SECRET      # e.g. `openssl rand -hex 32`
   npx wrangler deploy
   ```
   Note the deployed URL, e.g. `https://snapbar-store.<you>.workers.dev`.

3. **Wire the site** (two constants):
   - `docs/buy.html` → `PAYMENT_LINKS = { lifetime: "...", monthly: "..." }`
   - `docs/thanks.html` → `WORKER_URL = "https://snapbar-store....workers.dev"`
   - Commit and push; Pages redeploys automatically.

Until these are filled in, `buy.html` shows a "store is opening" notice with an
email fallback, so nothing on the site is a dead link.

## Notes

- Subscriptions: the monthly plan issues the same offline key. To *revoke* keys
  on cancellation you'd need the app to phone home — deliberately not built, in
  keeping with the no-cloud promise. Treat monthly as pay-what-feels-right.
- If `LICENSE_SECRET` ever leaks, rotate it; old keys stay valid (offline
  checksum) but new sessions derive different keys.
