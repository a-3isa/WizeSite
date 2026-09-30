"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const revenuecat_status_1 = require("./revenuecat_status");
(0, node_test_1.default)("CANCELLATION stays active until expiry and turns auto-renew off", () => {
    const mapped = (0, revenuecat_status_1.mapRevenueCatEvent)({
        eventType: "CANCELLATION",
        periodType: "NORMAL",
        currentStatus: "active",
        entitlements: ["pro"],
    });
    strict_1.default.equal(mapped.status, "active");
    strict_1.default.equal(mapped.isAutoRenewing, false);
});
(0, node_test_1.default)("CANCELLATION without a current status defaults to active", () => {
    const mapped = (0, revenuecat_status_1.mapRevenueCatEvent)({
        eventType: "CANCELLATION",
        periodType: "NORMAL",
        entitlements: ["pro"],
    });
    strict_1.default.equal(mapped.status, "active");
    strict_1.default.equal(mapped.isAutoRenewing, false);
});
(0, node_test_1.default)("EXPIRATION marks the subscription expired", () => {
    const mapped = (0, revenuecat_status_1.mapRevenueCatEvent)({
        eventType: "EXPIRATION",
        periodType: "NORMAL",
        currentStatus: "active",
        entitlements: ["pro"],
    });
    strict_1.default.equal(mapped.status, "expired");
    strict_1.default.equal(mapped.isAutoRenewing, false);
});
(0, node_test_1.default)("unknown events with pro entitlements do not write unknown", () => {
    const mapped = (0, revenuecat_status_1.mapRevenueCatEvent)({
        eventType: "PRODUCT_CHANGE",
        periodType: "NORMAL",
        currentStatus: "active",
        entitlements: ["pro"],
    });
    strict_1.default.equal(mapped.status, "active");
    strict_1.default.notEqual(mapped.status, "unknown");
});
(0, node_test_1.default)("unknown events with pro and no current status stay active", () => {
    const mapped = (0, revenuecat_status_1.mapRevenueCatEvent)({
        eventType: "TRANSFER",
        periodType: "NORMAL",
        entitlements: ["pro"],
    });
    strict_1.default.equal(mapped.status, "active");
});
(0, node_test_1.default)("INITIAL_PURCHASE trial maps to trial", () => {
    const mapped = (0, revenuecat_status_1.mapRevenueCatEvent)({
        eventType: "INITIAL_PURCHASE",
        periodType: "TRIAL",
        entitlements: ["pro"],
    });
    strict_1.default.equal(mapped.status, "trial");
    strict_1.default.equal(mapped.isAutoRenewing, true);
});
(0, node_test_1.default)("mapRevenueCatTier detects pro entitlements", () => {
    strict_1.default.equal((0, revenuecat_status_1.mapRevenueCatTier)(["pro"]), "pro");
    strict_1.default.equal((0, revenuecat_status_1.mapRevenueCatTier)(["free"]), "free");
});
(0, node_test_1.default)("authorizationHeaderMatches is length-safe", () => {
    strict_1.default.equal((0, revenuecat_status_1.authorizationHeaderMatches)("Bearer secret", "secret"), true);
    strict_1.default.equal((0, revenuecat_status_1.authorizationHeaderMatches)("Bearer secretx", "secret"), false);
    strict_1.default.equal((0, revenuecat_status_1.authorizationHeaderMatches)(undefined, "secret"), false);
});
(0, node_test_1.default)("revenueCatEventId prefers event.id", () => {
    strict_1.default.equal((0, revenuecat_status_1.revenueCatEventId)({ id: "evt_1" }), "evt_1");
    strict_1.default.equal((0, revenuecat_status_1.revenueCatEventId)({ event_id: "evt_2" }), "evt_2");
});
//# sourceMappingURL=revenuecat_status.test.js.map