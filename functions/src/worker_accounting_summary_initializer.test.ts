import assert from "node:assert/strict";
import test from "node:test";
import {
  buildWorkerSummaryInitializationPayload,
  collectWorkerSummaryInitializationTargets,
} from "./worker_accounting_summary_initializer";

test("worker summary initialization targets unique valid worker ledgers", () => {
  const result = collectWorkerSummaryInitializationTargets([
    {
      id: "record_1",
      data: { workspaceId: "workspace_1", workerId: "worker_1" },
    },
    {
      id: "record_2",
      data: { workspaceId: "workspace_1", workerId: "worker_1" },
    },
    {
      id: "record_3",
      data: { workspaceId: "workspace_1", workerId: "worker_2" },
    },
    {
      id: "record_4",
      data: { workspaceId: "", workerId: "worker_3" },
    },
  ]);

  assert.deepEqual(result.targets, [
    { key: "workspace_1_worker_1", workspaceId: "workspace_1", workerId: "worker_1" },
    { key: "workspace_1_worker_2", workspaceId: "workspace_1", workerId: "worker_2" },
  ]);
  assert.equal(result.skippedInvalidTarget, 1);
});

test("worker summary initialization uses canonical partial-payment totals", () => {
  const payload = buildWorkerSummaryInitializationPayload({
    workspaceId: "workspace_1",
    workerId: "worker_1",
    records: [
      { amount: 100, paymentStatus: "paid" },
      { amount: 80, paymentStatus: "unpaid" },
      { amount: 60, paymentStatus: "partial", paidAmount: 25 },
      { amount: 40, paymentStatus: "partial" },
    ],
  });

  assert.equal(payload.workspaceId, "workspace_1");
  assert.equal(payload.workerId, "worker_1");
  assert.equal(payload.totalAmount, 280);
  assert.equal(payload.confirmedPaid, 125);
  assert.equal(payload.confirmedOutstanding, 115);
  assert.equal(payload.unresolvedLegacyCount, 1);
  assert.equal(payload.recordCount, 4);
});
