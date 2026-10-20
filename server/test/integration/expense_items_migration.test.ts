/**
 * Feature 005 (T031, US4): migration 007 leaves every existing expense and every total untouched.
 * Rolls 007 down, inserts rows in the pre-007 shape, re-applies 007 and compares.
 */
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { after, before, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { withTransaction } from "../../src/db/tx";
import { recomputeProject } from "../../src/recompute/persist";
import { resetDatabase, seedWorkspace, skipReason, testSql } from "./helpers";

let sql: Sql;
before(() => {
  if (!skipReason) sql = testSql();
});
after(async () => {
  if (sql) await sql.end();
});

async function migration007(): Promise<{ up: string; down: string }> {
  const file = path.resolve(__dirname, "../../../migrations/007_expense_items.sql");
  const [up, down] = (await readFile(file, "utf8")).split("-- Down Migration");
  return { up: up.replace("-- Up Migration", ""), down };
}

const totals = () => sql<{ project_id: string; total: string; rows: number }[]>`
  SELECT project_id, sum(amount)::text AS total, count(*)::int AS rows
  FROM expenses WHERE NOT is_archived GROUP BY project_id ORDER BY project_id`;

test("migration 007 keeps legacy expenses and totals identical", { skip: skipReason }, async () => {
  const { up, down } = await migration007();
  await resetDatabase(sql);
  await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "u1" });
  await sql`INSERT INTO projects (id, workspace_id, name) VALUES ('p1', 'ws_1', 'برج'), ('p2', 'ws_1', 'فيلا')`;

  await sql.unsafe(down);
  try {
    // Pre-007 column list (002_accounting.sql); no items column exists here.
    await sql`INSERT INTO expenses (id, workspace_id, project_id, amount, date, category, description, notes) VALUES
      ('old_1', 'ws_1', 'p1', 250.50, '2026-05-01', 'materials', 'أسمنت', ''),
      ('old_2', 'ws_1', 'p1', 1000.00, '2026-05-02', 'equipment', '', 'إيجار ونش'),
      ('old_3', 'ws_1', 'p2', 75.25, '2026-05-03', 'transport', '', '')`;
    await withTransaction(sql, async (t) => {
      await recomputeProject(t, "ws_1", "p1");
      await recomputeProject(t, "ws_1", "p2");
    });
    const before = await totals();
    const metricsBefore = await sql`SELECT project_id, payload->>'totalExpenses' AS total FROM project_metrics ORDER BY 1`;

    await sql.unsafe(up);
    // Prepared statements cached before the schema change would fail ("cached plan must not change
    // result type"); production restarts the API after migrating (ops/deploy.sh), so reconnect here.
    await sql.end();
    sql = testSql();

    const rows = await sql<{ id: string; items: unknown; amount: string }[]>`
      SELECT id, items, amount FROM expenses ORDER BY id`;
    assert.deepEqual(rows.map((r) => [r.id, r.items, r.amount]), [
      ["old_1", [], "250.50"], ["old_2", [], "1000.00"], ["old_3", [], "75.25"],
    ]);
    assert.deepEqual(await totals(), before);
    await withTransaction(sql, async (t) => {
      await recomputeProject(t, "ws_1", "p1");
      await recomputeProject(t, "ws_1", "p2");
    });
    const metricsAfter = await sql`SELECT project_id, payload->>'totalExpenses' AS total FROM project_metrics ORDER BY 1`;
    assert.deepEqual([...metricsAfter], [...metricsBefore]);
  } finally {
    // Leave the schema migrated for the other suites even if an assertion failed.
    const [{ exists }] = await sql`SELECT EXISTS (SELECT 1 FROM information_schema.columns
      WHERE table_name = 'expenses' AND column_name = 'items') AS exists`;
    if (!exists) await sql.unsafe(up);
  }
});
