"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mapRevenueCatTier = mapRevenueCatTier;
exports.hasProEntitlement = hasProEntitlement;
exports.mapRevenueCatEvent = mapRevenueCatEvent;
exports.authorizationHeaderMatches = authorizationHeaderMatches;
exports.revenueCatEventId = revenueCatEventId;
const node_crypto_1 = require("node:crypto");
const GOOD_STATUSES = [
    "trial",
    "active",
    "grace",
    "expired",
    "canceled",
];
function asStatus(input) {
    if (!input) {
        return undefined;
    }
    if (GOOD_STATUSES.includes(input)) {
        return input;
    }
    return undefined;
}
function mapRevenueCatTier(entitlements) {
    if (!Array.isArray(entitlements)) {
        return "free";
    }
    const hasPro = entitlements.some((item) => `${item}`.toLowerCase().includes("pro"));
    return hasPro ? "pro" : "free";
}
function hasProEntitlement(entitlements) {
    return mapRevenueCatTier(entitlements) === "pro";
}
/**
 * Maps a RevenueCat webhook event to a subscription status.
 * CANCELLATION keeps access until EXPIRATION (`isAutoRenewing: false`).
 * Unknown events with a Pro entitlement never overwrite a good status with
 * `unknown`.
 */
function mapRevenueCatEvent(input) {
    const eventType = input.eventType;
    const periodType = input.periodType;
    const current = asStatus(input.currentStatus);
    const pro = hasProEntitlement(input.entitlements);
    if (eventType === "BILLING_ISSUE") {
        return { status: "grace", isAutoRenewing: true };
    }
    if (eventType === "EXPIRATION") {
        return { status: "expired", isAutoRenewing: false };
    }
    if (eventType === "CANCELLATION") {
        const status = current && current !== "expired" ? current : "active";
        return { status, isAutoRenewing: false };
    }
    if (eventType === "INITIAL_PURCHASE" ||
        eventType === "RENEWAL" ||
        eventType === "UNCANCELLATION") {
        const status = periodType === "TRIAL" ? "trial" : "active";
        return { status, isAutoRenewing: true };
    }
    if (pro) {
        if (current) {
            return {
                status: current,
                isAutoRenewing: current === "active" || current === "trial" || current === "grace",
            };
        }
        return { status: "active", isAutoRenewing: true };
    }
    return { status: current ?? "unknown", isAutoRenewing: false };
}
function authorizationHeaderMatches(header, secret) {
    const incoming = Array.isArray(header) ? header[0] : (header ?? "");
    const expected = `Bearer ${secret}`;
    const left = Buffer.from(incoming);
    const right = Buffer.from(expected);
    if (left.length !== right.length) {
        return false;
    }
    return (0, node_crypto_1.timingSafeEqual)(left, right);
}
function revenueCatEventId(event) {
    return `${event.id ?? event.event_id ?? ""}`.trim();
}
//# sourceMappingURL=revenuecat_status.js.map