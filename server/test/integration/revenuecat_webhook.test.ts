/** T066: POST /v1/webhooks/revenuecat, every case in contracts/webhooks.md. */
import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";

import type { FastifyInstance } from "fastify";

import { buildApp } from "../../src/app";
import type { Sql } from "../../src/db/pool";
import { resetDatabase, seedWorkspace, skipReason, stubVerifier, testSql } from "./helpers";

const SECRET = "rc-secret-123";
let sql: Sql;
let app: FastifyInstance;
let noSecretApp: FastifyInstance;

before(async () => {
  if (skipReason) return;
  sql = testSql();
  const files = { root: "/tmp", signingKey: "k", publicUrl: "https://api.test" };
  app = await buildApp({ sql, verifier: stubVerifier, files, logLevel: "silent", revenueCatWebhookSecret: SECRET });
  noSecretApp = await buildApp({ sql, verifier: stubVerifier, files, logLevel: "silent", revenueCatWebhookSecret: "" });
});
after(async () => {
  await app?.close();
  await noSecretApp?.close();
  if (sql) await sql.end();
});
beforeEach(async () => {
  if (!skipReason) {
    await resetDatabase(sql);
    await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "u1", members: { m1: "member" } });
  }
});

const event = (data: Record<string, unknown> = {}) => ({
  event: {
    id: "evt_1",
    type: "INITIAL_PURCHASE",
    period_type: "NORMAL",
    app_user_id: "ws_1",
    entitlement_ids: ["pro"],
    expiration_at_ms: Date.UTC(2026, 11, 1),
    store: "PLAY_STORE",
    ...data,
  },
});
const post = (target: FastifyInstance, payload: unknown, authorization = `Bearer ${SECRET}`) =>
  target.inject({ method: "POST", url: "/v1/webhooks/revenuecat", headers: { authorization }, payload: payload as never });

test("method, secret and authorization checks", { skip: skipReason }, async () => {
  const get = await app.inject({ method: "GET", url: "/v1/webhooks/revenuecat" });
  assert.deepEqual([get.statusCode, get.json()], [405, { error: "method_not_allowed" }]);
  const missing = await post(noSecretApp, event());
  assert.deepEqual([missing.statusCode, missing.json()], [500, { error: "missing_server_secret" }]);
  const wrong = await post(app, event(), "Bearer nope");
  assert.deepEqual([wrong.statusCode, wrong.json()], [401, { error: "unauthorized" }]);
  const noWorkspace = await post(app, event({ app_user_id: " " }));
  assert.deepEqual([noWorkspace.statusCode, noWorkspace.json()], [400, { error: "missing_workspace" }]);
});

test("valid event: subscription upserted, event recorded, members notified; replay is a no-op", { skip: skipReason }, async () => {
  const first = await post(app, event());
  assert.deepEqual([first.statusCode, first.json()], [200, { ok: true }]);
  const [sub] = await sql`SELECT tier, status, store, is_auto_renewing, period_ends_at, trial_ends_at FROM subscriptions WHERE workspace_id = 'ws_1'`;
  assert.equal(sub.tier, "pro");
  assert.equal(sub.status, "active");
  assert.equal(sub.store, "PLAY_STORE");
  assert.equal(sub.is_auto_renewing, true);
  assert.equal(new Date(sub.period_ends_at).toISOString(), "2026-12-01T00:00:00.000Z");
  assert.equal(sub.trial_ends_at, null);
  const notified = await sql`SELECT target_user_id, message FROM notifications ORDER BY target_user_id`;
  assert.deepEqual(notified.map((n) => n.target_user_id), ["m1", "u1"]);
  assert.equal(notified[0].message, "Subscription is now PRO (active)");

  const replay = await post(app, event({ type: "EXPIRATION" }));
  assert.deepEqual([replay.statusCode, replay.json()], [200, { ok: true, duplicate: true }]);
  const [again] = await sql`SELECT status FROM subscriptions WHERE workspace_id = 'ws_1'`;
  assert.equal(again.status, "active", "deduped by event id");
});

test("trial sets trial end; a later event without id still applies", { skip: skipReason }, async () => {
  await post(app, event({ id: "evt_trial", period_type: "TRIAL" }));
  const [sub] = await sql`SELECT status, trial_ends_at FROM subscriptions WHERE workspace_id = 'ws_1'`;
  assert.equal(sub.status, "trial");
  assert.ok(sub.trial_ends_at);
  const res = await post(app, event({ id: undefined, type: "EXPIRATION", entitlement_ids: [] }));
  assert.equal(res.statusCode, 200);
  const [after2] = await sql`SELECT tier, status FROM subscriptions WHERE workspace_id = 'ws_1'`;
  assert.deepEqual({ ...after2 }, { tier: "free", status: "expired" });
});

test("an unknown workspace is recorded and acknowledged (no retry storm)", { skip: skipReason }, async () => {
  const res = await post(app, event({ id: "evt_x", app_user_id: "$RCAnonymousID:abc" }));
  assert.deepEqual([res.statusCode, res.json()], [200, { ok: true, ignored: "unknown_workspace" }]);
  const [recorded] = await sql`SELECT workspace_id FROM webhook_events WHERE id = 'evt_x'`;
  assert.equal(recorded.workspace_id, "$RCAnonymousID:abc");
  const subs = await sql`SELECT 1 FROM subscriptions`;
  assert.equal(subs.length, 0);
});
