/** T060: worker and worker-entry RPCs ported from functions/src/index.ts. */
import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { withTransaction } from "../../src/db/tx";
import { periodKey } from "../../src/rpc/quota";
import {
  archiveWorkerEntryWithQuotaRefundForUser,
  archiveWorkerForUser,
  createWorkerEntryWithQuotaForUser,
  createWorkerForUser,
  updateWorkerEntryForUser,
  updateWorkerForUser,
} from "../../src/rpc/workers";
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
    await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "u1", members: { entry: "entryOnly" } });
    await sql`INSERT INTO projects (id, workspace_id, name) VALUES ('p1', 'ws_1', 'برج'), ('p2', 'ws_1', 'فيلا')`;
    await sql`INSERT INTO projects (id, workspace_id, name, is_archived) VALUES ('p_arch', 'ws_1', 'Old', true)`;
  }
});

const tx = <T>(fn: (t: Sql) => Promise<T>) => withTransaction(sql, fn);
async function rejectsWith(promise: Promise<unknown>, code: string, message: string) {
  await assert.rejects(promise, (error: { code?: string; message?: string }) => {
    assert.equal(error.code, code);
    assert.equal(error.message, message);
    return true;
  });
}
const totalExpenses = async (projectId: string) => {
  const [row] = await sql<{ payload: Record<string, number> }[]>`
    SELECT payload FROM project_metrics WHERE project_id = ${projectId}`;
  return row?.payload.totalExpenses;
};

// ---------------------------------------------------------------- workers

test("createWorker: daily wage required for daily workers; project billing stores 0", { skip: skipReason }, async () => {
  const create = (data: Record<string, unknown>) =>
    tx((t) => createWorkerForUser(t, "entry", { workspaceId: "ws_1", name: "علي", ...data }));
  await rejectsWith(create({ dailyWage: 0 }), "invalid-argument", "Daily workers must have daily wage greater than zero");
  await rejectsWith(create({ dailyWage: 100, status: "retired" }), "invalid-argument", "Worker status must be active, inactive, or terminated.");
  const { id } = await create({ dailyWage: 150, clientMutationId: "w-cm" });
  const replay = await create({ dailyWage: 150, clientMutationId: "w-cm" });
  assert.equal(replay.id, id);
  const { id: pid } = await create({ dailyWage: 0, billingType: "PROJECT" });
  const rows = await sql`SELECT id, daily_wage, billing_type, status FROM workers ORDER BY daily_wage DESC`;
  assert.deepEqual(rows.map((r) => ({ ...r })), [
    { id, daily_wage: "150.00", billing_type: "daily", status: "active" },
    { id: pid, daily_wage: "0.00", billing_type: "project", status: "active" },
  ]);
});

test("updateWorker / archiveWorker: archived workers cannot be edited", { skip: skipReason }, async () => {
  const { id } = await tx((t) => createWorkerForUser(t, "u1", { workspaceId: "ws_1", name: "A", dailyWage: 100 }));
  await tx((t) =>
    updateWorkerForUser(t, "u1", { workspaceId: "ws_1", workerId: id, name: "B", dailyWage: 120, status: "inactive" }),
  );
  const [row] = await sql`SELECT name, daily_wage, status FROM workers WHERE id = ${id}`;
  assert.deepEqual({ ...row }, { name: "B", daily_wage: "120.00", status: "inactive" });
  await tx((t) => archiveWorkerForUser(t, "u1", { workspaceId: "ws_1", workerId: id }));
  await rejectsWith(
    tx((t) => updateWorkerForUser(t, "u1", { workspaceId: "ws_1", workerId: id, name: "C", dailyWage: 1 })),
    "failed-precondition",
    "Archived workers cannot be edited.",
  );
  await rejectsWith(
    tx((t) => archiveWorkerForUser(t, "u1", { workspaceId: "ws_1", workerId: "nope" })),
    "not-found",
    "Worker not found",
  );
});

// ---------------------------------------------------------------- worker entries

async function worker() {
  return (await tx((t) => createWorkerForUser(t, "u1", { workspaceId: "ws_1", name: "علي", dailyWage: 75.25 }))).id;
}
const entry = (workerId: string, data: Record<string, unknown> = {}) => ({
  workspaceId: "ws_1",
  workerId,
  projectId: "p1",
  daysWorked: 1.25,
  dailyWage: 75.25,
  date: "2026-06-03T00:00:00.000Z",
  ...data,
});

test("entry create: exact total cost (4 decimals), counter, metrics", { skip: skipReason }, async () => {
  const w = await worker();
  const { id } = await tx((t) => createWorkerEntryWithQuotaForUser(t, "u1", entry(w)));
  const [row] = await sql`SELECT total_cost, days_worked FROM worker_entries WHERE id = ${id}`;
  assert.equal(row.total_cost, "94.0625", "1.25 × 75.25 kept exactly, not rounded to cents");
  assert.equal(row.days_worked, "1.25");
  assert.equal(await totalExpenses("p1"), 94.0625);
  const [c] = await sql`SELECT worker_entries_count FROM usage_counters WHERE period = ${periodKey()}`;
  assert.equal(c.worker_entries_count, 1);
});

test("entry create: validation, archived worker/project, 10 per month", { skip: skipReason }, async () => {
  const w = await worker();
  const create = (uid: string, data: Record<string, unknown>) => tx((t) => createWorkerEntryWithQuotaForUser(t, uid, data));
  await rejectsWith(create("u1", entry(w, { daysWorked: 0 })), "invalid-argument", "Days worked and daily wage must be > 0");
  await rejectsWith(create("u1", entry("nope")), "invalid-argument", "Worker does not exist");
  await rejectsWith(create("u1", entry(w, { projectId: "p_arch" })), "permission-denied", "Project is archived and can no longer accept worker entries.");
  await rejectsWith(create("entry", entry(w)), "permission-denied", "Accounting access required");
  await sql`UPDATE workers SET is_archived = true WHERE id = ${w}`;
  await rejectsWith(create("u1", entry(w)), "permission-denied", "Worker is archived and can no longer accept new entries.");
  await sql`UPDATE workers SET is_archived = false WHERE id = ${w}`;
  await sql`INSERT INTO usage_counters (id, workspace_id, period, worker_entries_count)
            VALUES (${`ws_1_${periodKey()}`}, 'ws_1', ${periodKey()}, 10)`;
  await rejectsWith(create("u1", entry(w)), "failed-precondition", "LIMIT_REACHED");
});

test("entry update moves projects; archive refunds and removes the cost", { skip: skipReason }, async () => {
  const w = await worker();
  const { id } = await tx((t) => createWorkerEntryWithQuotaForUser(t, "u1", entry(w, { daysWorked: 2, dailyWage: 100 })));
  await tx((t) =>
    updateWorkerEntryForUser(t, "u1", { ...entry(w, { projectId: "p2", daysWorked: 3, dailyWage: 100 }), entryId: id }),
  );
  assert.equal(await totalExpenses("p1"), 0);
  assert.equal(await totalExpenses("p2"), 300);
  await tx((t) => archiveWorkerEntryWithQuotaRefundForUser(t, "u1", { workspaceId: "ws_1", entryId: id }));
  await tx((t) => archiveWorkerEntryWithQuotaRefundForUser(t, "u1", { workspaceId: "ws_1", entryId: id }));
  assert.equal(await totalExpenses("p2"), 0);
  const [c] = await sql`SELECT worker_entries_count FROM usage_counters WHERE period = ${periodKey()}`;
  assert.equal(c.worker_entries_count, 0);
  await rejectsWith(
    tx((t) => updateWorkerEntryForUser(t, "u1", { ...entry(w), entryId: id })),
    "failed-precondition",
    "Archived worker entries cannot be edited.",
  );
});

test("money inputs with more than 2 decimals are refused, never rounded", { skip: skipReason }, async () => {
  const w = await worker();
  await rejectsWith(
    tx((t) => createWorkerEntryWithQuotaForUser(t, "u1", entry(w, { dailyWage: 75.255 }))),
    "invalid-argument",
    "dailyWage can have at most 2 decimal places",
  );
});
