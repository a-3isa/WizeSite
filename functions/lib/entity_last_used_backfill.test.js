"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const entity_last_used_backfill_1 = require("./entity_last_used_backfill");
(0, node_test_1.default)("entity lastUsedAt backfill prefers createdAt then updatedAt then epoch", () => {
    const created = (0, entity_last_used_backfill_1.buildEntityLastUsedAtBackfillPatch)("entity_created", {
        name: "Steel Supplier",
        createdAt: new Date(Date.UTC(2026, 5, 1)),
    });
    strict_1.default.equal(created?.id, "entity_created");
    strict_1.default.equal(created?.normalizedName, "steel supplier");
    strict_1.default.deepEqual(created?.lastUsedAt, new Date(Date.UTC(2026, 5, 1)));
    const updated = (0, entity_last_used_backfill_1.buildEntityLastUsedAtBackfillPatch)("entity_updated", {
        name: "Updated Supplier",
        updatedAt: new Date(Date.UTC(2026, 5, 2)),
    });
    strict_1.default.deepEqual(updated?.lastUsedAt, new Date(Date.UTC(2026, 5, 2)));
    const epoch = (0, entity_last_used_backfill_1.buildEntityLastUsedAtBackfillPatch)("entity_epoch", {
        name: "No Dates",
    });
    strict_1.default.deepEqual(epoch?.lastUsedAt, new Date(0));
});
(0, node_test_1.default)("entity lastUsedAt backfill is idempotent for already-normalized records", () => {
    const patch = (0, entity_last_used_backfill_1.buildEntityLastUsedAtBackfillPatch)("entity_ready", {
        id: "entity_ready",
        name: "Ready Supplier",
        normalizedName: "ready supplier",
        createdAt: new Date(Date.UTC(2026, 5, 1)),
        lastUsedAt: new Date(Date.UTC(2026, 5, 3)),
    });
    strict_1.default.equal(patch, null);
});
//# sourceMappingURL=entity_last_used_backfill.test.js.map