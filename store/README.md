# SnapBar store — payment setup

**Status: LIVE in Stripe test mode.** Products, prices and Payment Links exist;
`docs/buy.html` redirects to them and `docs/thanks.html` issues license keys.
Test checkout with card `4242 4242 4242 4242`, any future expiry, any CVC.

- Lifetime $14.99 → https://buy.stripe.com/test_4gMcN456o0oX19q7TJgQE00
- Monthly $1.99 → https://buy.stripe.com/test_3cI8wO8iA8Vt9FWa1RgQE01

**To take real money:** switch the Stripe account to live mode, recreate the two
Payment Links with a live key (same two API calls, see git history), and swap
the URLs in `docs/buy.html`. The secret key is deliberately not stored in this
repo — keep it in a keychain or env var.

**Key delivery (current):** `thanks.html` derives the key client-side from the
Stripe session id (SHA-256 → base-36 checksum format). Deterministic, so
revisiting the link re-shows the same key. This is honor-system: it doesn't
verify payment server-side — same trust level as the app's offline validation.

**Key delivery (upgrade):** deploy `worker.js` to Cloudflare and set
`WORKER_URL` in `thanks.html`; the page then verifies the session was actually
paid via the Stripe API before issuing a key. Setup below (~15 minutes; the
worker also needs a free Cloudflare account).

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
