import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {verifyHttpAppCheck} from "./http_app_check";

test("HTTP App Check rejects missing tokens by default", async () => {
  await assert.rejects(
    () => verifyHttpAppCheck(undefined, async () => undefined),
    (error: unknown) =>
      error instanceof HttpsError &&
      error.code === "failed-precondition" &&
      error.message === "Missing App Check token",
  );
});

test("HTTP App Check rejects invalid tokens", async () => {
  const originalWarn = console.warn;
  const warnings: unknown[][] = [];
  console.warn = (...args: unknown[]) => {
    warnings.push(args);
  };

  try {
    await assert.rejects(
      () =>
        verifyHttpAppCheck("invalid-token", async () => {
          throw new Error("bad token");
        }),
      (error: unknown) =>
        error instanceof HttpsError &&
        error.code === "failed-precondition" &&
        error.message === "Invalid App Check token",
    );
  } finally {
    console.warn = originalWarn;
  }

  assert.deepEqual(
    warnings,
    [["HTTP callable endpoint received an invalid App Check token"]],
  );
});

test("HTTP App Check accepts valid tokens", async () => {
  let verifiedToken = "";

  await verifyHttpAppCheck("valid-token", async (token: string) => {
    verifiedToken = token;
  });

  assert.equal(verifiedToken, "valid-token");
});
