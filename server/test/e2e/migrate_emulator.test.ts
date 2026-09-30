/**
 * End-to-end migrator run against the Firebase emulators (Firestore + Storage + Auth).
 *
 *   firebase emulators:exec --only firestore,storage,auth --project demo-wizesite \
 *     "cd server && TEST_DATABASE_URL=... npm run test:e2e"
 *
 * Seeds Firebase, runs the real CLI (dist/tools/migrate-from-firestore/index.js) into the test
 * Postgres, then checks the report, the rows and the copied file.
 */
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";
import { promisify } from "node:util";

import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import type { Sql } from "../../src/db/pool";
import { resetDatabase, TEST_DATABASE_URL, testSql } from "../integration/helpers";

const run = promisify(execFile);
const PROJECT = "demo-wizesite";
const BUCKET = `${PROJECT}.appspot.com`;
const skip =
  TEST_DATABASE_URL && process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST
    ? false
    : "needs TEST_DATABASE_URL and the Firebase emulators (firestore, storage, auth)";

let sql: Sql;
const receipt = Buffer.from("fake-jpeg-bytes-إيصال", "utf8");

before(async () => {
  if (skip) return;
  sql = testSql();
  await resetDatabase(sql);
  const app = getApps()[0] ?? initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = getFirestore(app);
  await getAuth(app).createUser({ uid: "owner_1", email: "owner@example.com" }).catch(() => undefined);
  // deleted_1 intentionally has no Auth account.

  const at = (iso: string) => Timestamp.fromDate(new Date(iso));
  const set = (c: string, id: string, data: Record<string, unknown>) => db.collection(c).doc(id).set(data);
  await set("users", "owner_1", { email: "owner@example.com", fullName: "مالك", workspaceId: "ws_1" });
  await set("users", "deleted_1", { email: "gone@example.com", workspaceId: "ws_gone" });
  await set("workspaces", "ws_1", { ownerId: "owner_1", name: "Main" });
  await set("workspaces", "ws_gone", { ownerId: "deleted_1", name: "Gone" });
  await set("memberships", "ws_1_owner_1", { workspaceId: "ws_1", userId: "owner_1", role: "owner" });
  await set("projects", "p1", { workspaceId: "ws_1", name: "Tower", contractValue: 1000, isArchived: false });
  await set("projects", "p_gone", { workspaceId: "ws_gone", name: "Orphaned", isArchived: false });
  await set("expenses", "e1", {
    workspaceId: "ws_1", projectId: "p1", amount: 120.5, category: "materials", date: at("2026-05-02"),
    isArchived: false,
    attachments: [{ id: "a1", fileName: "إيصال.jpg", storagePath: "receipts/owner_1/receipt.jpg", uploadedAt: at("2026-05-02") }],
  });
  await set("payments", "pay1", {
    workspaceId: "ws_1", projectId: "p1", amount: 300, paymentStatus: "paid", date: at("2026-06-01"), isArchived: false,
  });
  // Stale Firestore metrics: must only produce a drift warning.
  await set("project_metrics", "p1", { workspaceId: "ws_1", totalExpenses: 100, totalPayments: 300, netProfit: 200 });
  await getStorage(app).bucket(BUCKET).file("receipts/owner_1/receipt.jpg").save(receipt);
});

after(async () => {
  if (sql) await sql.end();
});

test("migrator exports, loads, copies files and produces a clean report", { skip }, async () => {
  const filesRoot = await mkdtemp(path.join(os.tmpdir(), "wizesite-files-"));
  const reportPath = path.join(filesRoot, "report.json");
  const cli = path.resolve(__dirname, "../../tools/migrate-from-firestore/index.js");
  const { stdout } = await run(process.execPath, [cli, "--target=e2e", `--report=${reportPath}`, "--reset"], {
    env: {
      ...process.env,
      DATABASE_URL: TEST_DATABASE_URL,
      FILES_ROOT: filesRoot,
      FIREBASE_PROJECT_ID: PROJECT,
      FIREBASE_STORAGE_BUCKET: BUCKET,
      GCLOUD_PROJECT: PROJECT,
    },
  });
  assert.match(stdout, /OK: 0 mismatch/);

  const report = JSON.parse(await readFile(reportPath, "utf8"));
  assert.equal(report.ok, true);
  assert.equal(report.summary.files, 1);
  assert.ok(report.warnings.some((w: string) => /p1 totalExpenses.*pre-existing drift/.test(w)));

  const [metrics] = await sql<{ payload: Record<string, unknown> }[]>`
    SELECT payload FROM project_metrics WHERE project_id = 'p1'`;
  assert.equal(metrics.payload.totalExpenses, 120.5);
  const gone = await sql`SELECT 1 FROM projects WHERE id = 'p_gone'`;
  assert.equal(gone.length, 0, "deleted owner's workspace data skipped");

  const copied = await readFile(path.join(filesRoot, "receipts/owner_1/receipt.jpg"));
  assert.equal(
    createHash("md5").update(copied).digest("hex"),
    createHash("md5").update(receipt).digest("hex"),
  );
});
