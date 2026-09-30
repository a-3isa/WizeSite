/** T031: the verification report fails loudly on every kind of mismatch (SC-001). */
import assert from "node:assert/strict";
import test from "node:test";

import { buildReport, type VerifyInput } from "../../tools/migrate-from-firestore/verify";

const totals = (e: number, p: number) => ({ totalExpenses: e, totalPayments: p, netProfit: p - e });

function clean(): VerifyInput {
  return {
    counts: [
      { collection: "expenses", table: "expenses", source: 3, skipped: 0, target: 3 },
      { collection: "projects", table: "projects", source: 2, skipped: 1, target: 1 },
    ],
    projects: [
      { projectId: "p1", fromSource: totals(300, 500), fromMigratedRows: totals(300, 500), stored: totals(300, 500) },
    ],
    files: [{ storagePath: "receipts/u1/a.jpg", sourceMd5: "abc", targetMd5: "abc" }],
    precisionFlags: [],
  };
}

test("a clean migration passes", () => {
  const report = buildReport(clean());
  assert.equal(report.ok, true);
  assert.deepEqual(report.mismatches, []);
});

test("count mismatch fails", () => {
  const input = clean();
  input.counts[0].target = 2;
  const report = buildReport(input);
  assert.equal(report.ok, false);
  assert.match(report.mismatches[0], /expenses: source 3 - skipped 0 != target 2/);
});

test("per-project total mismatch fails (source vs migrated rows vs stored metrics)", () => {
  const input = clean();
  input.projects[0].stored = totals(300, 499.99);
  const report = buildReport(input);
  assert.equal(report.ok, false);
  assert.match(report.mismatches.join("\n"), /p1 totalPayments/);
});

test("rounding noise below half a cent is not a mismatch", () => {
  const input = clean();
  input.projects[0].fromMigratedRows = totals(300.0000001, 500);
  assert.equal(buildReport(input).ok, true);
});

test("MD5 mismatch and missing file fail", () => {
  const input = clean();
  input.files.push({ storagePath: "receipts/u1/b.jpg", sourceMd5: "x", targetMd5: "y" });
  input.files.push({ storagePath: "receipts/u1/إيصال.pdf", sourceMd5: "z", targetMd5: null });
  const report = buildReport(input);
  assert.equal(report.ok, false);
  assert.equal(report.mismatches.length, 2);
  assert.match(report.mismatches.join("\n"), /إيصال\.pdf: missing/);
});

test("money precision flags fail the report", () => {
  const input = clean();
  input.precisionFlags = [{ table: "expenses", id: "e9", column: "amount", value: 10.005 }];
  assert.equal(buildReport(input).ok, false);
});

test("old Firestore metrics drift is a warning, not a failure", () => {
  const input = clean();
  input.projects[0].firestoreMetrics = totals(290, 500);
  const report = buildReport(input);
  assert.equal(report.ok, true);
  assert.match(report.warnings.join("\n"), /p1.*pre-existing drift/);
});
