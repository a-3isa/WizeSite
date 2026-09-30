/**
 * T032: derived-state computation from Postgres-shaped rows.
 * The builders are verbatim ports (src/domain/accounting.ts); this checks the row→document
 * mapping and the recompute orchestration ported from recomputeProjectSummary. Full
 * cross-implementation parity against the Firebase emulator is the T057 parity harness.
 */
import assert from "node:assert/strict";
import test from "node:test";

import {
  buildAccountingSummaryPayloads,
  classifyProjectRisk,
} from "../../src/domain/accounting";
import { computeProjectDerived } from "../../src/recompute/project";
import { rowToDoc } from "../../src/recompute/rows";

const now = new Date(Date.UTC(2026, 5, 10, 12)); // 2026-06-10

// Rows exactly as postgres.js returns them: snake_case, NUMERIC as strings, timestamptz as Date.
const projectRow = {
  id: "p1",
  workspace_id: "ws_1",
  name: "برج A",
  status: "active",
  contract_value: "1000.00",
  budget_limit: "200.00",
  completion_percentage: "50.00",
  is_archived: false,
  legacy: {},
};
const expenseRows = [
  { id: "e1", workspace_id: "ws_1", project_id: "p1", amount: "100.00", category: "materials",
    date: new Date(Date.UTC(2026, 4, 2)), entity_name: "مورد", is_archived: false, attachments: [], legacy: {} },
  { id: "e2", workspace_id: "ws_1", project_id: "p1", amount: "50.00", category: "labor",
    date: new Date(Date.UTC(2026, 5, 3)), is_archived: false, attachments: [], legacy: {} },
];
const paymentRows = [
  { id: "pay1", workspace_id: "ws_1", project_id: "p1", amount: "400.00", payment_status: "paid",
    payment_method: "cash", date: new Date(Date.UTC(2026, 5, 5)), is_archived: false, attachments: [], legacy: {} },
  { id: "pay2", workspace_id: "ws_1", project_id: "p1", amount: "300.00", paid_amount: "100.00",
    payment_status: "partial", payment_method: "bank", date: new Date(Date.UTC(2026, 5, 6)),
    is_archived: false, attachments: [], legacy: {} },
];
const workerEntryRows = [
  { id: "we1", workspace_id: "ws_1", project_id: "p1", worker_id: "w1", days_worked: "2.00",
    daily_wage: "75.00", total_cost: null, date: new Date(Date.UTC(2026, 5, 4)),
    is_archived: false, attachments: [], legacy: {} },
];

function compute() {
  return computeProjectDerived({
    workspaceId: "ws_1",
    projectId: "p1",
    project: rowToDoc(projectRow),
    expenses: expenseRows.map(rowToDoc),
    payments: paymentRows.map(rowToDoc),
    workerEntries: workerEntryRows.map(rowToDoc),
    workerNames: new Map([["w1", "علي"]]),
    now,
  });
}

test("rowToDoc maps snake_case to the Firestore field names, NUMERIC to numbers, null total cost dropped", () => {
  const doc = rowToDoc(workerEntryRows[0]);
  assert.equal(doc.id, "we1");
  assert.equal(doc.workspaceId, "ws_1");
  assert.equal(doc.daysWorked, 2);
  assert.equal(doc.dailyWage, 75);
  assert.equal("totalCost" in doc, false, "NULL columns are absent, like missing Firestore fields");
  assert.ok(doc.date instanceof Date);
});

test("rowToDoc keeps unmapped legacy fields but lets columns win", () => {
  const doc = rowToDoc({ id: "x", amount: "5.00", legacy: { amount: 999, oldField: "kept" } });
  assert.equal(doc.amount, 5);
  assert.equal(doc.oldField, "kept");
});

test("project metrics totals, categories and monthly flow match the Cloud Functions rules", () => {
  const { projectMetrics: m } = compute();
  assert.equal(m.totalExpenses, 300, "150 manual + 150 derived labor");
  assert.equal(m.totalLaborCost, 150);
  assert.equal(m.totalPayments, 500, "partial payment counts its paid amount");
  assert.equal(m.netProfit, 200);
  assert.equal(m.remainingBalance, 500);
  assert.equal(m.expectedFinalCost, 600);
  assert.equal(m.budgetExceeded, true);
  assert.deepEqual(m.categoryTotals, { materials: 100, worker: 200 }, "legacy labor folds into worker");
  assert.deepEqual(m.monthlyFlow, [
    { month: "2026-05", expenses: 100, income: 0 },
    { month: "2026-06", expenses: 200, income: 500 },
  ]);
  assert.deepEqual(m.topWorkers, [{ workerId: "w1", name: "علي", totalCost: 150, totalDays: 2 }]);
  const verdict = classifyProjectRisk({ contractValue: 1000, netProfit: 200, expectedFinalCost: 600 });
  assert.equal(m.riskLevel, verdict.riskLevel);
  assert.equal(m.healthStatus, verdict.healthStatus);
});

test("no contract value → no risk verdict and no remaining balance (feature 003)", () => {
  const { projectMetrics: m } = computeProjectDerived({
    workspaceId: "ws_1",
    projectId: "p1",
    project: rowToDoc({ ...projectRow, contract_value: null }),
    expenses: expenseRows.map(rowToDoc),
    payments: [],
    workerEntries: [],
    workerNames: new Map(),
    now,
  });
  assert.equal(m.riskLevel, null);
  assert.equal(m.remainingBalance, null);
});

test("accounting summaries equal the verbatim builder output for the same documents", () => {
  const { summaries } = compute();
  const expected = buildAccountingSummaryPayloads({
    workspaceId: "ws_1",
    projectId: "p1",
    expenses: expenseRows.map(rowToDoc),
    payments: paymentRows.map(rowToDoc),
    workerEntries: workerEntryRows.map(rowToDoc),
    now,
  });
  assert.deepEqual(summaries, expected);
});
