"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const index_1 = require("./index");
/**
 * Risk classification for projects with and without a Contract Value.
 *
 * Runs without the Firestore emulator, deliberately: this rule decides whether
 * a notification is pushed to every member with risk alerts enabled, and it
 * used to fire on both of its arms for any project that had expenses and no
 * contract. Leaving it covered only by emulator-gated tests would mean it ships
 * unverified in most environments.
 */
(0, node_test_1.default)("a project with no contract value receives no verdict at all", () => {
    const verdict = (0, index_1.classifyProjectRisk)({
        contractValue: null,
        netProfit: -5000,
        expectedFinalCost: 5000,
    });
    // Null, not "low": the project is unrated, not certified healthy.
    strict_1.default.equal(verdict.riskLevel, null);
    strict_1.default.equal(verdict.healthStatus, null);
});
(0, node_test_1.default)("the negative-net rule alone cannot flag a contract-less project", () => {
    // This is the case that made the original rule misfire. An expense-only
    // project always has netProfit < 0 once it records anything, so suppressing
    // only the contract comparison would have flagged every one as "losing".
    const verdict = (0, index_1.classifyProjectRisk)({
        contractValue: null,
        netProfit: -1,
        expectedFinalCost: 1,
    });
    strict_1.default.equal(verdict.riskLevel, null);
    strict_1.default.notEqual(verdict.riskLevel, "high");
});
(0, node_test_1.default)("a contract-less project stays unrated no matter how large the spend", () => {
    const verdict = (0, index_1.classifyProjectRisk)({
        contractValue: null,
        netProfit: -10_000_000,
        expectedFinalCost: 10_000_000,
    });
    strict_1.default.equal(verdict.riskLevel, null);
    strict_1.default.equal(verdict.healthStatus, null);
});
(0, node_test_1.default)("a healthy contract-bearing project is unchanged", () => {
    const verdict = (0, index_1.classifyProjectRisk)({
        contractValue: 100_000,
        netProfit: 20_000,
        expectedFinalCost: 50_000,
    });
    strict_1.default.equal(verdict.riskLevel, "low");
    strict_1.default.equal(verdict.healthStatus, "healthy");
});
(0, node_test_1.default)("a contract-bearing project nearing its contract warns", () => {
    const verdict = (0, index_1.classifyProjectRisk)({
        contractValue: 100_000,
        netProfit: 5_000,
        expectedFinalCost: 95_000,
    });
    strict_1.default.equal(verdict.riskLevel, "medium");
    strict_1.default.equal(verdict.healthStatus, "warning");
});
(0, node_test_1.default)("a contract-bearing project running at a loss is still high risk", () => {
    const verdict = (0, index_1.classifyProjectRisk)({
        contractValue: 100_000,
        netProfit: -1,
        expectedFinalCost: 10_000,
    });
    strict_1.default.equal(verdict.riskLevel, "high");
    strict_1.default.equal(verdict.healthStatus, "losing");
});
(0, node_test_1.default)("a contract-bearing project overrunning its contract is high risk", () => {
    const verdict = (0, index_1.classifyProjectRisk)({
        contractValue: 100_000,
        netProfit: 1_000,
        expectedFinalCost: 120_000,
    });
    strict_1.default.equal(verdict.riskLevel, "high");
    strict_1.default.equal(verdict.healthStatus, "losing");
});
//# sourceMappingURL=project_risk_classification.test.js.map