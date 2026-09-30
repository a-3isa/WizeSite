import assert from "node:assert/strict";
import test from "node:test";
import {
  authorizationHeaderMatches,
  mapRevenueCatEvent,
  mapRevenueCatTier,
  revenueCatEventId,
} from "../../src/domain/revenuecat_status";

test("CANCELLATION stays active until expiry and turns auto-renew off", () => {
  const mapped = mapRevenueCatEvent({
    eventType: "CANCELLATION",
    periodType: "NORMAL",
    currentStatus: "active",
    entitlements: ["pro"],
  });
  assert.equal(mapped.status, "active");
  assert.equal(mapped.isAutoRenewing, false);
});

test("CANCELLATION without a current status defaults to active", () => {
  const mapped = mapRevenueCatEvent({
    eventType: "CANCELLATION",
    periodType: "NORMAL",
    entitlements: ["pro"],
  });
  assert.equal(mapped.status, "active");
  assert.equal(mapped.isAutoRenewing, false);
});

test("EXPIRATION marks the subscription expired", () => {
  const mapped = mapRevenueCatEvent({
    eventType: "EXPIRATION",
    periodType: "NORMAL",
    currentStatus: "active",
    entitlements: ["pro"],
  });
  assert.equal(mapped.status, "expired");
  assert.equal(mapped.isAutoRenewing, false);
});

test("unknown events with pro entitlements do not write unknown", () => {
  const mapped = mapRevenueCatEvent({
    eventType: "PRODUCT_CHANGE",
    periodType: "NORMAL",
    currentStatus: "active",
    entitlements: ["pro"],
  });
  assert.equal(mapped.status, "active");
  assert.notEqual(mapped.status, "unknown");
});

test("unknown events with pro and no current status stay active", () => {
  const mapped = mapRevenueCatEvent({
    eventType: "TRANSFER",
    periodType: "NORMAL",
    entitlements: ["pro"],
  });
  assert.equal(mapped.status, "active");
});

test("INITIAL_PURCHASE trial maps to trial", () => {
  const mapped = mapRevenueCatEvent({
    eventType: "INITIAL_PURCHASE",
    periodType: "TRIAL",
    entitlements: ["pro"],
  });
  assert.equal(mapped.status, "trial");
  assert.equal(mapped.isAutoRenewing, true);
});

test("mapRevenueCatTier detects pro entitlements", () => {
  assert.equal(mapRevenueCatTier(["pro"]), "pro");
  assert.equal(mapRevenueCatTier(["free"]), "free");
});

test("authorizationHeaderMatches is length-safe", () => {
  assert.equal(authorizationHeaderMatches("Bearer secret", "secret"), true);
  assert.equal(authorizationHeaderMatches("Bearer secretx", "secret"), false);
  assert.equal(authorizationHeaderMatches(undefined, "secret"), false);
});

test("revenueCatEventId prefers event.id", () => {
  assert.equal(revenueCatEventId({id: "evt_1"}), "evt_1");
  assert.equal(revenueCatEventId({event_id: "evt_2"}), "evt_2");
});
