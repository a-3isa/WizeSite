/** T059: expense and payment RPCs ported from functions/src/index.ts, with in-transaction recompute. */
import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { withTransaction } from "../../src/db/tx";
import {
  archiveExpenseWithQuotaRefundForUser,
  createExpenseWithQuotaForUser,
  updateExpenseForUser,
} from "../../src/rpc/expenses";
import {
  archivePaymentWithQuotaRefundForUser,
  createPaymentWithQuotaForUser,
  updatePaymentForUser,
} from "../../src/rpc/payments";
import { periodKey } from "../../src/rpc/quota";
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
    await sql`INSERT INTO projects (id, workspace_id, name, contract_value) VALUES
      ('p1', 'ws_1', 'برج', 10000), ('p2', 'ws_1', 'فيلا', 5000), ('p_nocontract', 'ws_1', 'Ledger', NULL)`;
    await sql`INSERT INTO projects (id, workspace_id, name, is_archived) VALUES ('p_arch', 'ws_1', 'Old', true)`;
  }
});

const tx = <T>(fn: (t: Sql) => Promise<T>) => withTransaction(sql, fn);
const metrics = async (projectId: string) => {
  const [row] = await sql<{ payload: Record<string, number> }[]>`
    SELECT payload FROM project_metrics WHERE project_id = ${projectId}`;
  return row?.payload;
};
const counter = async () => {
  const [row] = await sql`SELECT expenses_count, payments_count FROM usage_counters
                          WHERE workspace_id = 'ws_1' AND period = ${periodKey()}`;
  return row ? { expenses: row.expenses_count, payments: row.payments_count } : undefined;
};
async function rejectsWith(promise: Promise<unknown>, code: string, message: string) {
  await assert.rejects(promise, (error: { code?: string; message?: string }) => {
    assert.equal(error.code, code);
    assert.equal(error.message, message);
    return true;
  });
}

const expense = (data: Record<string, unknown> = {}) => ({
  workspaceId: "ws_1",
  projectId: "p1",
  category: "materials",
  amount: 250.5,
  date: "2026-06-01T10:00:00.000Z",
  supplierName: "مورد",
  ...data,
});

// ---------------------------------------------------------------- expenses

test("expense create: row, monthly counter and metrics in one transaction", { skip: skipReason }, async () => {
  const { id } = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ clientMutationId: "e-cm1", source: "nope" })));
  const [row] = await sql`SELECT * FROM expenses WHERE id = ${id}`;
  assert.equal(row.amount, "250.50");
  assert.equal(row.project_name, "برج", "falls back to the project's name");
  assert.equal(row.entity_name, "مورد", "entityName falls back to supplierName");
  assert.equal(row.entity_type, "supplier");
  assert.equal(row.payment_status, "unpaid");
  assert.equal(row.currency, "EGP");
  assert.equal(row.source, "", "unknown source stored as none");
  assert.equal(row.created_by, "u1");
  assert.deepEqual(await counter(), { expenses: 1, payments: 0 });
  assert.equal((await metrics("p1")).totalExpenses, 250.5);
});

test("expense create: validation, roles and project checks keep today's messages", { skip: skipReason }, async () => {
  const create = (uid: string, data: Record<string, unknown>) => tx((t) => createExpenseWithQuotaForUser(t, uid, data));
  await rejectsWith(create("u1", expense({ category: "food" })), "invalid-argument", "Unsupported expense category");
  await rejectsWith(create("u1", expense({ amount: 0 })), "invalid-argument", "Amount must be greater than zero");
  await rejectsWith(create("u1", expense({ inputMethod: "fax" })), "invalid-argument", "inputMethod must be manual, voice or text");
  await rejectsWith(create("u1", expense({ projectId: "nope" })), "invalid-argument", "Project does not exist");
  await rejectsWith(create("u1", expense({ projectId: "p_arch" })), "permission-denied", "Project is not available in this workspace");
  await rejectsWith(create("entry", expense()), "permission-denied", "Accounting access required");
});

test("expense create: 30 per month on free, then LIMIT_REACHED; replays never count", { skip: skipReason }, async () => {
  await sql`INSERT INTO usage_counters (id, workspace_id, period, expenses_count)
            VALUES (${`ws_1_${periodKey()}`}, 'ws_1', ${periodKey()}, 29)`;
  const first = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ clientMutationId: "x" })));
  const replay = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ clientMutationId: "x" })));
  assert.deepEqual(replay, first);
  await assert.rejects(tx((t) => createExpenseWithQuotaForUser(t, "u1", expense())), (error: { message?: string; details?: unknown }) => {
    assert.equal(error.message, "LIMIT_REACHED");
    assert.deepEqual(error.details, { code: "LIMIT_REACHED", limitType: "expensesPerMonth", current: 30, max: 30 });
    return true;
  });
  assert.deepEqual(await counter(), { expenses: 30, payments: 0 });
});

test("expense update: moving projects recomputes both; archived expenses cannot be edited", { skip: skipReason }, async () => {
  const { id } = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ amount: 100 })));
  await tx((t) => updateExpenseForUser(t, "u1", expense({ expenseId: id, projectId: "p2", amount: 40, category: "transport" })));
  assert.equal((await metrics("p1")).totalExpenses, 0);
  assert.equal((await metrics("p2")).totalExpenses, 40);
  const [row] = await sql`SELECT project_id, category, amount FROM expenses WHERE id = ${id}`;
  assert.deepEqual({ ...row }, { project_id: "p2", category: "transport", amount: "40.00" });

  await tx((t) => archiveExpenseWithQuotaRefundForUser(t, "u1", { workspaceId: "ws_1", expenseId: id }));
  await rejectsWith(
    tx((t) => updateExpenseForUser(t, "u1", expense({ expenseId: id, projectId: "p2" }))),
    "failed-precondition",
    "Archived expenses cannot be edited.",
  );
});

test("expense archive: refunds the monthly count once and removes it from totals", { skip: skipReason }, async () => {
  const { id } = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ amount: 100 })));
  await tx((t) => archiveExpenseWithQuotaRefundForUser(t, "u1", { workspaceId: "ws_1", expenseId: id }));
  await tx((t) => archiveExpenseWithQuotaRefundForUser(t, "u1", { workspaceId: "ws_1", expenseId: id }));
  assert.deepEqual(await counter(), { expenses: 0, payments: 0 });
  assert.equal((await metrics("p1")).totalExpenses, 0);
  const [row] = await sql`SELECT is_archived, archived_at FROM expenses WHERE id = ${id}`;
  assert.equal(row.is_archived, true);
  assert.ok(row.archived_at);
  await rejectsWith(
    tx((t) => archiveExpenseWithQuotaRefundForUser(t, "u1", { workspaceId: "ws_1", expenseId: "nope" })),
    "not-found",
    "Expense not found",
  );
});

// ---------------------------------------------------------------- expense items (feature 005)

const plumbing = [
  { id: "item_faucet", name: "حنفية", amount: 100 },
  { id: "item_gasket", name: "جلبه", amount: 50 },
  { id: "item_pipe", name: "ماسورة", amount: 90 },
];
const itemsOf = async (id: string) => {
  const [row] = await sql<{ items: Array<Record<string, unknown>>; amount: string; description: string }[]>`
    SELECT items, amount, description FROM expenses WHERE id = ${id}`;
  return row;
};

test("expense items: create stores ordered items, sets amount to their sum, counts once", { skip: skipReason }, async () => {
  const { amount: _omit, ...withoutAmount } = expense();
  const { id } = await tx((t) => createExpenseWithQuotaForUser(t, "u1", {
    ...withoutAmount, items: plumbing, description: "سباكه شهر 10",
  }));
  const row = await itemsOf(id);
  assert.equal(row.amount, "240.00");
  assert.equal(row.description, "سباكه شهر 10");
  assert.deepEqual(row.items.map((i) => [i.id, i.name, i.amount]), [
    ["item_faucet", "حنفية", 100], ["item_gasket", "جلبه", 50], ["item_pipe", "ماسورة", 90],
  ]);
  assert.equal((await metrics("p1")).totalExpenses, 240);
  assert.deepEqual(await counter(), { expenses: 1, payments: 0 }, "one receipt is one expense for the quota");

  const matching = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ items: plumbing, amount: 240 })));
  assert.equal((await itemsOf(matching.id)).amount, "240.00");
});

test("expense items: mismatching amount and invalid items are rejected before any write", { skip: skipReason }, async () => {
  const create = (data: Record<string, unknown>) => tx((t) => createExpenseWithQuotaForUser(t, "u1", expense(data)));
  await rejectsWith(create({ items: plumbing, amount: 250 }), "invalid-argument", "Amount must equal the sum of items");
  await rejectsWith(create({ items: [] }), "invalid-argument", "Expense must have between 1 and 100 items");
  await rejectsWith(create({ items: [{ name: "", amount: 5 }] }), "invalid-argument", "Item 1: name is required");
  const [{ count }] = await sql`SELECT count(*)::int AS count FROM expenses`;
  assert.equal(count, 0);
  assert.equal(await counter(), undefined, "no quota consumed by rejected creates");
});

test("expense items: legacy create (no items) keeps today's shape; text input method accepted", { skip: skipReason }, async () => {
  const { id } = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ amount: 75, inputMethod: "text", transcript: "رمل 75" })));
  const row = await itemsOf(id);
  assert.deepEqual(row.items, []);
  assert.equal(row.amount, "75.00");
  const [{ input_method, transcript }] = await sql`SELECT input_method, transcript FROM expenses WHERE id = ${id}`;
  assert.deepEqual({ input_method, transcript }, { input_method: "text", transcript: "رمل 75" });
});

test("expense items: the database rejects an amount that no longer matches the items", { skip: skipReason }, async () => {
  const { id } = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ items: plumbing, amount: undefined })));
  await assert.rejects(sql`UPDATE expenses SET amount = 1 WHERE id = ${id}`, (error: { code?: string; constraint_name?: string }) => {
    assert.equal(error.code, "23514");
    assert.equal(error.constraint_name, "expenses_amount_matches_items");
    return true;
  });
});

test("expense items: update replaces items and total; metrics follow", { skip: skipReason }, async () => {
  const { id } = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ items: plumbing, amount: undefined })));
  const edited = [
    { ...plumbing[0] }, { ...plumbing[1] }, { ...plumbing[2], amount: 95 },
    { id: "item_teflon", name: "شريط تيفلون", amount: 10 },
  ];
  await tx((t) => updateExpenseForUser(t, "u1", expense({ expenseId: id, items: edited, amount: undefined })));
  const row = await itemsOf(id);
  assert.equal(row.amount, "255.00");
  assert.equal(row.items.length, 4);
  assert.equal((await metrics("p1")).totalExpenses, 255);
});

test("expense items: legacy update payloads branch on the stored items", { skip: skipReason }, async () => {
  const legacy = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ amount: 100 })));
  await tx((t) => updateExpenseForUser(t, "u1", expense({ expenseId: legacy.id, amount: 120 })));
  assert.deepEqual(await itemsOf(legacy.id), { items: [], amount: "120.00", description: "" });

  const single = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({
    items: [{ id: "item_sand", name: "رمل", amount: 2000, quantity: 3, note: "ناعم" }], amount: undefined,
  })));
  await tx((t) => updateExpenseForUser(t, "u1", expense({ expenseId: single.id, amount: 2100 })));
  const singleRow = await itemsOf(single.id);
  assert.equal(singleRow.amount, "2100.00");
  assert.deepEqual(singleRow.items, [{ id: "item_sand", name: "رمل", amount: 2100, quantity: 3, note: "ناعم" }]);

  const multi = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ items: plumbing, amount: undefined })));
  await rejectsWith(
    tx((t) => updateExpenseForUser(t, "u1", expense({ expenseId: multi.id, amount: 300 }))),
    "failed-precondition",
    "This expense has several items; edit its items to change the amount",
  );
  assert.equal((await itemsOf(multi.id)).amount, "240.00", "row unchanged");
});

test("expense items: title is saved on update only when sent", { skip: skipReason }, async () => {
  const { id } = await tx((t) => createExpenseWithQuotaForUser(t, "u1", expense({ description: "قديم" })));
  await tx((t) => updateExpenseForUser(t, "u1", expense({ expenseId: id, description: "  سباكه شهر 10 " })));
  assert.equal((await itemsOf(id)).description, "سباكه شهر 10");
  await tx((t) => updateExpenseForUser(t, "u1", expense({ expenseId: id })));
  assert.equal((await itemsOf(id)).description, "سباكه شهر 10", "absent description leaves the title");
  await tx((t) => updateExpenseForUser(t, "u1", expense({ expenseId: id, description: null })));
  assert.equal((await itemsOf(id)).description, "سباكه شهر 10", "null description leaves the title");
});

// ---------------------------------------------------------------- payments

const payment = (data: Record<string, unknown> = {}) => ({
  workspaceId: "ws_1",
  projectId: "p1",
  amount: 1000,
  date: "2026-06-02T10:00:00.000Z",
  ...data,
});

test("payment create: cash collected follows status; counter and metrics updated", { skip: skipReason }, async () => {
  const { id } = await tx((t) =>
    createPaymentWithQuotaForUser(t, "u1", payment({ paymentStatus: "partial", paidAmount: 300 })),
  );
  const [row] = await sql`SELECT payment_status, paid_amount, payment_method, entity_type FROM payments WHERE id = ${id}`;
  assert.deepEqual({ ...row }, { payment_status: "partial", paid_amount: "300.00", payment_method: "cash", entity_type: "other" });
  assert.deepEqual(await counter(), { expenses: 0, payments: 1 });
  assert.equal((await metrics("p1")).totalPayments, 300);
});

test("payment create: needs a contract value, checked before any quota is used", { skip: skipReason }, async () => {
  await rejectsWith(
    tx((t) => createPaymentWithQuotaForUser(t, "u1", payment({ projectId: "p_nocontract" }))),
    "failed-precondition",
    "Set a contract value on this project before recording payments.",
  );
  assert.equal(await counter(), undefined);
  await rejectsWith(
    tx((t) => createPaymentWithQuotaForUser(t, "u1", payment({ projectId: "p_arch" }))),
    "permission-denied",
    "Project is archived and can no longer accept payments.",
  );
});

test("payment create: 10 per month on free", { skip: skipReason }, async () => {
  await sql`INSERT INTO usage_counters (id, workspace_id, period, payments_count)
            VALUES (${`ws_1_${periodKey()}`}, 'ws_1', ${periodKey()}, 10)`;
  await rejectsWith(tx((t) => createPaymentWithQuotaForUser(t, "u1", payment())), "failed-precondition", "LIMIT_REACHED");
});

test("payment update stores an edited paidAmount (Firebase dropped it) and totals follow it", { skip: skipReason }, async () => {
  const { id } = await tx((t) =>
    createPaymentWithQuotaForUser(t, "u1", payment({ paymentStatus: "partial", paidAmount: 300 })),
  );
  await tx((t) => updatePaymentForUser(t, "u1", payment({ paymentId: id, paymentStatus: "partial", paidAmount: 650 })));
  const [row] = await sql`SELECT paid_amount FROM payments WHERE id = ${id}`;
  assert.equal(row.paid_amount, "650.00");
  assert.equal((await metrics("p1")).totalPayments, 650);
  // Not sent: the stored value stays.
  await tx((t) => updatePaymentForUser(t, "u1", payment({ paymentId: id, paymentStatus: "partial" })));
  const [kept] = await sql`SELECT paid_amount FROM payments WHERE id = ${id}`;
  assert.equal(kept.paid_amount, "650.00");
});

test("payment update: cannot move onto a project without a contract; totals follow", { skip: skipReason }, async () => {
  const { id } = await tx((t) => createPaymentWithQuotaForUser(t, "u1", payment()));
  await rejectsWith(
    tx((t) => updatePaymentForUser(t, "u1", payment({ paymentId: id, projectId: "p_nocontract" }))),
    "failed-precondition",
    "Set a contract value on this project before recording payments.",
  );
  await tx((t) => updatePaymentForUser(t, "u1", payment({ paymentId: id, projectId: "p2", amount: 700 })));
  assert.equal((await metrics("p1")).totalPayments, 0);
  assert.equal((await metrics("p2")).totalPayments, 700);
});

test("payment archive: refunds the count once and removes the cash from totals", { skip: skipReason }, async () => {
  const { id } = await tx((t) => createPaymentWithQuotaForUser(t, "u1", payment()));
  await tx((t) => archivePaymentWithQuotaRefundForUser(t, "u1", { workspaceId: "ws_1", paymentId: id }));
  await tx((t) => archivePaymentWithQuotaRefundForUser(t, "u1", { workspaceId: "ws_1", paymentId: id }));
  assert.deepEqual(await counter(), { expenses: 0, payments: 0 });
  assert.equal((await metrics("p1")).totalPayments, 0);
});
