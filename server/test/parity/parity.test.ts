/**
 * T057: the same scenario on the Cloud Functions (Firestore + Storage emulators, in-process) and
 * on the new API (Postgres) must leave the same records, usage counters and derived totals.
 *
 *   firebase emulators:exec --config server/test/parity/firebase.parity.json \
 *     --only firestore,storage --project demo-wizesite "cd server && npm run test:parity"
 *
 * Needs TEST_DATABASE_URL (a migrated test Postgres) as well.
 */
import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";

import type { Sql } from "../../src/db/pool";
import { resetDatabase, TEST_DATABASE_URL, testSql } from "../integration/helpers";
import {
  firebaseBackend,
  firebaseBugsHit,
  RECORD_COLLECTIONS,
  runScenario,
  serverBackend,
  type Snapshot,
} from "./scenario";

const skip =
  TEST_DATABASE_URL && process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST
    ? false
    : "needs TEST_DATABASE_URL and the Firebase emulators (firestore, storage)";

/** Fields compared per collection; references are compared by scenario label. */
const FIELDS: Record<(typeof RECORD_COLLECTIONS)[number], string[]> = {
  projects: ["name", "clientName", "contractValue", "budgetLimit", "completionPercentage", "status", "isArchived"],
  expenses: ["projectId", "category", "amount", "currency", "paymentStatus", "entityName", "entityType", "supplierName", "isArchived"],
  payments: ["projectId", "amount", "paymentStatus", "paidAmount", "paymentMethod", "entityName", "entityType", "isArchived"],
  workers: ["name", "dailyWage", "billingType", "status", "isArchived"],
  worker_entries: ["projectId", "workerId", "daysWorked", "dailyWage", "totalCost", "isArchived"],
};

let sql: Sql;
let firebase: { ids: Map<string, string>; snap: Snapshot };
let server: { ids: Map<string, string>; snap: Snapshot };

before(async () => {
  if (skip) return;
  process.env.GCLOUD_PROJECT ??= "demo-wizesite";
  sql = testSql();
  await resetDatabase(sql);
  const fb = firebaseBackend();
  const fbIds = await runScenario(fb);
  firebase = { ids: fbIds, snap: await fb.snapshot() };
  const root = await mkdtemp(path.join(os.tmpdir(), "parity-files-"));
  const sv = serverBackend(sql, root);
  const svIds = await runScenario(sv);
  server = { ids: svIds, snap: await sv.snapshot() };
});
after(async () => {
  if (sql) await sql.end();
});

/** id → label for one backend, so references compare across backends. */
function labeller(ids: Map<string, string>) {
  const byId = new Map([...ids].map(([label, id]) => [id, label]));
  return (value: unknown) => (typeof value === "string" && byId.has(value) ? byId.get(value) : value);
}

function normalise(value: unknown): unknown {
  // Firestore stores absent optionals as null or leaves them out; Postgres omits NULLs.
  if (value === undefined) return null;
  if (typeof value === "number") return Math.round(value * 10_000) / 10_000;
  return value;
}

function recordsByLabel(side: { ids: Map<string, string>; snap: Snapshot }, collection: (typeof RECORD_COLLECTIONS)[number]) {
  const label = labeller(side.ids);
  const out: Record<string, Record<string, unknown>> = {};
  for (const [id, doc] of side.snap.records[collection]) {
    const key = `${label(id)}`;
    out[key] = Object.fromEntries(FIELDS[collection].map((f) => [f, normalise(label(doc[f]))]));
    if (collection === "expenses") {
      const attachments = Array.isArray(doc.attachments) ? (doc.attachments as Array<Record<string, unknown>>) : [];
      out[key].attachments = attachments.map((a) => a.storagePath);
    }
  }
  return out;
}

test("sanity: both sides hold the scenario's data (an empty match would prove nothing)", { skip }, () => {
  for (const side of [firebase, server]) {
    const labels = (c: (typeof RECORD_COLLECTIONS)[number]) => [...side.snap.records[c].keys()].map(labeller(side.ids)).sort();
    assert.deepEqual(labels("projects"), ["P1", "P2"]);
    assert.deepEqual(labels("expenses"), ["E1", "E2"]);
    assert.deepEqual(labels("payments"), ["PAY1", "PAY2"]);
    assert.deepEqual(labels("worker_entries"), ["WE1"]);
    const p1 = side.snap.projectMetrics.get(side.ids.get("P1")!);
    // E1 300 + WE1 2 x 150; PAY1 partial 300 cash; PAY2 archived.
    assert.equal(Number(p1?.totalExpenses), 600);
    assert.equal(Number(p1?.totalPayments), 300);
    assert.ok(Object.keys(p1 ?? {}).length > 5);
  }
  // 3 expenses - E2 archived - E3 refunded by the cascade; 2 entries - WE3; 3 projects - P2 archived - P3 deleted.
  assert.deepEqual(firebase.snap.counters, { expenses: 1, payments: 1, workerEntries: 1, activeProjects: 1 });
});

for (const collection of RECORD_COLLECTIONS) {
  test(`records match: ${collection}`, { skip }, () => {
    assert.deepEqual(recordsByLabel(server, collection), recordsByLabel(firebase, collection));
  });
}

test("usage counters match (creates counted once, archive refunds, cascade refunds)", { skip }, () => {
  assert.deepEqual(server.snap.counters, firebase.snap.counters);
});

/** Every number and string the Cloud Functions stored must be the same on the new API. */
function compareDerived(name: string, fb: Record<string, unknown> | undefined, sv: Record<string, unknown> | undefined) {
  assert.ok(fb, `${name}: Firebase has no row`);
  assert.ok(sv, `${name}: new API has no row`);
  const label = (value: unknown) => value;
  const diffs: string[] = [];
  for (const [key, value] of Object.entries(fb)) {
    if (["updatedAt", "computedAt", "lastComputedAt", "createdAt", "projectId", "id"].includes(key)) continue;
    if (typeof value === "number" || typeof value === "string" || typeof value === "boolean" || value === null) {
      const other = normalise(label(sv[key]));
      if (JSON.stringify(normalise(value)) !== JSON.stringify(other)) {
        diffs.push(`${key}: firebase ${JSON.stringify(value)} vs new ${JSON.stringify(sv[key])}`);
      }
    }
  }
  assert.deepEqual(diffs, [], `${name} differs`);
}

test("derived project metrics match for every live project", { skip }, () => {
  const fbLabel = labeller(firebase.ids);
  const svLabel = labeller(server.ids);
  const fbByLabel = new Map([...firebase.snap.projectMetrics].map(([id, m]) => [`${fbLabel(id)}`, m]));
  const svByLabel = new Map([...server.snap.projectMetrics].map(([id, m]) => [`${svLabel(id)}`, m]));
  assert.deepEqual([...svByLabel.keys()].sort(), [...fbByLabel.keys()].sort(), "same projects have metrics");
  for (const [labelName, fb] of fbByLabel) {
    compareDerived(`project_metrics ${labelName}`, fb, svByLabel.get(labelName));
  }
});

test("derived workspace metrics match", { skip }, () => {
  compareDerived("workspace_metrics", firebase.snap.workspaceMetrics, server.snap.workspaceMetrics);
});

test("the deleted project and its records are gone on both sides", { skip }, () => {
  for (const side of [firebase, server]) {
    const label = labeller(side.ids);
    const labels = (c: (typeof RECORD_COLLECTIONS)[number]) => [...side.snap.records[c].keys()].map((id) => label(id));
    assert.ok(!labels("projects").includes("P3"));
    assert.ok(!labels("expenses").includes("E3"));
    assert.ok(!labels("worker_entries").includes("WE3"));
  }
});

test("known Cloud Functions bug: archive with refund always fails on Firebase (the new API works)", { skip }, () => {
  // Reads after writes in one Firestore transaction; see firebaseBugsHit in scenario.ts.
  assert.deepEqual(firebaseBugsHit.sort(), ["archiveExpenseWithQuotaRefund", "archivePaymentWithQuotaRefund"]);
});
