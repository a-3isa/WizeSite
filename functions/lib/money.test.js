"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const money_1 = require("./money");
(0, node_test_1.default)("missing payment status counts as paid cash", () => {
    strict_1.default.equal((0, money_1.cashCollectedAmount)({ amount: 1500 }), 1500);
});
(0, node_test_1.default)("unpaid payments do not count as cash collected", () => {
    strict_1.default.equal((0, money_1.cashCollectedAmount)({ amount: 3000, paymentStatus: "unpaid" }), 0);
});
(0, node_test_1.default)("archiving an unpaid payment does not change cash metrics", () => {
    strict_1.default.equal((0, money_1.archivePaymentCashDelta)({ amount: 3000, paymentStatus: "unpaid" }), 0);
});
(0, node_test_1.default)("archiving a paid payment subtracts cash collected", () => {
    strict_1.default.equal((0, money_1.archivePaymentCashDelta)({ amount: 1500, paymentStatus: "paid" }), -1500);
});
(0, node_test_1.default)("roundMoney uses two decimal places", () => {
    strict_1.default.equal((0, money_1.roundMoney)(10.129), 10.13);
    strict_1.default.equal((0, money_1.cashCollectedAmount)({ amount: 10.129, paymentStatus: "paid" }), 10.13);
});
(0, node_test_1.default)("partial with paidAmount counts only the paid split", () => {
    strict_1.default.equal((0, money_1.cashCollectedAmount)({
        amount: 2000,
        paymentStatus: "partial",
        paidAmount: 750,
    }), 750);
});
(0, node_test_1.default)("legacy labor category is stored as worker", () => {
    strict_1.default.equal((0, money_1.normalizeExpenseCategory)("labor"), "worker");
    strict_1.default.equal((0, money_1.isAllowedExpenseCategory)("worker"), true);
    strict_1.default.equal((0, money_1.isAllowedExpenseCategory)("labor"), true);
});
(0, node_test_1.default)("parsePaymentStatus falls back when the value is junk", () => {
    strict_1.default.equal((0, money_1.parsePaymentStatus)("nope", "unpaid"), "unpaid");
    strict_1.default.equal((0, money_1.parsePaymentStatus)("paid", "unpaid"), "paid");
});
(0, node_test_1.default)("admins and accounting can create projects; entryOnly cannot", () => {
    strict_1.default.equal((0, money_1.canCreateProject)("admin"), true);
    strict_1.default.equal((0, money_1.canCreateProject)("accountingApproved"), true);
    strict_1.default.equal((0, money_1.canCreateProject)("entryOnly"), false);
    strict_1.default.equal((0, money_1.canUpdateProject)("member"), true);
    strict_1.default.equal((0, money_1.canUpdateProject)("entryOnly"), false);
});
(0, node_test_1.default)("only owner and admin may cascade-delete a project", () => {
    strict_1.default.equal((0, money_1.canDeleteProjectCascade)("owner"), true);
    strict_1.default.equal((0, money_1.canDeleteProjectCascade)("member"), false);
    strict_1.default.equal((0, money_1.canDeleteProjectCascade)("entryOnly"), false);
});
(0, node_test_1.default)("entryOnly cannot mutate money through callables", () => {
    strict_1.default.equal((0, money_1.canMutateMoneyViaCallable)("member"), true);
    strict_1.default.equal((0, money_1.canMutateMoneyViaCallable)("entryOnly"), false);
});
//# sourceMappingURL=money.test.js.map