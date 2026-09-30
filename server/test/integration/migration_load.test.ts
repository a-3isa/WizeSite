/** T037: loading transformed rows into Postgres, atomically, then recomputing derived state. */
import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";
import { Timestamp } from "firebase-admin/firestore";

import type { Sql } from "../../src/db/pool";
import { findOrphans, loadMigration, readTableColumns } from "../../tools/migrate-from-firestore/load";
import { transformExport, type ExportedCollections } from "../../tools/migrate-from-firestore/transform";
import { resetDatabase, skipReason, testSql } from "./helpers";

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

const at = (iso: string) => Timestamp.fromDate(new Date(iso));

function fixture(): ExportedCollections {
  return {
    users: [{ id: "u1", data: { email: "u1@example.com", workspaceId: "ws_1", fullName: "مالك" } }],
    workspaces: [{ id: "ws_1", data: { ownerId: "u1", name: "Main" } }],
    memberships: [{ id: "ws_1_u1", data: { workspaceId: "ws_1", userId: "u1", role: "owner" } }],
    projects: [{ id: "p1", data: { workspaceId: "ws_1", name: "Tower", contractValue: 1000, isArchived: false } }],
    workers: [{ id: "w1", data: { workspaceId: "ws_1", name: "علي", isArchived: false } }],
    expenses: [
      { id: "e1", data: { workspaceId: "ws_1", projectId: "p1", amount: 100, category: "materials", date: at("2026-05-02"), isArchived: false, attachments: [] } },
    ],
    payments: [
      { id: "pay1", data: { workspaceId: "ws_1", projectId: "p1", amount: 400, paymentStatus: "paid", date: at("2026-06-05"), isArchived: false } },
    ],
    worker_entries: [
      { id: "we1", data: { workspaceId: "ws_1", projectId: "p1", workerId: "w1", daysWorked: 2, dailyWage: 75, date: at("2026-06-04"), isArchived: false } },
    ],
  };
}

test("loads every table in FK order and recomputes derived state", { skip: skipReason }, async () => {
  const columns = await readTableColumns(sql);
  const { rows } = transformExport(fixture(), columns, new Set(["u1"]));
  const result = await loadMigration(sql, rows, { now: new Date(Date.UTC(2026, 5, 10)) });

  assert.equal(result.loaded.get("expenses"), 1);
  const [metrics] = await sql<{ payload: Record<string, unknown> }[]>`
    SELECT payload FROM project_metrics WHERE project_id = 'p1'`;
  assert.equal(metrics.payload.totalExpenses, 250);
  assert.equal(metrics.payload.totalPayments, 400);
  const [profile] = await sql<{ full_name: string; active_workspace_id: string }[]>`
    SELECT full_name, active_workspace_id FROM user_profiles WHERE uid = 'u1'`;
  assert.equal(profile.full_name, "مالك");
  assert.equal(profile.active_workspace_id, "ws_1");
});

test("orphaned references are reported before anything is written", { skip: skipReason }, async () => {
  const data = fixture();
  data.expenses.push({
    id: "e_orphan",
    data: { workspaceId: "ws_1", projectId: "p_missing", amount: 5, category: "other", date: at("2026-06-01") },
  });
  const columns = await readTableColumns(sql);
  const { rows } = transformExport(data, columns, new Set(["u1"]));
  const orphans = findOrphans(rows);
  assert.deepEqual(orphans, ["expenses/e_orphan.project_id -> projects/p_missing (missing)"]);
  await assert.rejects(loadMigration(sql, rows), /orphaned references/);
  const count = await sql`SELECT 1 FROM workspaces`;
  assert.equal(count.length, 0, "nothing written");
});

test("a failure mid-load rolls back everything", { skip: skipReason }, async () => {
  const data = fixture();
  // Violates the category CHECK constraint on insert.
  data.expenses.push({
    id: "e_bad",
    data: { workspaceId: "ws_1", projectId: "p1", amount: 5, category: "not-a-category", date: at("2026-06-01") },
  });
  const columns = await readTableColumns(sql);
  const { rows } = transformExport(data, columns, new Set(["u1"]));
  await assert.rejects(loadMigration(sql, rows));
  const count = await sql`SELECT 1 FROM projects`;
  assert.equal(count.length, 0, "transaction rolled back");
});

test("refuses to load into a non-empty database unless reset is requested", { skip: skipReason }, async () => {
  const columns = await readTableColumns(sql);
  const { rows } = transformExport(fixture(), columns, new Set(["u1"]));
  await loadMigration(sql, rows);
  await assert.rejects(loadMigration(sql, rows), /not empty/);
  const again = await loadMigration(sql, rows, { reset: true });
  assert.equal(again.loaded.get("projects"), 1);
});

test("a user whose active workspace was skipped gets a null active workspace", { skip: skipReason }, async () => {
  const data = fixture();
  data.users[0].data.workspaceId = "ws_deleted_elsewhere";
  const columns = await readTableColumns(sql);
  const { rows } = transformExport(data, columns, new Set(["u1"]));
  await loadMigration(sql, rows);
  const [profile] = await sql<{ active_workspace_id: string | null }[]>`
    SELECT active_workspace_id FROM user_profiles WHERE uid = 'u1'`;
  assert.equal(profile.active_workspace_id, null);
});
