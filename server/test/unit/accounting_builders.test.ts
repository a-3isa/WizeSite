import assert from "node:assert/strict";
import test from "node:test";
import { Timestamp } from "firebase-admin/firestore";

// Pure builder tests ported from functions/src/project_recompute_trigger.test.ts (tasks.md T014).

test("summary builder maintains project, weekly, entity, and category payloads", async () => {
  const { buildAccountingSummaryPayloads } = await import("../../src/domain/accounting");
  const now = new Date(Date.UTC(2026, 4, 28, 10));
  const monday = new Date(Date.UTC(2026, 4, 25, 9));
  const previousWeek = new Date(Date.UTC(2026, 4, 18, 9));

  const summaries = buildAccountingSummaryPayloads({
    workspaceId: "workspace_1",
    projectId: "project_1",
    now,
    expenses: [
      {
        id: "expense_1",
        workspaceId: "workspace_1",
        projectId: "project_1",
        entityId: "supplier_1",
        entityName: "Steel Supplier",
        entityType: "supplier",
        category: "materials",
        amount: 200,
        date: Timestamp.fromDate(now),
        attachments: [{ id: "attachment_1" }],
      },
      {
        id: "expense_2",
        workspaceId: "workspace_1",
        projectId: "project_1",
        entityName: "Equipment Rental",
        entityType: "equipment",
        category: "equipment",
        amount: 50,
        date: Timestamp.fromDate(previousWeek),
      },
    ],
    payments: [
      {
        id: "payment_1",
        workspaceId: "workspace_1",
        projectId: "project_1",
        entityId: "client_1",
        entityName: "Client One",
        entityType: "client",
        amount: 125,
        paymentMethod: "cash",
        date: Timestamp.fromDate(monday),
        attachments: [{ id: "attachment_2" }],
      },
    ],
    workerEntries: [
      {
        id: "entry_1",
        workspaceId: "workspace_1",
        projectId: "project_1",
        workerId: "worker_1",
        workerName: "Worker One",
        daysWorked: 2,
        dailyWage: 75,
        date: Timestamp.fromDate(monday),
      },
    ],
  });

  assert.equal(Number(summaries.projectSummary.todayExpenses ?? 0), 200);
  assert.equal(Number(summaries.projectSummary.weeklyExpenses ?? 0), 200);
  assert.equal(Number(summaries.projectSummary.monthlyExpenses ?? 0), 250);
  assert.equal(Number(summaries.projectSummary.totalPayments ?? 0), 125);

  const unpaidSummaries = buildAccountingSummaryPayloads({
    workspaceId: "workspace_1",
    projectId: "project_1",
    now,
    expenses: [],
    workerEntries: [],
    payments: [
      {
        id: "payment_unpaid",
        amount: 500,
        paymentStatus: "unpaid",
        paymentMethod: "cash",
        date: Timestamp.fromDate(monday),
      },
    ],
  });
  assert.equal(
    Number(unpaidSummaries.projectSummary.totalPayments ?? 0),
    0,
  );
  assert.equal(Number(summaries.projectSummary.transactionCount ?? 0), 4);
  assert.equal(Number(summaries.projectSummary.attachmentCount ?? 0), 2);

  const currentWeekly = summaries.weeklySummaries.find((summary) =>
    `${summary.id ?? ""}`.includes("2026_05_25"),
  );
  assert.ok(currentWeekly);
  assert.equal(Number(currentWeekly.totalExpenses ?? 0), 350);
  assert.equal(Number(currentWeekly.totalPayments ?? 0), 125);
  assert.deepEqual(currentWeekly.topCategory, {
    id: "materials",
    name: "materials",
    total: 200,
  });

  const supplierSummary = summaries.entitySummaries.find(
    (summary) => summary.entityId === "supplier_1",
  );
  assert.ok(supplierSummary);
  assert.equal(Number(supplierSummary.totalExpenses ?? 0), 200);
  assert.equal(Number(supplierSummary.attachmentCount ?? 0), 1);
  assert.deepEqual(supplierSummary.categoryBreakdown, { materials: 200 });

  const laborSummary = summaries.categorySummaries.find(
    (summary) => summary.category === "labor",
  );
  assert.ok(laborSummary);
  assert.equal(Number(laborSummary.totalAmount ?? 0), 150);
  assert.equal(Number(laborSummary.transactionCount ?? 0), 1);
});

test("worker accounting summary builder excludes unresolved legacy partials from confirmed totals", async () => {
  const { buildWorkerAccountingSummaryPayload } = await import("../../src/domain/accounting");

  const summary = buildWorkerAccountingSummaryPayload({
    workspaceId: "workspace_1",
    workerId: "worker_1",
    records: [
      { amount: 100, paymentStatus: "paid" },
      { amount: 200, paymentStatus: "unpaid" },
      { amount: 300, paymentStatus: "partial", paidAmount: 125 },
      { amount: 400, paymentStatus: "partial" },
    ],
  });

  assert.equal(Number(summary.totalAmount ?? 0), 1000);
  assert.equal(Number(summary.confirmedPaid ?? 0), 225);
  assert.equal(Number(summary.confirmedOutstanding ?? 0), 375);
  assert.equal(Number(summary.unresolvedLegacyCount ?? 0), 1);
  assert.equal(Number(summary.recordCount ?? 0), 4);
});

test("workspace metrics builder composes bounded financial dashboard data", async () => {
  const {buildWorkspaceMetricsPayload} = await import("../../src/domain/accounting");
  const payload = buildWorkspaceMetricsPayload("workspace_1", [
    {
      projectId: "project_1",
      status: "active",
      isArchived: false,
      totalExpenses: 500,
      totalIncome: 900,
      weeklyExpenses: 80,
      weeklyIncome: 120,
      categoryTotals: {materials: 300, labor: 200},
      entityTotals: {Acme: 400},
      paymentMethodTotals: {cash: 120},
      totalLaborCost: 200,
      totalEquipmentCost: 40,
      recentTransactions: [
        {id: "payment_1", type: "payment", title: "Client", amount: 120, date: "2026-06-15T10:00:00.000Z"},
      ],
    },
    {
      projectId: "project_2",
      status: "completed",
      isArchived: false,
      totalExpenses: 100,
      totalIncome: 50,
      weeklyExpenses: 20,
      weeklyIncome: 10,
      categoryTotals: {materials: 100},
      entityTotals: {Acme: 50, Beta: 90},
      paymentMethodTotals: {bank: 10},
      totalLaborCost: 0,
      totalEquipmentCost: 10,
      recentTransactions: [],
    },
  ]);

  assert.equal(payload.totalProjects, 2);
  assert.equal(payload.activeProjects, 1);
  assert.equal(payload.totalExpenses, 600);
  assert.equal(payload.totalIncome, 950);
  assert.equal(payload.weeklyExpenses, 100);
  assert.equal(payload.weeklyIncome, 130);
  assert.equal(payload.topCategory, "materials");
  assert.equal(payload.topEntity, "Acme");
  assert.equal((payload.recentTransactions as unknown[]).length, 1);
});
