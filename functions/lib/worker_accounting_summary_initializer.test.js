"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const worker_accounting_summary_initializer_1 = require("./worker_accounting_summary_initializer");
(0, node_test_1.default)("worker summary initialization targets unique valid worker ledgers", () => {
    const result = (0, worker_accounting_summary_initializer_1.collectWorkerSummaryInitializationTargets)([
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
    strict_1.default.deepEqual(result.targets, [
        { key: "workspace_1_worker_1", workspaceId: "workspace_1", workerId: "worker_1" },
        { key: "workspace_1_worker_2", workspaceId: "workspace_1", workerId: "worker_2" },
    ]);
    strict_1.default.equal(result.skippedInvalidTarget, 1);
});
(0, node_test_1.default)("worker summary initialization uses canonical partial-payment totals", () => {
    const payload = (0, worker_accounting_summary_initializer_1.buildWorkerSummaryInitializationPayload)({
        workspaceId: "workspace_1",
        workerId: "worker_1",
        records: [
            { amount: 100, paymentStatus: "paid" },
            { amount: 80, paymentStatus: "unpaid" },
            { amount: 60, paymentStatus: "partial", paidAmount: 25 },
            { amount: 40, paymentStatus: "partial" },
        ],
    });
    strict_1.default.equal(payload.workspaceId, "workspace_1");
    strict_1.default.equal(payload.workerId, "worker_1");
    strict_1.default.equal(payload.totalAmount, 280);
    strict_1.default.equal(payload.confirmedPaid, 125);
    strict_1.default.equal(payload.confirmedOutstanding, 115);
    strict_1.default.equal(payload.unresolvedLegacyCount, 1);
    strict_1.default.equal(payload.recordCount, 4);
});
//# sourceMappingURL=worker_accounting_summary_initializer.test.js.map