import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";

import { assertMember } from "../../src/auth/roles";
import type { Sql } from "../../src/db/pool";
import { RpcError } from "../../src/domain/errors";
import type { RpcRegistry } from "../../src/rpc/types";
import {
  authHeaders,
  buildTestApp,
  resetDatabase,
  seedWorkspace,
  skipReason,
  testSql,
} from "./helpers";

// Handler authorises like the Cloud Functions do: assertMember, then a role predicate.
const registry: RpcRegistry = {
  whoAmI: {
    mutating: false,
    async handler(ctx, data) {
      const workspaceId = `${(data as { workspaceId?: string }).workspaceId ?? ""}`;
      const role = await assertMember(ctx.sql, workspaceId, ctx.uid);
      if (role === "entryOnly") {
        throw new RpcError("permission-denied", "Accounting access required");
      }
      return { uid: ctx.uid, role };
    },
  },
};

let sql: Sql;

before(() => {
  if (!skipReason) sql = testSql();
});
after(async () => {
  if (sql) await sql.end();
});
beforeEach(async () => {
  if (skipReason) return;
  await resetDatabase(sql);
  await seedWorkspace(sql, {
    workspaceId: "ws_1",
    ownerUid: "owner_1",
    members: { entry_1: "entryOnly" },
  });
});

test("missing ID token → 401 unauthenticated", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const res = await app.inject({
    method: "POST",
    url: "/v1/rpc/whoAmI",
    headers: { "x-firebase-appcheck": "ok" },
    payload: { data: { workspaceId: "ws_1" } },
  });
  assert.equal(res.statusCode, 401);
  assert.equal(res.json().error.code, "unauthenticated");
  await app.close();
});

test("invalid App Check token → 401 unauthenticated", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const res = await app.inject({
    method: "POST",
    url: "/v1/rpc/whoAmI",
    headers: { ...authHeaders("owner_1"), "x-firebase-appcheck": "forged" },
    payload: { data: { workspaceId: "ws_1" } },
  });
  assert.equal(res.statusCode, 401);
  assert.equal(res.json().error.code, "unauthenticated");
  await app.close();
});

test("valid caller with no membership → 403 permission-denied", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const res = await app.inject({
    method: "POST",
    url: "/v1/rpc/whoAmI",
    headers: authHeaders("stranger_1"),
    payload: { data: { workspaceId: "ws_1" } },
  });
  assert.equal(res.statusCode, 403);
  assert.equal(res.json().error.code, "permission-denied");
  assert.equal(res.json().error.message, "User is not a member of this workspace");
  await app.close();
});

test("role predicate denies entryOnly and allows owner", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const denied = await app.inject({
    method: "POST",
    url: "/v1/rpc/whoAmI",
    headers: authHeaders("entry_1"),
    payload: { data: { workspaceId: "ws_1" } },
  });
  assert.equal(denied.statusCode, 403);

  const allowed = await app.inject({
    method: "POST",
    url: "/v1/rpc/whoAmI",
    headers: authHeaders("owner_1"),
    payload: { data: { workspaceId: "ws_1" } },
  });
  assert.equal(allowed.statusCode, 200);
  assert.deepEqual(allowed.json(), { result: { uid: "owner_1", role: "owner" } });
  await app.close();
});
