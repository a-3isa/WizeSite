/**
 * T063: RPCs that replace the app's direct Firestore writes. Each enforces what firestore.rules
 * enforces for that path today, except where the rules blocked what the app does (noted inline).
 */
import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { withTransaction } from "../../src/db/tx";
import { upsertAccountingRecordForUser } from "../../src/rpc/accounting_records";
import { deleteEntityForUser, touchEntityLastUsedForUser, upsertEntityForUser } from "../../src/rpc/entities";
import { markNotificationsReadForUser } from "../../src/rpc/notifications";
import { restoreMembershipForUser } from "../../src/rpc/session";
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
    await seedWorkspace(sql, { workspaceId: "ws_1", ownerUid: "u1", members: { acc: "accountingApproved", mem: "member" } });
    await seedWorkspace(sql, { workspaceId: "ws_2", ownerUid: "other" });
    await sql`INSERT INTO projects (id, workspace_id, name) VALUES ('p1', 'ws_1', 'برج'), ('p_other', 'ws_2', 'X')`;
  }
});

const tx = <T>(fn: (t: Sql) => Promise<T>) => withTransaction(sql, fn);
async function rejectsWith(promise: Promise<unknown>, code: string, message?: string) {
  await assert.rejects(promise, (error: { code?: string; message?: string }) => {
    assert.equal(error.code, code);
    if (message) assert.equal(error.message, message);
    return true;
  });
}

// ---------------------------------------------------------------- entities

test("upsertEntity: members create and edit contacts, incl. phone/notes/rate the rules used to block", { skip: skipReason }, async () => {
  const created = await tx((t) =>
    upsertEntityForUser(t, "mem", { workspaceId: "ws_1", name: "  Ahmed   Ali ", type: "supplier", phoneNumber: "010", defaultRate: 12.5 }),
  );
  assert.match(`${created.id}`, /^[A-Za-z0-9]{20}$/);
  assert.equal(created.normalizedName, "ahmed ali");
  assert.equal(created.phoneNumber, "010");
  const updated = await tx((t) =>
    upsertEntityForUser(t, "mem", { workspaceId: "ws_1", id: created.id, name: "Ahmed", type: "contractor", notes: "ملاحظة" }),
  );
  assert.equal(updated.name, "Ahmed");
  assert.equal(updated.notes, "ملاحظة");
  assert.equal(updated.phoneNumber, "", "cleared like FieldValue.delete()");
  assert.equal(updated.defaultRate, undefined);
  await rejectsWith(tx((t) => upsertEntityForUser(t, "stranger", { workspaceId: "ws_1", name: "X" })), "permission-denied");
  await rejectsWith(
    tx((t) => upsertEntityForUser(t, "other", { workspaceId: "ws_2", id: created.id, name: "Stolen" })),
    "permission-denied",
    "Entity is not available in this workspace",
  );
});

test("touchEntityLastUsed and deleteEntity (owner/admin only)", { skip: skipReason }, async () => {
  const id = String((await tx((t) => upsertEntityForUser(t, "u1", { workspaceId: "ws_1", name: "A" }))).id);
  await sql`UPDATE entities SET last_used_at = '2020-01-01' WHERE id = ${id}`;
  await tx((t) => touchEntityLastUsedForUser(t, "mem", { workspaceId: "ws_1", entityId: id }));
  const [e] = await sql`SELECT last_used_at FROM entities WHERE id = ${id}`;
  assert.ok(new Date(e.last_used_at).getFullYear() > 2020);
  await rejectsWith(tx((t) => deleteEntityForUser(t, "mem", { workspaceId: "ws_1", entityId: id })), "permission-denied");
  await tx((t) => deleteEntityForUser(t, "u1", { workspaceId: "ws_1", entityId: id }));
  const left = await sql`SELECT 1 FROM entities WHERE id = ${id}`;
  assert.equal(left.length, 0);
});

// ---------------------------------------------------------------- accounting records

const record = (data: Record<string, unknown> = {}) => ({
  workspaceId: "ws_1",
  projectId: "p1",
  description: "دفعة",
  amount: 500,
  date: "2026-06-01T00:00:00.000Z",
  paymentMethod: "cash",
  paymentStatus: "paid",
  notes: "",
  ...data,
});

test("accounting records: accounting roles only; same validation as firestore.rules", { skip: skipReason }, async () => {
  const upsert = (uid: string, kind: string, data: Record<string, unknown>) =>
    tx((t) => upsertAccountingRecordForUser(t, uid, kind as never, data));
  await rejectsWith(upsert("mem", "contractor", record({ contractorId: "k1", contractorName: "مقاول" })), "permission-denied");
  await rejectsWith(upsert("acc", "contractor", record({ contractorId: "", contractorName: "x" })), "invalid-argument");
  await rejectsWith(upsert("acc", "contractor", record({ contractorId: "k1", contractorName: "x", amount: 0 })), "invalid-argument");
  await rejectsWith(upsert("acc", "contractor", record({ contractorId: "k1", contractorName: "x", paymentStatus: "maybe" })), "invalid-argument");
  await rejectsWith(upsert("acc", "contractor", record({ contractorId: "k1", contractorName: "x", projectId: "p_other" })), "invalid-argument", "Project does not exist");
  const { id } = await upsert("acc", "contractor", record({ contractorId: "k1", contractorName: "مقاول" }));
  const [row] = await sql`SELECT contractor_id, contractor_name, amount FROM contractor_accounting_records WHERE id = ${id}`;
  assert.deepEqual({ ...row }, { contractor_id: "k1", contractor_name: "مقاول", amount: "500.00" });
});

test("equipment records use providerId/providerName, as the app sends (the rules' equipmentId blocked every save)", { skip: skipReason }, async () => {
  const { id } = await tx((t) =>
    upsertAccountingRecordForUser(t, "u1", "equipment", record({ providerId: "eq1", providerName: "حفار" })),
  );
  const [row] = await sql`SELECT provider_id, provider_name FROM equipment_accounting_records WHERE id = ${id}`;
  assert.deepEqual({ ...row }, { provider_id: "eq1", provider_name: "حفار" });
});

test("worker records: partial needs 0 < paidAmount < amount; the worker summary is recomputed", { skip: skipReason }, async () => {
  const w = (data: Record<string, unknown>) => record({ workerId: "w1", workerName: "علي", ...data });
  await rejectsWith(
    tx((t) => upsertAccountingRecordForUser(t, "u1", "worker", w({ paymentStatus: "partial", paidAmount: 500 }))),
    "invalid-argument",
  );
  const { id } = await tx((t) => upsertAccountingRecordForUser(t, "u1", "worker", w({ paymentStatus: "partial", paidAmount: 200 })));
  await tx((t) => upsertAccountingRecordForUser(t, "u1", "worker", w({ id, paymentStatus: "paid", amount: 800 })));
  const [summary] = await sql<{ payload: Record<string, number> }[]>`
    SELECT payload FROM worker_accounting_summaries WHERE id = 'ws_1_w1'`;
  assert.equal(summary.payload.totalAmount, 800);
  assert.equal(summary.payload.recordCount, 1);
});

// ---------------------------------------------------------------- notifications + session

test("markNotificationsRead: only the target user, all or nothing", { skip: skipReason }, async () => {
  await sql`INSERT INTO notifications (id, workspace_id, target_user_id) VALUES
    ('n1', 'ws_1', 'mem'), ('n2', 'ws_1', 'mem'), ('n_u1', 'ws_1', 'u1')`;
  await rejectsWith(
    tx((t) => markNotificationsReadForUser(t, "mem", { notificationIds: ["n1", "n_u1"] })),
    "permission-denied",
  );
  const unread = await sql`SELECT id FROM notifications WHERE read_at IS NOT NULL`;
  assert.equal(unread.length, 0);
  await tx((t) => markNotificationsReadForUser(t, "mem", { notificationIds: ["n1", "n2"] }));
  const read = await sql`SELECT id FROM notifications WHERE read_at IS NOT NULL ORDER BY id`;
  assert.deepEqual(read.map((r) => r.id), ["n1", "n2"]);
});

test("restoreMembership: repairs a missing owner membership; others are refused", { skip: skipReason }, async () => {
  await sql`DELETE FROM memberships WHERE id = 'ws_1_u1'`;
  const result = await tx((t) => restoreMembershipForUser(t, "u1", { workspaceId: "ws_1" }));
  assert.deepEqual(result, { workspaceId: "ws_1", restored: true });
  const again = await tx((t) => restoreMembershipForUser(t, "u1", { workspaceId: "ws_1" }));
  assert.deepEqual(again, { workspaceId: "ws_1", restored: false });
  await rejectsWith(tx((t) => restoreMembershipForUser(t, "stranger", { workspaceId: "ws_1" })), "permission-denied");
});
