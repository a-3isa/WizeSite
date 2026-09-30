import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { RpcError, type RpcErrorCode } from "../../src/domain/errors";
import type { RpcRegistry } from "../../src/rpc/types";
import { authHeaders, buildTestApp, resetDatabase, skipReason, testSql } from "./helpers";

const registry: RpcRegistry = {
  echo: {
    mutating: false,
    async handler(_ctx, data) {
      return { echoed: data };
    },
  },
  fail: {
    mutating: false,
    async handler(_ctx, data) {
      const code = (data as { code: RpcErrorCode }).code;
      throw new RpcError(code, `failed with ${code}`, { reason: "test" });
    },
  },
  crash: {
    mutating: false,
    async handler() {
      throw new Error("secret internal detail");
    },
  },
  createThing: {
    mutating: true,
    async handler(ctx, data) {
      const name = `${(data as { name?: string }).name ?? ""}`;
      const [row] = await ctx.sql<{ id: string }[]>`
        INSERT INTO workspaces (id, owner_uid, name)
        VALUES (${`ws_${name}_${Date.now()}_${Math.random()}`}, ${ctx.uid}, ${name})
        RETURNING id`;
      return { id: row.id };
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
  if (!skipReason) await resetDatabase(sql);
});

test("{data} request → {result} response", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const res = await app.inject({
    method: "POST",
    url: "/v1/rpc/echo",
    headers: authHeaders("u1"),
    payload: { data: { a: 1, text: "مرحبا" } },
  });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.json(), { result: { echoed: { a: 1, text: "مرحبا" } } });
  await app.close();
});

test("each error code maps to its HTTP status with the envelope", { skip: skipReason }, async () => {
  const expected: Record<string, number> = {
    "invalid-argument": 400,
    "failed-precondition": 412,
    unauthenticated: 401,
    "permission-denied": 403,
    "not-found": 404,
    "already-exists": 409,
    "resource-exhausted": 429,
    internal: 500,
    unavailable: 503,
  };
  const app = await buildTestApp(sql, registry);
  for (const [code, status] of Object.entries(expected)) {
    const res = await app.inject({
      method: "POST",
      url: "/v1/rpc/fail",
      headers: authHeaders("u1"),
      payload: { data: { code } },
    });
    assert.equal(res.statusCode, status, code);
    assert.deepEqual(res.json(), {
      error: { code, message: `failed with ${code}`, details: { reason: "test" } },
    });
  }
  await app.close();
});

test("unexpected errors become internal without leaking detail", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const res = await app.inject({
    method: "POST",
    url: "/v1/rpc/crash",
    headers: authHeaders("u1"),
    payload: { data: {} },
  });
  assert.equal(res.statusCode, 500);
  assert.equal(res.json().error.code, "internal");
  assert.doesNotMatch(res.body, /secret internal detail/);
  await app.close();
});

test("unknown function → 404 not-found", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const res = await app.inject({
    method: "POST",
    url: "/v1/rpc/doesNotExist",
    headers: authHeaders("u1"),
    payload: { data: {} },
  });
  assert.equal(res.statusCode, 404);
  assert.equal(res.json().error.code, "not-found");
  await app.close();
});

test("body over 1 MB → 413", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const res = await app.inject({
    method: "POST",
    url: "/v1/rpc/echo",
    headers: { ...authHeaders("u1"), "content-type": "application/json" },
    payload: JSON.stringify({ data: { blob: "x".repeat(1024 * 1024 + 10) } }),
  });
  assert.equal(res.statusCode, 413);
  await app.close();
});

test("rate limit → 429 resource-exhausted with retryAfterSeconds", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry, { rateLimitMax: 3 });
  let last = 0;
  let body: { error?: { code: string; details?: { retryAfterSeconds?: number } } } = {};
  for (let i = 0; i < 4; i++) {
    const res = await app.inject({
      method: "POST",
      url: "/v1/rpc/echo",
      headers: authHeaders("u_rate"),
      payload: { data: {} },
    });
    last = res.statusCode;
    body = res.json();
  }
  assert.equal(last, 429);
  assert.equal(body.error?.code, "resource-exhausted");
  assert.ok((body.error?.details?.retryAfterSeconds ?? 0) > 0);
  await app.close();
});

test("mutating function requires X-Idempotency-Key", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const res = await app.inject({
    method: "POST",
    url: "/v1/rpc/createThing",
    headers: authHeaders("u1"),
    payload: { data: { name: "a" } },
  });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error.code, "invalid-argument");
  await app.close();
});

test("replaying an idempotency key returns the stored response and writes once", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const send = () =>
    app.inject({
      method: "POST",
      url: "/v1/rpc/createThing",
      headers: authHeaders("u1", "key-123"),
      payload: { data: { name: "once" } },
    });
  const first = await send();
  const second = await send();
  assert.equal(first.statusCode, 200);
  assert.equal(second.statusCode, 200);
  assert.deepEqual(second.json(), first.json());
  const [{ count }] = await sql<{ count: string }[]>`
    SELECT count(*) FROM workspaces WHERE name = 'once'`;
  assert.equal(Number(count), 1);
  await app.close();
});

test("a failed mutation stores nothing, so a retry can succeed", { skip: skipReason }, async () => {
  const failingRegistry: RpcRegistry = {
    ...registry,
    flaky: {
      mutating: true,
      async handler(ctx) {
        await ctx.sql`INSERT INTO workspaces (id, owner_uid, name) VALUES ('ws_flaky', ${ctx.uid}, 'flaky')`;
        throw new RpcError("unavailable", "try again");
      },
    },
  };
  const app = await buildTestApp(sql, failingRegistry);
  const res = await app.inject({
    method: "POST",
    url: "/v1/rpc/flaky",
    headers: authHeaders("u1", "key-flaky"),
    payload: { data: {} },
  });
  assert.equal(res.statusCode, 503);
  const rows = await sql`SELECT 1 FROM workspaces WHERE id = 'ws_flaky'
                         UNION ALL SELECT 1 FROM idempotency_keys`;
  assert.equal(rows.length, 0, "transaction rolled back: no row, no stored key");
  await app.close();
});

test("concurrent requests with the same key write exactly once", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, registry);
  const send = () =>
    app.inject({
      method: "POST",
      url: "/v1/rpc/createThing",
      headers: authHeaders("u1", "key-race"),
      payload: { data: { name: "race" } },
    });
  const responses = await Promise.all([send(), send(), send(), send()]);
  assert.ok(responses.every((r) => r.statusCode === 200));
  const ids = new Set(responses.map((r) => r.json().result.id));
  assert.equal(ids.size, 1, "every caller sees the same stored result");
  const [{ count }] = await sql<{ count: string }[]>`
    SELECT count(*) FROM workspaces WHERE name = 'race'`;
  assert.equal(Number(count), 1);
  await app.close();
});
