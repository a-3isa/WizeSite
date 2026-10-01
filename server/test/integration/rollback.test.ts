/**
 * T099: what the rollback tool picks up after cutover (migration 006 tombstones + updated_at
 * touch). Firestore itself is not written here (db = null); the mapping is covered by
 * test/migration/rollback_mapping.test.ts.
 */
import assert from "node:assert/strict";
import { after, before, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { rollback } from "../../tools/rollback-to-firestore/index";
import { resetDatabase, skipReason, testSql } from "./helpers";

let sql: Sql;

before(async () => {
  if (skipReason) return;
  sql = testSql();
  await resetDatabase(sql);
  await sql`INSERT INTO workspaces (id, owner_uid, name) VALUES ('ws_rb', 'u_rb', 'W')`;
  await sql`INSERT INTO projects (id, workspace_id, name) VALUES ('p_old', 'ws_rb', 'Old'), ('p_gone', 'ws_rb', 'Gone')`;
  await sql`INSERT INTO expenses (id, workspace_id, project_id, amount, date, category)
            VALUES ('e_old', 'ws_rb', 'p_old', 10, now(), 'materials')`;
  // Everything above happened "before cutover".
  for (const table of ["workspaces", "projects", "expenses"]) {
    await sql`UPDATE ${sql(table)} SET updated_at = now() - interval '2 days'`;
  }
});
after(async () => {
  if (sql) await sql.end();
});

test("changes, new rows and deletions after cutover are picked up; older rows are not", { skip: skipReason }, async () => {
  const cutoverAt = new Date(Date.now() - 60_000);

  // An update that does not set updated_at still counts (touch trigger).
  await sql`UPDATE expenses SET category = 'labor' WHERE id = 'e_old'`;
  await sql`INSERT INTO expenses (id, workspace_id, project_id, amount, date, category)
            VALUES ('e_new', 'ws_rb', 'p_old', 25.5, now(), 'materials')`;
  await sql`DELETE FROM projects WHERE id = 'p_gone'`;

  const { deletes, writes, projects, summary } = await rollback(sql, null, cutoverAt);

  assert.deepEqual(deletes, [{ collection: "projects", id: "p_gone" }]);
  const expenseWrites = writes.filter((w) => w.collection === "expenses").map((w) => w.id).sort();
  assert.deepEqual(expenseWrites, ["e_new", "e_old"]);
  assert.equal(writes.some((w) => w.collection === "workspaces"), false, "untouched rows stay out");
  const eOld = writes.find((w) => w.id === "e_old")!;
  assert.equal(eOld.data.category, "labor");
  assert.equal(writes.find((w) => w.id === "e_new")!.data.amount, 25.5);
  assert.deepEqual([...projects], ["p_old"]);
  assert.equal(summary.deleted, 1);
});

test("a row deleted and created again is not deleted in Firestore", { skip: skipReason }, async () => {
  const cutoverAt = new Date(Date.now() - 60_000);
  await sql`INSERT INTO projects (id, workspace_id, name) VALUES ('p_again', 'ws_rb', 'A')`;
  await sql`DELETE FROM projects WHERE id = 'p_again'`;
  await sql`INSERT INTO projects (id, workspace_id, name) VALUES ('p_again', 'ws_rb', 'A2')`;
  const { deletes, writes } = await rollback(sql, null, cutoverAt);
  assert.equal(deletes.some((d) => d.id === "p_again"), false);
  assert.equal(writes.find((w) => w.id === "p_again")?.data.name, "A2");
});
