import assert from "node:assert/strict";
import test from "node:test";
import {
  ACCOUNT_DELETION_REAUTH_SECONDS,
  isRecentLogin,
  ownerDeletionBlocked,
  userStoragePrefixes,
  WORKSPACE_SCOPED_COLLECTIONS,
} from "./account_deletion";

test("recent login accepts auth_time inside the window", () => {
  const now = 1_800_000_000;
  assert.equal(isRecentLogin(now - 60, now), true);
  assert.equal(
    isRecentLogin(now - ACCOUNT_DELETION_REAUTH_SECONDS, now),
    true,
  );
});

test("stale or missing auth_time requires a fresh sign-in", () => {
  const now = 1_800_000_000;
  assert.equal(
    isRecentLogin(now - ACCOUNT_DELETION_REAUTH_SECONDS - 1, now),
    false,
  );
  assert.equal(isRecentLogin(undefined, now), false);
  assert.equal(isRecentLogin("123", now), false);
});

test("solo owners can delete; shared owners cannot", () => {
  assert.equal(ownerDeletionBlocked(0), false);
  assert.equal(ownerDeletionBlocked(1), true);
});

test("workspace-scoped collections include money ledgers", () => {
  assert.ok(WORKSPACE_SCOPED_COLLECTIONS.includes("expenses"));
  assert.ok(WORKSPACE_SCOPED_COLLECTIONS.includes("payments"));
  assert.ok(WORKSPACE_SCOPED_COLLECTIONS.includes("worker_entries"));
  assert.ok(WORKSPACE_SCOPED_COLLECTIONS.includes("idempotency_keys"));
});

test("account deletion storage prefixes are user-scoped", () => {
  assert.deepEqual(userStoragePrefixes("user_1"), [
    "attachments/user_1/",
    "receipts/user_1/",
    "voice-expenses/user_1/",
    "profile-photos/user_1/",
  ]);
  assert.deepEqual(userStoragePrefixes("  "), []);
});
