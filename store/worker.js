/**
 * SnapBar license worker (Cloudflare Workers).
 *
 * GET /redeem?session_id=cs_...
 *   Verifies the Stripe Checkout session is paid, then returns a license key
 *   derived deterministically from the session id — so re-visiting the thank-you
 *   page always shows the same key, with no database needed.
 *
 * Key format matches LicenseManager.swift: SNAP2-<base64url(id)>.<base64url(sig)>,
 * where id is the first 12 bytes of HMAC(LICENSE_SECRET, session id) and sig is
 * an Ed25519 signature over "snapbar-license-v2:" + id. The app only holds the
 * public key, so keys can't be forged from the source.
 *
 * Required secrets (wrangler secret put ...):
 *   STRIPE_SECRET_KEY    — sk_live_... (restricted key with Checkout Session read is enough)
 *   LICENSE_SECRET       — any long random string; changing it changes the key a
 *                          revisited thanks link shows (old keys stay valid)
 *   LICENSE_SIGNING_KEY  — base64 raw 32-byte Ed25519 private key, from
 *                          store/.secrets-signing-key
 */

const CORS = {
  "Access-Control-Allow-Origin": "https://ivanegerev.github.io",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Content-Type": "application/json",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: CORS });
    }

    if (url.pathname === "/redeem") {
      const sessionId = url.searchParams.get("session_id") || "";
      if (!/^cs_[a-zA-Z0-9_]+$/.test(sessionId)) {
        return json({ error: "bad session id" }, 400);
      }

      const resp = await fetch(
        `https://api.stripe.com/v1/checkout/sessions/${sessionId}`,
        { headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` } }
      );
      if (!resp.ok) return json({ error: "unknown session" }, 404);

      const session = await resp.json();
      if (session.payment_status !== "paid") {
        return json({ error: "not paid" }, 402);
      }

      const key = await makeKey(sessionId, env.LICENSE_SECRET, env.LICENSE_SIGNING_KEY);
      return json({ key, email: session.customer_details?.email ?? null });
    }

    return json({ error: "not found" }, 404);
  },
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: CORS });
}

// PKCS#8 DER header for an Ed25519 private key; WebCrypto can't import a raw one.
const PKCS8_ED25519 = [0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20];
const enc = new TextEncoder();

async function makeKey(seed, secret, signingKey) {
  const hmacKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const id = new Uint8Array(await crypto.subtle.sign("HMAC", hmacKey, enc.encode(seed))).slice(0, 12);

  const raw = Uint8Array.from(atob(signingKey.trim()), (c) => c.charCodeAt(0));
  const edKey = await crypto.subtle.importKey(
    "pkcs8",
    new Uint8Array([...PKCS8_ED25519, ...raw]),
    { name: "Ed25519" },
    false,
    ["sign"]
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("Ed25519", edKey, new Uint8Array([...enc.encode("snapbar-license-v2:"), ...id]))
  );
  return `SNAP2-${base64url(id)}.${base64url(sig)}`;
}

function base64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
