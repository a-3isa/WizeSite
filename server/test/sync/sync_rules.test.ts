/**
 * Sync-rule tests against a real PowerSync service (compose.test.yml, powersync.test.yaml).
 * Verifies visibility copied from firestore.rules (contracts/sync-rules.md "Guarantees tested").
 * Skipped unless TEST_DATABASE_URL and SYNC_TEST_URL are set.
 */
import assert from "node:assert/strict";
import { createHmac, randomUUID } from "node:crypto";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { resetDatabase, seedWorkspace, TEST_DATABASE_URL, testSql } from "../integration/helpers";

const SYNC_URL = process.env.SYNC_TEST_URL ?? "";
const skip = TEST_DATABASE_URL && SYNC_URL ? false : "TEST_DATABASE_URL / SYNC_TEST_URL not set";
const TEST_SECRET = "wizesite-sync-rules-test-secret-000"; // matches powersync.test.yaml
const REPLICATION_TIMEOUT_MS = 20_000;

type Rows = Map<string, Map<string, Record<string, unknown>>>; // table -> id -> row

function b64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

function tokenFor(uid: string): string {
  const header = b64url(JSON.stringify({ alg: "HS256", typ: "JWT", kid: "wizesite-test" }));
  const now = Math.floor(Date.now() / 1000);
  const payload = b64url(
    JSON.stringify({ sub: uid, aud: "wizesite-test", iat: now, exp: now + 300 }),
  );
  const signature = createHmac("sha256", TEST_SECRET).update(`${header}.${payload}`).digest();
  return `${header}.${payload}.${b64url(signature)}`;
}

/** Opens a fresh sync stream and returns the device-visible rows at the first full checkpoint. */
async function syncOnce(uid: string): Promise<Rows> {
  const controller = new AbortController();
  const res = await fetch(`${SYNC_URL}/sync/stream`, {
    method: "POST",
    headers: { authorization: `Token ${tokenFor(uid)}`, "content-type": "application/json" },
    body: JSON.stringify({ buckets: [], include_checksum: true, raw_data: true, client_id: randomUUID() }),
    signal: controller.signal,
  });
  assert.equal(res.status, 200, `sync stream status for ${uid}`);
  const rows: Rows = new Map();
  const reader = res.body!.getReader();
  const decoder = new TextDecoder();
  let buffered = "";
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buffered += decoder.decode(value, { stream: true });
      let newline: number;
      while ((newline = buffered.indexOf("\n")) >= 0) {
        const line = buffered.slice(0, newline).trim();
        buffered = buffered.slice(newline + 1);
        if (!line) continue;
        const message = JSON.parse(line);
        if (message.data) {
          for (const op of message.data.data as Array<Record<string, unknown>>) {
            const table = `${op.object_type}`;
            const id = `${op.object_id}`;
            if (!rows.has(table)) rows.set(table, new Map());
            if (op.op === "PUT") {
              const data = typeof op.data === "string" ? JSON.parse(op.data) : op.data;
              rows.get(table)!.set(id, data as Record<string, unknown>);
            } else if (op.op === "REMOVE") {
              rows.get(table)!.delete(id);
            }
          }
        }
        if (message.checkpoint_complete) {
          return rows;
        }
      }
    }
  } finally {
    controller.abort();
  }
  return rows;
}

/** Polls fresh syncs until `ready(rows)` holds, absorbing replication lag. */
async function syncUntil(uid: string, ready: (rows: Rows) => boolean): Promise<Rows> {
  const deadline = Date.now() + REPLICATION_TIMEOUT_MS;
  let rows = await syncOnce(uid);
  while (!ready(rows) && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    rows = await syncOnce(uid);
  }
  return rows;
}

const has = (rows: Rows, table: string, id: string) => rows.get(table)?.has(id) ?? false;
const count = (rows: Rows, table: string) => rows.get(table)?.size ?? 0;

let sql: Sql;
before(() => {
  if (!skip) sql = testSql();
});
after(async () => {
  if (sql) await sql.end();
});

async function seedFinancialData(workspaceId: string, suffix: string): Promise<void> {
  await sql`INSERT INTO projects (id, workspace_id, name, contract_value)
            VALUES (${`p_${suffix}`}, ${workspaceId}, 'Tower', 1000)`;
  await sql`INSERT INTO expenses (id, workspace_id, project_id, amount, date, category)
            VALUES (${`e_${suffix}`}, ${workspaceId}, ${`p_${suffix}`}, 100, now(), 'materials')`;
  await sql`INSERT INTO payments (id, workspace_id, project_id, amount, date)
            VALUES (${`pay_${suffix}`}, ${workspaceId}, ${`p_${suffix}`}, 500, now())`;
  await sql`INSERT INTO project_metrics (project_id, workspace_id, payload)
            VALUES (${`p_${suffix}`}, ${workspaceId}, ${sql.json({ totalExpenses: 100 })})`;
}

beforeEach(async () => {
  if (skip) return;
  await resetDatabase(sql);
  await seedWorkspace(sql, {
    workspaceId: "ws_a",
    ownerUid: "owner_a",
    members: { member_a: "member", acct_a: "accountingApproved" },
  });
  await seedWorkspace(sql, { workspaceId: "ws_b", ownerUid: "owner_b" });
  await seedFinancialData("ws_a", "a");
  await seedFinancialData("ws_b", "b");
});

test("owner receives member and financial rows of own workspace only", { skip }, async () => {
  const rows = await syncUntil("owner_a", (r) => has(r, "payments", "pay_a"));
  assert.ok(has(rows, "expenses", "e_a"));
  assert.ok(has(rows, "payments", "pay_a"));
  assert.ok(has(rows, "project_metrics", "p_a"), "metrics synced with project_id aliased as id");
  assert.ok(!has(rows, "expenses", "e_b"), "no rows from another workspace");
  assert.ok(!has(rows, "payments", "pay_b"));
});

test("plain member receives zero rows from financial tables", { skip }, async () => {
  const rows = await syncUntil("member_a", (r) => has(r, "expenses", "e_a"));
  assert.ok(has(rows, "expenses", "e_a"), "member sees expenses (inWorkspace)");
  assert.ok(has(rows, "projects", "p_a"));
  for (const table of ["payments", "project_metrics", "attachments", "project_summaries"]) {
    assert.equal(count(rows, table), 0, `${table} must not reach a plain member`);
  }
});

test("accountingApproved receives financial rows", { skip }, async () => {
  const rows = await syncUntil("acct_a", (r) => has(r, "payments", "pay_a"));
  assert.ok(has(rows, "payments", "pay_a"));
});

test("non-member receives nothing from either workspace", { skip }, async () => {
  await sql`INSERT INTO workspaces (id, owner_uid, name) VALUES ('ws_c', 'stranger', 'C')`;
  const rows = await syncUntil("stranger", (r) => has(r, "workspaces", "ws_c"));
  assert.ok(has(rows, "workspaces", "ws_c"), "sees own workspace");
  for (const table of ["expenses", "payments", "projects"]) {
    assert.equal(count(rows, table), 0, `${table} leaked to a non-member`);
  }
});

test("workspace owner without a membership row still syncs (isWorkspaceOwner)", { skip }, async () => {
  await sql`DELETE FROM memberships WHERE id = 'ws_a_owner_a'`;
  const rows = await syncUntil("owner_a", (r) => has(r, "payments", "pay_a"));
  assert.ok(has(rows, "expenses", "e_a"));
  assert.ok(has(rows, "payments", "pay_a"));
});

test("removing a membership removes that workspace's rows", { skip }, async () => {
  await syncUntil("member_a", (r) => has(r, "expenses", "e_a"));
  await sql`DELETE FROM memberships WHERE id = 'ws_a_member_a'`;
  const rows = await syncUntil("member_a", (r) => !has(r, "expenses", "e_a"));
  assert.equal(count(rows, "expenses"), 0);
  assert.equal(count(rows, "projects"), 0);
});

test("deletes propagate", { skip }, async () => {
  await syncUntil("owner_a", (r) => has(r, "expenses", "e_a"));
  await sql`DELETE FROM expenses WHERE id = 'e_a'`;
  const rows = await syncUntil("owner_a", (r) => !has(r, "expenses", "e_a"));
  assert.ok(!has(rows, "expenses", "e_a"));
});

test("user_self bucket carries own profile (uid aliased as id) and notifications", { skip }, async () => {
  await sql`INSERT INTO user_profiles (uid, email, full_name) VALUES ('member_a', 'm@example.com', 'مستخدم')`;
  await sql`INSERT INTO notifications (id, workspace_id, target_user_id, title)
            VALUES ('n1', 'ws_a', 'member_a', 'Hi'), ('n2', 'ws_a', 'owner_a', 'Other')`;
  const rows = await syncUntil("member_a", (r) => has(r, "user_profiles", "member_a"));
  assert.equal(rows.get("user_profiles")?.get("member_a")?.full_name, "مستخدم");
  assert.ok(has(rows, "notifications", "n1"));
  assert.ok(!has(rows, "notifications", "n2"), "other users' notifications never sync");
});
