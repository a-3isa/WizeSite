import assert from "node:assert/strict";
import test from "node:test";
import { HttpsError } from "firebase-functions/v2/https";

test("worker status mutation input defaults to active", async () => {
  const { normalizeWorkerStatus } = await import("./index");

  assert.equal(normalizeWorkerStatus(undefined), "active");
  assert.equal(normalizeWorkerStatus(null), "active");
});

test("worker status mutation input accepts only supported statuses", async () => {
  const { normalizeWorkerStatus } = await import("./index");

  assert.equal(normalizeWorkerStatus("active"), "active");
  assert.equal(normalizeWorkerStatus("inactive"), "inactive");
  assert.equal(normalizeWorkerStatus("terminated"), "terminated");
  assert.throws(
    () => normalizeWorkerStatus("suspended"),
    (error) =>
      error instanceof HttpsError &&
      error.code === "invalid-argument" &&
      error.message.includes("Worker status"),
  );
});
