import assert from "node:assert/strict";
import test from "node:test";
import {
  RulesTestEnvironment,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as admin from "firebase-admin";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;

type TriggerData = Record<string, unknown>;

type RecomputeHandler<TParams extends Record<string, string | undefined>> = (event: {
  data?: {
    before?: {data: () => TriggerData | undefined};
    after?: {data: () => TriggerData | undefined};
  };
  params: TParams;
}) => Promise<void>;

function snapshotOf(data: TriggerData | undefined) {
  if (!data) {
    return undefined;
  }
  return {data: () => data};
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
    params: {projectId},
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
    params: {expenseId},
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
    params: {entryId},
  };
}

if (!emulatorHost) {
  test(
    "Project trigger emulator tests require FIRESTORE_EMULATOR_HOST (skipped)",
    {skip: true},
    () => {},
  );
} else {
  const [host, portText] = emulatorHost.split(":");
  const projectId = "buildtrack-trigger-test";
  process.env.GCLOUD_PROJECT = projectId;
  process.env.FIREBASE_CONFIG = JSON.stringify({projectId});

  let env: RulesTestEnvironment;
  let db: admin.firestore.Firestore;
  let handleProjectWriteRecompute: RecomputeHandler<{projectId?: string}>;
  let handleExpenseWriteRecompute: RecomputeHandler<{expenseId?: string}>;
  let handleWorkerEntryWriteRecompute: RecomputeHandler<{entryId?: string}>;

  const workspaceId = "workspace_1";
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
    await db.collection("projects").doc("project_1").set({
      ...baseProject,
    });
    await db.collection("expenses").doc("expense_1").set({
      id: "expense_1",
      workspaceId,
      projectId: "project_1",
      category: "materials",
      amount: 200,
      date: admin.firestore.Timestamp.now(),
      isArchived: false,
    });
    await db.collection("payments").doc("payment_1").set({
      id: "payment_1",
      workspaceId,
      projectId: "project_1",
      amount: 300,
      date: admin.firestore.Timestamp.now(),
      isArchived: false,
    });
    await db.collection("workers").doc("worker_1").set({
      id: "worker_1",
      workspaceId,
      name: "Worker One",
      isArchived: false,
    });
    await db.collection("worker_entries").doc("entry_1").set({
      id: "entry_1",
      workspaceId,
      workerId: "worker_1",
      projectId: "project_1",
      daysWorked: 1,
      dailyWage: 100,
      totalCost: 100,
      date: admin.firestore.Timestamp.now(),
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
    handleWorkerEntryWriteRecompute = indexModule.handleWorkerEntryWriteRecompute;
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

  test("project write does not loop on derived-only project field changes", async () => {
    await seedRecomputeInputs();

    const projectRef = db.collection("projects").doc("project_1");
    const beforeSnap = await projectRef.get();
    const beforeData = beforeSnap.data() as TriggerData;
    const afterData = {...beforeData, totalExpenses: 999};

    await handleProjectWriteRecompute(projectWriteEvent(beforeData, afterData));

    const afterSnap = await projectRef.get();
    const metricsSnap = await db.collection("project_metrics").doc("project_1").get();

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
    const after = {...before, completionPercentage: 25};
    await projectRef.set(after, {merge: true});
    const projectBeforeHandler = await projectRef.get();

    await handleProjectWriteRecompute(projectWriteEvent(before, after));

    const projectAfterHandler = await projectRef.get();
    const projectMetricsSnap = await db.collection("project_metrics").doc("project_1").get();
    const workspaceMetricsSnap = await db.collection("workspace_metrics").doc(workspaceId).get();
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
    const workspaceMetricsRef = db.collection("workspace_metrics").doc(workspaceId);

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

    await handleExpenseWriteRecompute(expenseWriteEvent(undefined, expenseAfter));

    const projectAfterExpenseSnap = await projectRef.get();
    const metricsSnap = await db.collection("project_metrics").doc("project_1").get();
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
    const metricsSnap = await db.collection("project_metrics").doc("project_1").get();
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
    const workspaceMetricsRef = db.collection("workspace_metrics").doc(workspaceId);
    const initialExpense = (await expenseRef.get()).data() as TriggerData;

    await handleExpenseWriteRecompute(expenseWriteEvent(undefined, initialExpense));

    const projectBefore = await projectRef.get();
    const projectMetricsBefore = await projectMetricsRef.get();
    const workspaceMetricsBefore = await workspaceMetricsRef.get();

    const updatedExpense = {
      ...initialExpense,
      updatedAt: admin.firestore.Timestamp.now(),
    };
    await expenseRef.set(updatedExpense, {merge: true});

    await handleExpenseWriteRecompute(
      expenseWriteEvent(initialExpense, updatedExpense),
    );

    const projectAfter = await projectRef.get();
    const projectMetricsAfter = await projectMetricsRef.get();
    const workspaceMetricsAfter = await workspaceMetricsRef.get();

    assert.equal(projectAfter.updateTime?.toMillis(), projectBefore.updateTime?.toMillis());
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
    const workspaceMetricsRef = db.collection("workspace_metrics").doc(workspaceId);

    await handleExpenseWriteRecompute(expenseWriteEvent(undefined, expenseAfter));
    const projectBefore = await projectRef.get();
    const projectMetricsBefore = await projectMetricsRef.get();
    const workspaceMetricsBefore = await workspaceMetricsRef.get();

    await handleExpenseWriteRecompute(expenseWriteEvent(undefined, expenseAfter));

    const projectAfter = await projectRef.get();
    const projectMetricsAfter = await projectMetricsRef.get();
    const workspaceMetricsAfter = await workspaceMetricsRef.get();

    assert.equal(projectAfter.updateTime?.toMillis(), projectBefore.updateTime?.toMillis());
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
    await handleExpenseWriteRecompute(expenseWriteEvent(undefined, beforeExpense));
    const projectBefore = await projectRef.get();

    const afterExpense = {...beforeExpense, amount: 250};
    await expenseRef.set(afterExpense, {merge: true});
    await handleExpenseWriteRecompute(expenseWriteEvent(beforeExpense, afterExpense));

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
    assert.equal(Number((metricsData.categoryTotals as TriggerData).materials ?? 0), 250);
    assert.equal(Number((metricsData.categoryTotals as TriggerData).labor ?? 0), 100);
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

    const metricsSnap = await db.collection("project_metrics").doc("project_1").get();
    const metricsData = metricsSnap.data() ?? {};
    const categoryTotals = metricsData.categoryTotals as TriggerData;
    const topWorkers = metricsData.topWorkers as TriggerData[];

    assert.equal(Number(metricsData.totalExpenses ?? 0), 450);
    assert.equal(Number(categoryTotals.labor ?? 0), 250);
    assert.equal(Number(topWorkers[0].totalCost ?? 0), 250);
  });
}
