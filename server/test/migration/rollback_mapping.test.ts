/** T099: the rollback mapping is the inverse of the migration mapping (row → original document). */
import assert from "node:assert/strict";
import test from "node:test";
import { Timestamp } from "firebase-admin/firestore";

import { rowToFirestoreDoc, TABLE_COLLECTIONS } from "../../tools/rollback-to-firestore/reverse";
import { transformExport, type ExportedCollections, type TableColumns } from "../../tools/migrate-from-firestore/transform";

const columns: TableColumns = new Map(
  Object.entries({
    workspaces: ["id", "owner_uid", "name", "created_at", "updated_at", "legacy"],
    memberships: ["id", "workspace_id", "user_uid", "role", "status", "created_at", "updated_at", "legacy"],
    user_profiles: ["uid", "email", "full_name", "active_workspace_id", "default_currency", "created_at", "updated_at", "legacy"],
    expenses: ["id", "workspace_id", "project_id", "amount", "date", "category", "attachments", "is_archived", "created_at", "updated_at", "legacy"],
    worker_entries: ["id", "workspace_id", "project_id", "days_worked", "daily_wage", "total_cost", "date", "updated_at", "legacy"],
    usage_counters: ["id", "workspace_id", "period", "expenses_count", "updated_at", "legacy"],
    drafts: ["id", "workspace_id", "uid", "payload", "created_at", "updated_at"],
  }).map(([t, cols]) => [t, new Set(cols)]),
);

const at = new Timestamp(1_780_000_000, 0);
const date = at.toDate();

const source: ExportedCollections = {
  users: [{ id: "u1", data: { email: "o@example.com", fullName: "أحمد", workspaceId: "ws_1", defaultCurrency: "EGP", favouriteColour: "blue" } }],
  workspaces: [{ id: "ws_1", data: { ownerId: "u1", name: "الورشة", createdAt: at } }],
  memberships: [{ id: "ws_1_u1", data: { workspaceId: "ws_1", userId: "u1", role: "owner", status: "active" } }],
  expenses: [{
    id: "e1",
    data: {
      workspaceId: "ws_1", projectId: "p1", amount: 12.5, date: at, category: "materials", isArchived: false,
      attachments: [{ storagePath: "attachments/u1/a.jpg", fileName: "a.jpg" }], supplierCode: "S-9",
    },
  }],
  worker_entries: [{ id: "we1", data: { workspaceId: "ws_1", projectId: "p1", daysWorked: 1.25, dailyWage: 75.25, totalCost: 94.0625, date: at } }],
  usage_counters: [{ id: "ws_1_202610", data: { workspaceId: "ws_1", expensesCount: 3 } }],
  drafts: [{ id: "d1", data: { workspaceId: "ws_1", uid: "u1", transcript: "اسمنت", createdAt: at } }],
};

/** Postgres hands NUMERIC back as strings; mimic that for the money columns. */
function asStored(table: string, row: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...row };
  for (const k of ["amount", "days_worked", "daily_wage", "total_cost"]) {
    if (typeof out[k] === "number") out[k] = String(out[k]);
  }
  void table;
  return out;
}

/** The original document with Timestamps as Dates (what the Admin SDK turns back into Timestamps). */
function expected(data: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(data).map(([k, v]) => [k, v instanceof Timestamp ? v.toDate() : v]),
  );
}

test("every migrated row maps back to its original document", () => {
  const { rows } = transformExport(source, columns, new Set(["u1"]));
  for (const [collection, docs] of Object.entries(source)) {
    const table = Object.entries(TABLE_COLLECTIONS).find(([, c]) => c === collection)?.[0];
    assert.ok(table, collection);
    for (const doc of docs) {
      const row = rows.get(table)!.find((r) => [r.id, r.uid].includes(doc.id))!;
      const back = rowToFirestoreDoc(table, asStored(table, row));
      assert.equal(back.collection, collection);
      assert.equal(back.id, doc.id);
      const want = expected(doc.data);
      if (table === "user_profiles") want.uid = doc.id; // uid column; harmless extra field
      assert.deepEqual(back.data, want, `${collection}/${doc.id}`);
    }
  }
  assert.equal(date.getTime(), at.toMillis());
});

test("webhook_events and derived tables are never written back", () => {
  assert.equal(TABLE_COLLECTIONS.webhook_events, undefined);
  assert.equal(TABLE_COLLECTIONS.project_metrics, undefined);
  assert.equal(TABLE_COLLECTIONS.expenses, "expenses");
});
