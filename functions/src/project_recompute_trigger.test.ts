import assert from "node:assert/strict";
import test from "node:test";
import {
  RulesTestEnvironment,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;

type TriggerData = Record<string, unknown>;

type RecomputeHandler<TParams extends Record<string, string | undefined>> =
  (event: {
    data?: {
      before?: { data: () => TriggerData | undefined };
      after?: { data: () => TriggerData | undefined };
    };
    params: TParams;
  }) => Promise<void>;

function snapshotOf(data: TriggerData | undefined) {
  if (!data) {
    return undefined;
  }
  return { data: () => data };
}

function projectWriteEvent(
  before: TriggerData | undefined,
  after: TriggerData | undefined,
  projectId = "project_1",
) {
  return {
    data: {
      before: snapshotOf(before),
      after: snapshotOf(after),
    },
    params: { projectId },
  };
}

function expenseWriteEvent(
  before: TriggerData | undefined,
  after: TriggerData | undefined,
  expenseId = "expense_1",
) {
  return {
    data: {
      before: snapshotOf(before),
      after: snapshotOf(after),
    },
    params: { expenseId },
  };
}

function paymentWriteEvent(
  before: TriggerData | undefined,
  after: TriggerData | undefined,
  paymentId = "payment_1",
) {
  return {
    data: {
      before: snapshotOf(before),
      after: snapshotOf(after),
    },
    params: { paymentId },
  };
}

function workerEntryWriteEvent(
  before: TriggerData | undefined,
  after: TriggerData | undefined,
  entryId = "entry_1",
) {
  return {
    data: {
      before: snapshotOf(before),
      after: snapshotOf(after),
    },
    params: { entryId },
  };
}

test("summary builder maintains project, weekly, entity, and category payloads", async () => {
  const { buildAccountingSummaryPayloads } = await import("./index");
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
        date: admin.firestore.Timestamp.fromDate(now),
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
        date: admin.firestore.Timestamp.fromDate(previousWeek),
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
        date: admin.firestore.Timestamp.fromDate(monday),
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
        date: admin.firestore.Timestamp.fromDate(monday),
      },
    ],
  });

  assert.equal(Number(summaries.projectSummary.todayExpenses ?? 0), 200);
  assert.equal(Number(summaries.projectSummary.weeklyExpenses ?? 0), 200);
  assert.equal(Number(summaries.projectSummary.monthlyExpenses ?? 0), 250);
  assert.equal(Number(summaries.projectSummary.totalPayments ?? 0), 125);
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

if (!emulatorHost) {
  test(
    "Project trigger emulator tests require FIRESTORE_EMULATOR_HOST (skipped)",
    { skip: true },
    () => {},
  );
} else {
  const [host, portText] = emulatorHost.split(":");
  const projectId = "buildtrack-trigger-test";
  process.env.GCLOUD_PROJECT = projectId;
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId });

  let env: RulesTestEnvironment;
  let db: admin.firestore.Firestore;
  let handleProjectWriteRecompute: RecomputeHandler<{ projectId?: string }>;
  let handleExpenseWriteRecompute: RecomputeHandler<{ expenseId?: string }>;
  let handlePaymentWriteRecompute: RecomputeHandler<{ paymentId?: string }>;
  let handleWorkerEntryWriteRecompute: RecomputeHandler<{ entryId?: string }>;
  let createExpenseWithQuotaForUser: (
    uid: string,
    data: Record<string, unknown>,
  ) => Promise<{ id: string }>;
  let createPaymentWithQuotaForUser: (
    uid: string,
    data: Record<string, unknown>,
  ) => Promise<{ id: string }>;
  let createWorkerEntryWithQuotaForUser: (
    uid: string,
    data: Record<string, unknown>,
  ) => Promise<{ id: string }>;

  const workspaceId = "workspace_1";
  const now = new Date();
  const currentMonthDate = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 10),
  );
  const previousMonthDate = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 12),
  );
  const twoMonthsAgoDate = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 2, 8),
  );
  const oldHistoryDate = new Date(
    Date.UTC(now.getUTCFullYear() - 1, now.getUTCMonth(), 5),
  );
  const baseProject = {
    id: "project_1",
    workspaceId,
    name: "Tower A",
    status: "active",
    isArchived: false,
    contractValue: 1000,
    completionPercentage: 50,
    budgetLimit: 700,
  };

  async function seedRecomputeInputs() {
    await db
      .collection("projects")
      .doc("project_1")
      .set({
        ...baseProject,
      });
    await db
      .collection("expenses")
      .doc("expense_1")
      .set({
        id: "expense_1",
        workspaceId,
        projectId: "project_1",
        category: "materials",
        amount: 200,
        date: admin.firestore.Timestamp.fromDate(previousMonthDate),
        isArchived: false,
      });
    await db
      .collection("payments")
      .doc("payment_1")
      .set({
        id: "payment_1",
        workspaceId,
        projectId: "project_1",
        amount: 300,
        date: admin.firestore.Timestamp.fromDate(currentMonthDate),
        isArchived: false,
      });
    await db.collection("workers").doc("worker_1").set({
      id: "worker_1",
      workspaceId,
      name: "Worker One",
      isArchived: false,
    });
    await db
      .collection("worker_entries")
      .doc("entry_1")
      .set({
        id: "entry_1",
        workspaceId,
        workerId: "worker_1",
        projectId: "project_1",
        daysWorked: 1,
        dailyWage: 100,
        totalCost: 100,
        date: admin.firestore.Timestamp.fromDate(twoMonthsAgoDate),
        isArchived: false,
      });
    await db.collection("memberships").doc(`${workspaceId}_user_1`).set({
      workspaceId,
      userId: "user_1",
      role: "owner",
    });
    await db.collection("users").doc("user_1").set({
      id: "user_1",
      workspaceId,
      riskAlertsEnabled: true,
    });
  }

  test.before(async () => {
    env = await initializeTestEnvironment({
      projectId,
      firestore: {
        host,
        port: Number(portText),
      },
    });

    const indexModule = await import("./index");
    handleProjectWriteRecompute = indexModule.handleProjectWriteRecompute;
    handleExpenseWriteRecompute = indexModule.handleExpenseWriteRecompute;
    handlePaymentWriteRecompute = indexModule.handlePaymentWriteRecompute;
    handleWorkerEntryWriteRecompute =
      indexModule.handleWorkerEntryWriteRecompute;
    createExpenseWithQuotaForUser = indexModule.createExpenseWithQuotaForUser;
    createPaymentWithQuotaForUser = indexModule.createPaymentWithQuotaForUser;
    createWorkerEntryWithQuotaForUser =
      indexModule.createWorkerEntryWithQuotaForUser;
    db = admin.firestore();
  });

  test.after(async () => {
    await env.cleanup();
    await Promise.all(
      admin.apps
        .filter((app): app is admin.app.App => app !== null)
        .map((app) => app.delete().catch(() => undefined)),
    );
  });

  test.beforeEach(async () => {
    await env.clearFirestore();
  });

  test("createExpenseWithQuotaForUser persists attachments", async () => {
    await db.collection("memberships").doc(`${workspaceId}_user_1`).set({
      workspaceId,
      userId: "user_1",
      role: "owner",
    });
    await db
      .collection("projects")
      .doc("project_1")
      .set({
        ...baseProject,
      });

    const result = await createExpenseWithQuotaForUser("user_1", {
      workspaceId,
      projectId: "project_1",
      category: "materials",
      amount: 50,
      date: admin.firestore.Timestamp.fromDate(currentMonthDate),
      notes: "Attachment test",
      paymentMethod: "cash",
      attachments: [
        {
          id: "attach_1",
          fileName: "receipt.pdf",
          downloadUrl: "https://example.com/receipt.pdf",
          storagePath: "attachments/receipt.pdf",
          uploadedAt: admin.firestore.Timestamp.fromDate(currentMonthDate),
          contentType: "application/pdf",
          size: 12345,
        },
      ],
      clientMutationId: "mutation_1",
    });

    const saved = (
      await db.collection("expenses").doc(result.id).get()
    ).data() as TriggerData & { attachments?: Array<Record<string, unknown>> };
    assert.equal(Array.isArray(saved.attachments), true);
    assert.equal(saved.attachments?.length, 1);
    assert.equal(saved.attachments?.[0]?.id, "attach_1");
    assert.equal(
      saved.attachments?.[0]?.downloadUrl,
      "https://example.com/receipt.pdf",
    );
  });

  test("createPaymentWithQuotaForUser persists attachments", async () => {
    await db.collection("memberships").doc(`${workspaceId}_user_1`).set({
      workspaceId,
      userId: "user_1",
      role: "owner",
    });
    await db
      .collection("projects")
      .doc("project_1")
      .set({
        ...baseProject,
      });

    const result = await createPaymentWithQuotaForUser("user_1", {
      workspaceId,
      projectId: "project_1",
      amount: 75,
      date: admin.firestore.Timestamp.fromDate(currentMonthDate),
      paymentMethod: "credit_card",
      notes: "Payment attachment test",
      attachments: [
        {
          id: "attach_2",
          fileName: "receipt.png",
          downloadUrl: "https://example.com/receipt.png",
          storagePath: "attachments/receipt.png",
          uploadedAt: admin.firestore.Timestamp.fromDate(currentMonthDate),
          contentType: "image/png",
          size: 54321,
        },
      ],
      clientMutationId: "mutation_2",
    });

    const saved = (
      await db.collection("payments").doc(result.id).get()
    ).data() as TriggerData & { attachments?: Array<Record<string, unknown>> };
    assert.equal(Array.isArray(saved.attachments), true);
    assert.equal(saved.attachments?.length, 1);
    assert.equal(saved.attachments?.[0]?.id, "attach_2");
    assert.equal(
      saved.attachments?.[0]?.downloadUrl,
      "https://example.com/receipt.png",
    );
  });

  test("project write does not loop on derived-only project field changes", async () => {
    await seedRecomputeInputs();

    const projectRef = db.collection("projects").doc("project_1");
    const beforeSnap = await projectRef.get();
    const beforeData = beforeSnap.data() as TriggerData;
    const afterData = { ...beforeData, totalExpenses: 999 };

    await handleProjectWriteRecompute(projectWriteEvent(beforeData, afterData));

    const afterSnap = await projectRef.get();
    const metricsSnap = await db
      .collection("project_metrics")
      .doc("project_1")
      .get();

    assert.equal(
      afterSnap.updateTime?.toMillis(),
      beforeSnap.updateTime?.toMillis(),
      "project doc must not be rewritten for derived-only changes",
    );
    assert.equal(metricsSnap.exists, false);
  });

  test("project write updates derived docs when relevant project fields change without rewriting source project doc", async () => {
    await seedRecomputeInputs();

    const projectRef = db.collection("projects").doc("project_1");
    const before = (await projectRef.get()).data() as TriggerData;
    const after = { ...before, completionPercentage: 25 };
    await projectRef.set(after, { merge: true });
    const projectBeforeHandler = await projectRef.get();

    await handleProjectWriteRecompute(projectWriteEvent(before, after));

    const projectAfterHandler = await projectRef.get();
    const projectMetricsSnap = await db
      .collection("project_metrics")
      .doc("project_1")
      .get();
    const workspaceMetricsSnap = await db
      .collection("workspace_metrics")
      .doc(workspaceId)
      .get();
    const metricsData = projectMetricsSnap.data() ?? {};

    assert.equal(
      projectAfterHandler.updateTime?.toMillis(),
      projectBeforeHandler.updateTime?.toMillis(),
      "onProjectWriteRecompute must not rewrite projects/{projectId}",
    );
    assert.equal(projectMetricsSnap.exists, true);
    assert.equal(workspaceMetricsSnap.exists, true);
    assert.equal(Number(metricsData.expectedFinalCost ?? 0), 1200);
  });

  test("project trigger is idempotent for repeated identical events", async () => {
    await seedRecomputeInputs();

    const projectRef = db.collection("projects").doc("project_1");
    const afterData = (await projectRef.get()).data() as TriggerData;
    const projectBeforeFirst = await projectRef.get();
    const projectMetricsRef = db.collection("project_metrics").doc("project_1");
    const workspaceMetricsRef = db
      .collection("workspace_metrics")
      .doc(workspaceId);

    await handleProjectWriteRecompute(projectWriteEvent(undefined, afterData));

    const projectAfterFirst = await projectRef.get();
    const projectMetricsAfterFirst = await projectMetricsRef.get();
    const workspaceMetricsAfterFirst = await workspaceMetricsRef.get();
    assert.equal(projectMetricsAfterFirst.exists, true);
    assert.equal(workspaceMetricsAfterFirst.exists, true);
    assert.equal(
      projectAfterFirst.updateTime?.toMillis(),
      projectBeforeFirst.updateTime?.toMillis(),
      "project doc must remain unchanged after first recompute pass",
    );

    await handleProjectWriteRecompute(projectWriteEvent(undefined, afterData));

    const projectAfterSecond = await projectRef.get();
    const projectMetricsAfter = await projectMetricsRef.get();
    const workspaceMetricsAfter = await workspaceMetricsRef.get();

    assert.equal(
      projectAfterSecond.updateTime?.toMillis(),
      projectAfterFirst.updateTime?.toMillis(),
      "project doc must remain input-only across repeated identical events",
    );
    assert.equal(
      projectMetricsAfter.updateTime?.toMillis(),
      projectMetricsAfterFirst.updateTime?.toMillis(),
      "project metrics must not be rewritten when unchanged",
    );
    assert.equal(
      workspaceMetricsAfter.updateTime?.toMillis(),
      workspaceMetricsAfterFirst.updateTime?.toMillis(),
      "workspace metrics must not be rewritten when unchanged",
    );
  });

  test("expense write recompute does not rewrite source project document", async () => {
    await seedRecomputeInputs();

    const projectRef = db.collection("projects").doc("project_1");
    const projectBeforeExpenseSnap = await projectRef.get();
    const expenseAfter = (
      await db.collection("expenses").doc("expense_1").get()
    ).data() as TriggerData;

    await handleExpenseWriteRecompute(
      expenseWriteEvent(undefined, expenseAfter),
    );

    const projectAfterExpenseSnap = await projectRef.get();
    const metricsSnap = await db
      .collection("project_metrics")
      .doc("project_1")
      .get();
    assert.equal(
      projectAfterExpenseSnap.updateTime?.toMillis(),
      projectBeforeExpenseSnap.updateTime?.toMillis(),
      "expense recompute must not mutate projects/{projectId}",
    );
    assert.equal(metricsSnap.exists, true);
  });

  test("worker entry write recompute does not rewrite source project document", async () => {
    await seedRecomputeInputs();

    const projectRef = db.collection("projects").doc("project_1");
    const projectBeforeWorkerSnap = await projectRef.get();
    const workerEntryAfter = (
      await db.collection("worker_entries").doc("entry_1").get()
    ).data() as TriggerData;

    await handleWorkerEntryWriteRecompute(
      workerEntryWriteEvent(undefined, workerEntryAfter),
    );

    const projectAfterWorkerSnap = await projectRef.get();
    const metricsSnap = await db
      .collection("project_metrics")
      .doc("project_1")
      .get();
    assert.equal(
      projectAfterWorkerSnap.updateTime?.toMillis(),
      projectBeforeWorkerSnap.updateTime?.toMillis(),
      "worker-entry recompute must not mutate projects/{projectId}",
    );
    assert.equal(metricsSnap.exists, true);
  });

  test("expense trigger skips writes when irrelevant fields change", async () => {
    await seedRecomputeInputs();

    const expenseRef = db.collection("expenses").doc("expense_1");
    const projectRef = db.collection("projects").doc("project_1");
    const projectMetricsRef = db.collection("project_metrics").doc("project_1");
    const workspaceMetricsRef = db
      .collection("workspace_metrics")
      .doc(workspaceId);
    const initialExpense = (await expenseRef.get()).data() as TriggerData;

    await handleExpenseWriteRecompute(
      expenseWriteEvent(undefined, initialExpense),
    );

    const projectBefore = await projectRef.get();
    const projectMetricsBefore = await projectMetricsRef.get();
    const workspaceMetricsBefore = await workspaceMetricsRef.get();

    const updatedExpense = {
      ...initialExpense,
      updatedAt: admin.firestore.Timestamp.now(),
    };
    await expenseRef.set(updatedExpense, { merge: true });

    await handleExpenseWriteRecompute(
      expenseWriteEvent(initialExpense, updatedExpense),
    );

    const projectAfter = await projectRef.get();
    const projectMetricsAfter = await projectMetricsRef.get();
    const workspaceMetricsAfter = await workspaceMetricsRef.get();

    assert.equal(
      projectAfter.updateTime?.toMillis(),
      projectBefore.updateTime?.toMillis(),
    );
    assert.equal(
      projectMetricsAfter.updateTime?.toMillis(),
      projectMetricsBefore.updateTime?.toMillis(),
    );
    assert.equal(
      workspaceMetricsAfter.updateTime?.toMillis(),
      workspaceMetricsBefore.updateTime?.toMillis(),
    );
  });

  test("expense trigger is idempotent when recompute is rerun with same input", async () => {
    await seedRecomputeInputs();

    const expenseAfter = (
      await db.collection("expenses").doc("expense_1").get()
    ).data() as TriggerData;
    const projectRef = db.collection("projects").doc("project_1");
    const projectMetricsRef = db.collection("project_metrics").doc("project_1");
    const workspaceMetricsRef = db
      .collection("workspace_metrics")
      .doc(workspaceId);

    await handleExpenseWriteRecompute(
      expenseWriteEvent(undefined, expenseAfter),
    );
    const projectBefore = await projectRef.get();
    const projectMetricsBefore = await projectMetricsRef.get();
    const workspaceMetricsBefore = await workspaceMetricsRef.get();

    await handleExpenseWriteRecompute(
      expenseWriteEvent(undefined, expenseAfter),
    );

    const projectAfter = await projectRef.get();
    const projectMetricsAfter = await projectMetricsRef.get();
    const workspaceMetricsAfter = await workspaceMetricsRef.get();

    assert.equal(
      projectAfter.updateTime?.toMillis(),
      projectBefore.updateTime?.toMillis(),
    );
    assert.equal(
      projectMetricsAfter.updateTime?.toMillis(),
      projectMetricsBefore.updateTime?.toMillis(),
    );
    assert.equal(
      workspaceMetricsAfter.updateTime?.toMillis(),
      workspaceMetricsBefore.updateTime?.toMillis(),
    );
  });

  test("derived docs update correctly when relevant expense fields change", async () => {
    await seedRecomputeInputs();

    const expenseRef = db.collection("expenses").doc("expense_1");
    const projectRef = db.collection("projects").doc("project_1");
    const projectMetricsRef = db.collection("project_metrics").doc("project_1");

    const beforeExpense = (await expenseRef.get()).data() as TriggerData;
    await handleExpenseWriteRecompute(
      expenseWriteEvent(undefined, beforeExpense),
    );
    const projectBefore = await projectRef.get();

    const afterExpense = { ...beforeExpense, amount: 250 };
    await expenseRef.set(afterExpense, { merge: true });
    await handleExpenseWriteRecompute(
      expenseWriteEvent(beforeExpense, afterExpense),
    );

    const projectAfter = await projectRef.get();
    const projectMetricsSnap = await projectMetricsRef.get();
    const metricsData = projectMetricsSnap.data() ?? {};

    assert.equal(
      projectAfter.updateTime?.toMillis(),
      projectBefore.updateTime?.toMillis(),
      "expense recompute must not write back to projects/{projectId}",
    );
    assert.equal(Number(metricsData.totalExpenses ?? 0), 350);
    assert.equal(Number(metricsData.totalIncome ?? 0), 300);
    assert.equal(Number(metricsData.netProfit ?? 0), -50);
    assert.equal(
      Number((metricsData.categoryTotals as TriggerData).materials ?? 0),
      250,
    );
    assert.equal(
      Number((metricsData.categoryTotals as TriggerData).labor ?? 0),
      100,
    );
  });

  test("worker entry recompute derives labor cost when legacy totalCost is missing", async () => {
    await seedRecomputeInputs();

    const workerEntryRef = db.collection("worker_entries").doc("entry_1");
    const beforeEntry = (await workerEntryRef.get()).data() as TriggerData;
    const afterEntry = {
      ...beforeEntry,
      daysWorked: 2,
      dailyWage: 125,
      totalCost: admin.firestore.FieldValue.delete(),
    };
    await workerEntryRef.update(afterEntry);

    const currentEntry = (await workerEntryRef.get()).data() as TriggerData;
    await handleWorkerEntryWriteRecompute(
      workerEntryWriteEvent(beforeEntry, currentEntry),
    );

    const metricsSnap = await db
      .collection("project_metrics")
      .doc("project_1")
      .get();
    const metricsData = metricsSnap.data() ?? {};
    const categoryTotals = metricsData.categoryTotals as TriggerData;
    const topWorkers = metricsData.topWorkers as TriggerData[];

    assert.equal(Number(metricsData.totalExpenses ?? 0), 450);
    assert.equal(Number(categoryTotals.labor ?? 0), 250);
    assert.equal(Number(topWorkers[0].totalCost ?? 0), 250);
  });

  test("recompute monthly flow preserves timestamp-dated expenses payments and worker entries", async () => {
    await seedRecomputeInputs();

    const projectData = (
      await db.collection("projects").doc("project_1").get()
    ).data() as TriggerData;
    await handleProjectWriteRecompute(
      projectWriteEvent(undefined, projectData),
    );

    const metricsSnap = await db
      .collection("project_metrics")
      .doc("project_1")
      .get();
    const monthlyFlow = (metricsSnap.data()?.monthlyFlow ?? []) as Array<
      Record<string, unknown>
    >;

    const previousKey = `${previousMonthDate.getUTCFullYear()}-${`${previousMonthDate.getUTCMonth() + 1}`.padStart(2, "0")}`;
    const currentKey = `${currentMonthDate.getUTCFullYear()}-${`${currentMonthDate.getUTCMonth() + 1}`.padStart(2, "0")}`;
    const twoMonthsAgoKey = `${twoMonthsAgoDate.getUTCFullYear()}-${`${twoMonthsAgoDate.getUTCMonth() + 1}`.padStart(2, "0")}`;

    const flowPointFor = (monthKey: string) =>
      monthlyFlow.find((item) => item["month"] === monthKey) ?? {};

    const previousMonthPoint = flowPointFor(previousKey);
    const currentMonthPoint = flowPointFor(currentKey);
    const twoMonthsAgoPoint = flowPointFor(twoMonthsAgoKey);

    assert.equal(Number(previousMonthPoint["expenses"] ?? 0), 200);
    assert.equal(Number(currentMonthPoint["income"] ?? 0), 300);
    assert.equal(Number(twoMonthsAgoPoint["expenses"] ?? 0), 100);
  });

  test("recompute monthly flow includes active finance records outside the latest six months", async () => {
    await seedRecomputeInputs();
    await db
      .collection("expenses")
      .doc("old_expense")
      .set({
        id: "old_expense",
        workspaceId,
        projectId: "project_1",
        category: "equipment",
        amount: 75,
        date: admin.firestore.Timestamp.fromDate(oldHistoryDate),
        isArchived: false,
      });
    await db
      .collection("payments")
      .doc("old_payment")
      .set({
        id: "old_payment",
        workspaceId,
        projectId: "project_1",
        amount: 125,
        date: admin.firestore.Timestamp.fromDate(oldHistoryDate),
        isArchived: false,
      });

    const projectData = (
      await db.collection("projects").doc("project_1").get()
    ).data() as TriggerData;
    await handleProjectWriteRecompute(
      projectWriteEvent(undefined, projectData),
    );

    const metricsSnap = await db
      .collection("project_metrics")
      .doc("project_1")
      .get();
    const monthlyFlow = (metricsSnap.data()?.monthlyFlow ?? []) as Array<
      Record<string, unknown>
    >;
    const oldMonthKey = `${oldHistoryDate.getUTCFullYear()}-${`${oldHistoryDate.getUTCMonth() + 1}`.padStart(2, "0")}`;
    const oldPoint =
      monthlyFlow.find((item) => item["month"] === oldMonthKey) ?? {};

    assert.equal(Number(oldPoint["expenses"] ?? 0), 75);
    assert.equal(Number(oldPoint["income"] ?? 0), 125);
    assert.deepEqual(
      monthlyFlow.map((item) => item["month"]),
      [...monthlyFlow].map((item) => item["month"]).sort(),
      "monthly flow should remain chronological",
    );
  });

  test("payment trigger recomputes when only the date changes", async () => {
    await seedRecomputeInputs();

    const paymentRef = db.collection("payments").doc("payment_1");
    const beforePayment = (await paymentRef.get()).data() as TriggerData;
    await handlePaymentWriteRecompute(
      paymentWriteEvent(undefined, beforePayment),
    );

    const targetDate = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 2, 20),
    );
    const afterPayment = {
      ...beforePayment,
      date: admin.firestore.Timestamp.fromDate(targetDate),
    };
    await paymentRef.set(afterPayment, { merge: true });

    const metricsBefore = await db
      .collection("project_metrics")
      .doc("project_1")
      .get();
    await handlePaymentWriteRecompute(
      paymentWriteEvent(beforePayment, afterPayment),
    );
    const metricsAfter = await db
      .collection("project_metrics")
      .doc("project_1")
      .get();

    const monthlyFlow = (metricsAfter.data()?.monthlyFlow ?? []) as Array<
      Record<string, unknown>
    >;
    const movedMonthKey = `${targetDate.getUTCFullYear()}-${`${targetDate.getUTCMonth() + 1}`.padStart(2, "0")}`;
    const originalMonthKey = `${currentMonthDate.getUTCFullYear()}-${`${currentMonthDate.getUTCMonth() + 1}`.padStart(2, "0")}`;
    const movedPoint =
      monthlyFlow.find((item) => item["month"] === movedMonthKey) ?? {};
    const originalPoint =
      monthlyFlow.find((item) => item["month"] === originalMonthKey) ?? {};

    assert.notEqual(
      metricsAfter.updateTime?.toMillis(),
      metricsBefore.updateTime?.toMillis(),
      "payment date-only changes must trigger a recompute",
    );
    assert.equal(Number(movedPoint["income"] ?? 0), 300);
    assert.equal(Number(originalPoint["income"] ?? 0), 0);
  });

  test("payment creation rejects archived projects", async () => {
    await seedRecomputeInputs();
    await db
      .collection("projects")
      .doc("project_1")
      .update({ isArchived: true });

    await assert.rejects(
      () =>
        createPaymentWithQuotaForUser("user_1", {
          workspaceId,
          projectId: "project_1",
          amount: 300,
          date: admin.firestore.Timestamp.fromDate(currentMonthDate),
          paymentMethod: "cash",
        }),
      (error: unknown) => {
        const handled = error as HttpsError;
        return (
          handled instanceof HttpsError &&
          handled.code === "permission-denied" &&
          handled.message.includes("Project is archived")
        );
      },
    );
  });

  test("payment creation increments project payment and net metrics", async () => {
    await seedRecomputeInputs();
    await db.collection("project_metrics").doc("project_1").set({
      workspaceId,
      projectId: "project_1",
      totalExpenses: 300,
      totalPayments: 300,
      netProfit: 0,
    });

    await createPaymentWithQuotaForUser("user_1", {
      workspaceId,
      projectId: "project_1",
      amount: 125,
      date: admin.firestore.Timestamp.fromDate(currentMonthDate),
      paymentMethod: "cash",
      clientMutationId: "client_payment_1",
    });

    const metricsSnap = await db
      .collection("project_metrics")
      .doc("project_1")
      .get();
    const metricsData = metricsSnap.data() ?? {};
    assert.equal(Number(metricsData.totalPayments ?? 0), 425);
    assert.equal(Number(metricsData.netProfit ?? 0), 125);
  });

  test("worker entry creation rejects archived projects", async () => {
    await seedRecomputeInputs();
    await db
      .collection("projects")
      .doc("project_1")
      .update({ isArchived: true });

    await assert.rejects(
      () =>
        createWorkerEntryWithQuotaForUser("user_1", {
          workspaceId,
          workerId: "worker_1",
          projectId: "project_1",
          daysWorked: 2,
          dailyWage: 125,
          date: admin.firestore.Timestamp.fromDate(currentMonthDate),
        }),
      (error: unknown) => {
        const handled = error as HttpsError;
        return (
          handled instanceof HttpsError &&
          handled.code === "permission-denied" &&
          handled.message.includes("Project is archived")
        );
      },
    );
  });

  test("worker entry creation rejects archived workers", async () => {
    await seedRecomputeInputs();
    await db.collection("workers").doc("worker_1").update({ isArchived: true });

    await assert.rejects(
      () =>
        createWorkerEntryWithQuotaForUser("user_1", {
          workspaceId,
          workerId: "worker_1",
          projectId: "project_1",
          daysWorked: 2,
          dailyWage: 125,
          date: admin.firestore.Timestamp.fromDate(currentMonthDate),
        }),
      (error: unknown) => {
        const handled = error as HttpsError;
        return (
          handled instanceof HttpsError &&
          handled.code === "permission-denied" &&
          handled.message.includes("Worker is archived")
        );
      },
    );
  });
}
