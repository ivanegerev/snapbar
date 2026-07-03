/**
 * SnapBar license worker (Cloudflare Workers).
 *
 * GET /redeem?session_id=cs_...
 *   Verifies the Stripe Checkout session is paid, then returns a license key
 *   derived deterministically from the session id — so re-visiting the thank-you
 *   page always shows the same key, with no database needed.
 *
 * Key format matches LicenseManager.swift: SNAP-XXXXX-XXXXX-XXXXX where the
 * 15-char base-36 body has a digit sum divisible by 36.
 *
 * Required secrets (wrangler secret put ...):
 *   STRIPE_SECRET_KEY  — sk_live_... (restricted key with Checkout Session read is enough)
 *   LICENSE_SECRET     — any long random string; changing it changes all keys
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

      const key = await makeKey(sessionId, env.LICENSE_SECRET);
      return json({ key, email: session.customer_details?.email ?? null });
    }

    return json({ error: "not found" }, 404);
  },
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: CORS });
}

const ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

async function makeKey(seed, secret) {
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("HMAC", keyMaterial, new TextEncoder().encode(seed))
  );

  const values = Array.from(sig.slice(0, 14), (b) => b % 36);
  const sum = values.reduce((a, b) => a + b, 0);
  values.push((36 - (sum % 36)) % 36);

  const body = values.map((v) => ALPHABET[v]).join("");
  return `SNAP-${body.slice(0, 5)}-${body.slice(5, 10)}-${body.slice(10, 15)}`;
}
