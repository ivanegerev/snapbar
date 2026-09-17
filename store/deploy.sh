#!/bin/bash
# Deploy the SnapBar license worker to Cloudflare.
#
#   bash store/deploy.sh
#
# Run from a Mac terminal (needs network and a browser for the Cloudflare
# login). No API token is stored anywhere: wrangler does a browser OAuth login
# the first time and remembers it afterwards.
set -euo pipefail
cd "$(dirname "$0")"

WRANGLER="npx --yes wrangler@4"
URL="https://snapbar-store.ivanegerev08.workers.dev"

if ! $WRANGLER whoami >/dev/null 2>&1; then
  echo "Logging in to Cloudflare (a browser window will open)…"
  $WRANGLER login
fi

echo "==> Deploying worker"
$WRANGLER deploy

# LICENSE_SECRET signs every license key. It lives in store/.secrets.md, which
# git ignores. Changing it changes the key issued for future checkouts; keys
# already sold keep working, since the app validates them offline by checksum.
if [ -f .secrets.md ]; then
  SECRET=$(grep -m1 '^LICENSE_SECRET=' .secrets.md | cut -d= -f2-)
  if [ -n "${SECRET:-}" ]; then
    echo "==> Setting LICENSE_SECRET (from store/.secrets.md)"
    printf '%s' "$SECRET" | $WRANGLER secret put LICENSE_SECRET
  fi
fi

# STRIPE_SECRET_KEY must be a LIVE restricted key with read access to Checkout
# Sessions and nothing else:
#   dashboard.stripe.com -> Developers -> API keys -> Create restricted key
# Paste it at the prompt. It goes straight to Cloudflare, never to disk here.
echo
read -r -p "Set STRIPE_SECRET_KEY now? (requires Stripe live mode) [y/N] " ans
case "${ans:-N}" in
  y|Y) $WRANGLER secret put STRIPE_SECRET_KEY ;;
  *)   echo "Skipped. Re-run this script once Stripe live mode is on." ;;
esac

echo
echo "==> Smoke test: GET $URL/redeem?session_id=bogus"
sleep 3
curl -s "$URL/redeem?session_id=bogus"; echo
echo
echo 'Expect {"error":"bad session id"} — the worker is live.'
echo 'Still "Hello World!" — the deploy did not take.'
