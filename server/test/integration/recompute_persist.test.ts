import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { recomputeProject, recomputeWorkerAccounting } from "../../src/recompute/persist";
import { resetDatabase, seedWorkspace, skipReason, testSql } from "./helpers";

let sql: Sql;
before(() => {
  if (!skipReason) sql = testSql();
});
after(async () => {
  if (sql) await sql.end();
});

const now = new Date(Date.UTC(2026, 5, 10, 12));

beforeEach(async () => {
  if (skipReason) return;
  await resetDatabase(sql);
  await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "owner_1" });
  await sql`INSERT INTO projects (id, workspace_id, name, contract_value, budget_limit, completion_percentage)
            VALUES ('p1', 'ws_1', 'Tower', 1000, 200, 50), ('p2', 'ws_1', 'Villa', NULL, NULL, 0)`;
  await sql`INSERT INTO workers (id, workspace_id, name) VALUES ('w1', 'ws_1', 'علي')`;
  await sql`INSERT INTO expenses (id, workspace_id, project_id, amount, category, date, entity_name)
            VALUES ('e1', 'ws_1', 'p1', 100, 'materials', '2026-05-02', 'مورد'),
                   ('e2', 'ws_1', 'p1', 50, 'labor', '2026-06-03', NULL),
                   ('e3', 'ws_1', 'p2', 70, 'materials', '2026-06-01', NULL)`;
  await sql`INSERT INTO expenses (id, workspace_id, project_id, amount, category, date, is_archived)
            VALUES ('e_archived', 'ws_1', 'p1', 9999, 'materials', '2026-06-01', true)`;
  await sql`INSERT INTO payments (id, workspace_id, project_id, amount, paid_amount, payment_status, payment_method, date)
            VALUES ('pay1', 'ws_1', 'p1', 400, NULL, 'paid', 'cash', '2026-06-05'),
                   ('pay2', 'ws_1', 'p1', 300, 100, 'partial', 'bank', '2026-06-06')`;
  await sql`INSERT INTO worker_entries (id, workspace_id, project_id, worker_id, days_worked, daily_wage, date)
            VALUES ('we1', 'ws_1', 'p1', 'w1', 2, 75, '2026-06-04')`;
});

test("recomputeProject writes metrics, summaries and workspace metrics", { skip: skipReason }, async () => {
  await recomputeProject(sql, "ws_1", "p1", now);
  await recomputeProject(sql, "ws_1", "p2", now);

  const [metrics] = await sql<{ payload: Record<string, unknown>; risk_level: string | null }[]>`
    SELECT payload, risk_level FROM project_metrics WHERE project_id = 'p1'`;
  assert.equal(metrics.payload.totalExpenses, 300, "archived expense excluded");
  assert.equal(metrics.payload.totalPayments, 500);
  assert.deepEqual(metrics.payload.categoryTotals, { materials: 100, worker: 200 });
  assert.equal(metrics.risk_level, metrics.payload.riskLevel ?? null);

  const [noContract] = await sql<{ payload: Record<string, unknown>; risk_level: string | null }[]>`
    SELECT payload, risk_level FROM project_metrics WHERE project_id = 'p2'`;
  assert.equal(noContract.risk_level, null);

  const summaries = await sql`SELECT count(*)::int AS n FROM project_summaries WHERE project_id = 'p1'`;
  assert.equal(summaries[0].n, 1);
  const categories = await sql<{ n: number }[]>`
    SELECT count(*)::int AS n FROM category_summaries WHERE project_id = 'p1'`;
  assert.ok(categories[0].n > 0);

  const [ws] = await sql<{ payload: Record<string, unknown> }[]>`
    SELECT payload FROM workspace_metrics WHERE workspace_id = 'ws_1'`;
  assert.ok(ws, "workspace metrics row exists");
});

test("recompute is idempotent: an unchanged project does not bump source_version", { skip: skipReason }, async () => {
  await recomputeProject(sql, "ws_1", "p1", now);
  const [first] = await sql<{ source_version: string }[]>`
    SELECT source_version FROM project_metrics WHERE project_id = 'p1'`;
  await recomputeProject(sql, "ws_1", "p1", now);
  const [second] = await sql<{ source_version: string }[]>`
    SELECT source_version FROM project_metrics WHERE project_id = 'p1'`;
  assert.equal(second.source_version, first.source_version);
});

test("scoped replace removes summary rows that no longer apply", { skip: skipReason }, async () => {
  await recomputeProject(sql, "ws_1", "p1", now);
  const before = await sql<{ id: string }[]>`SELECT id FROM entity_summaries WHERE project_id = 'p1'`;
  assert.ok(before.length > 0);
  await sql`UPDATE expenses SET is_archived = true WHERE project_id = 'p1'`;
  await sql`UPDATE payments SET is_archived = true WHERE project_id = 'p1'`;
  await sql`UPDATE worker_entries SET is_archived = true WHERE project_id = 'p1'`;
  await recomputeProject(sql, "ws_1", "p1", now);
  const afterRows = await sql<{ id: string }[]>`SELECT id FROM entity_summaries WHERE project_id = 'p1'`;
  assert.equal(afterRows.length, 0, "entity summaries of fully archived project are removed");
  const [metrics] = await sql<{ payload: Record<string, unknown> }[]>`
    SELECT payload FROM project_metrics WHERE project_id = 'p1'`;
  assert.equal(metrics.payload.totalExpenses, 0);
});

test("recomputing a missing project is a no-op", { skip: skipReason }, async () => {
  await recomputeProject(sql, "ws_1", "does_not_exist", now);
  const rows = await sql`SELECT 1 FROM project_metrics WHERE project_id = 'does_not_exist'`;
  assert.equal(rows.length, 0);
});

test("worker accounting summary is written and removed with its records", { skip: skipReason }, async () => {
  await sql`INSERT INTO worker_accounting_records (id, workspace_id, worker_id, amount, date, payment_status)
            VALUES ('war1', 'ws_1', 'w1', 250, '2026-06-01', 'paid')`;
  await recomputeWorkerAccounting(sql, "ws_1", "w1");
  const [row] = await sql<{ id: string; payload: Record<string, unknown> }[]>`
    SELECT id, payload FROM worker_accounting_summaries WHERE worker_id = 'w1'`;
  assert.equal(row.id, "ws_1_w1");
  await sql`DELETE FROM worker_accounting_records WHERE id = 'war1'`;
  await recomputeWorkerAccounting(sql, "ws_1", "w1");
  const gone = await sql`SELECT 1 FROM worker_accounting_summaries WHERE worker_id = 'w1'`;
  assert.equal(gone.length, 0);
});
