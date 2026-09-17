# SnapBar store — payment setup

**Status: checkout is OFF.** `docs/buy.html` has an empty `PAYMENT_LINKS`, so
clicking Buy on the site shows the trial + "email for a key" page instead of
redirecting anywhere. That is deliberate: the Stripe account is still a sandbox,
and a test-mode Payment Link declines every real card on a page that looks like
a real store. Checkout turns back on the moment two live links go into that
object.

Prices on the site: **$19.99 lifetime**, **$2.99/month**. Both plans issue the
same key format.

## What's left to take real money

1. **Activate Stripe** (only Ivan can do this — identity and bank details):
   dashboard.stripe.com → *Verify your business*. Business type "Individual",
   website `https://ivanegerev.github.io/snapbar/`.

2. **Create two live Payment Links** at the prices above. For each one set
   *After payment → redirect to*:
   `https://ivanegerev.github.io/snapbar/thanks.html?session_id={CHECKOUT_SESSION_ID}`

3. **Paste them into `docs/buy.html`** (`PAYMENT_LINKS.lifetime` and
   `.monthly`), commit, push. Pages redeploys on its own.

4. **Deploy the licence worker**: `bash store/deploy.sh`. It logs in to
   Cloudflare through the browser, deploys `worker.js`, sets `LICENSE_SECRET`
   from `store/.secrets.md`, and prompts for a live restricted Stripe key
   (Checkout Sessions: read). The worker already exists at
   `https://snapbar-store.ivanegerev08.workers.dev` but is still the Cloudflare
   hello-world placeholder until this runs.

5. **Point the site at the worker**: set `WORKER_URL` in `docs/thanks.html` to
   the workers.dev URL. Do this *after* step 4, not before — with a
   `WORKER_URL` set and no `STRIPE_SECRET_KEY` on the worker, every buyer sees
   "we couldn't verify this purchase".

## How key delivery works

Stripe redirects to `thanks.html?session_id=cs_…`. That page either

- **calls the worker** (`WORKER_URL` set): the worker asks Stripe whether the
  session is actually paid, and only then returns a key derived as
  `HMAC(LICENSE_SECRET, session_id)`; or
- **derives the key in the browser** (`WORKER_URL` empty — today's behaviour):
  `SHA-256("snapbar-license-v1:" + session_id)`, with no payment check.

Both produce the same `SNAP-XXXXX-XXXXX-XXXXX` shape, and the app validates
either offline in `LicenseManager.swift`, so keys issued under one scheme keep
working after a switch to the other. Either way the page is deterministic:
reopening the link re-shows the same key. Stripe emails the receipt separately.

## Notes

- Subscriptions issue the same offline key. Revoking a key on cancellation
  would need the app to phone home, which it deliberately never does. Treat the
  monthly plan as pay-what-feels-right.
- If `LICENSE_SECRET` leaks, rotate it. Keys already issued stay valid, since
  validation is an offline checksum; new sessions just derive different keys.
- `store/.secrets*` is gitignored. Nothing in this directory that is committed
  contains a credential.
