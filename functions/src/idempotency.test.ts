import assert from "node:assert/strict";
import test from "node:test";
import {
  idempotencyDocId,
  normalizedClientMutationId,
} from "./idempotency";

test("normalizedClientMutationId trims and treats blanks as empty", () => {
  assert.equal(normalizedClientMutationId("  abc  "), "abc");
  assert.equal(normalizedClientMutationId(""), "");
  assert.equal(normalizedClientMutationId(undefined), "");
  assert.equal(normalizedClientMutationId(null), "");
});

test("idempotencyDocId is workspace-and-kind scoped and strips slashes", () => {
  assert.equal(
    idempotencyDocId("ws_1", "expenses", "mut-1"),
    "ws_1__expenses__mut-1",
  );
  assert.equal(
    idempotencyDocId("ws_1", "expenses", "a/b"),
    "ws_1__expenses__a_b",
  );
});

test("corrupt idempotency keys with empty docId are rejected", async () => {
  const {readExistingMutation} = await import("./idempotency");
  const snap = {exists: true, data: () => ({docId: "  "})};
  const db = {
    collection: () => ({
      doc: () => ({
        get: async () => snap,
      }),
    }),
  };
  await assert.rejects(
    () =>
      readExistingMutation(
        db as never,
        "ws_1",
        "expenses",
        "mut-1",
      ),
    /Corrupt idempotency key/,
  );
});
