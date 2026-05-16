"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const rules_unit_testing_1 = require("@firebase/rules-unit-testing");
const admin = __importStar(require("firebase-admin"));
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
function snapshotOf(data) {
    if (!data) {
        return undefined;
    }
    return { data: () => data };
}
function projectWriteEvent(before, after, projectId = "project_1") {
    return {
        data: {
            before: snapshotOf(before),
            after: snapshotOf(after),
        },
        params: { projectId },
    };
}
function expenseWriteEvent(before, after, expenseId = "expense_1") {
    return {
        data: {
            before: snapshotOf(before),
            after: snapshotOf(after),
        },
        params: { expenseId },
    };
}
function workerEntryWriteEvent(before, after, entryId = "entry_1") {
    return {
        data: {
            before: snapshotOf(before),
            after: snapshotOf(after),
        },
        params: { entryId },
    };
}
if (!emulatorHost) {
    (0, node_test_1.default)("Project trigger emulator tests require FIRESTORE_EMULATOR_HOST (skipped)", { skip: true }, () => { });
}
else {
    const [host, portText] = emulatorHost.split(":");
    const projectId = "buildtrack-trigger-test";
    process.env.GCLOUD_PROJECT = projectId;
    process.env.FIREBASE_CONFIG = JSON.stringify({ projectId });
    let env;
    let db;
    let handleProjectWriteRecompute;
    let handleExpenseWriteRecompute;
    let handleWorkerEntryWriteRecompute;
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
    node_test_1.default.before(async () => {
        env = await (0, rules_unit_testing_1.initializeTestEnvironment)({
            projectId,
            firestore: {
                host,
                port: Number(portText),
            },
        });
        const indexModule = await Promise.resolve().then(() => __importStar(require("./index")));
        handleProjectWriteRecompute = indexModule.handleProjectWriteRecompute;
        handleExpenseWriteRecompute = indexModule.handleExpenseWriteRecompute;
        handleWorkerEntryWriteRecompute = indexModule.handleWorkerEntryWriteRecompute;
        db = admin.firestore();
    });
    node_test_1.default.after(async () => {
        await env.cleanup();
        await Promise.all(admin.apps
            .filter((app) => app !== null)
            .map((app) => app.delete().catch(() => undefined)));
    });
    node_test_1.default.beforeEach(async () => {
        await env.clearFirestore();
    });
    (0, node_test_1.default)("project write does not loop on derived-only project field changes", async () => {
        await seedRecomputeInputs();
        const projectRef = db.collection("projects").doc("project_1");
        const beforeSnap = await projectRef.get();
        const beforeData = beforeSnap.data();
        const afterData = { ...beforeData, totalExpenses: 999 };
        await handleProjectWriteRecompute(projectWriteEvent(beforeData, afterData));
        const afterSnap = await projectRef.get();
        const metricsSnap = await db.collection("project_metrics").doc("project_1").get();
        strict_1.default.equal(afterSnap.updateTime?.toMillis(), beforeSnap.updateTime?.toMillis(), "project doc must not be rewritten for derived-only changes");
        strict_1.default.equal(metricsSnap.exists, false);
    });
    (0, node_test_1.default)("project write updates derived docs when relevant project fields change without rewriting source project doc", async () => {
        await seedRecomputeInputs();
        const projectRef = db.collection("projects").doc("project_1");
        const before = (await projectRef.get()).data();
        const after = { ...before, completionPercentage: 25 };
        await projectRef.set(after, { merge: true });
        const projectBeforeHandler = await projectRef.get();
        await handleProjectWriteRecompute(projectWriteEvent(before, after));
        const projectAfterHandler = await projectRef.get();
        const projectMetricsSnap = await db.collection("project_metrics").doc("project_1").get();
        const workspaceMetricsSnap = await db.collection("workspace_metrics").doc(workspaceId).get();
        const metricsData = projectMetricsSnap.data() ?? {};
        strict_1.default.equal(projectAfterHandler.updateTime?.toMillis(), projectBeforeHandler.updateTime?.toMillis(), "onProjectWriteRecompute must not rewrite projects/{projectId}");
        strict_1.default.equal(projectMetricsSnap.exists, true);
        strict_1.default.equal(workspaceMetricsSnap.exists, true);
        strict_1.default.equal(Number(metricsData.expectedFinalCost ?? 0), 1200);
    });
    (0, node_test_1.default)("project trigger is idempotent for repeated identical events", async () => {
        await seedRecomputeInputs();
        const projectRef = db.collection("projects").doc("project_1");
        const afterData = (await projectRef.get()).data();
        const projectBeforeFirst = await projectRef.get();
        const projectMetricsRef = db.collection("project_metrics").doc("project_1");
        const workspaceMetricsRef = db.collection("workspace_metrics").doc(workspaceId);
        await handleProjectWriteRecompute(projectWriteEvent(undefined, afterData));
        const projectAfterFirst = await projectRef.get();
        const projectMetricsAfterFirst = await projectMetricsRef.get();
        const workspaceMetricsAfterFirst = await workspaceMetricsRef.get();
        strict_1.default.equal(projectMetricsAfterFirst.exists, true);
        strict_1.default.equal(workspaceMetricsAfterFirst.exists, true);
        strict_1.default.equal(projectAfterFirst.updateTime?.toMillis(), projectBeforeFirst.updateTime?.toMillis(), "project doc must remain unchanged after first recompute pass");
        await handleProjectWriteRecompute(projectWriteEvent(undefined, afterData));
        const projectAfterSecond = await projectRef.get();
        const projectMetricsAfter = await projectMetricsRef.get();
        const workspaceMetricsAfter = await workspaceMetricsRef.get();
        strict_1.default.equal(projectAfterSecond.updateTime?.toMillis(), projectAfterFirst.updateTime?.toMillis(), "project doc must remain input-only across repeated identical events");
        strict_1.default.equal(projectMetricsAfter.updateTime?.toMillis(), projectMetricsAfterFirst.updateTime?.toMillis(), "project metrics must not be rewritten when unchanged");
        strict_1.default.equal(workspaceMetricsAfter.updateTime?.toMillis(), workspaceMetricsAfterFirst.updateTime?.toMillis(), "workspace metrics must not be rewritten when unchanged");
    });
    (0, node_test_1.default)("expense write recompute does not rewrite source project document", async () => {
        await seedRecomputeInputs();
        const projectRef = db.collection("projects").doc("project_1");
        const projectBeforeExpenseSnap = await projectRef.get();
        const expenseAfter = (await db.collection("expenses").doc("expense_1").get()).data();
        await handleExpenseWriteRecompute(expenseWriteEvent(undefined, expenseAfter));
        const projectAfterExpenseSnap = await projectRef.get();
        const metricsSnap = await db.collection("project_metrics").doc("project_1").get();
        strict_1.default.equal(projectAfterExpenseSnap.updateTime?.toMillis(), projectBeforeExpenseSnap.updateTime?.toMillis(), "expense recompute must not mutate projects/{projectId}");
        strict_1.default.equal(metricsSnap.exists, true);
    });
    (0, node_test_1.default)("worker entry write recompute does not rewrite source project document", async () => {
        await seedRecomputeInputs();
        const projectRef = db.collection("projects").doc("project_1");
        const projectBeforeWorkerSnap = await projectRef.get();
        const workerEntryAfter = (await db.collection("worker_entries").doc("entry_1").get()).data();
        await handleWorkerEntryWriteRecompute(workerEntryWriteEvent(undefined, workerEntryAfter));
        const projectAfterWorkerSnap = await projectRef.get();
        const metricsSnap = await db.collection("project_metrics").doc("project_1").get();
        strict_1.default.equal(projectAfterWorkerSnap.updateTime?.toMillis(), projectBeforeWorkerSnap.updateTime?.toMillis(), "worker-entry recompute must not mutate projects/{projectId}");
        strict_1.default.equal(metricsSnap.exists, true);
    });
    (0, node_test_1.default)("expense trigger skips writes when irrelevant fields change", async () => {
        await seedRecomputeInputs();
        const expenseRef = db.collection("expenses").doc("expense_1");
        const projectRef = db.collection("projects").doc("project_1");
        const projectMetricsRef = db.collection("project_metrics").doc("project_1");
        const workspaceMetricsRef = db.collection("workspace_metrics").doc(workspaceId);
        const initialExpense = (await expenseRef.get()).data();
        await handleExpenseWriteRecompute(expenseWriteEvent(undefined, initialExpense));
        const projectBefore = await projectRef.get();
        const projectMetricsBefore = await projectMetricsRef.get();
        const workspaceMetricsBefore = await workspaceMetricsRef.get();
        const updatedExpense = {
            ...initialExpense,
            updatedAt: admin.firestore.Timestamp.now(),
        };
        await expenseRef.set(updatedExpense, { merge: true });
        await handleExpenseWriteRecompute(expenseWriteEvent(initialExpense, updatedExpense));
        const projectAfter = await projectRef.get();
        const projectMetricsAfter = await projectMetricsRef.get();
        const workspaceMetricsAfter = await workspaceMetricsRef.get();
        strict_1.default.equal(projectAfter.updateTime?.toMillis(), projectBefore.updateTime?.toMillis());
        strict_1.default.equal(projectMetricsAfter.updateTime?.toMillis(), projectMetricsBefore.updateTime?.toMillis());
        strict_1.default.equal(workspaceMetricsAfter.updateTime?.toMillis(), workspaceMetricsBefore.updateTime?.toMillis());
    });
    (0, node_test_1.default)("expense trigger is idempotent when recompute is rerun with same input", async () => {
        await seedRecomputeInputs();
        const expenseAfter = (await db.collection("expenses").doc("expense_1").get()).data();
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
        strict_1.default.equal(projectAfter.updateTime?.toMillis(), projectBefore.updateTime?.toMillis());
        strict_1.default.equal(projectMetricsAfter.updateTime?.toMillis(), projectMetricsBefore.updateTime?.toMillis());
        strict_1.default.equal(workspaceMetricsAfter.updateTime?.toMillis(), workspaceMetricsBefore.updateTime?.toMillis());
    });
    (0, node_test_1.default)("derived docs update correctly when relevant expense fields change", async () => {
        await seedRecomputeInputs();
        const expenseRef = db.collection("expenses").doc("expense_1");
        const projectRef = db.collection("projects").doc("project_1");
        const projectMetricsRef = db.collection("project_metrics").doc("project_1");
        const beforeExpense = (await expenseRef.get()).data();
        await handleExpenseWriteRecompute(expenseWriteEvent(undefined, beforeExpense));
        const projectBefore = await projectRef.get();
        const afterExpense = { ...beforeExpense, amount: 250 };
        await expenseRef.set(afterExpense, { merge: true });
        await handleExpenseWriteRecompute(expenseWriteEvent(beforeExpense, afterExpense));
        const projectAfter = await projectRef.get();
        const projectMetricsSnap = await projectMetricsRef.get();
        const metricsData = projectMetricsSnap.data() ?? {};
        strict_1.default.equal(projectAfter.updateTime?.toMillis(), projectBefore.updateTime?.toMillis(), "expense recompute must not write back to projects/{projectId}");
        strict_1.default.equal(Number(metricsData.totalExpenses ?? 0), 350);
        strict_1.default.equal(Number(metricsData.totalIncome ?? 0), 300);
        strict_1.default.equal(Number(metricsData.netProfit ?? 0), -50);
        strict_1.default.equal(Number(metricsData.categoryTotals.materials ?? 0), 250);
        strict_1.default.equal(Number(metricsData.categoryTotals.labor ?? 0), 100);
    });
    (0, node_test_1.default)("worker entry recompute derives labor cost when legacy totalCost is missing", async () => {
        await seedRecomputeInputs();
        const workerEntryRef = db.collection("worker_entries").doc("entry_1");
        const beforeEntry = (await workerEntryRef.get()).data();
        const afterEntry = {
            ...beforeEntry,
            daysWorked: 2,
            dailyWage: 125,
            totalCost: admin.firestore.FieldValue.delete(),
        };
        await workerEntryRef.update(afterEntry);
        const currentEntry = (await workerEntryRef.get()).data();
        await handleWorkerEntryWriteRecompute(workerEntryWriteEvent(beforeEntry, currentEntry));
        const metricsSnap = await db.collection("project_metrics").doc("project_1").get();
        const metricsData = metricsSnap.data() ?? {};
        const categoryTotals = metricsData.categoryTotals;
        const topWorkers = metricsData.topWorkers;
        strict_1.default.equal(Number(metricsData.totalExpenses ?? 0), 450);
        strict_1.default.equal(Number(categoryTotals.labor ?? 0), 250);
        strict_1.default.equal(Number(topWorkers[0].totalCost ?? 0), 250);
    });
}
//# sourceMappingURL=project_recompute_trigger.test.js.map