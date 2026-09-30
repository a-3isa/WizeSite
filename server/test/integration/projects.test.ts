/** T058: project RPCs ported from functions/src/index.ts, with in-transaction recompute. */
import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { withTransaction } from "../../src/db/tx";
import {
  archiveProjectForUser,
  createProjectWithQuotaForUser,
  unarchiveProjectForUser,
  updateProjectForUser,
} from "../../src/rpc/projects";
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
  if (!skipReason) {
    await resetDatabase(sql);
    await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "u1", members: { viewer: "entryOnly", m1: "member" } });
  }
});

const tx = <T>(fn: (t: Sql) => Promise<T>) => withTransaction(sql, fn);
const create = (uid: string, data: Record<string, unknown>) =>
  tx((t) => createProjectWithQuotaForUser(t, uid, { workspaceId: "ws_1", ...data }));

async function rejectsWith(promise: Promise<unknown>, code: string, message?: string | RegExp) {
  await assert.rejects(promise, (error: { code?: string; message?: string }) => {
    assert.equal(error.code, code);
    if (typeof message === "string") assert.equal(error.message, message);
    if (message instanceof RegExp) assert.match(`${error.message}`, message);
    return true;
  });
}

test("create: stores the project, counts it, recomputes metrics; contract value optional", { skip: skipReason }, async () => {
  const { id, clientMutationId } = await create("u1", {
    name: " برج ",
    clientName: "عميل",
    contractValue: 0,
    budgetLimit: "",
    completionPercentage: 32.80725319006043,
    clientMutationId: "cm1",
    startDate: "2026-06-01T00:00:00.000Z",
  });
  assert.match(id, /^[A-Za-z0-9]{20}$/);
  assert.equal(clientMutationId, "cm1");
  const [p] = await sql`SELECT * FROM projects WHERE id = ${id}`;
  assert.equal(p.name, "برج");
  assert.equal(p.contract_value, null, "zero means not set");
  assert.equal(p.budget_limit, null);
  assert.equal(p.completion_percentage, 32.80725319006043);
  assert.equal(p.status, "active");
  assert.equal(p.is_archived, false);
  assert.equal(p.created_by, "u1");
  assert.equal(new Date(p.start_date).toISOString(), "2026-06-01T00:00:00.000Z");
  const [counter] = await sql`SELECT active_projects FROM usage_counters WHERE workspace_id = 'ws_1' AND period = 'projects'`;
  assert.equal(counter.active_projects, 1);
  const [metrics] = await sql`SELECT payload FROM project_metrics WHERE project_id = ${id}`;
  assert.ok(metrics, "project_metrics recomputed in the same transaction");
});

test("create: same clientMutationId replays the first project, no second row or count", { skip: skipReason }, async () => {
  await sql`INSERT INTO subscriptions (workspace_id, tier, status) VALUES ('ws_1', 'pro', 'active')`;
  const first = await create("u1", { name: "A", clientMutationId: "cm1" });
  const second = await create("u1", { name: "A", clientMutationId: "cm1" });
  assert.deepEqual(second, first);
  const [{ count }] = await sql`SELECT count(*)::int AS count FROM projects`;
  assert.equal(count, 1);
});

test("create: the free plan allows 1 active project, then LIMIT_REACHED (same error as today)", { skip: skipReason }, async () => {
  await create("u1", { name: "A" });
  await assert.rejects(create("u1", { name: "B" }), (error: { code?: string; message?: string; details?: unknown }) => {
    assert.equal(error.code, "failed-precondition");
    assert.equal(error.message, "LIMIT_REACHED");
    assert.deepEqual(error.details, { code: "LIMIT_REACHED", limitType: "activeProjects", current: 1, max: 1 });
    return true;
  });
});

test("create: pro (active/trial/grace) is unlimited", { skip: skipReason }, async () => {
  await sql`INSERT INTO subscriptions (workspace_id, tier, status) VALUES ('ws_1', 'pro', 'grace')`;
  await create("u1", { name: "A" });
  await create("u1", { name: "B" });
  const [counter] = await sql`SELECT active_projects FROM usage_counters WHERE period = 'projects'`;
  assert.equal(counter.active_projects, 2);
});

test("create: validation and roles", { skip: skipReason }, async () => {
  await rejectsWith(create("u1", { name: " " }), "invalid-argument", "Missing required field: name");
  await rejectsWith(create("u1", { name: "A", contractValue: -1 }), "invalid-argument", "contractValue must not be negative");
  await rejectsWith(create("stranger", { name: "A" }), "permission-denied", "User is not a member of this workspace");
  await rejectsWith(create("viewer", { name: "A" }), "permission-denied", "Not allowed to create project");
});

test("update: edits fields; archived projects cannot be edited", { skip: skipReason }, async () => {
  const { id } = await create("m1", { name: "A", contractValue: 1000 });
  await tx((t) =>
    updateProjectForUser(t, "m1", { workspaceId: "ws_1", projectId: id, name: "B", contractValue: 2000, status: "completed" }),
  );
  const [p] = await sql`SELECT name, contract_value, status FROM projects WHERE id = ${id}`;
  assert.deepEqual({ ...p }, { name: "B", contract_value: "2000.00", status: "completed" });

  await tx((t) => archiveProjectForUser(t, "u1", { workspaceId: "ws_1", projectId: id }));
  await rejectsWith(
    tx((t) => updateProjectForUser(t, "u1", { workspaceId: "ws_1", projectId: id, name: "C" })),
    "failed-precondition",
    "Archived projects cannot be edited.",
  );
});

test("update: cannot clear the contract value while live payments exist", { skip: skipReason }, async () => {
  const { id } = await create("u1", { name: "A", contractValue: 1000 });
  await sql`INSERT INTO payments (id, workspace_id, project_id, amount, date, payment_status)
            VALUES ('pay1', 'ws_1', ${id}, 100, now(), 'paid')`;
  await rejectsWith(
    tx((t) => updateProjectForUser(t, "u1", { workspaceId: "ws_1", projectId: id, name: "A", contractValue: null })),
    "failed-precondition",
    "Remove this project's payments before clearing its contract value.",
  );
  await sql`UPDATE payments SET is_archived = true WHERE id = 'pay1'`;
  await tx((t) => updateProjectForUser(t, "u1", { workspaceId: "ws_1", projectId: id, name: "A", contractValue: null }));
  const [p] = await sql`SELECT contract_value FROM projects WHERE id = ${id}`;
  assert.equal(p.contract_value, null);
});

test("archive refunds the active-project count; unarchive re-checks the quota", { skip: skipReason }, async () => {
  const { id: a } = await create("u1", { name: "A" });
  await tx((t) => archiveProjectForUser(t, "u1", { workspaceId: "ws_1", projectId: a }));
  await tx((t) => archiveProjectForUser(t, "u1", { workspaceId: "ws_1", projectId: a })); // idempotent
  let [counter] = await sql`SELECT active_projects FROM usage_counters WHERE period = 'projects'`;
  assert.equal(counter.active_projects, 0);

  const { id: b } = await create("u1", { name: "B" });
  await assert.rejects(
    tx((t) => unarchiveProjectForUser(t, "u1", { workspaceId: "ws_1", projectId: a })),
    (error: { message?: string }) => error.message === "LIMIT_REACHED",
  );
  await tx((t) => archiveProjectForUser(t, "u1", { workspaceId: "ws_1", projectId: b }));
  await tx((t) => unarchiveProjectForUser(t, "u1", { workspaceId: "ws_1", projectId: a }));
  [counter] = await sql`SELECT active_projects FROM usage_counters WHERE period = 'projects'`;
  assert.equal(counter.active_projects, 1);
  const [p] = await sql`SELECT is_archived FROM projects WHERE id = ${a}`;
  assert.equal(p.is_archived, false);
});

test("a counter missing after migration is seeded from the active projects", { skip: skipReason }, async () => {
  await sql`INSERT INTO projects (id, workspace_id, name) VALUES ('legacy', 'ws_1', 'Old')`;
  await rejectsWith(create("u1", { name: "A" }), "failed-precondition", "LIMIT_REACHED");
});

test("through the API: idempotency key replays; errors use the envelope", { skip: skipReason }, async () => {
  const app = await buildTestApp(sql, buildRegistry({ files: { root: "/tmp", signingKey: "k".repeat(32), publicUrl: "https://api.test" } }));
  try {
    const call = (key: string, data: Record<string, unknown>) =>
      app.inject({ method: "POST", url: "/v1/rpc/createProjectWithQuota", headers: authHeaders("u1", key), payload: { data } });
    const first = await call("k1", { workspaceId: "ws_1", name: "A" });
    assert.equal(first.statusCode, 200);
    const replay = await call("k1", { workspaceId: "ws_1", name: "A" });
    assert.deepEqual(replay.json(), first.json());
    const limited = await call("k2", { workspaceId: "ws_1", name: "B" });
    assert.equal(limited.statusCode, 412);
    assert.equal(limited.json().error.message, "LIMIT_REACHED");
  } finally {
    await app.close();
  }
});

test("deleteProjectCascade: removes children, refunds counters, deletes files, keeps accounting records", { skip: skipReason }, async () => {
  const { mkdtemp, mkdir, writeFile, access } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const path = await import("node:path");
  const { deleteProjectCascadeForUser } = await import("../../src/rpc/projects");
  const { periodKey } = await import("../../src/rpc/quota");

  const root = await mkdtemp(path.join(tmpdir(), "cascade-"));
  const file = "receipts/u1/r1.jpg";
  await mkdir(path.join(root, "receipts/u1"), { recursive: true });
  await writeFile(path.join(root, file), "x");

  const { id } = await create("u1", { name: "A", contractValue: 1000 });
  const attachments = [{ id: "a1", fileName: "r.jpg", storagePath: file }];
  await sql`INSERT INTO expenses (id, workspace_id, project_id, amount, date, attachments)
            VALUES ('e1', 'ws_1', ${id}, 10, now(), ${sql.json(attachments)}), ('e_arch', 'ws_1', ${id}, 5, now(), '[]'::jsonb)`;
  await sql`UPDATE expenses SET is_archived = true WHERE id = 'e_arch'`;
  await sql`INSERT INTO payments (id, workspace_id, project_id, amount, date) VALUES ('pay1', 'ws_1', ${id}, 100, now())`;
  await sql`INSERT INTO contractor_accounting_records (id, workspace_id, project_id, contractor_id, amount, date)
            VALUES ('c1', 'ws_1', ${id}, 'k1', 50, now())`;
  await sql`INSERT INTO notifications (id, workspace_id, target_user_id, legacy)
            VALUES ('n1', 'ws_1', 'u1', ${sql.json({ projectId: id })}), ('n2', 'ws_1', 'u1', '{}'::jsonb)`;
  await sql`INSERT INTO usage_counters (id, workspace_id, period, expenses_count, payments_count)
            VALUES (${`ws_1_${periodKey()}`}, 'ws_1', ${periodKey()}, 5, 5)`;

  await rejectsWith(
    tx((t) => deleteProjectCascadeForUser(t, "m1", { workspaceId: "ws_1", projectId: id }, { root })),
    "permission-denied",
    "Not allowed to delete project",
  );
  await tx((t) => deleteProjectCascadeForUser(t, "u1", { workspaceId: "ws_1", projectId: id }, { root }));

  const [left] = await sql`SELECT
      (SELECT count(*)::int FROM projects) AS projects, (SELECT count(*)::int FROM expenses) AS expenses,
      (SELECT count(*)::int FROM payments) AS payments, (SELECT count(*)::int FROM project_metrics) AS metrics,
      (SELECT count(*)::int FROM notifications WHERE id = 'n1') AS notifications`;
  assert.deepEqual({ ...left }, { projects: 0, expenses: 0, payments: 0, metrics: 0, notifications: 0 });
  const [n2] = await sql`SELECT id FROM notifications WHERE id = 'n2'`;
  assert.ok(n2, "notifications of other projects stay");
  const [c1] = await sql`SELECT project_id, legacy FROM contractor_accounting_records WHERE id = 'c1'`;
  assert.equal(c1.project_id, null, "detached, not deleted (Firebase never deleted them)");
  assert.equal(c1.legacy.projectId, id, "the app still reads the old projectId");
  const [counter] = await sql`SELECT expenses_count, payments_count FROM usage_counters WHERE period = ${periodKey()}`;
  assert.deepEqual({ ...counter }, { expenses_count: 4, payments_count: 4 }, "only live records refunded");
  const [projects] = await sql`SELECT active_projects FROM usage_counters WHERE period = 'projects'`;
  assert.equal(projects.active_projects, 0);
  await assert.rejects(access(path.join(root, file)), "attachment file deleted");
});
