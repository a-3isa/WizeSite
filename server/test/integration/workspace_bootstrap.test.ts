/** T039: ensureUserWorkspaceBootstrap / setActiveWorkspace, ported from functions/src/index.ts. */
import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { bootstrapWorkspaceForUser, setActiveWorkspaceForUser } from "../../src/rpc/workspace";
import { buildRegistry } from "../../src/rpc/registry";
import { authHeaders, buildTestApp, resetDatabase, seedWorkspace, skipReason, testSql } from "./helpers";

let sql: Sql;
before(() => {
  if (!skipReason) sql = testSql();
});
after(async () => {
  if (sql) await sql.end();
});
beforeEach(async () => {
  if (!skipReason) await resetDatabase(sql);
});

test("existing member: returns their workspace and keeps profile values", { skip: skipReason }, async () => {
  await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "u1" });
  await sql`INSERT INTO user_profiles (uid, email, full_name, default_currency, setup_completed, active_workspace_id)
            VALUES ('u1', 'old@example.com', 'اسم قديم', 'SAR', true, 'ws_1')`;

  const result = await bootstrapWorkspaceForUser(sql, { uid: "u1", email: "NEW@example.com", fullName: "New Name" });

  assert.deepEqual(result, { workspaceId: "ws_1", created: false, setupCompleted: true });
  const [profile] = await sql`SELECT email, full_name, default_currency FROM user_profiles WHERE uid = 'u1'`;
  assert.equal(profile.email, "old@example.com", "existing values win over token values");
  assert.equal(profile.full_name, "اسم قديم");
  assert.equal(profile.default_currency, "SAR");
});

test("brand-new user: creates workspace, owner membership and profile", { skip: skipReason }, async () => {
  const result = await bootstrapWorkspaceForUser(sql, { uid: "new_1", email: "N@Example.com", fullName: "Sara" });

  assert.equal(result.created, true);
  assert.equal(result.setupCompleted, false);
  assert.match(result.workspaceId, /^[A-Za-z0-9]{20}$/, "Firestore-style id");
  const [ws] = await sql`SELECT name, owner_uid FROM workspaces WHERE id = ${result.workspaceId}`;
  assert.equal(ws.name, "Sara Workspace");
  assert.equal(ws.owner_uid, "new_1");
  const [m] = await sql`SELECT role FROM memberships WHERE workspace_id = ${result.workspaceId} AND user_uid = 'new_1'`;
  assert.equal(m.role, "owner");
  const [p] = await sql`SELECT email, default_currency, risk_alerts_enabled, setup_completed FROM user_profiles WHERE uid = 'new_1'`;
  assert.deepEqual(
    { ...p },
    { email: "n@example.com", default_currency: "EGP", risk_alerts_enabled: true, setup_completed: false },
  );
});

test("bootstrap is stable: a second call returns the same workspace", { skip: skipReason }, async () => {
  const first = await bootstrapWorkspaceForUser(sql, { uid: "new_2" });
  const second = await bootstrapWorkspaceForUser(sql, { uid: "new_2" });
  assert.equal(second.workspaceId, first.workspaceId);
  assert.equal(second.created, false);
  const [{ n }] = await sql<{ n: number }[]>`SELECT count(*)::int AS n FROM workspaces WHERE owner_uid = 'new_2'`;
  assert.equal(n, 1);
});

test("legacy active workspace owned by the user gets an owner membership", { skip: skipReason }, async () => {
  await sql`INSERT INTO workspaces (id, owner_uid, name) VALUES ('ws_legacy', 'u2', 'Legacy')`;
  await sql`INSERT INTO user_profiles (uid, active_workspace_id, setup_completed) VALUES ('u2', 'ws_legacy', true)`;

  const result = await bootstrapWorkspaceForUser(sql, { uid: "u2" });

  assert.deepEqual(result, { workspaceId: "ws_legacy", created: false, setupCompleted: true });
  const [m] = await sql`SELECT role FROM memberships WHERE workspace_id = 'ws_legacy' AND user_uid = 'u2'`;
  assert.equal(m.role, "owner");
});

test("legacy pointer to someone else's workspace without membership is rejected", { skip: skipReason }, async () => {
  await sql`INSERT INTO workspaces (id, owner_uid, name) VALUES ('ws_other', 'someone', 'Other')`;
  await sql`INSERT INTO user_profiles (uid, active_workspace_id) VALUES ('u3', 'ws_other')`;
  await assert.rejects(
    bootstrapWorkspaceForUser(sql, { uid: "u3" }),
    (e: unknown) => (e as { code?: string }).code === "failed-precondition",
  );
});

test("setActiveWorkspace: member can switch; stranger is denied; owner without membership is repaired", { skip: skipReason }, async () => {
  await seedWorkspace(sql, { workspaceId: "ws_a", ownerUid: "u1", members: { u2: "member" } });
  await sql`INSERT INTO workspaces (id, owner_uid, name) VALUES ('ws_owned', 'u2', 'Owned')`;

  assert.deepEqual(await setActiveWorkspaceForUser(sql, { uid: "u2", workspaceId: "ws_a" }), { workspaceId: "ws_a" });
  const [p] = await sql`SELECT active_workspace_id FROM user_profiles WHERE uid = 'u2'`;
  assert.equal(p.active_workspace_id, "ws_a");

  await assert.rejects(
    setActiveWorkspaceForUser(sql, { uid: "stranger", workspaceId: "ws_a" }),
    (e: unknown) => (e as { code?: string }).code === "permission-denied",
  );

  await setActiveWorkspaceForUser(sql, { uid: "u2", workspaceId: "ws_owned" });
  const [m] = await sql`SELECT role FROM memberships WHERE workspace_id = 'ws_owned' AND user_uid = 'u2'`;
  assert.equal(m.role, "owner");
});

test("RPC endpoints are registered and use the caller's token claims", { skip: skipReason }, async () => {
  const app = await buildTestApp(
    sql,
    buildRegistry({ files: { root: "/tmp", signingKey: "k", publicUrl: "https://api.test" } }),
  );
  const res = await app.inject({
    method: "POST",
    url: "/v1/rpc/ensureUserWorkspaceBootstrap",
    headers: authHeaders("rpc_user", "boot-1"),
    payload: { data: {} },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().result.created, true);

  const missing = await app.inject({
    method: "POST",
    url: "/v1/rpc/setActiveWorkspace",
    headers: authHeaders("rpc_user", "switch-1"),
    payload: { data: {} },
  });
  assert.equal(missing.statusCode, 400);
  assert.equal(missing.json().error.message, "Missing required field: workspaceId");
  await app.close();
});
