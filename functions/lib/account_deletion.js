"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.WORKSPACE_SCOPED_COLLECTIONS = exports.ACCOUNT_DELETION_REAUTH_SECONDS = void 0;
exports.isRecentLogin = isRecentLogin;
exports.ownerDeletionBlocked = ownerDeletionBlocked;
exports.userStoragePrefixes = userStoragePrefixes;
exports.ACCOUNT_DELETION_REAUTH_SECONDS = 5 * 60;
exports.WORKSPACE_SCOPED_COLLECTIONS = [
    "attachments",
    "category_summaries",
    "contractor_accounting_records",
    "drafts",
    "entities",
    "entity_summaries",
    "equipment_accounting_records",
    "expenses",
    "idempotency_keys",
    "memberships",
    "notifications",
    "payments",
    "project_metrics",
    "project_summaries",
    "projects",
    "report_exports",
    "reports",
    "transport_provider_accounting_records",
    "usage_counters",
    "weekly_summaries",
    "worker_accounting_records",
    "worker_accounting_summaries",
    "worker_entries",
    "workers",
];
function isRecentLogin(authTimeSeconds, nowSeconds = Date.now() / 1000) {
    if (typeof authTimeSeconds !== "number" || !Number.isFinite(authTimeSeconds)) {
        return false;
    }
    return nowSeconds - authTimeSeconds <= exports.ACCOUNT_DELETION_REAUTH_SECONDS;
}
function ownerDeletionBlocked(otherMemberCount) {
    return otherMemberCount > 0;
}
function userStoragePrefixes(uid) {
    const safe = uid.trim();
    if (!safe) {
        return [];
    }
    return [
        `attachments/${safe}/`,
        `receipts/${safe}/`,
        `voice-expenses/${safe}/`,
        `profile-photos/${safe}/`,
    ];
}
//# sourceMappingURL=account_deletion.js.map