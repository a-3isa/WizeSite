/** T030: Firestore documents → Postgres rows (tools/migrate-from-firestore/transform.ts). */
import assert from "node:assert/strict";
import test from "node:test";
import { Timestamp } from "firebase-admin/firestore";

import {
  transformExport,
  type ExportedCollections,
  type TableColumns,
} from "../../tools/migrate-from-firestore/transform";

// Column sets as the loader reads them from information_schema (subset of the real schema).
const columns: TableColumns = new Map(
  Object.entries({
    workspaces: ["id", "owner_uid", "name", "created_at", "updated_at", "legacy"],
    memberships: ["id", "workspace_id", "user_uid", "role", "status", "invited_by", "created_at", "updated_at", "legacy"],
    user_profiles: ["uid", "email", "full_name", "photo_url", "active_workspace_id", "default_currency",
      "risk_alerts_enabled", "setup_completed", "created_at", "updated_at", "legacy"],
    projects: ["id", "workspace_id", "name", "contract_value", "completion_percentage", "is_archived", "created_at", "updated_at", "legacy"],
    expenses: ["id", "workspace_id", "project_id", "amount", "date", "category", "notes", "attachments",
      "is_archived", "created_at", "updated_at", "legacy"],
    usage_counters: ["id", "workspace_id", "period", "expenses_count", "active_projects", "updated_at", "legacy"],
    subscriptions: ["workspace_id", "tier", "status", "period_ends_at", "updated_at", "legacy"],
  }).map(([t, cols]) => [t, new Set(cols)]),
);

const createdAt = new Timestamp(1_780_000_000, 123_456_000); // microsecond part must survive

function exported(): ExportedCollections {
  return {
    users: [
      { id: "owner_1", data: { id: "owner_1", email: "o@example.com", fullName: "أحمد", workspaceId: "ws_1", setupCompleted: true, createdAt } },
      { id: "deleted_1", data: { id: "deleted_1", email: "gone@example.com", workspaceId: "ws_gone" } },
    ],
    workspaces: [
      { id: "ws_1", data: { id: "ws_1", ownerId: "owner_1", name: "الورشة" } },
      { id: "ws_gone", data: { id: "ws_gone", ownerId: "deleted_1", name: "Gone" } },
    ],
    memberships: [
      { id: "ws_1_owner_1", data: { workspaceId: "ws_1", userId: "owner_1", role: "owner" } },
      { id: "ws_gone_deleted_1", data: { workspaceId: "ws_gone", userId: "deleted_1", role: "owner" } },
    ],
    projects: [
      { id: "p1", data: { workspaceId: "ws_1", name: "Tower", contractValue: 1000, completionPercentage: 32.80725319006043, isArchived: false, colour: "blue" } },
      { id: "p_gone", data: { workspaceId: "ws_gone", name: "Orphan" } },
    ],
    expenses: [
      {
        id: "e1",
        data: {
          workspaceId: "ws_1", projectId: "p1", amount: 12.5, date: createdAt, category: "materials",
          notes: "حديد", isArchived: false,
          attachments: [{ id: "a1", fileName: "إيصال.jpg", storagePath: "receipts/owner_1/x.jpg", uploadedAt: createdAt }],
        },
      },
      { id: "e_precise", data: { workspaceId: "ws_1", projectId: "p1", amount: 10.005, date: createdAt, category: "other" } },
      { id: "e_float_noise", data: { workspaceId: "ws_1", projectId: "p1", amount: 0.1 + 0.2, date: createdAt, category: "other" } },
    ],
    usage_counters: [
      { id: "ws_1_2026-06", data: { workspaceId: "ws_1", expensesCount: 3 } },
      { id: "ws_1_projects", data: { workspaceId: "ws_1", activeProjects: 1 } },
    ],
    subscriptions: [{ id: "ws_1", data: { workspaceId: "ws_1", tier: "pro", status: "active", periodEndsAt: createdAt } }],
  };
}

const liveUids = new Set(["owner_1"]);

test("Timestamp becomes a Date with microseconds preserved", () => {
  const { rows } = transformExport(exported(), columns, liveUids);
  const profile = rows.get("user_profiles")!.find((r) => r.uid === "owner_1")!;
  const date = profile.created_at as Date;
  assert.ok(date instanceof Date);
  assert.equal(date.getTime(), 1_780_000_000_123);
  const expense = rows.get("expenses")!.find((r) => r.id === "e1")!;
  assert.equal((expense.date as Date).getTime(), createdAt.toMillis());
});

test("field renames per table (users→user_profiles, ownerId, userId, workspaceId)", () => {
  const { rows } = transformExport(exported(), columns, liveUids);
  const profile = rows.get("user_profiles")!.find((r) => r.uid === "owner_1")!;
  assert.equal(profile.active_workspace_id, "ws_1");
  assert.equal(profile.full_name, "أحمد", "Arabic text unchanged");
  assert.equal(rows.get("workspaces")!.find((r) => r.id === "ws_1")!.owner_uid, "owner_1");
  const membership = rows.get("memberships")!.find((r) => r.id === "ws_1_owner_1")!;
  assert.equal(membership.user_uid, "owner_1");
  assert.equal(membership.status, "active", "missing status defaults to active (existence = membership)");
});

test("unknown fields are preserved in legacy, never dropped", () => {
  const { rows } = transformExport(exported(), columns, liveUids);
  const project = rows.get("projects")!.find((r) => r.id === "p1")!;
  assert.deepEqual(project.legacy, { colour: "blue" });
});

test("money with more than 2 decimals is flagged, not rounded; float noise is not flagged", () => {
  const { rows, precisionFlags } = transformExport(exported(), columns, liveUids);
  assert.deepEqual(
    precisionFlags.map((f) => [f.table, f.id, f.column]),
    [["expenses", "e_precise", "amount"]],
  );
  assert.equal(rows.get("expenses")!.find((r) => r.id === "e_precise")!.amount, "10.005", "passed through exactly");
  assert.equal(rows.get("expenses")!.find((r) => r.id === "e_float_noise")!.amount, "0.30");
});

test("completion percentage is not money: stored exactly as a float, never flagged", () => {
  const { rows, precisionFlags } = transformExport(exported(), columns, liveUids);
  assert.equal(precisionFlags.some((f) => f.column === "completion_percentage"), false);
  assert.equal(rows.get("projects")!.find((r) => r.id === "p1")!.completion_percentage, 32.80725319006043);
});

test("duplicate memberships for one (workspace, user) merge into the canonical doc and are counted", () => {
  const data = exported();
  data.memberships = [
    ...data.memberships!,
    // Legacy random-id twin of ws_1_owner_1 (seen in production data).
    { id: "QIQdh2LZD244vdjh7lxU", data: { workspaceId: "ws_1", userId: "owner_1", role: "owner" } },
  ];
  const { rows, skipped, duplicates } = transformExport(data, columns, liveUids);
  const kept = rows.get("memberships")!.filter((r) => r.workspace_id === "ws_1" && r.user_uid === "owner_1");
  assert.deepEqual(kept.map((r) => r.id), ["ws_1_owner_1"]);
  assert.equal(skipped.get("memberships"), 2, "1 dead-account membership + 1 merged duplicate");
  assert.deepEqual(duplicates, [
    { workspaceId: "ws_1", userId: "owner_1", kept: "ws_1_owner_1", dropped: ["QIQdh2LZD244vdjh7lxU"], conflicting: false },
  ]);
});

test("duplicate memberships that disagree on role are flagged as conflicting", () => {
  const data = exported();
  data.memberships = [
    ...data.memberships!,
    { id: "rnd", data: { workspaceId: "ws_1", userId: "owner_1", role: "member" } },
  ];
  const { duplicates } = transformExport(data, columns, liveUids);
  assert.equal(duplicates[0].conflicting, true);
});

test("embedded attachments stay a JSON array; Timestamps inside become ISO strings; non-ASCII names intact", () => {
  const { rows } = transformExport(exported(), columns, liveUids);
  const attachments = rows.get("expenses")!.find((r) => r.id === "e1")!.attachments as Array<Record<string, unknown>>;
  assert.equal(attachments[0].fileName, "إيصال.jpg");
  assert.equal(attachments[0].storagePath, "receipts/owner_1/x.jpg");
  assert.equal(attachments[0].uploadedAt, new Date(createdAt.toMillis()).toISOString());
});

test("data of deleted accounts and their owned workspaces is skipped and counted (FR-014)", () => {
  const { rows, skipped } = transformExport(exported(), columns, liveUids);
  assert.ok(!rows.get("user_profiles")!.some((r) => r.uid === "deleted_1"));
  assert.ok(!rows.get("workspaces")!.some((r) => r.id === "ws_gone"));
  assert.ok(!rows.get("projects")!.some((r) => r.id === "p_gone"));
  assert.ok(!rows.get("memberships")!.some((r) => r.id === "ws_gone_deleted_1"));
  assert.equal(skipped.get("projects"), 1);
  assert.equal(skipped.get("users"), 1);
});

test("usage counters and subscriptions keep their Firestore document identity", () => {
  const { rows } = transformExport(exported(), columns, liveUids);
  const monthly = rows.get("usage_counters")!.find((r) => r.id === "ws_1_2026-06")!;
  assert.equal(monthly.period, "2026-06");
  assert.equal(monthly.expenses_count, 3);
  assert.equal(rows.get("usage_counters")!.find((r) => r.id === "ws_1_projects")!.period, "projects");
  const sub = rows.get("subscriptions")![0];
  assert.equal(sub.workspace_id, "ws_1");
  assert.ok(sub.period_ends_at instanceof Date);
});
