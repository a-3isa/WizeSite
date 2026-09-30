/** T078: nightly reconciler recomputes every project and reports money drift. */
import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { recomputeProject } from "../../src/recompute/persist";
import { msUntilNextRun, reconcile, runAndRecord } from "../../src/recompute/reconcile";
import { resetDatabase, seedWorkspace, skipReason, testSql } from "./helpers";

let sql: Sql;
before(() => {
  if (!skipReason) sql = testSql();
});
after(async () => {
  if (sql) await sql.end();
});
beforeEach(async () => {
  if (!skipReason) {
    await resetDatabase(sql);
    await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "u1" });
    await sql`INSERT INTO projects (id, workspace_id, name, contract_value) VALUES ('p1', 'ws_1', 'A', 1000), ('p2', 'ws_1', 'B', 500)`;
    await recomputeProject(sql, "ws_1", "p1");
    await recomputeProject(sql, "ws_1", "p2");
  }
});

test("no drift when stored totals match the records", { skip: skipReason }, async () => {
  const result = await reconcile(sql);
  assert.equal(result.projects, 2);
  assert.deepEqual(result.drift, []);
});

test("a record written behind the API's back is reported once and repaired", { skip: skipReason }, async () => {
  await sql`INSERT INTO expenses (id, workspace_id, project_id, amount, date) VALUES ('e1', 'ws_1', 'p1', 75.5, now())`;
  const first = await reconcile(sql);
  assert.deepEqual(first.drift, [
    { workspaceId: "ws_1", projectId: "p1", field: "totalExpenses", stored: 0, recomputed: 75.5 },
    { workspaceId: "ws_1", projectId: "p1", field: "netProfit", stored: 0, recomputed: -75.5 },
  ]);
  const second = await reconcile(sql);
  assert.deepEqual(second.drift, []);
});

test("runAndRecord writes the state file and signals drift through its result", { skip: skipReason }, async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "reconcile-"));
  const file = path.join(dir, "reconcile.json");
  await sql`INSERT INTO payments (id, workspace_id, project_id, amount, date, payment_status) VALUES ('pay1', 'ws_1', 'p2', 100, now(), 'paid')`;
  const ok = await runAndRecord(sql, file);
  assert.equal(ok, false);
  const saved = JSON.parse(await readFile(file, "utf8"));
  assert.equal(saved.projects, 2);
  assert.equal(saved.drift.length, 2);
  assert.ok(Date.parse(saved.finishedAt) > 0);
  assert.equal(await runAndRecord(sql, file), true);
});

test("the daily schedule waits until the next 02:00 UTC", () => {
  assert.equal(msUntilNextRun(new Date("2026-06-01T01:00:00Z"), 2), 60 * 60 * 1000);
  assert.equal(msUntilNextRun(new Date("2026-06-01T02:00:00Z"), 2), 24 * 60 * 60 * 1000);
  assert.equal(msUntilNextRun(new Date("2026-06-01T23:30:00Z"), 2), 2.5 * 60 * 60 * 1000);
});
