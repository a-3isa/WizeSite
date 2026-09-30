#!/usr/bin/env node
/**
 * Spike check (tasks.md T012): does the self-hosted sync service accept a REAL Firebase ID token?
 *
 * Signs in with Firebase Auth (email/password, public web API key), opens the PowerSync sync
 * stream with that token, reads until the first complete checkpoint, and prints only the outcome
 * and per-table row counts. The password is read from an environment variable and never printed.
 *
 * PowerShell:
 *   $env:FB_EMAIL = "you@example.com"; $env:FB_PASSWORD = Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText
 *   node server/tools/check-sync-token.mjs
 *   Remove-Item Env:FB_PASSWORD
 *
 * (Windows PowerShell 5.1 lacks -AsPlainText; there use:  $env:FB_PASSWORD = "<password>"  then remove it.)
 * Google-only accounts have no password: set FB_ID_TOKEN to an ID token instead of FB_EMAIL/FB_PASSWORD.
 */
const WEB_API_KEY = "AIzaSyARUbYBu2-1LN7yoMIpPvfVOEQsEfydOV0"; // public client key (lib/firebase_options.dart)
const SYNC_URL = process.env.SYNC_URL ?? "https://sync.buildozer.dpdns.org";

async function idToken() {
  if (process.env.FB_ID_TOKEN) return { token: process.env.FB_ID_TOKEN.trim(), uid: "(from FB_ID_TOKEN)" };
  const email = process.env.FB_EMAIL;
  const password = process.env.FB_PASSWORD;
  if (!email || !password) {
    console.error("Set FB_EMAIL and FB_PASSWORD (or FB_ID_TOKEN). See the header of this file.");
    process.exit(2);
  }
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_API_KEY}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = await res.json();
  if (!res.ok) {
    console.error(`Firebase sign-in failed: ${body?.error?.message ?? res.status}`);
    process.exit(1);
  }
  return { token: body.idToken, uid: body.localId };
}

const { token, uid } = await idToken();
console.log(`Signed in to Firebase as uid ${uid}`);

const started = Date.now();
const controller = new AbortController();
const timer = setTimeout(() => controller.abort(), 30_000);
const res = await fetch(`${SYNC_URL}/sync/stream`, {
  method: "POST",
  headers: { authorization: `Token ${token}`, "content-type": "application/json" },
  body: JSON.stringify({ buckets: [], include_checksum: true, raw_data: true, client_id: "spike-check" }),
  signal: controller.signal,
});

if (res.status !== 200) {
  console.log(`FAIL: sync service returned HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
  process.exit(1);
}

const counts = new Map();
const reader = res.body.getReader();
const decoder = new TextDecoder();
let buffered = "";
let complete = false;
try {
  while (!complete) {
    const { value, done } = await reader.read();
    if (done) break;
    buffered += decoder.decode(value, { stream: true });
    let nl;
    while ((nl = buffered.indexOf("\n")) >= 0) {
      const line = buffered.slice(0, nl).trim();
      buffered = buffered.slice(nl + 1);
      if (!line) continue;
      const msg = JSON.parse(line);
      for (const op of msg.data?.data ?? []) {
        if (op.op === "PUT") counts.set(op.object_type, (counts.get(op.object_type) ?? 0) + 1);
      }
      if (msg.checkpoint_complete) complete = true;
    }
  }
} finally {
  clearTimeout(timer);
  controller.abort();
}

console.log(
  complete
    ? `PASS: real Firebase token accepted; first checkpoint complete in ${Date.now() - started} ms`
    : "FAIL: stream ended before a complete checkpoint",
);
console.log(
  counts.size === 0
    ? "Rows synced: none (expected until your data is migrated)"
    : `Rows synced: ${[...counts].map(([t, n]) => `${t}=${n}`).join(", ")}`,
);
process.exit(complete ? 0 : 1);
