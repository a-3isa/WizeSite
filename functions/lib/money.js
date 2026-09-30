"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.EXPENSE_CATEGORIES = exports.PAYMENT_STATUSES = void 0;
exports.parsePaymentStatus = parsePaymentStatus;
exports.normalizeExpenseCategory = normalizeExpenseCategory;
exports.isAllowedExpenseCategory = isAllowedExpenseCategory;
exports.roundMoney = roundMoney;
exports.archivePaymentCashDelta = archivePaymentCashDelta;
exports.cashCollectedAmount = cashCollectedAmount;
exports.canCreateProject = canCreateProject;
exports.canUpdateProject = canUpdateProject;
exports.canDeleteProjectCascade = canDeleteProjectCascade;
exports.canMutateMoneyViaCallable = canMutateMoneyViaCallable;
exports.PAYMENT_STATUSES = [
    "unpaid",
    "partial",
    "paid",
    "refunded",
    "cancelled",
];
exports.EXPENSE_CATEGORIES = [
    "labor",
    "worker",
    "materials",
    "equipment",
    "transport",
    "contractor",
    "storage",
    "rentals",
    "payments",
    "other",
];
function parsePaymentStatus(input, fallback) {
    const raw = `${input ?? fallback}`.trim().toLowerCase();
    if (exports.PAYMENT_STATUSES.includes(raw)) {
        return raw;
    }
    return fallback;
}
function normalizeExpenseCategory(category) {
    const raw = category.trim().toLowerCase();
    if (raw === "labor") {
        return "worker";
    }
    if (exports.EXPENSE_CATEGORIES.includes(raw)) {
        return raw;
    }
    return "other";
}
function isAllowedExpenseCategory(category) {
    return exports.EXPENSE_CATEGORIES.includes(category.trim().toLowerCase());
}
/**
 * Cash actually received. Unpaid/refunded/cancelled contribute 0.
 * Partial uses `paidAmount` when present, otherwise the full amount
 * (legacy partial docs without a paid split). Missing status is paid.
 */
function roundMoney(value) {
    if (!Number.isFinite(value)) {
        return 0;
    }
    return Math.round(value * 100) / 100;
}
/**
 * Metrics delta when a payment is archived. Unpaid/refunded/cancelled
 * contribute 0, matching create-path cash collected.
 */
function archivePaymentCashDelta(payment) {
    const delta = roundMoney(-cashCollectedAmount(payment));
    return delta === 0 ? 0 : delta;
}
function cashCollectedAmount(data) {
    const amount = Number(data.amount ?? 0);
    if (!Number.isFinite(amount) || amount <= 0) {
        return 0;
    }
    const status = parsePaymentStatus(data.paymentStatus, "paid");
    if (status === "unpaid" ||
        status === "refunded" ||
        status === "cancelled") {
        return 0;
    }
    if (status === "partial") {
        const paid = Number(data.paidAmount);
        if (Number.isFinite(paid) && paid > 0) {
            return roundMoney(Math.min(paid, amount));
        }
        return roundMoney(amount);
    }
    return roundMoney(amount);
}
function canCreateProject(role) {
    return (role === "owner" ||
        role === "admin" ||
        role === "accountingApproved" ||
        role === "member");
}
function canUpdateProject(role) {
    return canCreateProject(role);
}
function canDeleteProjectCascade(role) {
    return role === "owner" || role === "admin";
}
function canMutateMoneyViaCallable(role) {
    return role !== "entryOnly";
}
//# sourceMappingURL=money.js.map