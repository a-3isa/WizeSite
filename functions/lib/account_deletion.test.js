"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const account_deletion_1 = require("./account_deletion");
(0, node_test_1.default)("recent login accepts auth_time inside the window", () => {
    const now = 1_800_000_000;
    strict_1.default.equal((0, account_deletion_1.isRecentLogin)(now - 60, now), true);
    strict_1.default.equal((0, account_deletion_1.isRecentLogin)(now - account_deletion_1.ACCOUNT_DELETION_REAUTH_SECONDS, now), true);
});
(0, node_test_1.default)("stale or missing auth_time requires a fresh sign-in", () => {
    const now = 1_800_000_000;
    strict_1.default.equal((0, account_deletion_1.isRecentLogin)(now - account_deletion_1.ACCOUNT_DELETION_REAUTH_SECONDS - 1, now), false);
    strict_1.default.equal((0, account_deletion_1.isRecentLogin)(undefined, now), false);
    strict_1.default.equal((0, account_deletion_1.isRecentLogin)("123", now), false);
});
(0, node_test_1.default)("solo owners can delete; shared owners cannot", () => {
    strict_1.default.equal((0, account_deletion_1.ownerDeletionBlocked)(0), false);
    strict_1.default.equal((0, account_deletion_1.ownerDeletionBlocked)(1), true);
});
(0, node_test_1.default)("workspace-scoped collections include money ledgers", () => {
    strict_1.default.ok(account_deletion_1.WORKSPACE_SCOPED_COLLECTIONS.includes("expenses"));
    strict_1.default.ok(account_deletion_1.WORKSPACE_SCOPED_COLLECTIONS.includes("payments"));
    strict_1.default.ok(account_deletion_1.WORKSPACE_SCOPED_COLLECTIONS.includes("worker_entries"));
    strict_1.default.ok(account_deletion_1.WORKSPACE_SCOPED_COLLECTIONS.includes("idempotency_keys"));
});
(0, node_test_1.default)("account deletion storage prefixes are user-scoped", () => {
    strict_1.default.deepEqual((0, account_deletion_1.userStoragePrefixes)("user_1"), [
        "attachments/user_1/",
        "receipts/user_1/",
        "voice-expenses/user_1/",
        "profile-photos/user_1/",
    ]);
    strict_1.default.deepEqual((0, account_deletion_1.userStoragePrefixes)("  "), []);
});
//# sourceMappingURL=account_deletion.test.js.map